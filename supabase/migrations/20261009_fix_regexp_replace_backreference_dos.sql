-- ══════════════════════════════════════════════════════════════════════════
-- CORREÇÃO — DoS na plataforma inteira via nome de contato em regexp_replace
--
-- CAUSA RAIZ
--   regexp_replace(string, padrao, substituicao, flags) no Postgres: no
--   argumento de SUBSTITUIÇÃO, "\1".."\9" são backreferences (mesmo quando
--   o padrão não tem nenhum grupo de captura) e "\&" significa "o texto
--   todo que casou". Em todo lugar que a gente monta mensagem a partir de
--   template com {nome}/{link}, o nome do contato (que vem do WhatsApp —
--   pushname, ninguém na clínica digitou) ia direto como substituição:
--
--     regexp_replace(tmpl, '\{nome\}', COALESCE(contact_nome, ''), 'gi')
--
--   Um nome de contato contendo barra invertida seguida de dígito (ex.: um
--   pushname "Jo\1o") faz o Postgres tentar resolver um backreference que
--   não existe (o padrão '\{nome\}' não tem grupo de captura nenhum) e
--   estoura erro em tempo de execução.
--
--   process_appointment_reminders()/process_appointment_followups()/
--   process_monthly_review_requests() rodam via pg_cron, cada chamada
--   processando os agendamentos due de TODAS as clínicas num laço só, sem
--   BEGIN/EXCEPTION ao redor do corpo do laço (só o net.http_post tinha
--   try/catch). Uma linha com nome "venenoso" estoura o laço inteiro,
--   derruba a transação da function inteira (desfaz inclusive linhas de
--   OUTRAS clínicas já processadas com sucesso nessa mesma chamada) e,
--   como o appointment nunca fica marcado como "já mandou", a próxima
--   execução do cron tenta de novo essa mesma linha e quebra de novo —
--   trava o lembrete/follow-up/pesquisa de avaliação pra TODAS as
--   clínicas da plataforma, indefinidamente, até alguém achar e arrumar.
--
-- A CORREÇÃO (achada numa auditoria de segurança pedida pelo usuário)
--   1) Troca regexp_replace() por replace() simples (sem regex nenhum) nos
--      placeholders — replace() nunca interpreta nada de especial na
--      substituição (sem backreference, sem \&), então o nome do contato
--      pode conter qualquer caractere sem quebrar a function. Único
--      efeito colateral: replace() é case-sensitive, e o regexp_replace
--      antigo usava 'gi' (aceitava {Nome}/{NOME} em templates digitados
--      por quem administra a clínica). Pra não perder isso, troca as 3
--      variações de caixa mais prováveis (minúsculo/Capitalizado/
--      MAIÚSCULO) em vez de só uma.
--   2) Embrulha o corpo de cada iteração do laço nas 3 functions batch
--      (reminders/followups/monthly-review) em BEGIN/EXCEPTION — uma
--      linha com qualquer problema (esse ou outro futuro) loga e pula pra
--      próxima, em vez de derrubar o lote inteiro de todas as clínicas.
--
-- Idempotente.
-- ══════════════════════════════════════════════════════════════════════════

SET search_path TO public;

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
    -- Uma linha com qualquer erro (nome com caractere problemático, etc.)
    -- loga e pula — não derruba o lote das outras clínicas nem desfaz o
    -- que já foi processado com sucesso nesta mesma chamada.
    BEGIN
      appt_local := r.starts_at AT TIME ZONE (r.tz_offset)::interval;

      tmpl := COALESCE(NULLIF(btrim(r.appt_msg), ''), NULLIF(btrim(r.proc_msg), ''));
      IF tmpl IS NOT NULL THEN
        -- replace() puro (sem regex): nunca interpreta \1../9 nem \& do
        -- nome do contato como backreference. Troca as 3 variações de
        -- caixa mais prováveis pra manter o que o 'gi' do regexp fazia.
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
-- 3) apply_satisfaction_poll_vote — já tinha EXCEPTION WHEN OTHERS no nível
--    do trigger inteiro (menor severidade: só essa linha de voto falha em
--    silêncio, não derruba lote de outras clínicas). Só troca pro
--    replace() sem regex mesmo assim, por consistência e robustez.
-- ─────────────────────────────────────────────────────────────────────────
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
          msg := tmpl;
          msg := replace(msg, '{nome}', COALESCE(NULLIF(btrim(appt.contact_nome), ''), 'oi'));
          msg := replace(msg, '{Nome}', COALESCE(NULLIF(btrim(appt.contact_nome), ''), 'oi'));
          msg := replace(msg, '{NOME}', COALESCE(NULLIF(btrim(appt.contact_nome), ''), 'oi'));
          msg := replace(msg, '{link}', comp.google_review_url);
          msg := replace(msg, '{Link}', comp.google_review_url);
          msg := replace(msg, '{LINK}', comp.google_review_url);
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

-- ─────────────────────────────────────────────────────────────────────────
-- 4) process_monthly_review_requests — reforço mensal
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
