-- ==============================================================
-- Lembrete automático agora É a enquete de confirmação
--
-- process_appointment_reminders() parava de mandar um texto solto de
-- lembrete — agora manda a ENQUETE com as 3 opções fixas (Confirmar /
-- Remarcar / Cancelar). O botão manual saiu do front (CompanyAgenda.jsx)
-- porque não faz mais sentido: agora é automático, dispara sozinho no
-- horário configurado em appointments.reminders, sem precisar de clique
-- — e não manda mais as duas mensagens juntas (lembrete de texto +
-- enquete), só a enquete. "Confirmar"/"Cancelar" mudam o status sozinhos
-- (trigger trg_poll_vote_to_appointment, 20260901_poll_confirm_appointment.sql).
--
-- Continua usando reminder_message (do agendamento ou do procedimento,
-- com {nome}/{data}) como pergunta da enquete quando existir; senão cai
-- no texto padrão — agora em formato de pergunta, pra combinar com a
-- enquete.
--
-- Idempotente. Cole no SQL Editor do Supabase.
-- ==============================================================

SET search_path TO public;

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
    appt_local := r.starts_at AT TIME ZONE (r.tz_offset)::interval;

    -- Pergunta da enquete: 1º a msg do agendamento, 2º a do procedimento,
    -- 3º o padrão (agora em formato de pergunta, pra combinar com a enquete).
    tmpl := COALESCE(NULLIF(btrim(r.appt_msg), ''), NULLIF(btrim(r.proc_msg), ''));
    IF tmpl IS NOT NULL THEN
      poll_name := regexp_replace(
               regexp_replace(tmpl, '\{nome\}', COALESCE(r.contact_nome, ''), 'gi'),
               '\{data\}', to_char(appt_local, 'DD/MM, HH24:MI'), 'gi');
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
      session_id := r.contact_numero || '@s.whatsapp.net';
      zeroed_votes := jsonb_build_array(
        jsonb_build_object('option', 'Confirmar', 'votes', 0),
        jsonb_build_object('option', 'Remarcar', 'votes', 0),
        jsonb_build_object('option', 'Cancelar', 'votes', 0)
      );

      INSERT INTO public.mensagens_geral
        (instancia, numero, mensagem, type, "horaLastMessage", created_at, aplicativo,
         poll_name, poll_options, poll_votes, poll_selectable_count, poll_appointment_id)
      VALUES
        (r.instancia, session_id, '📊 ' || poll_name, 'atendente',
         to_char(now() AT TIME ZONE (r.tz_offset)::interval, 'HH24:MI'), now(), 'whatsapp',
         poll_name, '["Confirmar","Remarcar","Cancelar"]'::jsonb, zeroed_votes, 1, r.id);

      payload := jsonb_build_object(
        'number', r.contact_numero, 'name', poll_name,
        'selectableCount', 1, 'values', jsonb_build_array('Confirmar', 'Remarcar', 'Cancelar'), 'delay', 1200,
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
  END LOOP;

  RETURN cnt;
END;
$$;

GRANT EXECUTE ON FUNCTION public.process_appointment_reminders() TO service_role;
