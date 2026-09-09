-- ==============================================================
-- Deixa a mensagem do follow-up e o link do Google editáveis pela
-- própria clínica (antes só dava pra mexer no link, e só pelo painel
-- Super Admin — nada de mensagem customizada em lugar nenhum).
--
-- Colunas novas em companies (as duas nullable — NULL = usa o texto
-- padrão em português que já tava hardcoded nas functions):
--   followup_question_message text  -- pergunta da enquete "como foi a consulta"
--                                     placeholder: {nome}
--   followup_review_message   text  -- mensagem que acompanha o link do Google
--                                     (mandada na hora pra quem respondeu bem,
--                                     e reforçada 1x/mês pra quem não respondeu)
--                                     placeholders: {nome} e {link}
--
-- process_appointment_followups(), apply_satisfaction_poll_vote() e
-- process_monthly_review_requests() passam a checar a coluna da
-- empresa antes de usar o texto padrão.
--
-- Idempotente. Cole no SQL Editor do Supabase.
-- ==============================================================

SET search_path TO public;

ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS followup_question_message text;

ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS followup_review_message text;

-- ─────────────────────────────────────────────────────────────────
-- 1) Pergunta da enquete de satisfação — usa o template da empresa
--    se tiver, senão cai no padrão de sempre.
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
  tmpl       text;
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
      c.api_instancia, c.name AS company_name, c.followup_question_message,
      COALESCE(NULLIF(c.timezone, ''), '-03:00') AS tz_offset,
      p.name AS prof_name
    FROM public.appointments a
    JOIN public.companies c ON c.instance = a.instancia
    LEFT JOIN public.professionals p ON p.id = a.professional_id
    WHERE a.status = 'concluido'
      AND a.followup_sent_at IS NULL
      AND a.contact_numero IS NOT NULL AND a.contact_numero <> ''
      -- espera 1h depois do fim do horário marcado antes de perguntar
      AND a.starts_at + make_interval(mins => COALESCE(a.duration_minutes, 30)) <= now() - interval '1 hour'
      AND a.starts_at > now() - interval '3 days'
  LOOP
    tmpl := NULLIF(btrim(r.followup_question_message), '');
    IF tmpl IS NOT NULL THEN
      poll_name := regexp_replace(tmpl, '\{nome\}', COALESCE(r.contact_nome, ''), 'gi');
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
  END LOOP;

  RETURN cnt;
END;
$$;

GRANT EXECUTE ON FUNCTION public.process_appointment_followups() TO service_role;

-- ─────────────────────────────────────────────────────────────────
-- 2) Voto Ótima/Boa → manda o link do Google na hora, com o texto
--    customizado da empresa se tiver.
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.apply_satisfaction_poll_vote()
RETURNS trigger LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
DECLARE
  old_ruim integer;
  new_ruim integer;
  old_bom  integer;
  new_bom  integer;
  appt     record;
  comp     record;
  session_id text;
  msg      text;
  tmpl     text;
  payload  jsonb;
BEGIN
  IF NEW.poll_kind IS DISTINCT FROM 'satisfacao' THEN RETURN NEW; END IF;
  IF NEW.poll_appointment_id IS NULL THEN RETURN NEW; END IF;
  IF NEW.poll_votes IS NOT DISTINCT FROM OLD.poll_votes
     AND NEW.poll_options IS NOT DISTINCT FROM OLD.poll_options THEN
    RETURN NEW;
  END IF;

  SELECT
    COALESCE(SUM(CASE WHEN lower(btrim(COALESCE(x->>'option', x->>'optionName', x->>'name',''))) IN ('regular','ruim')
      THEN (CASE WHEN jsonb_typeof(x->'voters')='array' THEN jsonb_array_length(x->'voters') WHEN (x->>'votes') ~ '^\d+$' THEN (x->>'votes')::int ELSE 0 END)
      ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN lower(btrim(COALESCE(x->>'option', x->>'optionName', x->>'name',''))) IN ('ótima','otima','boa')
      THEN (CASE WHEN jsonb_typeof(x->'voters')='array' THEN jsonb_array_length(x->'voters') WHEN (x->>'votes') ~ '^\d+$' THEN (x->>'votes')::int ELSE 0 END)
      ELSE 0 END), 0)
  INTO old_ruim, old_bom
  FROM jsonb_array_elements(COALESCE(OLD.poll_votes,'[]'::jsonb) || COALESCE(OLD.poll_options,'[]'::jsonb)) x;

  SELECT
    COALESCE(SUM(CASE WHEN lower(btrim(COALESCE(x->>'option', x->>'optionName', x->>'name',''))) IN ('regular','ruim')
      THEN (CASE WHEN jsonb_typeof(x->'voters')='array' THEN jsonb_array_length(x->'voters') WHEN (x->>'votes') ~ '^\d+$' THEN (x->>'votes')::int ELSE 0 END)
      ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN lower(btrim(COALESCE(x->>'option', x->>'optionName', x->>'name',''))) IN ('ótima','otima','boa')
      THEN (CASE WHEN jsonb_typeof(x->'voters')='array' THEN jsonb_array_length(x->'voters') WHEN (x->>'votes') ~ '^\d+$' THEN (x->>'votes')::int ELSE 0 END)
      ELSE 0 END), 0)
  INTO new_ruim, new_bom
  FROM jsonb_array_elements(COALESCE(NEW.poll_votes,'[]'::jsonb) || COALESCE(NEW.poll_options,'[]'::jsonb)) x;

  -- Regular/Ruim → alerta pra recepção (igual já era)
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

  -- Ótima/Boa → manda o link do Google NA HORA (se a clínica configurou)
  ELSIF new_bom > 0 AND old_bom = 0 THEN
    SELECT id, instancia, contact_nome, contact_numero INTO appt
      FROM public.appointments WHERE id = NEW.poll_appointment_id;
    IF FOUND THEN
      SELECT google_review_url, api_instancia, name AS company_name, followup_review_message
        INTO comp FROM public.companies WHERE instance = appt.instancia;

      IF comp.google_review_url IS NOT NULL AND comp.google_review_url <> '' THEN
        session_id := appt.contact_numero || '@s.whatsapp.net';
        tmpl := NULLIF(btrim(comp.followup_review_message), '');
        IF tmpl IS NOT NULL THEN
          msg := regexp_replace(
                   regexp_replace(tmpl, '\{nome\}', COALESCE(NULLIF(btrim(appt.contact_nome), ''), 'oi'), 'gi'),
                   '\{link\}', comp.google_review_url, 'gi');
        ELSE
          msg := format(
            'Que ótimo, %s! 😄 Se puder, deixa sua avaliação — ajuda muito a gente: %s',
            COALESCE(NULLIF(btrim(appt.contact_nome), ''), 'oi'), comp.google_review_url);
        END IF;

        INSERT INTO public.mensagens_geral
          (instancia, numero, mensagem, type, "horaLastMessage", created_at, aplicativo)
        VALUES
          (appt.instancia, session_id, msg, 'atendente', to_char(now(), 'HH24:MI'), now(), 'whatsapp');

        payload := jsonb_build_object(
          'message', msg, 'session_id', session_id, 'phone', appt.contact_numero,
          'instancia', appt.instancia, 'api_instancia', comp.api_instancia,
          'company', comp.company_name,
          'sender_name', 'Sistema (Pesquisa de satisfação)', 'sender_email', 'sistema@clinisac');
        BEGIN
          PERFORM net.http_post(
            url := 'https://n8n.nexladesenvolvimento.com.br/webhook/envioNexla',
            body := payload, headers := '{"Content-Type": "application/json"}'::jsonb);
        EXCEPTION WHEN OTHERS THEN
          RAISE NOTICE 'webhook link google fail appt %: %', appt.id, SQLERRM;
        END;

        -- marca o paciente como já pedido — a pesquisa mensal não repete
        -- o pedido pra ele nos próximos 30 dias
        UPDATE public.saved_contacts
           SET last_review_request_at = now()
         WHERE instancia = appt.instancia
           AND regexp_replace(numero, '\D', '', 'g') = regexp_replace(appt.contact_numero, '\D', '', 'g');
      END IF;
    END IF;
  END IF;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RETURN NEW;
END;
$$;

-- ─────────────────────────────────────────────────────────────────
-- 3) Pesquisa mensal (safety net pra quem não respondeu o follow-up
--    individual) — mesmo texto customizado da empresa.
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
  tmpl    text;
  session_id text;
  payload jsonb;
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
      AND a.starts_at > now() - interval '12 months'   -- só paciente ativo (visitou no último ano)
      AND (sc.last_review_request_at IS NULL OR sc.last_review_request_at < now() - interval '30 days')
      AND sc.numero IS NOT NULL AND sc.numero <> ''
  LOOP
    tmpl := NULLIF(btrim(r.followup_review_message), '');
    IF tmpl IS NOT NULL THEN
      msg := regexp_replace(
               regexp_replace(tmpl, '\{nome\}', COALESCE(NULLIF(btrim(r.nome), ''), 'tudo bem'), 'gi'),
               '\{link\}', r.google_review_url, 'gi');
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
  END LOOP;

  RETURN cnt;
END;
$$;

GRANT EXECUTE ON FUNCTION public.process_monthly_review_requests() TO service_role;
