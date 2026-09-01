-- ==============================================================
-- Enquete de confirmação: tira "Remarcar" (fica só Confirmar/Cancelar)
-- + cria alerta no painel de Avisos quando o paciente cancela
--
-- 1) process_appointment_reminders(): enquete agora só com 2 opções
--    fixas — Confirmar / Cancelar.
--
-- 2) apply_poll_vote_to_appointment(): quando o voto vencedor é
--    "Cancelar", além de mudar appointments.status pra 'cancelado',
--    insere uma linha em public.alerts ("Paciente X cancelou a consulta
--    pela enquete. Por favor, entrar em contato.") — aparece na hora
--    no painel de Avisos (CompanyAlerts.jsx já assina realtime nessa
--    tabela).
--
--    Sem duplicar alerta: só insere quando o UPDATE realmente TRANSITA
--    pra 'cancelado' (status anterior <> 'cancelado'). Se o paciente
--    votar de novo, ou a enquete atualizar de novo com o mesmo
--    resultado, não gera um segundo alerta. Se trocar o voto de volta
--    pra "Confirmar", o status volta (sem alerta novo).
--
-- Idempotente. Cole no SQL Editor do Supabase.
-- ==============================================================

SET search_path TO public;

-- ─────────────────────────────────────────────────────────────────
-- 1) Lembrete automático: só Confirmar / Cancelar
-- ─────────────────────────────────────────────────────────────────
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
        jsonb_build_object('option', 'Cancelar', 'votes', 0)
      );

      INSERT INTO public.mensagens_geral
        (instancia, numero, mensagem, type, "horaLastMessage", created_at, aplicativo,
         poll_name, poll_options, poll_votes, poll_selectable_count, poll_appointment_id)
      VALUES
        (r.instancia, session_id, '📊 ' || poll_name, 'atendente',
         to_char(now() AT TIME ZONE (r.tz_offset)::interval, 'HH24:MI'), now(), 'whatsapp',
         poll_name, '["Confirmar","Cancelar"]'::jsonb, zeroed_votes, 1, r.id);

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
  END LOOP;

  RETURN cnt;
END;
$$;

GRANT EXECUTE ON FUNCTION public.process_appointment_reminders() TO service_role;

-- ─────────────────────────────────────────────────────────────────
-- 2) Trigger: Cancelar → status + alerta no painel de Avisos
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.apply_poll_vote_to_appointment()
RETURNS trigger LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
DECLARE
  confirm_votes integer;
  cancel_votes  integer;
  appt          record;
BEGIN
  IF NEW.poll_appointment_id IS NULL THEN RETURN NEW; END IF;
  IF NEW.poll_votes IS NOT DISTINCT FROM OLD.poll_votes
     AND NEW.poll_options IS NOT DISTINCT FROM OLD.poll_options THEN
    RETURN NEW;
  END IF;

  SELECT
    COALESCE(SUM(CASE WHEN lower(btrim(COALESCE(x ->> 'option', x ->> 'optionName', x ->> 'name', ''))) = 'confirmar'
      THEN (CASE WHEN jsonb_typeof(x -> 'voters') = 'array' THEN jsonb_array_length(x -> 'voters')
                 WHEN (x ->> 'votes') ~ '^\d+$' THEN (x ->> 'votes')::int ELSE 0 END)
      ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN lower(btrim(COALESCE(x ->> 'option', x ->> 'optionName', x ->> 'name', ''))) = 'cancelar'
      THEN (CASE WHEN jsonb_typeof(x -> 'voters') = 'array' THEN jsonb_array_length(x -> 'voters')
                 WHEN (x ->> 'votes') ~ '^\d+$' THEN (x ->> 'votes')::int ELSE 0 END)
      ELSE 0 END), 0)
  INTO confirm_votes, cancel_votes
  FROM jsonb_array_elements(
    COALESCE(NEW.poll_votes, '[]'::jsonb) || COALESCE(NEW.poll_options, '[]'::jsonb)
  ) x;

  IF cancel_votes > 0 AND confirm_votes = 0 THEN
    UPDATE public.appointments
       SET status = 'cancelado'
     WHERE id = NEW.poll_appointment_id
       AND status <> 'cancelado'
       AND status IN ('agendado', 'confirmado')
    RETURNING id, instancia, contact_nome, contact_numero INTO appt;

    -- Só cria o alerta se a transição realmente aconteceu agora
    -- (evita duplicar se a enquete atualizar de novo com o mesmo resultado).
    IF FOUND THEN
      INSERT INTO public.alerts (instancia, mensagem, numero)
      VALUES (
        appt.instancia,
        'Paciente ' || COALESCE(NULLIF(btrim(appt.contact_nome), ''), 'sem nome')
          || ' cancelou a consulta pela enquete. Por favor, entrar em contato.',
        appt.contact_numero || '@s.whatsapp.net'
      );
    END IF;

  ELSIF confirm_votes > 0 AND cancel_votes = 0 THEN
    UPDATE public.appointments
       SET status = 'confirmado'
     WHERE id = NEW.poll_appointment_id
       AND status <> 'confirmado'
       AND status IN ('agendado', 'cancelado');
  END IF;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RETURN NEW;
END;
$$;
