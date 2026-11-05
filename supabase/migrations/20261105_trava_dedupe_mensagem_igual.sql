-- ==============================================================
-- Trava extra: antes de mandar, confere se já não mandou a mesma
-- mensagem pra esse mesmo agendamento/contato há pouco tempo
--
-- O advisory lock (778899/778901/778902) já impede duas execuções da
-- MESMA function rodando ao mesmo tempo. Mas isso só cobre "duas
-- chamadas concorrentes dessa function especificamente" — não cobre,
-- por exemplo, um n8n Schedule node chamando a MESMA ação por outro
-- caminho, nem qualquer outro jeito de duas linhas conseguirem passar
-- pela checagem de "ainda não enviado" antes de uma marcar a outra como
-- enviada.
--
-- Esta migration adiciona uma segunda trava, independente da primeira:
-- imediatamente antes de inserir a mensagem em mensagens_geral, confere
-- se já não existe uma mensagem idêntica (mesmo agendamento/contato,
-- mesmo tipo de aviso) inserida nos últimos 2 minutos. Se existir, não
-- manda de novo — só marca o lembrete como enviado (pra não ficar
-- tentando de novo a cada tick do cron) e segue pro próximo.
--
-- Por que 2 minutos e não "pra sempre": um paciente PODE ter mais de um
-- lembrete de verdade pro mesmo agendamento (ex.: aviso de 24h antes E
-- de 1h antes) — isso é esperado, não é duplicata. Só precisa travar
-- contra a mesma mensagem saindo duas vezes no MESMO disparo.
--
-- Idempotente.
-- ==============================================================

SET search_path TO public;

-- Índice pra a checagem de dedupe (poll_appointment_id + poll_kind) não
-- virar table scan em mensagens_geral a cada tick do cron.
CREATE INDEX IF NOT EXISTS idx_mensagens_geral_poll_dedupe
  ON public.mensagens_geral (poll_appointment_id, poll_kind, created_at)
  WHERE poll_appointment_id IS NOT NULL;

-- ─────────────────────────────────────────────────────────────────────────
-- 1) process_appointment_reminders — confirmação de presença
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.process_appointment_reminders()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  r             record;
  e             jsonb;
  new_reminders jsonb;
  sent_any      boolean;
  cnt           integer := 0;
  poll_name     text;
  tmpl          text;
  appt_local    timestamp;
  session_id    text;
  payload       jsonb;
  zeroed_votes  jsonb;
  ja_mandou     boolean;
BEGIN
  IF NOT pg_try_advisory_xact_lock(778899) THEN
    RETURN 0;
  END IF;

  FOR r IN
    SELECT
      a.id, a.contact_numero, a.contact_nome, a.starts_at, a.instancia,
      a.reminders, a.procedure_id, a.reminder_message AS appt_msg,
      c.name              AS company_name,
      c.api_instancia,
      COALESCE(NULLIF(c.timezone, ''), '-03:00') AS tz_offset,
      p.name              AS prof_name,
      pr.reminder_message AS proc_msg
    FROM public.appointments a
    JOIN public.companies c   ON c.instance = a.instancia
    LEFT JOIN public.professionals p ON p.id = a.professional_id
    LEFT JOIN public.procedures   pr ON pr.id = a.procedure_id
    WHERE a.status IN ('agendado', 'confirmado')
      AND a.contact_numero IS NOT NULL AND a.contact_numero <> ''
      AND a.starts_at > now()
      AND jsonb_typeof(a.reminders) = 'array'
      AND EXISTS (
        SELECT 1 FROM jsonb_array_elements(a.reminders) x
        WHERE (x->>'sent_at') IS NULL
          AND a.starts_at - make_interval(mins => (x->>'offset_minutes')::int) <= now()
      )
  LOOP
    BEGIN
      appt_local := r.starts_at AT TIME ZONE (r.tz_offset)::interval;

      tmpl := COALESCE(NULLIF(btrim(r.appt_msg), ''), NULLIF(btrim(r.proc_msg), ''));
      IF tmpl IS NOT NULL THEN
        poll_name := tmpl;
        poll_name := replace(poll_name, '{nome}', COALESCE(r.contact_nome, ''));
        poll_name := replace(poll_name, '{Nome}', COALESCE(r.contact_nome, ''));
        poll_name := replace(poll_name, '{NOME}', COALESCE(r.contact_nome, ''));
        poll_name := replace(poll_name, '{data}', to_char(appt_local, 'DD/MM, HH24:MI'));
        poll_name := replace(poll_name, '{Data}', to_char(appt_local, 'DD/MM, HH24:MI'));
        poll_name := replace(poll_name, '{DATA}', to_char(appt_local, 'DD/MM, HH24:MI'));
      ELSE
        poll_name := format(
          'Olá %s! 👋 Confirma sua consulta no dia %s às %s%s?',
          r.contact_nome, to_char(appt_local, 'DD/MM'), to_char(appt_local, 'HH24:MI'),
          CASE WHEN r.prof_name IS NOT NULL AND r.prof_name <> ''
            THEN ' com ' || r.prof_name ELSE '' END);
      END IF;

      new_reminders := '[]'::jsonb;
      sent_any := false;
      FOR e IN SELECT * FROM jsonb_array_elements(r.reminders) LOOP
        IF (e->>'sent_at') IS NULL
           AND r.starts_at - make_interval(mins => (e->>'offset_minutes')::int) <= now() THEN
          new_reminders := new_reminders || jsonb_build_object(
            'offset_minutes', (e->>'offset_minutes')::int,
            'sent_at', to_char(now(), 'YYYY-MM-DD"T"HH24:MI:SS'));
          sent_any := true;
        ELSE
          new_reminders := new_reminders || e;
        END IF;
      END LOOP;

      IF sent_any THEN
        -- Trava extra: já existe uma confirmação pra esse agendamento
        -- inserida nos últimos 2 minutos? Então é duplicata de algum
        -- outro disparo concorrente -- só marca como enviado e não manda
        -- de novo.
        SELECT EXISTS (
          SELECT 1 FROM public.mensagens_geral
           WHERE poll_appointment_id = r.id
             AND poll_kind = 'confirmacao'
             AND created_at > now() - interval '2 minutes'
        ) INTO ja_mandou;

        IF ja_mandou THEN
          RAISE NOTICE 'process_appointment_reminders: confirmacao duplicada evitada pra appt %', r.id;
          UPDATE public.appointments SET reminders = new_reminders WHERE id = r.id;
          CONTINUE;
        END IF;

        session_id := r.contact_numero || '@s.whatsapp.net';
        zeroed_votes := jsonb_build_array(
          jsonb_build_object('option', 'Confirmar', 'votes', 0),
          jsonb_build_object('option', 'Cancelar', 'votes', 0)
        );

        INSERT INTO public.mensagens_geral
          (instancia, numero, mensagem, type, "horaLastMessage", created_at, aplicativo,
           poll_name, poll_options, poll_votes, poll_selectable_count, poll_appointment_id, poll_kind)
        VALUES
          (r.instancia, session_id, '📊 ' || poll_name, 'atendente',
           to_char(now() AT TIME ZONE (r.tz_offset)::interval, 'HH24:MI'), now(), 'whatsapp',
           poll_name, '["Confirmar","Cancelar"]'::jsonb, zeroed_votes, 1, r.id, 'confirmacao');

        payload := jsonb_build_object(
          'number', r.contact_numero, 'name', poll_name,
          'selectableCount', 1, 'values', jsonb_build_array('Confirmar', 'Cancelar'), 'delay', 1200,
          'instancia', r.instancia, 'api_instancia', r.api_instancia,
          'session_id', session_id, 'appointment_id', r.id, 'contact_nome', r.contact_nome,
          'company', r.company_name,
          'sender_name', 'Sistema (Lembrete automático)', 'sender_email', 'sistema@clinisac');
        BEGIN
          PERFORM net.http_post(
            url := 'https://n8n.nexladesenvolvimento.com.br/webhook/templete-pergunta',
            body := payload, headers := '{"Content-Type": "application/json"}'::jsonb);
        EXCEPTION WHEN OTHERS THEN
          RAISE NOTICE 'webhook lembrete/enquete fail appt %: %', r.id, SQLERRM;
        END;

        UPDATE public.appointments SET reminders = new_reminders WHERE id = r.id;
        cnt := cnt + 1;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'process_appointment_reminders falhou pra appt %: %', r.id, SQLERRM;
    END;
  END LOOP;

  RETURN cnt;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- 2) process_appointment_followups — "como foi sua consulta?"
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.process_appointment_followups()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  r          record;
  cnt        integer := 0;
  poll_name  text;
  tmpl       text;
  session_id text;
  payload    jsonb;
  zeroed_votes jsonb;
  ja_mandou  boolean;
BEGIN
  IF NOT pg_try_advisory_xact_lock(778901) THEN
    RETURN 0;
  END IF;

  FOR r IN
    SELECT
      a.id, a.contact_numero, a.contact_nome, a.starts_at, a.duration_minutes, a.instancia,
      c.api_instancia, c.name AS company_name, c.followup_question_message,
      COALESCE(NULLIF(c.timezone, ''), '-03:00') AS tz_offset,
      p.name AS prof_name
    FROM public.appointments a
    JOIN public.companies c ON c.instance = a.instancia
    LEFT JOIN public.professionals p ON p.id = a.professional_id
    WHERE a.status = 'concluido'
      AND a.followup_sent_at IS NULL
      AND a.contact_numero IS NOT NULL AND a.contact_numero <> ''
      AND a.starts_at + make_interval(mins => COALESCE(a.duration_minutes, 30)) <= now() - interval '1 hour'
      AND a.starts_at > now() - interval '3 days'
  LOOP
    BEGIN
      -- Trava extra: idem reminders -- se já tem um follow-up recém-criado
      -- pra esse agendamento, não manda de novo. Marca como enviado e sai.
      SELECT EXISTS (
        SELECT 1 FROM public.mensagens_geral
         WHERE poll_appointment_id = r.id
           AND poll_kind = 'satisfacao'
           AND created_at > now() - interval '2 minutes'
      ) INTO ja_mandou;

      IF ja_mandou THEN
        RAISE NOTICE 'process_appointment_followups: follow-up duplicado evitado pra appt %', r.id;
        UPDATE public.appointments SET followup_sent_at = now() WHERE id = r.id;
        CONTINUE;
      END IF;

      tmpl := NULLIF(btrim(r.followup_question_message), '');
      IF tmpl IS NOT NULL THEN
        poll_name := tmpl;
        poll_name := replace(poll_name, '{nome}', COALESCE(r.contact_nome, ''));
        poll_name := replace(poll_name, '{Nome}', COALESCE(r.contact_nome, ''));
        poll_name := replace(poll_name, '{NOME}', COALESCE(r.contact_nome, ''));
      ELSE
        poll_name := format(
          'Olá %s! 👋 Como foi sua consulta%s?',
          r.contact_nome,
          CASE WHEN r.prof_name IS NOT NULL AND r.prof_name <> '' THEN ' com ' || r.prof_name ELSE '' END);
      END IF;

      session_id := r.contact_numero || '@s.whatsapp.net';
      zeroed_votes := jsonb_build_array(
        jsonb_build_object('option', 'Ótima', 'votes', 0),
        jsonb_build_object('option', 'Boa', 'votes', 0),
        jsonb_build_object('option', 'Regular', 'votes', 0),
        jsonb_build_object('option', 'Ruim', 'votes', 0)
      );

      INSERT INTO public.mensagens_geral
        (instancia, numero, mensagem, type, "horaLastMessage", created_at, aplicativo,
         poll_name, poll_options, poll_votes, poll_selectable_count, poll_appointment_id, poll_kind)
      VALUES
        (r.instancia, session_id, '📊 ' || poll_name, 'atendente',
         to_char(now() AT TIME ZONE (r.tz_offset)::interval, 'HH24:MI'), now(), 'whatsapp',
         poll_name, '["Ótima","Boa","Regular","Ruim"]'::jsonb, zeroed_votes, 1, r.id, 'satisfacao');

      payload := jsonb_build_object(
        'number', r.contact_numero, 'name', poll_name,
        'selectableCount', 1, 'values', jsonb_build_array('Ótima', 'Boa', 'Regular', 'Ruim'), 'delay', 1200,
        'instancia', r.instancia, 'api_instancia', r.api_instancia,
        'session_id', session_id, 'appointment_id', r.id, 'contact_nome', r.contact_nome,
        'company', r.company_name,
        'sender_name', 'Sistema (Follow-up pós-consulta)', 'sender_email', 'sistema@clinisac');
      BEGIN
        PERFORM net.http_post(
          url := 'https://n8n.nexladesenvolvimento.com.br/webhook/templete-pergunta',
          body := payload, headers := '{"Content-Type": "application/json"}'::jsonb);
      EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'webhook follow-up fail appt %: %', r.id, SQLERRM;
      END;

      UPDATE public.appointments SET followup_sent_at = now() WHERE id = r.id;
      cnt := cnt + 1;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'process_appointment_followups falhou pra appt %: %', r.id, SQLERRM;
    END;
  END LOOP;

  RETURN cnt;
END;
$$;

GRANT EXECUTE ON FUNCTION public.process_appointment_followups() TO service_role;

-- ─────────────────────────────────────────────────────────────────────────
-- 3) process_monthly_review_requests — reforço mensal (sem poll_appointment_id
--    pra agarrar; dedupe por instancia+numero+criado há pouco)
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.process_monthly_review_requests()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  r       record;
  cnt     integer := 0;
  msg     text;
  tmpl    text;
  session_id text;
  payload jsonb;
  ja_mandou boolean;
BEGIN
  IF NOT pg_try_advisory_xact_lock(778902) THEN
    RETURN 0;
  END IF;

  FOR r IN
    SELECT DISTINCT ON (sc.id)
      sc.id, sc.numero, sc.nome, sc.instancia, sc.last_review_request_at,
      c.api_instancia, c.name AS company_name, c.google_review_url, c.followup_review_message,
      COALESCE(NULLIF(c.timezone, ''), '-03:00') AS tz_offset
    FROM public.saved_contacts sc
    JOIN public.companies c ON c.instance = sc.instancia
    JOIN public.appointments a ON a.instancia = sc.instancia
      AND regexp_replace(a.contact_numero, '\D', '', 'g') = regexp_replace(sc.numero, '\D', '', 'g')
    WHERE c.google_review_url IS NOT NULL AND c.google_review_url <> ''
      AND a.status = 'concluido'
      AND a.starts_at > now() - interval '12 months'
      AND (sc.last_review_request_at IS NULL OR sc.last_review_request_at < now() - interval '30 days')
      AND sc.numero IS NOT NULL AND sc.numero <> ''
  LOOP
    BEGIN
      SELECT EXISTS (
        SELECT 1 FROM public.mensagens_geral
         WHERE instancia = r.instancia
           AND numero = r.numero || '@s.whatsapp.net'
           AND created_at > now() - interval '2 minutes'
      ) INTO ja_mandou;

      IF ja_mandou THEN
        RAISE NOTICE 'process_monthly_review_requests: pesquisa duplicada evitada pro contato %', r.id;
        UPDATE public.saved_contacts SET last_review_request_at = now() WHERE id = r.id;
        CONTINUE;
      END IF;

      tmpl := NULLIF(btrim(r.followup_review_message), '');
      IF tmpl IS NOT NULL THEN
        msg := tmpl;
        msg := replace(msg, '{nome}', COALESCE(NULLIF(btrim(r.nome), ''), 'tudo bem'));
        msg := replace(msg, '{Nome}', COALESCE(NULLIF(btrim(r.nome), ''), 'tudo bem'));
        msg := replace(msg, '{NOME}', COALESCE(NULLIF(btrim(r.nome), ''), 'tudo bem'));
        msg := replace(msg, '{link}', r.google_review_url);
        msg := replace(msg, '{Link}', r.google_review_url);
        msg := replace(msg, '{LINK}', r.google_review_url);
      ELSE
        msg := format(
          'Olá %s! 👋 Esperamos que esteja tudo bem. Se puder, deixa sua avaliação sobre o atendimento — ajuda muito a gente: %s',
          COALESCE(NULLIF(btrim(r.nome), ''), 'tudo bem'), r.google_review_url);
      END IF;

      session_id := r.numero || '@s.whatsapp.net';

      INSERT INTO public.mensagens_geral
        (instancia, numero, mensagem, type, "horaLastMessage", created_at, aplicativo)
      VALUES
        (r.instancia, session_id, msg, 'atendente',
         to_char(now() AT TIME ZONE (r.tz_offset)::interval, 'HH24:MI'), now(), 'whatsapp');

      payload := jsonb_build_object(
        'message', msg, 'session_id', session_id, 'phone', r.numero,
        'instancia', r.instancia, 'api_instancia', r.api_instancia,
        'company', r.company_name,
        'sender_name', 'Sistema (Pesquisa de satisfação)', 'sender_email', 'sistema@clinisac');
      BEGIN
        PERFORM net.http_post(
          url := 'https://n8n.nexladesenvolvimento.com.br/webhook/envioNexla',
          body := payload, headers := '{"Content-Type": "application/json"}'::jsonb);
      EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'webhook pesquisa mensal fail contato %: %', r.id, SQLERRM;
      END;

      UPDATE public.saved_contacts SET last_review_request_at = now() WHERE id = r.id;
      cnt := cnt + 1;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'process_monthly_review_requests falhou pro contato %: %', r.id, SQLERRM;
    END;
  END LOOP;

  RETURN cnt;
END;
$$;

GRANT EXECUTE ON FUNCTION public.process_monthly_review_requests() TO service_role;
