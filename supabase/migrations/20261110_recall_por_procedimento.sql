-- ==============================================================
-- "Recall por procedimento" — recurso prometido na landing page
-- ("Você escolhe, por procedimento, depois de quanto tempo o
-- paciente recebe um 'já é hora de voltar?'") que não existia de
-- verdade no sistema. Implementa:
--
--   1) procedures.recall_months (int) + procedures.recall_message
--      (text, opcional, com {nome}/{procedimento}) — configurado na
--      tela de edição do procedimento (Catálogo Clínico).
--   2) appointments.recall_sent_at — marca quando o recall já foi
--      mandado, pra não repetir.
--   3) process_procedure_recall() — acha, por procedimento com
--      recall_months configurado, o último agendamento CONCLUÍDO de
--      cada paciente pra aquele procedimento específico que já passou
--      do prazo e cujo paciente NÃO tem nenhum agendamento mais novo
--      (de qualquer procedimento) — ou seja, realmente não voltou
--      ainda — e manda uma mensagem de texto simples via WhatsApp.
--   4) cron diário (recall não precisa de precisão de minutos).
--
-- Trava de duplicata: além de recall_sent_at (por linha), confere se
-- já não mandou QUALQUER mensagem pro mesmo número nos últimos 2min
-- (mesmo padrão das outras functions de hoje) e loga erro real em
-- cron_error_log em vez de só RAISE NOTICE.
--
-- Idempotente.
-- ==============================================================

ALTER TABLE public.procedures
  ADD COLUMN IF NOT EXISTS recall_months integer,
  ADD COLUMN IF NOT EXISTS recall_message text;

ALTER TABLE public.appointments
  ADD COLUMN IF NOT EXISTS recall_sent_at timestamptz;

CREATE OR REPLACE FUNCTION public.process_procedure_recall()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  r         record;
  cnt       integer := 0;
  msg       text;
  tmpl      text;
  session_id text;
  payload   jsonb;
  ja_mandou boolean;
BEGIN
  IF NOT pg_try_advisory_xact_lock(778903) THEN
    RETURN 0;
  END IF;

  FOR r IN
    SELECT
      a.id, a.contact_numero, a.contact_nome, a.starts_at, a.instancia, a.procedure_id,
      pr.name AS procedure_name, pr.recall_message,
      c.api_instancia, c.name AS company_name,
      COALESCE(NULLIF(c.timezone, ''), '-03:00') AS tz_offset
    FROM public.appointments a
    JOIN public.procedures pr ON pr.id = a.procedure_id
    JOIN public.companies  c  ON c.instance = a.instancia
    WHERE a.status = 'concluido'
      AND pr.recall_months IS NOT NULL AND pr.recall_months > 0
      AND a.contact_numero IS NOT NULL AND a.contact_numero <> ''
      AND a.recall_sent_at IS NULL
      AND a.starts_at + make_interval(months => pr.recall_months) <= now()
      -- só o agendamento MAIS RECENTE concluído desse procedimento pra esse paciente
      AND a.starts_at = (
        SELECT MAX(a2.starts_at) FROM public.appointments a2
         WHERE a2.instancia = a.instancia AND a2.contact_numero = a.contact_numero
           AND a2.procedure_id = a.procedure_id AND a2.status = 'concluido'
      )
      -- e o paciente não tem NENHUM agendamento mais novo (já voltou por conta própria)
      AND NOT EXISTS (
        SELECT 1 FROM public.appointments a3
         WHERE a3.instancia = a.instancia AND a3.contact_numero = a.contact_numero
           AND a3.starts_at > a.starts_at
      )
    ORDER BY a.starts_at ASC
  LOOP
    BEGIN
      session_id := r.contact_numero || '@s.whatsapp.net';

      SELECT EXISTS (
        SELECT 1 FROM public.mensagens_geral
         WHERE instancia = r.instancia AND numero = session_id
           AND created_at > now() - interval '2 minutes'
      ) INTO ja_mandou;

      IF ja_mandou THEN
        RAISE NOTICE 'process_procedure_recall: duplicata evitada pra appt %', r.id;
        UPDATE public.appointments SET recall_sent_at = now() WHERE id = r.id;
        CONTINUE;
      END IF;

      tmpl := NULLIF(btrim(r.recall_message), '');
      IF tmpl IS NOT NULL THEN
        msg := tmpl;
        msg := replace(msg, '{nome}', COALESCE(NULLIF(btrim(r.contact_nome), ''), 'tudo bem'));
        msg := replace(msg, '{Nome}', COALESCE(NULLIF(btrim(r.contact_nome), ''), 'tudo bem'));
        msg := replace(msg, '{NOME}', COALESCE(NULLIF(btrim(r.contact_nome), ''), 'tudo bem'));
        msg := replace(msg, '{procedimento}', COALESCE(r.procedure_name, 'procedimento'));
        msg := replace(msg, '{Procedimento}', COALESCE(r.procedure_name, 'Procedimento'));
      ELSE
        msg := format(
          'Olá %s! 👋 Já faz um tempo desde seu(sua) %s — que tal agendar um retorno?',
          COALESCE(NULLIF(btrim(r.contact_nome), ''), 'tudo bem'), r.procedure_name);
      END IF;

      INSERT INTO public.mensagens_geral
        (instancia, numero, mensagem, type, "horaLastMessage", created_at, aplicativo)
      VALUES
        (r.instancia, session_id, msg, 'atendente',
         to_char(now() AT TIME ZONE (r.tz_offset)::interval, 'HH24:MI'), now(), 'whatsapp');

      payload := jsonb_build_object(
        'message', msg, 'session_id', session_id, 'phone', r.contact_numero,
        'instancia', r.instancia, 'api_instancia', r.api_instancia,
        'company', r.company_name,
        'sender_name', 'Sistema (Recall de procedimento)', 'sender_email', 'sistema@clinisac');
      BEGIN
        PERFORM net.http_post(
          url := 'https://n8n.nexladesenvolvimento.com.br/webhook/envioNexla',
          body := payload, headers := '{"Content-Type": "application/json"}'::jsonb);
      EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'webhook recall fail appt %: %', r.id, SQLERRM;
        INSERT INTO public.cron_error_log (function_name, context_id, error_message)
        VALUES ('process_procedure_recall:webhook', r.id::text, SQLERRM);
      END;

      UPDATE public.appointments SET recall_sent_at = now() WHERE id = r.id;
      cnt := cnt + 1;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'process_procedure_recall falhou pra appt %: %', r.id, SQLERRM;
      INSERT INTO public.cron_error_log (function_name, context_id, error_message)
      VALUES ('process_procedure_recall', r.id::text, SQLERRM);
    END;
  END LOOP;

  RETURN cnt;
END;
$$;

GRANT EXECUTE ON FUNCTION public.process_procedure_recall() TO service_role;

-- Cron diário às 10h (recall não precisa de precisão de minutos, só de dia).
DO $$
BEGIN
  PERFORM cron.unschedule('procedure-recall');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

SELECT cron.schedule(
  'procedure-recall',
  '0 10 * * *',
  $cron$SELECT public.process_procedure_recall();$cron$
);
