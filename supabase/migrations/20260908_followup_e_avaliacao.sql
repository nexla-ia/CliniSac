-- ==============================================================
-- Follow-up pós-consulta + pesquisa mensal de satisfação (Google)
--
-- A landing prometia isso e não existia nada implementado — essa
-- migration constrói de verdade, reaproveitando a infra de enquete
-- já usada na confirmação de presença (poll_name/poll_options/
-- poll_votes/poll_appointment_id em mensagens_geral).
--
-- DUAS coisas, disparadas por dois crons separados:
--
-- 1) FOLLOW-UP PÓS-CONSULTA (por agendamento)
--    3h depois que um agendamento vira 'concluido', manda uma enquete
--    "Como foi sua consulta?" com 4 opções (Ótima/Boa/Regular/Ruim).
--    Se vier Regular/Ruim, cria um alerta pra recepção ligar ANTES
--    que vire avaliação negativa pública — funil de reputação, não só
--    "perguntar por perguntar".
--
-- 2) PESQUISA MENSAL COM LINK DO GOOGLE (por paciente)
--    Uma vez por mês, manda o link de avaliação do Google Meu Negócio
--    (configurado por clínica) pra quem teve consulta concluída nos
--    últimos 12 meses. Só dispara se a clínica configurou o link
--    (companies.google_review_url) — sem link, não manda nada.
--
-- Colunas novas:
--   companies.google_review_url          text      -- link do Google Meu Negócio da clínica
--   appointments.followup_sent_at        timestamptz -- já mandou o "como foi" desse agendamento?
--   saved_contacts.last_review_request_at timestamptz -- última vez que esse paciente recebeu o pedido mensal
--   mensagens_geral.poll_kind             text      -- 'confirmacao' | 'satisfacao' — distingue o TIPO de
--                                                     enquete pro trigger saber o que fazer com o voto
--
-- (A enquete de confirmação de presença passa a gravar poll_kind =
--  'confirmacao' também, pra não ficar ambíguo com a nova.)
--
-- Idempotente. Cole no SQL Editor do Supabase.
-- ==============================================================

SET search_path TO public;

ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS google_review_url text;

ALTER TABLE public.appointments
  ADD COLUMN IF NOT EXISTS followup_sent_at timestamptz;

ALTER TABLE public.saved_contacts
  ADD COLUMN IF NOT EXISTS last_review_request_at timestamptz;

ALTER TABLE public.mensagens_geral
  ADD COLUMN IF NOT EXISTS poll_kind text;

-- ─────────────────────────────────────────────────────────────────
-- Marca a enquete de confirmação de presença com poll_kind, pra não
-- ficar ambígua com a nova de satisfação (mesma função de sempre, só
-- adiciona 'confirmacao' no INSERT).
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
  END LOOP;

  RETURN cnt;
END;
$$;

GRANT EXECUTE ON FUNCTION public.process_appointment_reminders() TO service_role;

-- ─────────────────────────────────────────────────────────────────
-- 1) Follow-up pós-consulta: "Como foi sua consulta?"
-- ─────────────────────────────────────────────────────────────────
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
  session_id text;
  payload    jsonb;
  zeroed_votes jsonb;
BEGIN
  IF NOT pg_try_advisory_xact_lock(778901) THEN
    RETURN 0;
  END IF;

  FOR r IN
    SELECT
      a.id, a.contact_numero, a.contact_nome, a.starts_at, a.duration_minutes, a.instancia,
      c.api_instancia, c.name AS company_name,
      COALESCE(NULLIF(c.timezone, ''), '-03:00') AS tz_offset,
      p.name AS prof_name
    FROM public.appointments a
    JOIN public.companies c ON c.instance = a.instancia
    LEFT JOIN public.professionals p ON p.id = a.professional_id
    WHERE a.status = 'concluido'
      AND a.followup_sent_at IS NULL
      AND a.contact_numero IS NOT NULL AND a.contact_numero <> ''
      -- espera 3h depois do fim do horário marcado antes de perguntar
      AND a.starts_at + make_interval(mins => COALESCE(a.duration_minutes, 30)) <= now() - interval '3 hours'
      -- não manda follow-up de agendamento muito antigo (ex.: primeira vez
      -- que essa função roda, com meses de "concluido" acumulado)
      AND a.starts_at > now() - interval '3 days'
  LOOP
    poll_name := format(
      'Olá %s! 👋 Como foi sua consulta%s?',
      r.contact_nome,
      CASE WHEN r.prof_name IS NOT NULL AND r.prof_name <> '' THEN ' com ' || r.prof_name ELSE '' END);

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
  END LOOP;

  RETURN cnt;
END;
$$;

GRANT EXECUTE ON FUNCTION public.process_appointment_followups() TO service_role;

-- ─────────────────────────────────────────────────────────────────
-- 2) Voto na enquete de satisfação: Regular/Ruim vira alerta pra
--    recepção ligar — antes que vire avaliação pública negativa.
--    Ótima/Boa não faz nada aqui (o link do Google vai na pesquisa
--    mensal separada, não junto com o follow-up individual).
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.apply_satisfaction_poll_vote()
RETURNS trigger LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
DECLARE
  old_ruim integer;
  new_ruim integer;
  appt     record;
BEGIN
  IF NEW.poll_kind IS DISTINCT FROM 'satisfacao' THEN RETURN NEW; END IF;
  IF NEW.poll_appointment_id IS NULL THEN RETURN NEW; END IF;
  IF NEW.poll_votes IS NOT DISTINCT FROM OLD.poll_votes
     AND NEW.poll_options IS NOT DISTINCT FROM OLD.poll_options THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(SUM(CASE WHEN lower(btrim(COALESCE(x->>'option', x->>'optionName', x->>'name',''))) IN ('regular','ruim')
    THEN (CASE WHEN jsonb_typeof(x->'voters')='array' THEN jsonb_array_length(x->'voters')
               WHEN (x->>'votes') ~ '^\d+$' THEN (x->>'votes')::int ELSE 0 END)
    ELSE 0 END), 0)
  INTO old_ruim
  FROM jsonb_array_elements(COALESCE(OLD.poll_votes,'[]'::jsonb) || COALESCE(OLD.poll_options,'[]'::jsonb)) x;

  SELECT COALESCE(SUM(CASE WHEN lower(btrim(COALESCE(x->>'option', x->>'optionName', x->>'name',''))) IN ('regular','ruim')
    THEN (CASE WHEN jsonb_typeof(x->'voters')='array' THEN jsonb_array_length(x->'voters')
               WHEN (x->>'votes') ~ '^\d+$' THEN (x->>'votes')::int ELSE 0 END)
    ELSE 0 END), 0)
  INTO new_ruim
  FROM jsonb_array_elements(COALESCE(NEW.poll_votes,'[]'::jsonb) || COALESCE(NEW.poll_options,'[]'::jsonb)) x;

  -- só cria o alerta na transição de 0 → tem voto ruim (evita duplicar se
  -- o mesmo resultado for regravado de novo)
  IF new_ruim > 0 AND old_ruim = 0 THEN
    SELECT id, instancia, contact_nome, contact_numero INTO appt
      FROM public.appointments WHERE id = NEW.poll_appointment_id;
    IF FOUND THEN
      INSERT INTO public.alerts (instancia, mensagem, numero)
      VALUES (
        appt.instancia,
        'Paciente ' || COALESCE(NULLIF(btrim(appt.contact_nome), ''), 'sem nome')
          || ' avaliou a consulta como regular/ruim na pesquisa de satisfação. Vale ligar antes que vire avaliação negativa no Google.',
        appt.contact_numero || '@s.whatsapp.net'
      );
    END IF;
  END IF;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_satisfaction_poll_vote ON public.mensagens_geral;
CREATE TRIGGER trg_satisfaction_poll_vote
  AFTER UPDATE OF poll_votes, poll_options ON public.mensagens_geral
  FOR EACH ROW
  WHEN (NEW.poll_kind = 'satisfacao' AND NEW.poll_appointment_id IS NOT NULL)
  EXECUTE FUNCTION public.apply_satisfaction_poll_vote();

-- ─────────────────────────────────────────────────────────────────
-- 3) Pesquisa mensal com o link do Google — por PACIENTE, não por
--    agendamento. Só dispara se a clínica configurou
--    companies.google_review_url. Mensagem de texto simples (não é
--    enquete — a avaliação acontece DENTRO do Google, fora do app).
-- ─────────────────────────────────────────────────────────────────
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
  session_id text;
  payload jsonb;
BEGIN
  IF NOT pg_try_advisory_xact_lock(778902) THEN
    RETURN 0;
  END IF;

  FOR r IN
    SELECT DISTINCT ON (sc.id)
      sc.id, sc.numero, sc.nome, sc.instancia, sc.last_review_request_at,
      c.api_instancia, c.name AS company_name, c.google_review_url,
      COALESCE(NULLIF(c.timezone, ''), '-03:00') AS tz_offset
    FROM public.saved_contacts sc
    JOIN public.companies c ON c.instance = sc.instancia
    JOIN public.appointments a ON a.instancia = sc.instancia
      AND regexp_replace(a.contact_numero, '\D', '', 'g') = regexp_replace(sc.numero, '\D', '', 'g')
    WHERE c.google_review_url IS NOT NULL AND c.google_review_url <> ''
      AND a.status = 'concluido'
      AND a.starts_at > now() - interval '12 months'   -- só paciente ativo (visitou no último ano)
      AND (sc.last_review_request_at IS NULL OR sc.last_review_request_at < now() - interval '30 days')
      AND sc.numero IS NOT NULL AND sc.numero <> ''
  LOOP
    msg := format(
      'Olá %s! 👋 Esperamos que esteja tudo bem. Se puder, deixa sua avaliação sobre o atendimento — ajuda muito a gente: %s',
      COALESCE(NULLIF(btrim(r.nome), ''), 'tudo bem'), r.google_review_url);

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
  END LOOP;

  RETURN cnt;
END;
$$;

GRANT EXECUTE ON FUNCTION public.process_monthly_review_requests() TO service_role;

-- ─────────────────────────────────────────────────────────────────
-- Agenda os 2 crons novos (mesmo padrão do lembrete automático,
-- 20260717_schedule_reminders_cron.sql). Requer pg_cron + pg_net já
-- habilitados (já estão, o lembrete automático depende deles).
-- ─────────────────────────────────────────────────────────────────
DO $$ BEGIN PERFORM cron.unschedule('appointment-followups'); EXCEPTION WHEN OTHERS THEN NULL; END $$;
SELECT cron.schedule(
  'appointment-followups',
  '*/15 * * * *',
  $$ SELECT public.process_appointment_followups(); $$
);

DO $$ BEGIN PERFORM cron.unschedule('monthly-review-requests'); EXCEPTION WHEN OTHERS THEN NULL; END $$;
SELECT cron.schedule(
  'monthly-review-requests',
  '0 13 * * *',   -- 1x por dia, 13:00 UTC (10h em -03:00) — dentro do horário comercial
  $$ SELECT public.process_monthly_review_requests(); $$
);
