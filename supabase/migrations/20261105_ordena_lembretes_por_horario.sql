-- ==============================================================
-- Quando duas confirmações saem no mesmo ciclo do cron (ex.: duas
-- consultas do mesmo paciente, 17:00 e 17:30), a ordem de inserção
-- em mensagens_geral não seguia a ordem cronológica dos agendamentos
-- -- a consulta não tinha ORDER BY, então o Postgres processa na
-- ordem que achar mais conveniente (não garantida). Resultado: a
-- poll da consulta das 17:30 podia aparecer ANTES da das 17:00 no
-- chat.
--
-- Adiciona ORDER BY a.starts_at ASC na consulta principal, pra
-- processar e inserir sempre na ordem cronológica do horário da
-- consulta.
--
-- Idempotente.
-- ==============================================================

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
    ORDER BY a.starts_at ASC
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
          INSERT INTO public.cron_error_log (function_name, context_id, error_message)
          VALUES ('process_appointment_reminders:webhook', r.id::text, SQLERRM);
        END;

        UPDATE public.appointments SET reminders = new_reminders WHERE id = r.id;
        cnt := cnt + 1;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'process_appointment_reminders falhou pra appt %: %', r.id, SQLERRM;
      INSERT INTO public.cron_error_log (function_name, context_id, error_message)
      VALUES ('process_appointment_reminders', r.id::text, SQLERRM);
    END;
  END LOOP;

  RETURN cnt;
END;
$$;
