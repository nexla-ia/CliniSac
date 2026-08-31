-- ============================================================================
-- CliniSac — SETUP COMPLETO DO BANCO (rode UMA vez num projeto Supabase NOVO)
-- = schema base (23/06) + todos os deltas até hoje, em ordem.
-- Cole tudo no SQL Editor do projeto novo. Se algum trecho der erro, me
-- manda a mensagem que eu corrijo o ponto específico.
-- ============================================================================

-- ==============================================================
-- MED MAG — Schema Consolidado
-- Gerado em: 2026-06-23
-- Para usar: Cole tudo no Supabase SQL Editor de um projeto novo
-- ==============================================================


-- ── 00000000000000_base_schema.sql ─────────────────────────────────────────────────────────

--
-- PostgreSQL database dump
--


-- Dumped from database version 17.6
-- Dumped by pg_dump version 18.3

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

-- CREATE SCHEMA public; -- already exists in Supabase


--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'standard public schema';


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: agendas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.agendas (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    instancia text NOT NULL,
    name text NOT NULL,
    color text DEFAULT '#2563EB'::text,
    working_days integer[] DEFAULT '{1,2,3,4,5}'::integer[],
    start_time time without time zone DEFAULT '08:00:00'::time without time zone,
    end_time time without time zone DEFAULT '18:00:00'::time without time zone,
    slot_minutes integer DEFAULT 30,
    active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now(),
    professional_id uuid
);


--
-- Name: api_agendas_list(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.api_agendas_list(p_instancia text) RETURNS SETOF public.agendas
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT * FROM agendas WHERE instancia = p_instancia ORDER BY name ASC;
$$;


--
-- Name: alerts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.alerts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    instancia text NOT NULL,
    mensagem text NOT NULL,
    resolved boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    numero text,
    forwarded_to_user_id uuid,
    forwarded_to_name text,
    forwarded_by_name text
);


--
-- Name: api_alert_create(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.api_alert_create(p_data jsonb) RETURNS public.alerts
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE v_row alerts;
BEGIN
  INSERT INTO alerts (instancia, numero, mensagem, resolved)
  VALUES (
    p_data->>'instancia', p_data->>'numero', p_data->>'mensagem',
    COALESCE((p_data->>'resolved')::boolean, false)
  )
  RETURNING * INTO v_row;
  RETURN v_row;
END $$;


--
-- Name: api_alert_resolve(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.api_alert_resolve(p_id uuid) RETURNS public.alerts
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE v_row alerts;
BEGIN
  UPDATE alerts SET resolved = true WHERE id = p_id RETURNING * INTO v_row;
  RETURN v_row;
END $$;


--
-- Name: api_alerts_pending(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.api_alerts_pending(p_instancia text) RETURNS SETOF public.alerts
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT * FROM alerts
   WHERE instancia = p_instancia AND resolved = false
   ORDER BY created_at DESC;
$$;


--
-- Name: appointments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.appointments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    agenda_id uuid,
    instancia text NOT NULL,
    contact_numero text,
    contact_nome text NOT NULL,
    starts_at timestamp with time zone NOT NULL,
    duration_minutes integer DEFAULT 30,
    status text DEFAULT 'agendado'::text,
    notes text,
    created_by_email text,
    created_at timestamp with time zone DEFAULT now(),
    professional_id uuid,
    procedure_id uuid,
    insurance_plan_id uuid,
    price numeric(10,2),
    payment_status text DEFAULT 'pendente'::text,
    paid_at timestamp with time zone
);


--
-- Name: api_appointment_create(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.api_appointment_create(p_data jsonb) RETURNS public.appointments
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE v_row appointments;
BEGIN
  INSERT INTO appointments (
    instancia, agenda_id, professional_id, procedure_id, insurance_plan_id,
    contact_nome, contact_numero, starts_at, duration_minutes, status,
    payment_status, price, notes
  ) VALUES (
    p_data->>'instancia',
    NULLIF(p_data->>'agenda_id','')::uuid,
    NULLIF(p_data->>'professional_id','')::uuid,
    NULLIF(p_data->>'procedure_id','')::uuid,
    NULLIF(p_data->>'insurance_plan_id','')::uuid,
    p_data->>'contact_nome', p_data->>'contact_numero',
    (p_data->>'starts_at')::timestamptz,
    COALESCE((p_data->>'duration_minutes')::int, 30),
    COALESCE(p_data->>'status', 'agendado'),
    COALESCE(p_data->>'payment_status', 'pendente'),
    NULLIF(p_data->>'price','')::numeric,
    p_data->>'notes'
  )
  RETURNING * INTO v_row;
  RETURN v_row;
END $$;


--
-- Name: api_appointment_update_status(uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.api_appointment_update_status(p_id uuid, p_status text, p_payment_status text DEFAULT NULL::text) RETURNS public.appointments
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE v_row appointments;
BEGIN
  UPDATE appointments SET
    status         = p_status,
    payment_status = COALESCE(p_payment_status, payment_status),
    paid_at        = CASE WHEN p_payment_status = 'pago' THEN now() ELSE paid_at END
  WHERE id = p_id
  RETURNING * INTO v_row;
  RETURN v_row;
END $$;


--
-- Name: api_appointments_busy_slots(text, uuid, timestamp with time zone, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.api_appointments_busy_slots(p_instancia text, p_professional_id uuid, p_from timestamp with time zone, p_to timestamp with time zone) RETURNS TABLE(starts_at timestamp with time zone, duration_minutes integer)
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT starts_at, duration_minutes FROM appointments
   WHERE instancia = p_instancia
     AND professional_id = p_professional_id
     AND status <> 'cancelado'
     AND starts_at >= p_from
     AND starts_at <  p_to
   ORDER BY starts_at ASC;
$$;


--
-- Name: api_appointments_by_date(text, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.api_appointments_by_date(p_instancia text, p_date date) RETURNS SETOF public.appointments
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT * FROM appointments
   WHERE instancia = p_instancia
     AND starts_at >= p_date::timestamptz
     AND starts_at <  (p_date + INTERVAL '1 day')::timestamptz
   ORDER BY starts_at ASC;
$$;


--
-- Name: api_appointments_by_phone(text, text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.api_appointments_by_phone(p_instancia text, p_phone text, p_limit integer DEFAULT 10) RETURNS SETOF public.appointments
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT * FROM appointments
   WHERE instancia = p_instancia AND contact_numero = p_phone
   ORDER BY starts_at DESC
   LIMIT p_limit;
$$;


--
-- Name: conversations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.conversations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    session_id text NOT NULL,
    instancia text NOT NULL,
    reason text,
    closed_at timestamp with time zone DEFAULT now()
);


--
-- Name: api_conversation_close(text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.api_conversation_close(p_session_id text, p_instancia text, p_reason text) RETURNS public.conversations
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE v_row conversations;
BEGIN
  INSERT INTO conversations (session_id, instancia, reason, closed_at)
  VALUES (p_session_id, p_instancia, p_reason, now())
  RETURNING * INTO v_row;
  BEGIN
    DELETE FROM attendances WHERE numero = p_session_id AND instancia = p_instancia;
  EXCEPTION WHEN undefined_table THEN NULL;
  END;
  RETURN v_row;
END $$;


--
-- Name: api_conversation_status(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.api_conversation_status(p_session_id text, p_instancia text) RETURNS jsonb
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT jsonb_build_object(
    'is_open', NOT EXISTS (
      SELECT 1 FROM conversations
       WHERE session_id = p_session_id AND instancia = p_instancia
    ),
    'last_close', (
      SELECT row_to_json(c) FROM conversations c
       WHERE c.session_id = p_session_id AND c.instancia = p_instancia
       ORDER BY c.closed_at DESC LIMIT 1
    )
  );
$$;


--
-- Name: insurance_plans; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.insurance_plans (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    instancia text NOT NULL,
    name text NOT NULL,
    active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: api_insurance_plans_list(text, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.api_insurance_plans_list(p_instancia text, p_only_active boolean DEFAULT true) RETURNS SETOF public.insurance_plans
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT * FROM insurance_plans
   WHERE instancia = p_instancia
     AND (NOT p_only_active OR active = true)
   ORDER BY name ASC;
$$;


--
-- Name: kanban_cards; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.kanban_cards (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    column_id uuid,
    instancia text NOT NULL,
    title text NOT NULL,
    description text,
    assigned_user_id uuid,
    assigned_user_name text,
    due_date date,
    priority text DEFAULT 'normal'::text,
    "position" double precision DEFAULT 0,
    created_by_email text,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: api_kanban_card_create(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.api_kanban_card_create(p_data jsonb) RETURNS public.kanban_cards
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE v_row kanban_cards;
BEGIN
  INSERT INTO kanban_cards (
    instancia, column_id, title, description, priority, due_date, position,
    assigned_user_id, assigned_user_name
  ) VALUES (
    p_data->>'instancia',
    NULLIF(p_data->>'column_id','')::uuid,
    p_data->>'title', p_data->>'description',
    COALESCE(p_data->>'priority', 'normal'),
    NULLIF(p_data->>'due_date','')::date,
    COALESCE((p_data->>'position')::int, 0),
    NULLIF(p_data->>'assigned_user_id','')::uuid,
    p_data->>'assigned_user_name'
  )
  RETURNING * INTO v_row;
  RETURN v_row;
END $$;


--
-- Name: api_kanban_cards(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.api_kanban_cards(p_instancia text) RETURNS SETOF public.kanban_cards
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT * FROM kanban_cards
   WHERE instancia = p_instancia ORDER BY position ASC;
$$;


--
-- Name: kanban_columns; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.kanban_columns (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    instancia text NOT NULL,
    name text NOT NULL,
    color text DEFAULT '#6B7280'::text,
    "position" double precision DEFAULT 0,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: api_kanban_columns(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.api_kanban_columns(p_instancia text) RETURNS SETOF public.kanban_columns
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT * FROM kanban_columns
   WHERE instancia = p_instancia ORDER BY position ASC;
$$;


--
-- Name: mensagens_geral; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mensagens_geral (
    id bigint NOT NULL,
    nome text,
    instancia text,
    numero text,
    mensagem text,
    "horaLastMessage" text,
    base64 text,
    type text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    id_mensagem text,
    aplicativo text DEFAULT 'whatsapp'::text,
    recipient_id text
);


--
-- Name: api_message_create(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.api_message_create(p_data jsonb) RETURNS public.mensagens_geral
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE v_row mensagens_geral;
BEGIN
  INSERT INTO mensagens_geral (instancia, numero, mensagem, type, "horaLastMessage")
  VALUES (
    p_data->>'instancia', p_data->>'numero', p_data->>'mensagem',
    COALESCE(p_data->>'type', 'ia'),
    COALESCE(p_data->>'horaLastMessage', to_char(now(), 'DD/MM/YYYY HH24:MI:SS'))
  )
  RETURNING * INTO v_row;
  RETURN v_row;
END $$;


--
-- Name: api_messages_by_phone(text, text, integer, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.api_messages_by_phone(p_instancia text, p_numero text, p_limit integer DEFAULT 20, p_only_client boolean DEFAULT false) RETURNS SETOF public.mensagens_geral
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT * FROM mensagens_geral
   WHERE instancia = p_instancia
     AND numero = p_numero
     AND (NOT p_only_client OR LOWER(type) = 'cliente')
   ORDER BY id DESC
   LIMIT p_limit;
$$;


--
-- Name: saved_contacts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.saved_contacts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    numero text NOT NULL,
    instancia text NOT NULL,
    nome text NOT NULL,
    notes text,
    created_by_email text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    birth_date date,
    cpf text,
    email text,
    address text,
    insurance_plan_id uuid,
    insurance_card text,
    photo text,
    phone_secondary text,
    gender text,
    profession text,
    rg text,
    emergency_contact text,
    emergency_phone text,
    allergies text,
    chronic_conditions text,
    medications text,
    clinical_notes text,
    nome_social text,
    marital_status text,
    blood_type text,
    weight numeric(5,2),
    height numeric(4,2),
    referral_source text,
    guardian_name text,
    guardian_phone text,
    ad_source text,
    ad_title text,
    ad_body text,
    ad_thumbnail_url text,
    ad_media_url text,
    ad_click_id text,
    ad_captured_at timestamp with time zone,
    ad_platform text,
    ad_source_type text,
    ad_entry_point text,
    ad_source_url text
);


--
-- Name: api_paciente_by_phone(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.api_paciente_by_phone(p_instancia text, p_numero text) RETURNS SETOF public.saved_contacts
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT * FROM saved_contacts
   WHERE instancia = p_instancia AND numero = p_numero
   LIMIT 1;
$$;


--
-- Name: api_paciente_create(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.api_paciente_create(p_data jsonb) RETURNS public.saved_contacts
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE v_row saved_contacts;
BEGIN
  INSERT INTO saved_contacts (
    instancia, nome, numero, birth_date, gender, email, phone_secondary,
    address, cpf, rg, profession, nome_social, marital_status, blood_type,
    weight, height, guardian_name, guardian_phone, insurance_plan_id,
    insurance_card, allergies, chronic_conditions, medications, clinical_notes,
    referral_source, photo, emergency_contact, emergency_phone, notes
  ) VALUES (
    p_data->>'instancia', p_data->>'nome', p_data->>'numero',
    NULLIF(p_data->>'birth_date','')::date, p_data->>'gender', p_data->>'email',
    p_data->>'phone_secondary', p_data->>'address', p_data->>'cpf',
    p_data->>'rg', p_data->>'profession', p_data->>'nome_social',
    p_data->>'marital_status', p_data->>'blood_type',
    NULLIF(p_data->>'weight','')::numeric, NULLIF(p_data->>'height','')::numeric,
    p_data->>'guardian_name', p_data->>'guardian_phone',
    NULLIF(p_data->>'insurance_plan_id','')::uuid, p_data->>'insurance_card',
    p_data->>'allergies', p_data->>'chronic_conditions', p_data->>'medications',
    p_data->>'clinical_notes', p_data->>'referral_source', p_data->>'photo',
    p_data->>'emergency_contact', p_data->>'emergency_phone', p_data->>'notes'
  )
  RETURNING * INTO v_row;
  RETURN v_row;
END $$;


--
-- Name: api_paciente_delete(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.api_paciente_delete(p_id uuid) RETURNS boolean
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  DELETE FROM saved_contacts WHERE id = p_id;
  SELECT TRUE;
$$;


--
-- Name: api_paciente_update(uuid, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.api_paciente_update(p_id uuid, p_data jsonb) RETURNS public.saved_contacts
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE v_row saved_contacts;
BEGIN
  UPDATE saved_contacts SET
    nome              = COALESCE(p_data->>'nome', nome),
    birth_date        = COALESCE(NULLIF(p_data->>'birth_date','')::date, birth_date),
    gender            = COALESCE(p_data->>'gender', gender),
    email             = COALESCE(p_data->>'email', email),
    phone_secondary   = COALESCE(p_data->>'phone_secondary', phone_secondary),
    address           = COALESCE(p_data->>'address', address),
    cpf               = COALESCE(p_data->>'cpf', cpf),
    rg                = COALESCE(p_data->>'rg', rg),
    profession        = COALESCE(p_data->>'profession', profession),
    nome_social       = COALESCE(p_data->>'nome_social', nome_social),
    marital_status    = COALESCE(p_data->>'marital_status', marital_status),
    blood_type        = COALESCE(p_data->>'blood_type', blood_type),
    weight            = COALESCE(NULLIF(p_data->>'weight','')::numeric, weight),
    height            = COALESCE(NULLIF(p_data->>'height','')::numeric, height),
    guardian_name     = COALESCE(p_data->>'guardian_name', guardian_name),
    guardian_phone    = COALESCE(p_data->>'guardian_phone', guardian_phone),
    insurance_plan_id = COALESCE(NULLIF(p_data->>'insurance_plan_id','')::uuid, insurance_plan_id),
    insurance_card    = COALESCE(p_data->>'insurance_card', insurance_card),
    allergies         = COALESCE(p_data->>'allergies', allergies),
    chronic_conditions = COALESCE(p_data->>'chronic_conditions', chronic_conditions),
    medications       = COALESCE(p_data->>'medications', medications),
    clinical_notes    = COALESCE(p_data->>'clinical_notes', clinical_notes),
    referral_source   = COALESCE(p_data->>'referral_source', referral_source),
    photo             = COALESCE(p_data->>'photo', photo),
    emergency_contact = COALESCE(p_data->>'emergency_contact', emergency_contact),
    emergency_phone   = COALESCE(p_data->>'emergency_phone', emergency_phone),
    notes             = COALESCE(p_data->>'notes', notes)
  WHERE id = p_id
  RETURNING * INTO v_row;
  RETURN v_row;
END $$;


--
-- Name: api_pacientes_list(text, text, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.api_pacientes_list(p_instancia text, p_search text DEFAULT NULL::text, p_limit integer DEFAULT 100, p_offset integer DEFAULT 0) RETURNS SETOF public.saved_contacts
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT * FROM saved_contacts
   WHERE instancia = p_instancia
     AND (p_search IS NULL
          OR nome ILIKE '%' || p_search || '%'
          OR numero ILIKE '%' || p_search || '%'
          OR cpf ILIKE '%' || p_search || '%')
   ORDER BY nome ASC
   LIMIT p_limit OFFSET p_offset;
$$;


--
-- Name: api_procedure_price(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.api_procedure_price(p_procedure_id uuid, p_insurance_plan_id uuid DEFAULT NULL::uuid) RETURNS jsonb
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT jsonb_build_object(
    'price', COALESCE(
      (SELECT price FROM procedure_prices
        WHERE procedure_id = p_procedure_id
          AND insurance_plan_id = p_insurance_plan_id),
      (SELECT price_particular FROM procedures WHERE id = p_procedure_id)
    ),
    'is_default', (
      SELECT NOT EXISTS (
        SELECT 1 FROM procedure_prices
         WHERE procedure_id = p_procedure_id
           AND insurance_plan_id = p_insurance_plan_id
      )
    )
  );
$$;


--
-- Name: procedures; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.procedures (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    instancia text NOT NULL,
    name text NOT NULL,
    type text DEFAULT 'consulta'::text,
    duration_minutes integer DEFAULT 30,
    price_particular numeric(10,2) DEFAULT 0,
    professional_id uuid,
    active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: api_procedures_list(text, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.api_procedures_list(p_instancia text, p_only_active boolean DEFAULT true) RETURNS SETOF public.procedures
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT * FROM procedures
   WHERE instancia = p_instancia
     AND (NOT p_only_active OR active = true)
   ORDER BY name ASC;
$$;


--
-- Name: professionals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.professionals (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    instancia text NOT NULL,
    name text NOT NULL,
    specialty text,
    registration text,
    color text DEFAULT '#2563EB'::text,
    active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now(),
    working_days integer[] DEFAULT '{1,2,3,4,5}'::integer[],
    start_time time without time zone DEFAULT '08:00:00'::time without time zone,
    end_time time without time zone DEFAULT '18:00:00'::time without time zone,
    break_start time without time zone,
    break_end time without time zone
);


--
-- Name: api_professionals_list(text, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.api_professionals_list(p_instancia text, p_only_active boolean DEFAULT true) RETURNS SETOF public.professionals
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT * FROM professionals
   WHERE instancia = p_instancia
     AND (NOT p_only_active OR active = true)
   ORDER BY name ASC;
$$;


--
-- Name: auto_close_inactive_conversations(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.auto_close_inactive_conversations() RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $_$
declare
  comp record;
  sess record;
  last_msg timestamptz;
begin
  for comp in
    select instance, history_table
    from public.companies
    where history_table is not null and active = true
  loop
    for sess in execute format(
      'select distinct session_id from public.%I
       where session_id not in (
         select session_id from public.conversations where instancia = $1
       )',
      comp.history_table
    ) using comp.instance
    loop
      execute format(
        'select max(data) from public.%I where session_id = $1',
        comp.history_table
      ) into last_msg using sess.session_id;

      if last_msg is not null and last_msg < now() - interval '1 hour' then
        insert into public.conversations (session_id, instancia, reason, closed_at)
        values (sess.session_id, comp.instance, 'encerrado_auto', now())
        on conflict do nothing;
      end if;
    end loop;
  end loop;
end;
$_$;


--
-- Name: create_user(text, text, text, text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_user(p_name text, p_email text, p_password text, p_role text, p_company_id uuid) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
declare new_id uuid;
begin
  insert into public.users (name, email, password_hash, role, company_id)
  values (p_name, p_email, crypt(p_password, gen_salt('bf')), p_role, p_company_id)
  returning id into new_id;
  return new_id;
end;
$$;


--
-- Name: delete_user(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.delete_user(p_user_id uuid) RETURNS json
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_user_email text;
BEGIN
  SELECT email INTO v_user_email FROM users WHERE id = p_user_id;

  IF v_user_email IS NULL THEN
    RETURN json_build_object('ok', false, 'error', 'Usuário não encontrado');
  END IF;

  -- Limpa vínculos best-effort (ignora se a tabela/coluna não existir ainda)
  BEGIN
    DELETE FROM sector_members WHERE user_id = p_user_id;
  EXCEPTION WHEN undefined_table THEN NULL;
  END;

  BEGIN
    UPDATE kanban_cards SET assignee_id = NULL WHERE assignee_id = p_user_id;
  EXCEPTION WHEN undefined_table OR undefined_column THEN NULL;
  END;

  BEGIN
    UPDATE attendances SET user_id = NULL WHERE user_id = p_user_id;
  EXCEPTION WHEN undefined_table OR undefined_column THEN NULL;
  END;

  BEGIN
    UPDATE alerts SET forwarded_to = NULL WHERE forwarded_to = p_user_id;
  EXCEPTION WHEN undefined_table OR undefined_column THEN NULL;
  END;

  DELETE FROM users WHERE id = p_user_id;

  RETURN json_build_object('ok', true, 'email', v_user_email);
END;
$$;


--
-- Name: ensure_table_setup(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ensure_table_setup(p_table text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
begin
  -- Habilita RLS
  execute format('alter table public.%I enable row level security', p_table);

  -- Cria política de leitura (idempotente)
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = p_table and policyname = 'allow_read'
  ) then
    execute format(
      'create policy allow_read on public.%I for select using (true)', p_table
    );
  end if;

  -- Adiciona à publicação Realtime (ignora erro se já existir)
  begin
    execute format('alter publication supabase_realtime add table public.%I', p_table);
  exception when others then null;
  end;

  -- Cria trigger para reabrir sessão quando chegar nova mensagem
  if not exists (
    select 1 from pg_trigger
    where tgname = 'trg_reopen_session'
    and tgrelid = (quote_ident(p_table))::regclass
  ) then
    execute format(
      'create trigger trg_reopen_session after insert on public.%I
       for each row execute function reopen_session_on_new_message()', p_table
    );
  end if;
end;
$$;


--
-- Name: insert_alert(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.insert_alert(instancia text, mensagem text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
declare new_id uuid;
begin
  insert into public.alerts (instancia, mensagem)
  values (instancia, mensagem)
  returning id into new_id;
  return new_id;
end;
$$;


--
-- Name: insert_alert(text, text, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.insert_alert(p_instance text, p_type text, p_contact_name text, p_phone text, p_message text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
declare
  v_company_id uuid;
begin
  select id into v_company_id from companies where instance = p_instance;
  if v_company_id is null then
    raise exception 'Instância não encontrada: %', p_instance;
  end if;

  insert into alerts (company_id, type, contact_name, phone, message)
  values (v_company_id, p_type, p_contact_name, p_phone, p_message);
end;
$$;


--
-- Name: login_user(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.login_user(p_email text, p_password text) RETURNS TABLE(id uuid, name text, email text, role text, active boolean, company_id uuid)
    LANGUAGE sql SECURITY DEFINER
    AS $$
  select id, name, email, role, active, company_id
  from public.users
  where email = p_email
    and password_hash = crypt(p_password, password_hash)
    and active = true;
$$;


--
-- Name: mark_company_paid(uuid, numeric, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.mark_company_paid(p_company_id uuid, p_amount numeric DEFAULT NULL::numeric, p_payment_method text DEFAULT NULL::text, p_notes text DEFAULT NULL::text) RETURNS json
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_company record;
  v_amount numeric;
  v_due date;
  v_next date;
BEGIN
  SELECT * INTO v_company FROM companies WHERE id = p_company_id;
  IF v_company IS NULL THEN
    RETURN json_build_object('ok', false, 'error', 'Empresa não encontrada');
  END IF;

  v_amount := COALESCE(p_amount, v_company.billing_amount);
  IF v_amount IS NULL OR v_amount <= 0 THEN
    RETURN json_build_object('ok', false, 'error', 'Valor da mensalidade não definido');
  END IF;

  -- Vencimento sendo pago: usa next_due_date se setado, senão calcula deste mês
  v_due := COALESCE(
    v_company.next_due_date,
    date_trunc('month', CURRENT_DATE)::date + (COALESCE(v_company.billing_day, 5) - 1)
  );

  -- Próximo vencimento: 1 mês depois
  v_next := (v_due + INTERVAL '1 month')::date;

  -- Insere invoice paga
  INSERT INTO invoices (company_id, amount, due_date, paid_at, payment_method, notes)
  VALUES (p_company_id, v_amount, v_due, now(), p_payment_method, p_notes);

  -- Avança next_due_date e desbloqueia (caso estivesse bloqueado)
  UPDATE companies
     SET next_due_date = v_next,
         billing_blocked = false
   WHERE id = p_company_id;

  RETURN json_build_object('ok', true, 'next_due_date', v_next);
END;
$$;


--
-- Name: n8n_clear_mensagens(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.n8n_clear_mensagens() RETURNS json
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
  v_count bigint;
BEGIN
  SELECT COUNT(*) INTO v_count FROM public.mensagens;

  TRUNCATE TABLE public.mensagens RESTART IDENTITY CASCADE;

  RETURN json_build_object(
    'ok', true,
    'deleted_before', v_count
  );
END;
$$;


--
-- Name: reopen_session_on_new_message(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.reopen_session_on_new_message() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
declare v_session_id text;
begin
  IF TG_TABLE_NAME = 'mensagens_geral' THEN
    v_session_id := NEW.numero;
  ELSE
    v_session_id := NEW.session_id;
  END IF;
  if v_session_id is not null then
    delete from public.conversations where session_id = v_session_id;
  end if;
  return NEW;
end; $$;


--
-- Name: send_mensagem_geral(text, text, text, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.send_mensagem_geral(p_instancia text, p_numero text, p_mensagem text, p_type text, p_hora text, p_base64 text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
  INSERT INTO public.mensagens_geral
    (instancia, numero, mensagem, type, "horaLastMessage", base64, created_at)
  VALUES
    (p_instancia, p_numero, p_mensagem, p_type, p_hora, p_base64, now());
END;
$$;


--
-- Name: support_bump_ticket(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.support_bump_ticket() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  UPDATE support_tickets
     SET last_message_at = NEW.created_at,
         last_sender     = NEW.sender_type,
         status          = CASE
           WHEN NEW.sender_type = 'adm'     AND status = 'open'    THEN 'answered'
           WHEN NEW.sender_type = 'company' AND status = 'closed'  THEN 'answered'
           WHEN NEW.sender_type = 'company' AND status = 'answered' THEN 'open'
           ELSE status
         END
   WHERE id = NEW.ticket_id;
  RETURN NEW;
END;
$$;


--
-- Name: update_user_password(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_user_password(p_user_id uuid, p_password text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
begin
  update public.users
  set password_hash = crypt(p_password, gen_salt('bf'))
  where id = p_user_id;
end;
$$;


--
-- Name: attendances; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.attendances (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    numero text NOT NULL,
    instancia text NOT NULL,
    sector_id uuid,
    sector_name text,
    sector_color text,
    attendant_name text,
    attendant_email text,
    assumed_at timestamp with time zone DEFAULT now()
);


--
-- Name: b2b-controleCliente; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."b2b-controleCliente" (
    "Identificador" bigint,
    "Nome" text,
    "Número do telefone" text,
    "E-mail" text,
    "Gênero" text,
    "Ativo" text,
    "Verificado" text,
    "App" text,
    "Data de nascimento" text,
    "Tipo de documento" text,
    "Documento" text,
    "Como nos conheceu?" text,
    "Data de desbloqueio da agenda" text,
    "Rua" text,
    "Número" text,
    "Complemento" text,
    "Bairro" text,
    "Cidade" text,
    "Estado" text,
    "Cep" text,
    "Observação" text,
    "Status de assinante" text,
    "Criando em" text,
    "Último atendimento" text,
    "Unidades" text,
    "EnvioMensagem?" text,
    semanal boolean DEFAULT false,
    id integer NOT NULL
);


--
-- Name: b2b-controleCliente_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public."b2b-controleCliente_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: b2b-controleCliente_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public."b2b-controleCliente_id_seq" OWNED BY public."b2b-controleCliente".id;


--
-- Name: b2b-controlecliente; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."b2b-controlecliente" (
    id bigint NOT NULL,
    "Nome" text,
    "Número do telefone" text,
    "E-mail" text,
    "Gênero" text,
    "Ativo" text,
    "Verificado" text,
    "App" text,
    "Data de nascimento" text,
    "Tipo de documento" text,
    "Documento" text,
    "Como nos conheceu?" text,
    "Data de desbloqueio da agenda" text,
    "Rua" text,
    "Número" text,
    "Complemento" text,
    "Bairro" text,
    "Cidade" text,
    "Estado" text,
    "Cep" text,
    "Observação" text,
    "Status de assinante" text,
    "Criando em" text,
    "Último atendimento" text,
    "Unidades" text,
    "EnvioMensagem?" text,
    semanal boolean DEFAULT false
);


--
-- Name: b2b-controlecliente_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public."b2b-controlecliente_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: b2b-controlecliente_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public."b2b-controlecliente_id_seq" OWNED BY public."b2b-controlecliente".id;


--
-- Name: clientes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.clientes (
    id bigint NOT NULL,
    nome text,
    numero text,
    instancia text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    primeiro_contato text,
    ultima_mensagem text,
    "data_ultimaMensagem" text,
    classificacao_lead text,
    origem text,
    session_id text,
    ad_source text,
    ad_title text,
    ad_body text,
    ad_thumbnail_url text,
    ad_media_url text,
    ad_click_id text,
    ad_captured_at timestamp with time zone,
    ad_platform text,
    ad_source_type text,
    ad_entry_point text,
    ad_source_url text
);


--
-- Name: clientes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.clientes ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.clientes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: companies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.companies (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    slug text NOT NULL,
    plan text DEFAULT 'Starter'::text NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    contacts_table text,
    history_table text,
    instance text,
    api_instancia text,
    max_users integer DEFAULT 5,
    digisac_url text,
    ai_enabled boolean DEFAULT true,
    evolution_url text,
    extra_users integer DEFAULT 0,
    max_professionals integer,
    max_agendas integer,
    billing_day integer,
    next_due_date date,
    billing_amount numeric(10,2),
    billing_grace_days integer DEFAULT 1,
    billing_reminder_days integer DEFAULT 3,
    billing_blocked boolean DEFAULT false,
    instagram_enabled boolean DEFAULT false NOT NULL,
    instagram_webhook_path text,
    CONSTRAINT companies_plan_check CHECK ((plan = ANY (ARRAY['Starter'::text, 'Pro'::text, 'Business'::text])))
);


--
-- Name: contacts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contacts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    name text NOT NULL,
    phone text NOT NULL,
    status text DEFAULT 'waiting'::text NOT NULL,
    last_msg text,
    unread integer DEFAULT 0 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT contacts_status_check CHECK ((status = ANY (ARRAY['attended'::text, 'waiting'::text, 'help'::text, 'scheduled'::text])))
);


--
-- Name: invoices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.invoices (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    amount numeric(10,2) NOT NULL,
    due_date date NOT NULL,
    paid_at timestamp with time zone,
    payment_method text,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: mensagens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mensagens (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    numero text NOT NULL,
    enviado boolean DEFAULT false NOT NULL,
    recebido boolean DEFAULT false NOT NULL,
    CONSTRAINT ck_flags_not_null CHECK (((enviado IS NOT NULL) AND (recebido IS NOT NULL)))
);


--
-- Name: mensagens_geral_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.mensagens_geral ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.mensagens_geral_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: messages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.messages (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    contact_id uuid NOT NULL,
    "from" text NOT NULL,
    text text NOT NULL,
    type text,
    pending boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT messages_from_check CHECK (("from" = ANY (ARRAY['client'::text, 'ai'::text]))),
    CONSTRAINT messages_type_check CHECK ((type = ANY (ARRAY['normal'::text, 'scheduled'::text, 'help'::text])))
);


--
-- Name: n8n_chat_histories_barbara; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.n8n_chat_histories_barbara (
    id integer NOT NULL,
    session_id character varying(255) NOT NULL,
    message jsonb NOT NULL
);


--
-- Name: n8n_chat_histories_barbara_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.n8n_chat_histories_barbara_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: n8n_chat_histories_barbara_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.n8n_chat_histories_barbara_id_seq OWNED BY public.n8n_chat_histories_barbara.id;


--
-- Name: n8n_chat_histories_clinicanexla; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.n8n_chat_histories_clinicanexla (
    id integer NOT NULL,
    session_id character varying(255) NOT NULL,
    message jsonb NOT NULL
);


--
-- Name: n8n_chat_histories_clinicanexla_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.n8n_chat_histories_clinicanexla_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: n8n_chat_histories_clinicanexla_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.n8n_chat_histories_clinicanexla_id_seq OWNED BY public.n8n_chat_histories_clinicanexla.id;


--
-- Name: n8n_chat_histories_clinicanexlainsta; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.n8n_chat_histories_clinicanexlainsta (
    id integer NOT NULL,
    session_id character varying(255) NOT NULL,
    message jsonb NOT NULL
);


--
-- Name: n8n_chat_histories_clinicanexlainsta_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.n8n_chat_histories_clinicanexlainsta_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: n8n_chat_histories_clinicanexlainsta_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.n8n_chat_histories_clinicanexlainsta_id_seq OWNED BY public.n8n_chat_histories_clinicanexlainsta.id;


--
-- Name: n8n_chat_histories_clinicaolhos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.n8n_chat_histories_clinicaolhos (
    id integer NOT NULL,
    session_id character varying(255) NOT NULL,
    message jsonb NOT NULL,
    data timestamp with time zone DEFAULT (now() AT TIME ZONE 'utc'::text)
);


--
-- Name: n8n_chat_histories_clinicaolhos_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.n8n_chat_histories_clinicaolhos_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: n8n_chat_histories_clinicaolhos_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.n8n_chat_histories_clinicaolhos_id_seq OWNED BY public.n8n_chat_histories_clinicaolhos.id;


--
-- Name: n8n_chat_histories_etuany; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.n8n_chat_histories_etuany (
    id integer NOT NULL,
    session_id character varying(255) NOT NULL,
    message jsonb NOT NULL
);


--
-- Name: n8n_chat_histories_etuany_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.n8n_chat_histories_etuany_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: n8n_chat_histories_etuany_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.n8n_chat_histories_etuany_id_seq OWNED BY public.n8n_chat_histories_etuany.id;


--
-- Name: n8n_chat_histories_gastroimagem; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.n8n_chat_histories_gastroimagem (
    id integer NOT NULL,
    session_id character varying(255) NOT NULL,
    message jsonb NOT NULL,
    data timestamp with time zone DEFAULT (now() AT TIME ZONE 'utc'::text)
);


--
-- Name: n8n_chat_histories_gastroimagem_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.n8n_chat_histories_gastroimagem_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: n8n_chat_histories_gastroimagem_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.n8n_chat_histories_gastroimagem_id_seq OWNED BY public.n8n_chat_histories_gastroimagem.id;


--
-- Name: nexla_historico; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.nexla_historico (
    id bigint NOT NULL,
    session_id text,
    message jsonb,
    data timestamp with time zone DEFAULT now()
);


--
-- Name: nexla_historico_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.nexla_historico_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: nexla_historico_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.nexla_historico_id_seq OWNED BY public.nexla_historico.id;


--
-- Name: pagou_NexlaDaily; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."pagou_NexlaDaily" (
    id bigint NOT NULL,
    "Numero" text,
    "pago_NexaDaily" boolean,
    "Nome" text,
    "data_UltimoPagamento" date,
    disparo_um time without time zone,
    disparo_dois time without time zone,
    disparo_tres time without time zone,
    "Check-in_list" text,
    observacoes_da_pessoa text,
    controle_financas text,
    disparo_quatro time without time zone,
    horario_disparo text,
    "realizados_doDia" text,
    "Observacao_fixa" text
);


--
-- Name: pagou_NexlaDaily_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public."pagou_NexlaDaily" ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."pagou_NexlaDaily_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: procedure_prices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.procedure_prices (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    procedure_id uuid,
    insurance_plan_id uuid,
    price numeric(10,2) NOT NULL,
    instancia text
);


--
-- Name: sector_members; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sector_members (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    sector_id uuid NOT NULL,
    user_id uuid NOT NULL
);


--
-- Name: sectors; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sectors (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    instancia text NOT NULL,
    color text DEFAULT '#2563EB'::text,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: support_messages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.support_messages (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    ticket_id uuid NOT NULL,
    sender_type text NOT NULL,
    sender_user_id uuid,
    sender_name text,
    message text,
    image text,
    read_by_company boolean DEFAULT false,
    read_by_adm boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: support_tickets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.support_tickets (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    subject text NOT NULL,
    status text DEFAULT 'open'::text NOT NULL,
    created_by_user_id uuid,
    created_by_name text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    last_message_at timestamp with time zone DEFAULT now() NOT NULL,
    last_sender text
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    email text NOT NULL,
    password_hash text NOT NULL,
    role text DEFAULT 'admin'::text NOT NULL,
    active boolean DEFAULT true NOT NULL,
    company_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT users_role_check CHECK ((role = ANY (ARRAY['adm'::text, 'admin'::text, 'viewer'::text])))
);


--
-- Name: b2b-controleCliente id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."b2b-controleCliente" ALTER COLUMN id SET DEFAULT nextval('public."b2b-controleCliente_id_seq"'::regclass);


--
-- Name: b2b-controlecliente id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."b2b-controlecliente" ALTER COLUMN id SET DEFAULT nextval('public."b2b-controlecliente_id_seq"'::regclass);


--
-- Name: n8n_chat_histories_barbara id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.n8n_chat_histories_barbara ALTER COLUMN id SET DEFAULT nextval('public.n8n_chat_histories_barbara_id_seq'::regclass);


--
-- Name: n8n_chat_histories_clinicanexla id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.n8n_chat_histories_clinicanexla ALTER COLUMN id SET DEFAULT nextval('public.n8n_chat_histories_clinicanexla_id_seq'::regclass);


--
-- Name: n8n_chat_histories_clinicanexlainsta id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.n8n_chat_histories_clinicanexlainsta ALTER COLUMN id SET DEFAULT nextval('public.n8n_chat_histories_clinicanexlainsta_id_seq'::regclass);


--
-- Name: n8n_chat_histories_clinicaolhos id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.n8n_chat_histories_clinicaolhos ALTER COLUMN id SET DEFAULT nextval('public.n8n_chat_histories_clinicaolhos_id_seq'::regclass);


--
-- Name: n8n_chat_histories_etuany id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.n8n_chat_histories_etuany ALTER COLUMN id SET DEFAULT nextval('public.n8n_chat_histories_etuany_id_seq'::regclass);


--
-- Name: n8n_chat_histories_gastroimagem id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.n8n_chat_histories_gastroimagem ALTER COLUMN id SET DEFAULT nextval('public.n8n_chat_histories_gastroimagem_id_seq'::regclass);


--
-- Name: nexla_historico id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.nexla_historico ALTER COLUMN id SET DEFAULT nextval('public.nexla_historico_id_seq'::regclass);


--
-- Name: agendas agendas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agendas
    ADD CONSTRAINT agendas_pkey PRIMARY KEY (id);


--
-- Name: alerts alerts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alerts
    ADD CONSTRAINT alerts_pkey PRIMARY KEY (id);


--
-- Name: appointments appointments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointments
    ADD CONSTRAINT appointments_pkey PRIMARY KEY (id);


--
-- Name: attendances attendances_numero_instancia_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendances
    ADD CONSTRAINT attendances_numero_instancia_key UNIQUE (numero, instancia);


--
-- Name: attendances attendances_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendances
    ADD CONSTRAINT attendances_pkey PRIMARY KEY (id);


--
-- Name: b2b-controleCliente b2b-controleCliente_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."b2b-controleCliente"
    ADD CONSTRAINT "b2b-controleCliente_pkey" PRIMARY KEY (id);


--
-- Name: b2b-controlecliente b2b-controlecliente_Número do telefone_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."b2b-controlecliente"
    ADD CONSTRAINT "b2b-controlecliente_Número do telefone_key" UNIQUE ("Número do telefone");


--
-- Name: b2b-controlecliente b2b-controlecliente_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."b2b-controlecliente"
    ADD CONSTRAINT "b2b-controlecliente_pkey" PRIMARY KEY (id);


--
-- Name: clientes clientes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.clientes
    ADD CONSTRAINT clientes_pkey PRIMARY KEY (id);


--
-- Name: companies companies_instance_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.companies
    ADD CONSTRAINT companies_instance_key UNIQUE (instance);


--
-- Name: companies companies_instance_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.companies
    ADD CONSTRAINT companies_instance_unique UNIQUE (instance);


--
-- Name: companies companies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.companies
    ADD CONSTRAINT companies_pkey PRIMARY KEY (id);


--
-- Name: companies companies_slug_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.companies
    ADD CONSTRAINT companies_slug_key UNIQUE (slug);


--
-- Name: contacts contacts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contacts
    ADD CONSTRAINT contacts_pkey PRIMARY KEY (id);


--
-- Name: conversations conversations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversations
    ADD CONSTRAINT conversations_pkey PRIMARY KEY (id);


--
-- Name: insurance_plans insurance_plans_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.insurance_plans
    ADD CONSTRAINT insurance_plans_pkey PRIMARY KEY (id);


--
-- Name: invoices invoices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT invoices_pkey PRIMARY KEY (id);


--
-- Name: kanban_cards kanban_cards_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.kanban_cards
    ADD CONSTRAINT kanban_cards_pkey PRIMARY KEY (id);


--
-- Name: kanban_columns kanban_columns_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.kanban_columns
    ADD CONSTRAINT kanban_columns_pkey PRIMARY KEY (id);


--
-- Name: mensagens_geral mensagens_geral_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mensagens_geral
    ADD CONSTRAINT mensagens_geral_pkey PRIMARY KEY (id);


--
-- Name: mensagens mensagens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mensagens
    ADD CONSTRAINT mensagens_pkey PRIMARY KEY (id);


--
-- Name: messages messages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_pkey PRIMARY KEY (id);


--
-- Name: n8n_chat_histories_barbara n8n_chat_histories_barbara_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.n8n_chat_histories_barbara
    ADD CONSTRAINT n8n_chat_histories_barbara_pkey PRIMARY KEY (id);


--
-- Name: n8n_chat_histories_clinicanexla n8n_chat_histories_clinicanexla_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.n8n_chat_histories_clinicanexla
    ADD CONSTRAINT n8n_chat_histories_clinicanexla_pkey PRIMARY KEY (id);


--
-- Name: n8n_chat_histories_clinicanexlainsta n8n_chat_histories_clinicanexlainsta_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.n8n_chat_histories_clinicanexlainsta
    ADD CONSTRAINT n8n_chat_histories_clinicanexlainsta_pkey PRIMARY KEY (id);


--
-- Name: n8n_chat_histories_clinicaolhos n8n_chat_histories_clinicaolhos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.n8n_chat_histories_clinicaolhos
    ADD CONSTRAINT n8n_chat_histories_clinicaolhos_pkey PRIMARY KEY (id);


--
-- Name: n8n_chat_histories_etuany n8n_chat_histories_etuany_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.n8n_chat_histories_etuany
    ADD CONSTRAINT n8n_chat_histories_etuany_pkey PRIMARY KEY (id);


--
-- Name: n8n_chat_histories_gastroimagem n8n_chat_histories_gastroimagem_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.n8n_chat_histories_gastroimagem
    ADD CONSTRAINT n8n_chat_histories_gastroimagem_pkey PRIMARY KEY (id);


--
-- Name: nexla_historico nexla_historico_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.nexla_historico
    ADD CONSTRAINT nexla_historico_pkey PRIMARY KEY (id);


--
-- Name: pagou_NexlaDaily pagou_NexlaDaily_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."pagou_NexlaDaily"
    ADD CONSTRAINT "pagou_NexlaDaily_pkey" PRIMARY KEY (id);


--
-- Name: procedure_prices procedure_prices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.procedure_prices
    ADD CONSTRAINT procedure_prices_pkey PRIMARY KEY (id);


--
-- Name: procedure_prices procedure_prices_procedure_id_insurance_plan_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.procedure_prices
    ADD CONSTRAINT procedure_prices_procedure_id_insurance_plan_id_key UNIQUE (procedure_id, insurance_plan_id);


--
-- Name: procedures procedures_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.procedures
    ADD CONSTRAINT procedures_pkey PRIMARY KEY (id);


--
-- Name: professionals professionals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.professionals
    ADD CONSTRAINT professionals_pkey PRIMARY KEY (id);


--
-- Name: saved_contacts saved_contacts_numero_instancia_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.saved_contacts
    ADD CONSTRAINT saved_contacts_numero_instancia_key UNIQUE (numero, instancia);


--
-- Name: saved_contacts saved_contacts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.saved_contacts
    ADD CONSTRAINT saved_contacts_pkey PRIMARY KEY (id);


--
-- Name: sector_members sector_members_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sector_members
    ADD CONSTRAINT sector_members_pkey PRIMARY KEY (id);


--
-- Name: sector_members sector_members_user_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sector_members
    ADD CONSTRAINT sector_members_user_id_key UNIQUE (user_id);


--
-- Name: sectors sectors_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sectors
    ADD CONSTRAINT sectors_pkey PRIMARY KEY (id);


--
-- Name: support_messages support_messages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.support_messages
    ADD CONSTRAINT support_messages_pkey PRIMARY KEY (id);


--
-- Name: support_tickets support_tickets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.support_tickets
    ADD CONSTRAINT support_tickets_pkey PRIMARY KEY (id);


--
-- Name: users users_email_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key UNIQUE (email);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: contacts_company_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contacts_company_id_idx ON public.contacts USING btree (company_id);


--
-- Name: contacts_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contacts_status_idx ON public.contacts USING btree (status);


--
-- Name: idx_clientes_ad_click_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_clientes_ad_click_id ON public.clientes USING btree (ad_click_id) WHERE (ad_click_id IS NOT NULL);


--
-- Name: idx_clientes_ad_title; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_clientes_ad_title ON public.clientes USING btree (ad_title) WHERE (ad_title IS NOT NULL);


--
-- Name: idx_invoices_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_invoices_company_id ON public.invoices USING btree (company_id);


--
-- Name: idx_invoices_due_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_invoices_due_date ON public.invoices USING btree (due_date);


--
-- Name: idx_mensagens_geral_aplicativo; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_mensagens_geral_aplicativo ON public.mensagens_geral USING btree (instancia, aplicativo, numero);


--
-- Name: idx_mensagens_geral_recipient_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_mensagens_geral_recipient_id ON public.mensagens_geral USING btree (recipient_id) WHERE (recipient_id IS NOT NULL);


--
-- Name: idx_saved_contacts_ad_title; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_saved_contacts_ad_title ON public.saved_contacts USING btree (ad_title) WHERE (ad_title IS NOT NULL);


--
-- Name: idx_support_messages_ticket; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_support_messages_ticket ON public.support_messages USING btree (ticket_id, created_at);


--
-- Name: idx_support_tickets_company; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_support_tickets_company ON public.support_tickets USING btree (company_id);


--
-- Name: idx_support_tickets_last_msg; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_support_tickets_last_msg ON public.support_tickets USING btree (last_message_at DESC);


--
-- Name: idx_support_tickets_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_support_tickets_status ON public.support_tickets USING btree (status);


--
-- Name: messages_contact_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX messages_contact_id_idx ON public.messages USING btree (contact_id);


--
-- Name: clientes trg_reopen_session; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_reopen_session AFTER INSERT ON public.clientes FOR EACH ROW EXECUTE FUNCTION public.reopen_session_on_new_message();


--
-- Name: mensagens_geral trg_reopen_session; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_reopen_session AFTER INSERT ON public.mensagens_geral FOR EACH ROW EXECUTE FUNCTION public.reopen_session_on_new_message();


--
-- Name: n8n_chat_histories_barbara trg_reopen_session; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_reopen_session AFTER INSERT ON public.n8n_chat_histories_barbara FOR EACH ROW EXECUTE FUNCTION public.reopen_session_on_new_message();


--
-- Name: n8n_chat_histories_clinicaolhos trg_reopen_session; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_reopen_session AFTER INSERT ON public.n8n_chat_histories_clinicaolhos FOR EACH ROW EXECUTE FUNCTION public.reopen_session_on_new_message();


--
-- Name: n8n_chat_histories_gastroimagem trg_reopen_session; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_reopen_session AFTER INSERT ON public.n8n_chat_histories_gastroimagem FOR EACH ROW EXECUTE FUNCTION public.reopen_session_on_new_message();


--
-- Name: support_messages trg_support_bump_ticket; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_support_bump_ticket AFTER INSERT ON public.support_messages FOR EACH ROW EXECUTE FUNCTION public.support_bump_ticket();


--
-- Name: agendas agendas_professional_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agendas
    ADD CONSTRAINT agendas_professional_id_fkey FOREIGN KEY (professional_id) REFERENCES public.professionals(id) ON DELETE SET NULL;


--
-- Name: alerts alerts_forwarded_to_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alerts
    ADD CONSTRAINT alerts_forwarded_to_user_id_fkey FOREIGN KEY (forwarded_to_user_id) REFERENCES public.users(id);


--
-- Name: alerts alerts_instancia_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alerts
    ADD CONSTRAINT alerts_instancia_fkey FOREIGN KEY (instancia) REFERENCES public.companies(instance) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: appointments appointments_agenda_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointments
    ADD CONSTRAINT appointments_agenda_id_fkey FOREIGN KEY (agenda_id) REFERENCES public.agendas(id) ON DELETE CASCADE;


--
-- Name: attendances attendances_sector_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendances
    ADD CONSTRAINT attendances_sector_id_fkey FOREIGN KEY (sector_id) REFERENCES public.sectors(id) ON DELETE SET NULL;


--
-- Name: contacts contacts_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contacts
    ADD CONSTRAINT contacts_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- Name: invoices invoices_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT invoices_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- Name: kanban_cards kanban_cards_column_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.kanban_cards
    ADD CONSTRAINT kanban_cards_column_id_fkey FOREIGN KEY (column_id) REFERENCES public.kanban_columns(id) ON DELETE CASCADE;


--
-- Name: messages messages_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id) ON DELETE CASCADE;


--
-- Name: procedure_prices procedure_prices_insurance_plan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.procedure_prices
    ADD CONSTRAINT procedure_prices_insurance_plan_id_fkey FOREIGN KEY (insurance_plan_id) REFERENCES public.insurance_plans(id) ON DELETE CASCADE;


--
-- Name: procedure_prices procedure_prices_procedure_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.procedure_prices
    ADD CONSTRAINT procedure_prices_procedure_id_fkey FOREIGN KEY (procedure_id) REFERENCES public.procedures(id) ON DELETE CASCADE;


--
-- Name: procedures procedures_professional_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.procedures
    ADD CONSTRAINT procedures_professional_id_fkey FOREIGN KEY (professional_id) REFERENCES public.professionals(id) ON DELETE CASCADE;


--
-- Name: saved_contacts saved_contacts_insurance_plan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.saved_contacts
    ADD CONSTRAINT saved_contacts_insurance_plan_id_fkey FOREIGN KEY (insurance_plan_id) REFERENCES public.insurance_plans(id);


--
-- Name: sector_members sector_members_sector_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sector_members
    ADD CONSTRAINT sector_members_sector_id_fkey FOREIGN KEY (sector_id) REFERENCES public.sectors(id) ON DELETE CASCADE;


--
-- Name: sector_members sector_members_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sector_members
    ADD CONSTRAINT sector_members_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: support_messages support_messages_ticket_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.support_messages
    ADD CONSTRAINT support_messages_ticket_id_fkey FOREIGN KEY (ticket_id) REFERENCES public.support_tickets(id) ON DELETE CASCADE;


--
-- Name: support_tickets support_tickets_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.support_tickets
    ADD CONSTRAINT support_tickets_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- Name: users users_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- Name: attendances Allow all attendances; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow all attendances" ON public.attendances USING (true) WITH CHECK (true);


--
-- Name: sector_members Allow all sector_members; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow all sector_members" ON public.sector_members USING (true) WITH CHECK (true);


--
-- Name: sectors Allow all sectors; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow all sectors" ON public.sectors USING (true) WITH CHECK (true);


--
-- Name: b2b-controleCliente Permitir DELETE para autenticados; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Permitir DELETE para autenticados" ON public."b2b-controleCliente" FOR DELETE TO authenticated USING (true);


--
-- Name: b2b-controleCliente Permitir INSERT para autenticados; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Permitir INSERT para autenticados" ON public."b2b-controleCliente" FOR INSERT TO authenticated WITH CHECK (true);


--
-- Name: b2b-controleCliente Permitir SELECT para anon e authenticated; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Permitir SELECT para anon e authenticated" ON public."b2b-controleCliente" FOR SELECT TO authenticated, anon USING (true);


--
-- Name: b2b-controleCliente Permitir SELECT para autenticados; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Permitir SELECT para autenticados" ON public."b2b-controleCliente" FOR SELECT TO authenticated USING (true);


--
-- Name: b2b-controleCliente Permitir UPDATE para anon e authenticated; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Permitir UPDATE para anon e authenticated" ON public."b2b-controleCliente" FOR UPDATE TO authenticated, anon USING (true) WITH CHECK (true);


--
-- Name: b2b-controleCliente Permitir UPDATE para autenticados; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Permitir UPDATE para autenticados" ON public."b2b-controleCliente" FOR UPDATE TO authenticated USING (true) WITH CHECK (true);


--
-- Name: pagou_NexlaDaily Service role can insert pagamentos; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Service role can insert pagamentos" ON public."pagou_NexlaDaily" FOR INSERT TO service_role WITH CHECK (true);


--
-- Name: pagou_NexlaDaily Service role can update pagamentos; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Service role can update pagamentos" ON public."pagou_NexlaDaily" FOR UPDATE TO service_role USING (true) WITH CHECK (true);


--
-- Name: agendas; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.agendas ENABLE ROW LEVEL SECURITY;

--
-- Name: agendas agendas_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY agendas_all ON public.agendas TO authenticated, anon USING (true) WITH CHECK (true);


--
-- Name: alerts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.alerts ENABLE ROW LEVEL SECURITY;

--
-- Name: conversations allow all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "allow all" ON public.conversations USING (true) WITH CHECK (true);


--
-- Name: nexla_historico allow all nexla_historico; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "allow all nexla_historico" ON public.nexla_historico USING (true) WITH CHECK (true);


--
-- Name: mensagens_geral allow insert mensagens_geral; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "allow insert mensagens_geral" ON public.mensagens_geral FOR INSERT WITH CHECK (true);


--
-- Name: clientes allow_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY allow_read ON public.clientes FOR SELECT USING (true);


--
-- Name: mensagens_geral allow_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY allow_read ON public.mensagens_geral FOR SELECT USING (true);


--
-- Name: n8n_chat_histories_barbara allow_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY allow_read ON public.n8n_chat_histories_barbara FOR SELECT USING (true);


--
-- Name: alerts anon can read alerts; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "anon can read alerts" ON public.alerts FOR SELECT USING (true);


--
-- Name: alerts anon can update alerts; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "anon can update alerts" ON public.alerts FOR UPDATE USING (true);


--
-- Name: n8n_chat_histories_gastroimagem anon read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "anon read" ON public.n8n_chat_histories_gastroimagem FOR SELECT USING (true);


--
-- Name: appointments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.appointments ENABLE ROW LEVEL SECURITY;

--
-- Name: appointments appointments_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY appointments_all ON public.appointments TO authenticated, anon USING (true) WITH CHECK (true);


--
-- Name: attendances; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.attendances ENABLE ROW LEVEL SECURITY;

--
-- Name: b2b-controleCliente; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public."b2b-controleCliente" ENABLE ROW LEVEL SECURITY;

--
-- Name: b2b-controlecliente; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public."b2b-controlecliente" ENABLE ROW LEVEL SECURITY;

--
-- Name: clientes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.clientes ENABLE ROW LEVEL SECURITY;

--
-- Name: companies; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;

--
-- Name: contacts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.contacts ENABLE ROW LEVEL SECURITY;

--
-- Name: conversations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;

--
-- Name: mensagens_geral gastro; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY gastro ON public.mensagens_geral USING (true) WITH CHECK (true);


--
-- Name: companies insert companies; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "insert companies" ON public.companies FOR INSERT WITH CHECK (true);


--
-- Name: users insert users; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "insert users" ON public.users FOR INSERT WITH CHECK (true);


--
-- Name: insurance_plans; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.insurance_plans ENABLE ROW LEVEL SECURITY;

--
-- Name: insurance_plans insurance_plans_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY insurance_plans_all ON public.insurance_plans TO authenticated, anon USING (true) WITH CHECK (true);


--
-- Name: invoices; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.invoices ENABLE ROW LEVEL SECURITY;

--
-- Name: invoices invoices_full_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY invoices_full_access ON public.invoices USING (true) WITH CHECK (true);


--
-- Name: kanban_cards; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.kanban_cards ENABLE ROW LEVEL SECURITY;

--
-- Name: kanban_cards kanban_cards_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY kanban_cards_all ON public.kanban_cards TO authenticated, anon USING (true) WITH CHECK (true);


--
-- Name: kanban_columns; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.kanban_columns ENABLE ROW LEVEL SECURITY;

--
-- Name: kanban_columns kanban_columns_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY kanban_columns_all ON public.kanban_columns TO authenticated, anon USING (true) WITH CHECK (true);


--
-- Name: mensagens_geral; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.mensagens_geral ENABLE ROW LEVEL SECURITY;

--
-- Name: messages; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

--
-- Name: n8n_chat_histories_barbara; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.n8n_chat_histories_barbara ENABLE ROW LEVEL SECURITY;

--
-- Name: n8n_chat_histories_gastroimagem; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.n8n_chat_histories_gastroimagem ENABLE ROW LEVEL SECURITY;

--
-- Name: nexla_historico; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.nexla_historico ENABLE ROW LEVEL SECURITY;

--
-- Name: pagou_NexlaDaily; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public."pagou_NexlaDaily" ENABLE ROW LEVEL SECURITY;

--
-- Name: procedure_prices; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.procedure_prices ENABLE ROW LEVEL SECURITY;

--
-- Name: procedure_prices procedure_prices_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY procedure_prices_all ON public.procedure_prices TO authenticated, anon USING (true) WITH CHECK (true);


--
-- Name: procedures; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.procedures ENABLE ROW LEVEL SECURITY;

--
-- Name: procedures procedures_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY procedures_all ON public.procedures TO authenticated, anon USING (true) WITH CHECK (true);


--
-- Name: professionals; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.professionals ENABLE ROW LEVEL SECURITY;

--
-- Name: professionals professionals_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY professionals_all ON public.professionals TO authenticated, anon USING (true) WITH CHECK (true);


--
-- Name: companies read companies; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "read companies" ON public.companies FOR SELECT USING (true);


--
-- Name: users read users; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "read users" ON public.users FOR SELECT USING (true);


--
-- Name: saved_contacts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.saved_contacts ENABLE ROW LEVEL SECURITY;

--
-- Name: saved_contacts saved_contacts_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY saved_contacts_all ON public.saved_contacts TO authenticated, anon USING (true) WITH CHECK (true);


--
-- Name: sector_members; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.sector_members ENABLE ROW LEVEL SECURITY;

--
-- Name: sectors; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.sectors ENABLE ROW LEVEL SECURITY;

--
-- Name: support_messages; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.support_messages ENABLE ROW LEVEL SECURITY;

--
-- Name: support_messages support_messages_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY support_messages_all ON public.support_messages USING (true) WITH CHECK (true);


--
-- Name: support_tickets; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.support_tickets ENABLE ROW LEVEL SECURITY;

--
-- Name: support_tickets support_tickets_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY support_tickets_all ON public.support_tickets USING (true) WITH CHECK (true);


--
-- Name: companies update companies; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "update companies" ON public.companies FOR UPDATE USING (true);


--
-- Name: users update users; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "update users" ON public.users FOR UPDATE USING (true);


--
-- Name: users; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

--
-- PostgreSQL database dump complete
--

-- Restaura search_path para public (o pg_dump seta como empty para seguranca,
-- mas as migrations seguintes usam nomes nao-qualificados em RETURNS SETOF)
SET search_path TO public;



-- ── 20260429_billing.sql ─────────────────────────────────────────────────────────

-- ────────────────────────────────────────────────────────────────────────────
-- Migration: sistema de cobrança/mensalidade
--
-- Adiciona em companies:
--   billing_day              — dia do mês de vencimento (1-31)
--   next_due_date            — próxima data de vencimento (avança ao marcar pago)
--   billing_amount           — valor mensal (R$)
--   billing_grace_days       — dias de carência após vencimento antes de bloquear (default 1)
--   billing_reminder_days    — quantos dias antes do vencimento começa o aviso (default 3)
--   billing_blocked          — bloqueio manual (override)
--
-- Cria tabela invoices: histórico de mensalidades
-- ────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS billing_day            integer,
  ADD COLUMN IF NOT EXISTS next_due_date          date,
  ADD COLUMN IF NOT EXISTS billing_amount         numeric(10,2),
  ADD COLUMN IF NOT EXISTS billing_grace_days     integer DEFAULT 1,
  ADD COLUMN IF NOT EXISTS billing_reminder_days  integer DEFAULT 3,
  ADD COLUMN IF NOT EXISTS billing_blocked        boolean DEFAULT false;

CREATE TABLE IF NOT EXISTS public.invoices (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id      uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  amount          numeric(10,2) NOT NULL,
  due_date        date NOT NULL,
  paid_at         timestamptz,
  payment_method  text,
  notes           text,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_invoices_company_id ON public.invoices(company_id);
CREATE INDEX IF NOT EXISTS idx_invoices_due_date   ON public.invoices(due_date);

-- RPC: marca empresa como paga (cria invoice + avança next_due_date 1 mês)
-- Security definer pra bypassar RLS — só o ADM chama isso
CREATE OR REPLACE FUNCTION public.mark_company_paid(
  p_company_id uuid,
  p_amount numeric DEFAULT NULL,
  p_payment_method text DEFAULT NULL,
  p_notes text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company record;
  v_amount numeric;
  v_due date;
  v_next date;
BEGIN
  SELECT * INTO v_company FROM companies WHERE id = p_company_id;
  IF v_company IS NULL THEN
    RETURN json_build_object('ok', false, 'error', 'Empresa não encontrada');
  END IF;

  v_amount := COALESCE(p_amount, v_company.billing_amount);
  IF v_amount IS NULL OR v_amount <= 0 THEN
    RETURN json_build_object('ok', false, 'error', 'Valor da mensalidade não definido');
  END IF;

  -- Vencimento sendo pago: usa next_due_date se setado, senão calcula deste mês
  v_due := COALESCE(
    v_company.next_due_date,
    date_trunc('month', CURRENT_DATE)::date + (COALESCE(v_company.billing_day, 5) - 1)
  );

  -- Próximo vencimento: 1 mês depois
  v_next := (v_due + INTERVAL '1 month')::date;

  -- Insere invoice paga
  INSERT INTO invoices (company_id, amount, due_date, paid_at, payment_method, notes)
  VALUES (p_company_id, v_amount, v_due, now(), p_payment_method, p_notes);

  -- Avança next_due_date e desbloqueia (caso estivesse bloqueado)
  UPDATE companies
     SET next_due_date = v_next,
         billing_blocked = false
   WHERE id = p_company_id;

  RETURN json_build_object('ok', true, 'next_due_date', v_next);
END;
$$;

GRANT EXECUTE ON FUNCTION public.mark_company_paid(uuid, numeric, text, text) TO anon, authenticated;

-- RLS: invoices acessível pra service_role livremente; anon só pode ler do próprio (não usado por enquanto)
ALTER TABLE public.invoices ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "invoices_full_access" ON public.invoices;
CREATE POLICY "invoices_full_access" ON public.invoices
  FOR ALL USING (true) WITH CHECK (true);


-- ── 20260429_clientes_add_session_id.sql ─────────────────────────────────────────────────────────

-- ────────────────────────────────────────────────────────────────────────────
-- Migration: adicionar session_id em clientes
-- Motivo: existe uma trigger na tabela `clientes` que referencia NEW.session_id
-- (provavelmente instalada por ensure_table_setup quando a empresa foi criada,
-- assumindo o padrão de mensagens_geral). A coluna não existia, então inserts
-- via n8n falhavam com:
--   record "new" has no field "session_id"
-- Adicionamos a coluna como nullable. A trigger resolve sem erro.
-- ────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.clientes
  ADD COLUMN IF NOT EXISTS session_id text;

-- Backfill opcional: copia o número (sem o sufixo @s.whatsapp.net) pro session_id
-- pra ficar consistente com o padrão das outras tabelas. Pode pular se não quiser.
UPDATE public.clientes
   SET session_id = split_part(numero, '@', 1)
 WHERE session_id IS NULL
   AND numero IS NOT NULL;


-- ── 20260429_companies_plan_limits.sql ─────────────────────────────────────────────────────────

-- ────────────────────────────────────────────────────────────────────────────
-- Migration: campos de limite/override por empresa em companies
-- Permite que o ADM:
--   1. Cobre add-on de usuários (extra_users)
--   2. Override individual de profissionais (max_professionals) e agendas (max_agendas)
--      pra clientes especiais sem ter que mudar de plano completamente
-- Defaults vêm do plano (Starter/Pro/Business) — quando o override é NULL,
-- o frontend usa PLAN_DEFAULTS de src/lib/planLimits.js.
-- ────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS extra_users        integer DEFAULT 0,
  ADD COLUMN IF NOT EXISTS max_professionals  integer NULL,
  ADD COLUMN IF NOT EXISTS max_agendas        integer NULL;

COMMENT ON COLUMN public.companies.extra_users
  IS 'Add-on de usuários extras (R$39 cada) somados aos inclusos no plano';
COMMENT ON COLUMN public.companies.max_professionals
  IS 'Override individual do limite de profissionais. NULL = usar default do plano';
COMMENT ON COLUMN public.companies.max_agendas
  IS 'Override individual do limite de agendas. NULL = usar default do plano';


-- ── 20260429_delete_user_rpc.sql ─────────────────────────────────────────────────────────

-- ────────────────────────────────────────────────────────────────────────────
-- Migration: delete_user RPC
-- Motivo: A tabela `users` não tem policy de DELETE no RLS, então o delete
-- direto via anon key é silenciosamente bloqueado (não retorna erro, mas o
-- registro permanece). Esta RPC roda como SECURITY DEFINER e bypassa RLS,
-- mesmo padrão de `create_user` e `update_user_password` que já existem.
--
-- Como aplicar:
--   1. Abra o Supabase Studio → SQL Editor
--   2. Cole este arquivo inteiro
--   3. Run
-- ────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.delete_user(p_user_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_email text;
BEGIN
  SELECT email INTO v_user_email FROM users WHERE id = p_user_id;

  IF v_user_email IS NULL THEN
    RETURN json_build_object('ok', false, 'error', 'Usuário não encontrado');
  END IF;

  -- Limpa vínculos best-effort (ignora se a tabela/coluna não existir ainda)
  BEGIN
    DELETE FROM sector_members WHERE user_id = p_user_id;
  EXCEPTION WHEN undefined_table THEN NULL;
  END;

  BEGIN
    UPDATE kanban_cards SET assignee_id = NULL WHERE assignee_id = p_user_id;
  EXCEPTION WHEN undefined_table OR undefined_column THEN NULL;
  END;

  BEGIN
    UPDATE attendances SET user_id = NULL WHERE user_id = p_user_id;
  EXCEPTION WHEN undefined_table OR undefined_column THEN NULL;
  END;

  BEGIN
    UPDATE alerts SET forwarded_to = NULL WHERE forwarded_to = p_user_id;
  EXCEPTION WHEN undefined_table OR undefined_column THEN NULL;
  END;

  DELETE FROM users WHERE id = p_user_id;

  RETURN json_build_object('ok', true, 'email', v_user_email);
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_user(uuid) TO anon, authenticated;


-- ── 20260430_api_rpc.sql ─────────────────────────────────────────────────────────

-- ────────────────────────────────────────────────────────────────────────────
-- API RPCs — todas as operações disponíveis via POST com body JSON
-- (em vez de GET com query string, pra não expor parâmetros na URL)
--
-- Uso: POST /rest/v1/rpc/{nome_funcao}
-- Body: { "param1": "valor1", ... }
--
-- v2: nomes de coluna corrigidos pra bater com schema real.
--   procedures.price_particular   (não default_price)
--   procedures.duration_minutes   (não duration_min)
--   saved_contacts.birth_date     (não birthdate)
--   saved_contacts.insurance_card (não card_number)
--   saved_contacts.nome_social    (não social_name)
--   saved_contacts.referral_source (não origem)
--   saved_contacts.guardian_name  (não legal_guardian)
--   appointments.contact_numero / contact_nome / duration_minutes (não patient_*/ends_at)
--   alerts.mensagem / alerts.numero (não message / phone) — sem coluna 'type'
--   kanban_cards.assigned_user_id / assigned_user_name (não assignee_id)
-- ────────────────────────────────────────────────────────────────────────────

-- Drop antigas se vieram da v1 com assinatura diferente (idempotente)
DROP FUNCTION IF EXISTS public.api_pacientes_list(text, text, int, int);
DROP FUNCTION IF EXISTS public.api_paciente_by_phone(text, text);
DROP FUNCTION IF EXISTS public.api_paciente_create(jsonb);
DROP FUNCTION IF EXISTS public.api_paciente_update(uuid, jsonb);
DROP FUNCTION IF EXISTS public.api_paciente_delete(uuid);
DROP FUNCTION IF EXISTS public.api_messages_by_phone(text, text, int, boolean);
DROP FUNCTION IF EXISTS public.api_message_create(jsonb);
DROP FUNCTION IF EXISTS public.api_conversation_close(text, text, text);
DROP FUNCTION IF EXISTS public.api_conversation_status(text, text);
DROP FUNCTION IF EXISTS public.api_professionals_list(text, boolean);
DROP FUNCTION IF EXISTS public.api_procedures_list(text, boolean);
DROP FUNCTION IF EXISTS public.api_insurance_plans_list(text, boolean);
DROP FUNCTION IF EXISTS public.api_procedure_price(uuid, uuid);
DROP FUNCTION IF EXISTS public.api_agendas_list(text);
DROP FUNCTION IF EXISTS public.api_appointments_by_date(text, date);
DROP FUNCTION IF EXISTS public.api_appointments_by_phone(text, text, int);
DROP FUNCTION IF EXISTS public.api_appointments_busy_slots(text, uuid, timestamptz, timestamptz);
DROP FUNCTION IF EXISTS public.api_appointment_create(jsonb);
DROP FUNCTION IF EXISTS public.api_appointment_update_status(uuid, text, text);
DROP FUNCTION IF EXISTS public.api_alert_create(jsonb);
DROP FUNCTION IF EXISTS public.api_alerts_pending(text);
DROP FUNCTION IF EXISTS public.api_alert_resolve(uuid);
DROP FUNCTION IF EXISTS public.api_kanban_columns(text);
DROP FUNCTION IF EXISTS public.api_kanban_cards(text);
DROP FUNCTION IF EXISTS public.api_kanban_card_create(jsonb);

-- ─── PACIENTES (saved_contacts) ─────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.api_pacientes_list(
  p_instancia text,
  p_search    text DEFAULT NULL,
  p_limit     int DEFAULT 100,
  p_offset    int DEFAULT 0
)
RETURNS SETOF saved_contacts
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT * FROM saved_contacts
   WHERE instancia = p_instancia
     AND (p_search IS NULL
          OR nome ILIKE '%' || p_search || '%'
          OR numero ILIKE '%' || p_search || '%'
          OR cpf ILIKE '%' || p_search || '%')
   ORDER BY nome ASC
   LIMIT p_limit OFFSET p_offset;
$$;

CREATE OR REPLACE FUNCTION public.api_paciente_by_phone(
  p_instancia text,
  p_numero    text
)
RETURNS SETOF saved_contacts
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT * FROM saved_contacts
   WHERE instancia = p_instancia AND numero = p_numero
   LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.api_paciente_create(p_data jsonb)
RETURNS saved_contacts
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_row saved_contacts;
BEGIN
  INSERT INTO saved_contacts (
    instancia, nome, numero, birth_date, gender, email, phone_secondary,
    address, cpf, rg, profession, nome_social, marital_status, blood_type,
    weight, height, guardian_name, guardian_phone, insurance_plan_id,
    insurance_card, allergies, chronic_conditions, medications, clinical_notes,
    referral_source, photo, emergency_contact, emergency_phone, notes
  ) VALUES (
    p_data->>'instancia', p_data->>'nome', p_data->>'numero',
    NULLIF(p_data->>'birth_date','')::date, p_data->>'gender', p_data->>'email',
    p_data->>'phone_secondary', p_data->>'address', p_data->>'cpf',
    p_data->>'rg', p_data->>'profession', p_data->>'nome_social',
    p_data->>'marital_status', p_data->>'blood_type',
    NULLIF(p_data->>'weight','')::numeric, NULLIF(p_data->>'height','')::numeric,
    p_data->>'guardian_name', p_data->>'guardian_phone',
    NULLIF(p_data->>'insurance_plan_id','')::uuid, p_data->>'insurance_card',
    p_data->>'allergies', p_data->>'chronic_conditions', p_data->>'medications',
    p_data->>'clinical_notes', p_data->>'referral_source', p_data->>'photo',
    p_data->>'emergency_contact', p_data->>'emergency_phone', p_data->>'notes'
  )
  RETURNING * INTO v_row;
  RETURN v_row;
END $$;

CREATE OR REPLACE FUNCTION public.api_paciente_update(
  p_id   uuid,
  p_data jsonb
)
RETURNS saved_contacts
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_row saved_contacts;
BEGIN
  UPDATE saved_contacts SET
    nome              = COALESCE(p_data->>'nome', nome),
    birth_date        = COALESCE(NULLIF(p_data->>'birth_date','')::date, birth_date),
    gender            = COALESCE(p_data->>'gender', gender),
    email             = COALESCE(p_data->>'email', email),
    phone_secondary   = COALESCE(p_data->>'phone_secondary', phone_secondary),
    address           = COALESCE(p_data->>'address', address),
    cpf               = COALESCE(p_data->>'cpf', cpf),
    rg                = COALESCE(p_data->>'rg', rg),
    profession        = COALESCE(p_data->>'profession', profession),
    nome_social       = COALESCE(p_data->>'nome_social', nome_social),
    marital_status    = COALESCE(p_data->>'marital_status', marital_status),
    blood_type        = COALESCE(p_data->>'blood_type', blood_type),
    weight            = COALESCE(NULLIF(p_data->>'weight','')::numeric, weight),
    height            = COALESCE(NULLIF(p_data->>'height','')::numeric, height),
    guardian_name     = COALESCE(p_data->>'guardian_name', guardian_name),
    guardian_phone    = COALESCE(p_data->>'guardian_phone', guardian_phone),
    insurance_plan_id = COALESCE(NULLIF(p_data->>'insurance_plan_id','')::uuid, insurance_plan_id),
    insurance_card    = COALESCE(p_data->>'insurance_card', insurance_card),
    allergies         = COALESCE(p_data->>'allergies', allergies),
    chronic_conditions = COALESCE(p_data->>'chronic_conditions', chronic_conditions),
    medications       = COALESCE(p_data->>'medications', medications),
    clinical_notes    = COALESCE(p_data->>'clinical_notes', clinical_notes),
    referral_source   = COALESCE(p_data->>'referral_source', referral_source),
    photo             = COALESCE(p_data->>'photo', photo),
    emergency_contact = COALESCE(p_data->>'emergency_contact', emergency_contact),
    emergency_phone   = COALESCE(p_data->>'emergency_phone', emergency_phone),
    notes             = COALESCE(p_data->>'notes', notes)
  WHERE id = p_id
  RETURNING * INTO v_row;
  RETURN v_row;
END $$;

CREATE OR REPLACE FUNCTION public.api_paciente_delete(p_id uuid)
RETURNS boolean
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  DELETE FROM saved_contacts WHERE id = p_id;
  SELECT TRUE;
$$;

-- ─── MENSAGENS ──────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.api_messages_by_phone(
  p_instancia text,
  p_numero    text,
  p_limit     int DEFAULT 20,
  p_only_client boolean DEFAULT false
)
RETURNS SETOF mensagens_geral
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT * FROM mensagens_geral
   WHERE instancia = p_instancia
     AND numero = p_numero
     AND (NOT p_only_client OR LOWER(type) = 'cliente')
   ORDER BY id DESC
   LIMIT p_limit;
$$;

CREATE OR REPLACE FUNCTION public.api_message_create(p_data jsonb)
RETURNS mensagens_geral
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_row mensagens_geral;
BEGIN
  INSERT INTO mensagens_geral (instancia, numero, mensagem, type, "horaLastMessage")
  VALUES (
    p_data->>'instancia', p_data->>'numero', p_data->>'mensagem',
    COALESCE(p_data->>'type', 'ia'),
    COALESCE(p_data->>'horaLastMessage', to_char(now(), 'DD/MM/YYYY HH24:MI:SS'))
  )
  RETURNING * INTO v_row;
  RETURN v_row;
END $$;

-- ─── CONVERSAS / TICKETS ────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.api_conversation_close(
  p_session_id text,
  p_instancia  text,
  p_reason     text
)
RETURNS conversations
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_row conversations;
BEGIN
  INSERT INTO conversations (session_id, instancia, reason, closed_at)
  VALUES (p_session_id, p_instancia, p_reason, now())
  RETURNING * INTO v_row;
  BEGIN
    DELETE FROM attendances WHERE numero = p_session_id AND instancia = p_instancia;
  EXCEPTION WHEN undefined_table THEN NULL;
  END;
  RETURN v_row;
END $$;

CREATE OR REPLACE FUNCTION public.api_conversation_status(
  p_session_id text,
  p_instancia  text
)
RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
    'is_open', NOT EXISTS (
      SELECT 1 FROM conversations
       WHERE session_id = p_session_id AND instancia = p_instancia
    ),
    'last_close', (
      SELECT row_to_json(c) FROM conversations c
       WHERE c.session_id = p_session_id AND c.instancia = p_instancia
       ORDER BY c.closed_at DESC LIMIT 1
    )
  );
$$;

-- ─── CATÁLOGO ───────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.api_professionals_list(
  p_instancia   text,
  p_only_active boolean DEFAULT true
)
RETURNS SETOF professionals
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT * FROM professionals
   WHERE instancia = p_instancia
     AND (NOT p_only_active OR active = true)
   ORDER BY name ASC;
$$;

CREATE OR REPLACE FUNCTION public.api_procedures_list(
  p_instancia   text,
  p_only_active boolean DEFAULT true
)
RETURNS SETOF procedures
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT * FROM procedures
   WHERE instancia = p_instancia
     AND (NOT p_only_active OR active = true)
   ORDER BY name ASC;
$$;

CREATE OR REPLACE FUNCTION public.api_insurance_plans_list(
  p_instancia   text,
  p_only_active boolean DEFAULT true
)
RETURNS SETOF insurance_plans
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT * FROM insurance_plans
   WHERE instancia = p_instancia
     AND (NOT p_only_active OR active = true)
   ORDER BY name ASC;
$$;

CREATE OR REPLACE FUNCTION public.api_procedure_price(
  p_procedure_id      uuid,
  p_insurance_plan_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
    'price', COALESCE(
      (SELECT price FROM procedure_prices
        WHERE procedure_id = p_procedure_id
          AND insurance_plan_id = p_insurance_plan_id),
      (SELECT price_particular FROM procedures WHERE id = p_procedure_id)
    ),
    'is_default', (
      SELECT NOT EXISTS (
        SELECT 1 FROM procedure_prices
         WHERE procedure_id = p_procedure_id
           AND insurance_plan_id = p_insurance_plan_id
      )
    )
  );
$$;

-- ─── AGENDA ─────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.api_agendas_list(p_instancia text)
RETURNS SETOF agendas
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT * FROM agendas WHERE instancia = p_instancia ORDER BY name ASC;
$$;

CREATE OR REPLACE FUNCTION public.api_appointments_by_date(
  p_instancia text,
  p_date      date
)
RETURNS SETOF appointments
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT * FROM appointments
   WHERE instancia = p_instancia
     AND starts_at >= p_date::timestamptz
     AND starts_at <  (p_date + INTERVAL '1 day')::timestamptz
   ORDER BY starts_at ASC;
$$;

CREATE OR REPLACE FUNCTION public.api_appointments_by_phone(
  p_instancia text,
  p_phone     text,
  p_limit     int DEFAULT 10
)
RETURNS SETOF appointments
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT * FROM appointments
   WHERE instancia = p_instancia AND contact_numero = p_phone
   ORDER BY starts_at DESC
   LIMIT p_limit;
$$;

CREATE OR REPLACE FUNCTION public.api_appointments_busy_slots(
  p_instancia       text,
  p_professional_id uuid,
  p_from            timestamptz,
  p_to              timestamptz
)
RETURNS TABLE (starts_at timestamptz, duration_minutes int)
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT starts_at, duration_minutes FROM appointments
   WHERE instancia = p_instancia
     AND professional_id = p_professional_id
     AND status <> 'cancelado'
     AND starts_at >= p_from
     AND starts_at <  p_to
   ORDER BY starts_at ASC;
$$;

CREATE OR REPLACE FUNCTION public.api_appointment_create(p_data jsonb)
RETURNS appointments
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_row appointments;
BEGIN
  INSERT INTO appointments (
    instancia, agenda_id, professional_id, procedure_id, insurance_plan_id,
    contact_nome, contact_numero, starts_at, duration_minutes, status,
    payment_status, price, notes
  ) VALUES (
    p_data->>'instancia',
    NULLIF(p_data->>'agenda_id','')::uuid,
    NULLIF(p_data->>'professional_id','')::uuid,
    NULLIF(p_data->>'procedure_id','')::uuid,
    NULLIF(p_data->>'insurance_plan_id','')::uuid,
    p_data->>'contact_nome', p_data->>'contact_numero',
    (p_data->>'starts_at')::timestamptz,
    COALESCE((p_data->>'duration_minutes')::int, 30),
    COALESCE(p_data->>'status', 'agendado'),
    COALESCE(p_data->>'payment_status', 'pendente'),
    NULLIF(p_data->>'price','')::numeric,
    p_data->>'notes'
  )
  RETURNING * INTO v_row;
  RETURN v_row;
END $$;

CREATE OR REPLACE FUNCTION public.api_appointment_update_status(
  p_id             uuid,
  p_status         text,
  p_payment_status text DEFAULT NULL
)
RETURNS appointments
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_row appointments;
BEGIN
  UPDATE appointments SET
    status         = p_status,
    payment_status = COALESCE(p_payment_status, payment_status),
    paid_at        = CASE WHEN p_payment_status = 'pago' THEN now() ELSE paid_at END
  WHERE id = p_id
  RETURNING * INTO v_row;
  RETURN v_row;
END $$;

-- ─── ALERTAS ────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.api_alert_create(p_data jsonb)
RETURNS alerts
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_row alerts;
BEGIN
  INSERT INTO alerts (instancia, numero, mensagem, resolved)
  VALUES (
    p_data->>'instancia', p_data->>'numero', p_data->>'mensagem',
    COALESCE((p_data->>'resolved')::boolean, false)
  )
  RETURNING * INTO v_row;
  RETURN v_row;
END $$;

CREATE OR REPLACE FUNCTION public.api_alerts_pending(p_instancia text)
RETURNS SETOF alerts
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT * FROM alerts
   WHERE instancia = p_instancia AND resolved = false
   ORDER BY created_at DESC;
$$;

CREATE OR REPLACE FUNCTION public.api_alert_resolve(p_id uuid)
RETURNS alerts
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_row alerts;
BEGIN
  UPDATE alerts SET resolved = true WHERE id = p_id RETURNING * INTO v_row;
  RETURN v_row;
END $$;

-- ─── KANBAN ─────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.api_kanban_columns(p_instancia text)
RETURNS SETOF kanban_columns
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT * FROM kanban_columns
   WHERE instancia = p_instancia ORDER BY position ASC;
$$;

CREATE OR REPLACE FUNCTION public.api_kanban_cards(p_instancia text)
RETURNS SETOF kanban_cards
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT * FROM kanban_cards
   WHERE instancia = p_instancia ORDER BY position ASC;
$$;

CREATE OR REPLACE FUNCTION public.api_kanban_card_create(p_data jsonb)
RETURNS kanban_cards
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_row kanban_cards;
BEGIN
  INSERT INTO kanban_cards (
    instancia, column_id, title, description, priority, due_date, position,
    assigned_user_id, assigned_user_name
  ) VALUES (
    p_data->>'instancia',
    NULLIF(p_data->>'column_id','')::uuid,
    p_data->>'title', p_data->>'description',
    COALESCE(p_data->>'priority', 'normal'),
    NULLIF(p_data->>'due_date','')::date,
    COALESCE((p_data->>'position')::int, 0),
    NULLIF(p_data->>'assigned_user_id','')::uuid,
    p_data->>'assigned_user_name'
  )
  RETURNING * INTO v_row;
  RETURN v_row;
END $$;

-- ─── GRANTS ─────────────────────────────────────────────────────────────────

GRANT EXECUTE ON FUNCTION
  public.api_pacientes_list(text, text, int, int),
  public.api_paciente_by_phone(text, text),
  public.api_paciente_create(jsonb),
  public.api_paciente_update(uuid, jsonb),
  public.api_paciente_delete(uuid),
  public.api_messages_by_phone(text, text, int, boolean),
  public.api_message_create(jsonb),
  public.api_conversation_close(text, text, text),
  public.api_conversation_status(text, text),
  public.api_professionals_list(text, boolean),
  public.api_procedures_list(text, boolean),
  public.api_insurance_plans_list(text, boolean),
  public.api_procedure_price(uuid, uuid),
  public.api_agendas_list(text),
  public.api_appointments_by_date(text, date),
  public.api_appointments_by_phone(text, text, int),
  public.api_appointments_busy_slots(text, uuid, timestamptz, timestamptz),
  public.api_appointment_create(jsonb),
  public.api_appointment_update_status(uuid, text, text),
  public.api_alert_create(jsonb),
  public.api_alerts_pending(text),
  public.api_alert_resolve(uuid),
  public.api_kanban_columns(text),
  public.api_kanban_cards(text),
  public.api_kanban_card_create(jsonb)
TO anon, authenticated;


-- ── 20260430_mensagens_aplicativo.sql ─────────────────────────────────────────────────────────

-- ────────────────────────────────────────────────────────────────────────────
-- Migration: adiciona coluna `aplicativo` em mensagens_geral
--
-- Identifica de qual canal a mensagem veio:
--   'whatsapp'  (default — todas as msgs antigas e novas sem flag explícita)
--   'instagram' (msgs do Instagram Direct, setadas pelo n8n no salvamento)
--
-- Com isso, a tela de Conversas mostra só WhatsApp e a tela de Direct
-- mostra só Instagram, mesmo que ambos cheguem na mesma tabela.
-- ────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.mensagens_geral
  ADD COLUMN IF NOT EXISTS aplicativo text DEFAULT 'whatsapp';

-- Backfill: tudo que está NULL vira 'whatsapp'
UPDATE public.mensagens_geral
   SET aplicativo = 'whatsapp'
 WHERE aplicativo IS NULL;

CREATE INDEX IF NOT EXISTS idx_mensagens_geral_aplicativo
  ON public.mensagens_geral(instancia, aplicativo, numero);


-- ── 20260430_support.sql ─────────────────────────────────────────────────────────

-- ────────────────────────────────────────────────────────────────────────────
-- Migration: sistema de suporte (chat empresa ↔ super ADM)
--
-- support_tickets : 1 chamado por contexto
-- support_messages: histórico do chat, com texto + imagem opcional (base64)
-- ────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.support_tickets (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id          uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  subject             text NOT NULL,
  status              text NOT NULL DEFAULT 'open', -- open | answered | closed
  created_by_user_id  uuid,
  created_by_name     text,
  created_at          timestamptz NOT NULL DEFAULT now(),
  last_message_at     timestamptz NOT NULL DEFAULT now(),
  last_sender         text
);
CREATE INDEX IF NOT EXISTS idx_support_tickets_company  ON public.support_tickets(company_id);
CREATE INDEX IF NOT EXISTS idx_support_tickets_status   ON public.support_tickets(status);
CREATE INDEX IF NOT EXISTS idx_support_tickets_last_msg ON public.support_tickets(last_message_at DESC);

CREATE TABLE IF NOT EXISTS public.support_messages (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id       uuid NOT NULL REFERENCES public.support_tickets(id) ON DELETE CASCADE,
  sender_type     text NOT NULL,        -- 'company' | 'adm'
  sender_user_id  uuid,
  sender_name     text,
  message         text,
  image           text,                  -- base64 da imagem (data URI sem o prefixo)
  read_by_company boolean DEFAULT false,
  read_by_adm     boolean DEFAULT false,
  created_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_support_messages_ticket ON public.support_messages(ticket_id, created_at);

-- RLS aberta (controlado em frontend — chamados são internos)
ALTER TABLE public.support_tickets  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "support_tickets_all"  ON public.support_tickets;
DROP POLICY IF EXISTS "support_messages_all" ON public.support_messages;

CREATE POLICY "support_tickets_all"  ON public.support_tickets  FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "support_messages_all" ON public.support_messages FOR ALL USING (true) WITH CHECK (true);

-- Realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.support_tickets;
ALTER PUBLICATION supabase_realtime ADD TABLE public.support_messages;

-- Trigger: atualiza last_message_at e last_sender no ticket quando chega msg
CREATE OR REPLACE FUNCTION public.support_bump_ticket()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE support_tickets
     SET last_message_at = NEW.created_at,
         last_sender     = NEW.sender_type,
         status          = CASE
           WHEN NEW.sender_type = 'adm'     AND status = 'open'    THEN 'answered'
           WHEN NEW.sender_type = 'company' AND status = 'closed'  THEN 'answered'
           WHEN NEW.sender_type = 'company' AND status = 'answered' THEN 'open'
           ELSE status
         END
   WHERE id = NEW.ticket_id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_support_bump_ticket ON public.support_messages;
CREATE TRIGGER trg_support_bump_ticket
  AFTER INSERT ON public.support_messages
  FOR EACH ROW EXECUTE FUNCTION public.support_bump_ticket();


-- ── 20260505_companies_instagram_enabled.sql ─────────────────────────────────────────────────────────

-- Adiciona flag de Instagram ativo por empresa.
-- Por padrão, Instagram fica DESATIVADO. Liberação manual via ADM exige
-- configuração técnica (n8n/Meta Business API), então não pode ser self-service.

ALTER TABLE companies
  ADD COLUMN IF NOT EXISTS instagram_enabled BOOLEAN NOT NULL DEFAULT false;

-- Libera apenas pra empresa-piloto que já tem o setup pronto.
UPDATE companies
SET instagram_enabled = true
WHERE name ILIKE '%Centro Terap%Bem Estar%'
   OR name ILIKE '%bem-estar%'
   OR name ILIKE '%bem estar%';


-- ── 20260505_companies_instagram_webhook.sql ─────────────────────────────────────────────────────────

-- Path do webhook do n8n para cada empresa com Instagram ativo.
-- Cada clínica tem um workflow próprio no n8n com path único — isso garante
-- que a mensagem cai no fluxo certo, com a credencial Meta correta.
--
-- Frontend lê esse campo e monta a URL final como:
-- https://n8n.nexladesenvolvimento.com.br/webhook/<path>
--
-- Nullable porque empresas sem Instagram (instagram_enabled=false) não têm.

ALTER TABLE companies
  ADD COLUMN IF NOT EXISTS instagram_webhook_path TEXT;

-- Centro Terapêutico Bem Estar usa o path piloto
UPDATE companies
SET instagram_webhook_path = 'envioNexlainstagram'
WHERE instagram_enabled = true
  AND instagram_webhook_path IS NULL;


-- ── 20260505_mensagens_recipient_id.sql ─────────────────────────────────────────────────────────

-- Adiciona coluna recipient_id em mensagens_geral.
-- Necessária pra Instagram Direct: a Meta Graph API exige o "recipient.id"
-- (PSID — Page-scoped ID da conversa) pra enviar resposta. O n8n preenche
-- esse campo quando a mensagem chega do cliente; no envio, o frontend lê
-- o valor mais recente da conversa e manda no payload do webhook.
--
-- Coluna nullable: WhatsApp não usa esse campo, fica NULL nessas linhas.

ALTER TABLE mensagens_geral
  ADD COLUMN IF NOT EXISTS recipient_id TEXT;

CREATE INDEX IF NOT EXISTS idx_mensagens_geral_recipient_id
  ON mensagens_geral (recipient_id)
  WHERE recipient_id IS NOT NULL;


-- ── 20260511_appointment_reminders.sql ─────────────────────────────────────────────────────────

-- ────────────────────────────────────────────────────────────────────────────
-- Migration: Lembretes automáticos de agendamento
--
-- Permite que cada empresa configure UM lembrete que dispara X horas antes
-- de cada agendamento. Disparo via pg_cron (a cada 5 minutos) que insere em
-- mensagens_geral — o n8n já consome essa tabela e despacha pela Evolution.
--
-- Colunas adicionadas:
--   companies.reminder_enabled        — liga/desliga o lembrete
--   companies.reminder_offset_minutes — quantos minutos antes do agendamento
--   appointments.reminder_sent_at     — marca quando o lembrete foi enfileirado
--                                       (evita reenvio)
--
-- Função:
--   process_appointment_reminders() — varre appointments futuros, monta a
--                                     mensagem e enfileira. Retorna a
--                                     quantidade de lembretes enfileirados.
--
-- Cron:
--   process-appointment-reminders — a cada 5 minutos
-- ────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS reminder_enabled boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS reminder_offset_minutes integer NOT NULL DEFAULT 1440;

COMMENT ON COLUMN public.companies.reminder_offset_minutes IS
  'Minutos antes do agendamento que o lembrete deve disparar. Valores comuns: 30 (30 min), 60 (1h), 1440 (24h), 2880 (48h), 10080 (7 dias).';

ALTER TABLE public.appointments
  ADD COLUMN IF NOT EXISTS reminder_sent_at timestamp with time zone;

CREATE INDEX IF NOT EXISTS appointments_reminder_lookup_idx
  ON public.appointments (starts_at)
  WHERE reminder_sent_at IS NULL;

-- ─── Função: processa lembretes pendentes ──────────────────────────────────
CREATE OR REPLACE FUNCTION public.process_appointment_reminders()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  r record;
  cnt integer := 0;
  msg text;
  appt_local timestamptz;
BEGIN
  FOR r IN
    SELECT
      a.id,
      a.contact_numero,
      a.contact_nome,
      a.starts_at,
      a.instancia,
      c.reminder_offset_minutes,
      p.name AS prof_name
    FROM public.appointments a
    JOIN public.companies c ON c.instance = a.instancia
    LEFT JOIN public.professionals p ON p.id = a.professional_id
    WHERE c.reminder_enabled = true
      AND c.reminder_offset_minutes IS NOT NULL
      AND a.reminder_sent_at IS NULL
      AND a.contact_numero IS NOT NULL
      AND a.contact_numero <> ''
      AND a.status IN ('agendado', 'confirmado')
      AND a.starts_at > now()
      AND a.starts_at - make_interval(mins => c.reminder_offset_minutes) <= now()
  LOOP
    appt_local := r.starts_at AT TIME ZONE 'America/Sao_Paulo';

    msg := format(
      'Olá %s! 👋 Passando pra lembrar da sua consulta no dia %s às %s%s. Até lá! 🩺',
      r.contact_nome,
      to_char(appt_local, 'DD/MM'),
      to_char(appt_local, 'HH24:MI'),
      CASE
        WHEN r.prof_name IS NOT NULL AND r.prof_name <> ''
          THEN ' com ' || r.prof_name
        ELSE ''
      END
    );

    INSERT INTO public.mensagens_geral
      (instancia, numero, mensagem, type, "horaLastMessage", created_at)
    VALUES
      (r.instancia, r.contact_numero, msg, 'text',
       to_char(now() AT TIME ZONE 'America/Sao_Paulo', 'HH24:MI'), now());

    UPDATE public.appointments
       SET reminder_sent_at = now()
     WHERE id = r.id;

    cnt := cnt + 1;
  END LOOP;

  RETURN cnt;
END;
$$;

GRANT EXECUTE ON FUNCTION public.process_appointment_reminders() TO service_role;

-- ─── pg_cron: roda a cada 5 minutos ────────────────────────────────────────
-- Idempotente: remove schedule antigo (se houver) antes de criar.
-- Se pg_cron não estiver habilitado, este bloco é ignorado silenciosamente.

DO $$
BEGIN
  -- Tenta habilitar a extensão (pode falhar se não tiver permissão)
  BEGIN
    CREATE EXTENSION IF NOT EXISTS pg_cron;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    -- Remove agendamento antigo (se já existir)
    PERFORM cron.unschedule(jobid)
       FROM cron.job
      WHERE jobname = 'process-appointment-reminders';

    -- Cria o novo agendamento (a cada 5 minutos)
    PERFORM cron.schedule(
      'process-appointment-reminders',
      '*/5 * * * *',
      $cron$SELECT public.process_appointment_reminders();$cron$
    );
  END IF;
END;
$$;


-- ── 20260511_feedbacks.sql ─────────────────────────────────────────────────────────

-- ────────────────────────────────────────────────────────────────────────────
-- Migration: tabela feedbacks
--
-- Cada empresa pode submeter sugestões, bugs, elogios e dúvidas com nota
-- de 1-5. O ADM Global lê tudo numa tela de moderação separada (futuro).
-- ────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.feedbacks (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id   uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  user_id      uuid REFERENCES public.users(id) ON DELETE SET NULL,
  user_name    text NOT NULL,
  user_email   text NOT NULL,
  category     text NOT NULL CHECK (category IN ('sugestao','bug','elogio','duvida','outro')),
  rating       smallint CHECK (rating BETWEEN 1 AND 5),
  message      text NOT NULL,
  status       text NOT NULL DEFAULT 'novo' CHECK (status IN ('novo','em_analise','planejado','feito','recusado')),
  adm_response text,
  created_at   timestamp with time zone NOT NULL DEFAULT now(),
  updated_at   timestamp with time zone NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS feedbacks_company_id_idx ON public.feedbacks (company_id, created_at DESC);
CREATE INDEX IF NOT EXISTS feedbacks_status_idx     ON public.feedbacks (status, created_at DESC);

-- RLS no padrão permissive do projeto (segurança via anon key + auth no app)
ALTER TABLE public.feedbacks ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "allow_read feedbacks"   ON public.feedbacks;
DROP POLICY IF EXISTS "allow_insert feedbacks" ON public.feedbacks;
DROP POLICY IF EXISTS "allow_update feedbacks" ON public.feedbacks;
DROP POLICY IF EXISTS "allow_delete feedbacks" ON public.feedbacks;

CREATE POLICY "allow_read feedbacks"   ON public.feedbacks FOR SELECT USING (true);
CREATE POLICY "allow_insert feedbacks" ON public.feedbacks FOR INSERT WITH CHECK (true);
CREATE POLICY "allow_update feedbacks" ON public.feedbacks FOR UPDATE USING (true);
CREATE POLICY "allow_delete feedbacks" ON public.feedbacks FOR DELETE USING (true);

-- Adiciona à publication supabase_realtime (pra notificações live no ADM)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename='feedbacks'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.feedbacks;
  END IF;
END;
$$;

-- Trigger pra updated_at automático
CREATE OR REPLACE FUNCTION public.feedbacks_set_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$;

DROP TRIGGER IF EXISTS feedbacks_updated_at ON public.feedbacks;
CREATE TRIGGER feedbacks_updated_at
  BEFORE UPDATE ON public.feedbacks
  FOR EACH ROW EXECUTE FUNCTION public.feedbacks_set_updated_at();


-- ── 20260511_realtime_publication.sql ─────────────────────────────────────────────────────────

-- ────────────────────────────────────────────────────────────────────────────
-- Migration: Habilita Realtime nas tabelas que o frontend assina
--
-- O dump do banco antigo não trouxe as memberships da publication
-- supabase_realtime (pg_dump --no-owner pula objetos owned por supabase_admin).
-- Resultado: nenhuma das tabelas estava na publicação no banco novo, então
-- conversas, agendamentos, kanban etc. não atualizavam em tempo real — o
-- usuário precisava recarregar a página pra ver nova mensagem.
--
-- Tabelas que o frontend usa via supabase.channel(...).on('postgres_changes'):
--   mensagens_geral    — conversas (CompanyConversations)
--   appointments       — agenda (CompanyAgenda, CompanyConversations)
--   saved_contacts     — pacientes (CompanyContacts, CompanyConversations)
--   attendances        — quem está atendendo (CompanyConversations)
--   conversations      — tickets encerrados
--   kanban_cards       — atividades (CompanyKanban)
--   kanban_columns     — colunas do kanban
--   alerts             — alertas (CompanyAlerts)
--   support_messages   — chat de suporte
--   support_tickets    — tickets de suporte
--
-- Idempotente: só adiciona se ainda não estiver na publication.
-- ────────────────────────────────────────────────────────────────────────────

DO $$
DECLARE
  t text;
  tables text[] := ARRAY[
    'mensagens_geral',
    'appointments',
    'saved_contacts',
    'attendances',
    'conversations',
    'kanban_cards',
    'kanban_columns',
    'alerts',
    'support_messages',
    'support_tickets'
  ];
BEGIN
  -- Garante que a publicação existe (Supabase já cria, mas por segurança)
  IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    CREATE PUBLICATION supabase_realtime;
  END IF;

  FOREACH t IN ARRAY tables LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = t
    ) THEN
      EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', t);
      RAISE NOTICE 'Added % to supabase_realtime', t;
    END IF;
  END LOOP;
END;
$$;

-- REPLICA IDENTITY FULL nas tabelas com event='*' (precisamos do old row
-- em UPDATE/DELETE pra alguns fluxos como apagar conversa encerrada).
-- Sem isso, payloads de UPDATE/DELETE vêm sem os campos antigos.
ALTER TABLE public.mensagens_geral SET (autovacuum_vacuum_scale_factor = 0.05);
ALTER TABLE public.attendances     REPLICA IDENTITY FULL;
ALTER TABLE public.conversations   REPLICA IDENTITY FULL;
ALTER TABLE public.mensagens_geral REPLICA IDENTITY FULL;
ALTER TABLE public.appointments    REPLICA IDENTITY FULL;
ALTER TABLE public.kanban_cards    REPLICA IDENTITY FULL;
ALTER TABLE public.saved_contacts  REPLICA IDENTITY FULL;
ALTER TABLE public.alerts          REPLICA IDENTITY FULL;


-- ── 20260511_reminder_fix_webhook.sql ─────────────────────────────────────────────────────────

-- ────────────────────────────────────────────────────────────────────────────
-- Migration: corrige process_appointment_reminders()
--   1. numero com sufixo @s.whatsapp.net (pra agrupar no mesmo ticket
--      do paciente — antes duplicava o card no painel de Conversas)
--   2. Dispara o webhook n8n via pg_net pra mensagem chegar no WhatsApp
--      (antes ficava só no banco como log, sem envio real)
-- ────────────────────────────────────────────────────────────────────────────

-- Habilita pg_net pra fazer HTTP POST de dentro do Postgres
CREATE EXTENSION IF NOT EXISTS pg_net;

CREATE OR REPLACE FUNCTION public.process_appointment_reminders()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  r           record;
  cnt         integer := 0;
  msg         text;
  appt_local  timestamptz;
  session_id  text;
  payload     jsonb;
BEGIN
  FOR r IN
    SELECT
      a.id,
      a.contact_numero,
      a.contact_nome,
      a.starts_at,
      a.instancia,
      c.name AS company_name,
      c.api_instancia,
      c.reminder_offset_minutes,
      p.name AS prof_name
    FROM public.appointments a
    JOIN public.companies c   ON c.instance = a.instancia
    LEFT JOIN public.professionals p ON p.id = a.professional_id
    WHERE c.reminder_enabled = true
      AND c.reminder_offset_minutes IS NOT NULL
      AND a.reminder_sent_at IS NULL
      AND a.contact_numero IS NOT NULL
      AND a.contact_numero <> ''
      AND a.status IN ('agendado', 'confirmado')
      AND a.starts_at > now()
      AND a.starts_at - make_interval(mins => c.reminder_offset_minutes) <= now()
  LOOP
    appt_local := r.starts_at AT TIME ZONE 'America/Sao_Paulo';

    msg := format(
      'Olá %s! 👋 Passando pra lembrar da sua consulta no dia %s às %s%s. Até lá! 🩺',
      r.contact_nome,
      to_char(appt_local, 'DD/MM'),
      to_char(appt_local, 'HH24:MI'),
      CASE
        WHEN r.prof_name IS NOT NULL AND r.prof_name <> ''
          THEN ' com ' || r.prof_name
        ELSE ''
      END
    );

    -- Session ID no formato Evolution (agrupa no mesmo ticket que as
    -- outras mensagens do paciente)
    session_id := r.contact_numero || '@s.whatsapp.net';

    -- 1) Loga no chat interno (aparece na thread de Conversas do painel)
    INSERT INTO public.mensagens_geral
      (instancia, numero, mensagem, type, "horaLastMessage", created_at, aplicativo)
    VALUES
      (r.instancia, session_id, msg, 'atendente',
       to_char(now() AT TIME ZONE 'America/Sao_Paulo', 'HH24:MI'),
       now(), 'whatsapp');

    -- 2) Dispara o webhook do n8n pra Evolution mandar no WhatsApp
    payload := jsonb_build_object(
      'message',       msg,
      'session_id',    session_id,
      'phone',         r.contact_numero,
      'instancia',     r.instancia,
      'api_instancia', r.api_instancia,
      'company',       r.company_name,
      'sender_name',   'Sistema (Lembrete automático)',
      'sender_email',  'sistema@medmag'
    );

    BEGIN
      PERFORM net.http_post(
        url     := 'https://n8n.nexladesenvolvimento.com.br/webhook/envioNexla',
        body    := payload,
        headers := '{"Content-Type": "application/json"}'::jsonb
      );
    EXCEPTION WHEN OTHERS THEN
      -- Não falha o lembrete se o webhook der erro — pelo menos o log
      -- ficou na conversa pra o operador saber que aconteceu
      RAISE NOTICE 'webhook fail for appt %: %', r.id, SQLERRM;
    END;

    UPDATE public.appointments
       SET reminder_sent_at = now()
     WHERE id = r.id;

    cnt := cnt + 1;
  END LOOP;

  RETURN cnt;
END;
$$;

GRANT EXECUTE ON FUNCTION public.process_appointment_reminders() TO service_role;

-- ─── Corrige a linha duplicada que foi inserida com numero errado ──────────
-- (cleanup do bug anterior — atualiza o numero pra ter o sufixo, assim
-- o painel agrupa com as outras mensagens do mesmo paciente)
UPDATE public.mensagens_geral
   SET numero = numero || '@s.whatsapp.net'
 WHERE numero NOT LIKE '%@%'
   AND numero ~ '^[0-9]+$';


-- ── 20260511_security_cleanup.sql ─────────────────────────────────────────────────────────

-- ────────────────────────────────────────────────────────────────────────────
-- Migration: Cleanup de segurança e schema
--
-- 1. Dropa 5 tabelas legadas n8n_chat_histories_* (lixo do banco antigo,
--    não usadas pelo CliniSac).
-- 2. Habilita RLS em public.mensagens com policy permissive (mesmo padrão
--    do resto do schema — segurança via anon key + custom auth).
-- 3. Remove índice duplicado companies_instance_unique (redundante com
--    companies_instance_key, ambos UNIQUE em instance).
--
-- Resolve os alertas CRITICAL do Supabase Security Advisor:
--   - RLS Disabled in Public (mensagens + 5 n8n_*)
--   - Sensitive Columns Exposed (5 n8n_*)
--   - Duplicate Index (companies)
-- ────────────────────────────────────────────────────────────────────────────

-- ─── 1. Drop tabelas legadas ───────────────────────────────────────────────
DROP TABLE IF EXISTS public.n8n_chat_histories_clinicanexla       CASCADE;
DROP TABLE IF EXISTS public.n8n_chat_histories_clinicanexlainsta  CASCADE;
DROP TABLE IF EXISTS public.n8n_chat_histories_etuany             CASCADE;
DROP TABLE IF EXISTS public.n8n_chat_histories_clinicaolhos       CASCADE;
DROP TABLE IF EXISTS public.n8n_chat_histories_adv_nexla          CASCADE;

-- ─── 2. RLS em mensagens ───────────────────────────────────────────────────
ALTER TABLE public.mensagens ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "allow_read mensagens"   ON public.mensagens;
DROP POLICY IF EXISTS "allow_insert mensagens" ON public.mensagens;
DROP POLICY IF EXISTS "allow_update mensagens" ON public.mensagens;
DROP POLICY IF EXISTS "allow_delete mensagens" ON public.mensagens;

CREATE POLICY "allow_read mensagens"   ON public.mensagens FOR SELECT USING (true);
CREATE POLICY "allow_insert mensagens" ON public.mensagens FOR INSERT WITH CHECK (true);
CREATE POLICY "allow_update mensagens" ON public.mensagens FOR UPDATE USING (true);
CREATE POLICY "allow_delete mensagens" ON public.mensagens FOR DELETE USING (true);

-- ─── 3. Remove constraint UNIQUE duplicado (companies_instance_key já cobre) ─
ALTER TABLE public.companies DROP CONSTRAINT IF EXISTS companies_instance_unique;


-- ── 20260512_companies_plan_price_override.sql ─────────────────────────────────────────────────────────

alter table companies add column if not exists plan_price_override numeric default null;


-- ── 20260512_companies_timezone.sql ─────────────────────────────────────────────────────────

alter table companies add column if not exists timezone text not null default '-03:00';


-- ── 20260512_contact_tags.sql ─────────────────────────────────────────────────────────

-- ────────────────────────────────────────────────────────────────────────────
-- Migration: tags de contato (etiquetas)
--
-- Permite a clínica criar etiquetas coloridas e atribuí-las aos
-- pacientes/contatos. Funciona por telefone (numero), não exige cadastro
-- completo do paciente — qualquer número que apareceu no chat pode receber tag.
--
-- Filtros nas telas de Conversas / Finalizados / Pacientes usam essas tags.
-- ────────────────────────────────────────────────────────────────────────────

-- 1) Definições das tags (uma por empresa/instância)
CREATE TABLE IF NOT EXISTS public.contact_tags (
  id         uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  instancia  text        NOT NULL,
  name       text        NOT NULL,
  color      text        NOT NULL DEFAULT '#2563EB',
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (instancia, name)
);

CREATE INDEX IF NOT EXISTS idx_contact_tags_instancia
  ON public.contact_tags (instancia);

-- 2) Atribuições (many-to-many entre número e tag)
CREATE TABLE IF NOT EXISTS public.contact_tag_assignments (
  id               uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  instancia        text        NOT NULL,
  numero           text        NOT NULL,   -- telefone bruto, sem sufixo @
  tag_id           uuid        NOT NULL REFERENCES public.contact_tags(id) ON DELETE CASCADE,
  created_at       timestamptz NOT NULL DEFAULT now(),
  created_by_email text,
  UNIQUE (instancia, numero, tag_id)
);

CREATE INDEX IF NOT EXISTS idx_contact_tag_assignments_lookup
  ON public.contact_tag_assignments (instancia, numero);

CREATE INDEX IF NOT EXISTS idx_contact_tag_assignments_tag
  ON public.contact_tag_assignments (tag_id);

-- 3) RLS — modelo permissive (seg. é no app)
ALTER TABLE public.contact_tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.contact_tag_assignments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS contact_tags_all ON public.contact_tags;
CREATE POLICY contact_tags_all ON public.contact_tags
  FOR ALL USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS contact_tag_assignments_all ON public.contact_tag_assignments;
CREATE POLICY contact_tag_assignments_all ON public.contact_tag_assignments
  FOR ALL USING (true) WITH CHECK (true);

-- 4) Realtime — pra picker/lista atualizarem ao vivo entre abas
ALTER PUBLICATION supabase_realtime ADD TABLE public.contact_tags;
ALTER PUBLICATION supabase_realtime ADD TABLE public.contact_tag_assignments;


-- ── 20260512_conversations_unique_session.sql ─────────────────────────────────────────────────────────

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'conversations_session_instancia_unique'
  ) then
    alter table conversations
      add constraint conversations_session_instancia_unique
      unique (session_id, instancia);
  end if;
end $$;


-- ── 20260512_performance_indexes.sql ─────────────────────────────────────────────────────────

-- Índices de performance para as tabelas multi-tenant mais consultadas.
-- mensagens_geral é a tabela mais pesada: todas as queries filtram por instancia+numero.
create index if not exists idx_mensagens_instancia_numero
  on mensagens_geral(instancia, numero);

create index if not exists idx_mensagens_instancia_created
  on mensagens_geral(instancia, created_at desc);

-- appointments: lookup por contato
create index if not exists idx_appointments_instancia_numero
  on appointments(instancia, contact_numero);

-- saved_contacts: lookup de número salvo
create index if not exists idx_saved_contacts_instancia_numero
  on saved_contacts(instancia, numero);

-- attendances: quem está atendendo qual número
create index if not exists idx_attendances_instancia_numero
  on attendances(instancia, numero);

-- kanban_cards: listagem por instância
create index if not exists idx_kanban_cards_instancia
  on kanban_cards(instancia);


-- ── 20260512_procedures_reminder.sql ─────────────────────────────────────────────────────────

alter table procedures add column if not exists reminder_message text;


-- ── 20260512_reminder_timestamp_fix.sql ─────────────────────────────────────────────────────────

-- ────────────────────────────────────────────────────────────────────────────
-- Migration: corrige horaLastMessage do process_appointment_reminders()
--
-- Antes: inseria só 'HH24:MI' (ex: '09:11') — o frontend tentava new Date('09:11')
--        e dava 'Invalid Date' no display da conversa.
-- Depois: usa 'DD/MM/YYYY HH24:MI:SS' (mesmo formato dos messages da IA),
--        que o parseTimestamp() do CompanyConversations já trata.
-- ────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.process_appointment_reminders()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  r           record;
  cnt         integer := 0;
  msg         text;
  appt_local  timestamptz;
  session_id  text;
  payload     jsonb;
BEGIN
  FOR r IN
    SELECT
      a.id,
      a.contact_numero,
      a.contact_nome,
      a.starts_at,
      a.instancia,
      c.name AS company_name,
      c.api_instancia,
      c.reminder_offset_minutes,
      p.name AS prof_name
    FROM public.appointments a
    JOIN public.companies c   ON c.instance = a.instancia
    LEFT JOIN public.professionals p ON p.id = a.professional_id
    WHERE c.reminder_enabled = true
      AND c.reminder_offset_minutes IS NOT NULL
      AND a.reminder_sent_at IS NULL
      AND a.contact_numero IS NOT NULL
      AND a.contact_numero <> ''
      AND a.status IN ('agendado', 'confirmado')
      AND a.starts_at > now()
      AND a.starts_at - make_interval(mins => c.reminder_offset_minutes) <= now()
  LOOP
    appt_local := r.starts_at AT TIME ZONE 'America/Sao_Paulo';

    msg := format(
      'Olá %s! 👋 Passando pra lembrar da sua consulta no dia %s às %s%s. Até lá! 🩺',
      r.contact_nome,
      to_char(appt_local, 'DD/MM'),
      to_char(appt_local, 'HH24:MI'),
      CASE
        WHEN r.prof_name IS NOT NULL AND r.prof_name <> ''
          THEN ' com ' || r.prof_name
        ELSE ''
      END
    );

    session_id := r.contact_numero || '@s.whatsapp.net';

    -- 1) Loga no chat interno com timestamp completo (DD/MM/YYYY HH:MM:SS)
    --    pra o parseTimestamp do frontend conseguir parsear
    INSERT INTO public.mensagens_geral
      (instancia, numero, mensagem, type, "horaLastMessage", created_at, aplicativo)
    VALUES
      (r.instancia, session_id, msg, 'atendente',
       to_char(now() AT TIME ZONE 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI:SS'),
       now(), 'whatsapp');

    -- 2) Webhook pro n8n → Evolution → WhatsApp
    payload := jsonb_build_object(
      'message',       msg,
      'session_id',    session_id,
      'phone',         r.contact_numero,
      'instancia',     r.instancia,
      'api_instancia', r.api_instancia,
      'company',       r.company_name,
      'sender_name',   'Sistema (Lembrete automático)',
      'sender_email',  'sistema@medmag'
    );

    BEGIN
      PERFORM net.http_post(
        url     := 'https://n8n.nexladesenvolvimento.com.br/webhook/envioNexla',
        body    := payload,
        headers := '{"Content-Type": "application/json"}'::jsonb
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'webhook fail for appt %: %', r.id, SQLERRM;
    END;

    UPDATE public.appointments
       SET reminder_sent_at = now()
     WHERE id = r.id;

    cnt := cnt + 1;
  END LOOP;

  RETURN cnt;
END;
$$;

GRANT EXECUTE ON FUNCTION public.process_appointment_reminders() TO service_role;

-- Cleanup retroativo: corrige mensagens existentes que ficaram com formato
-- só 'HH:MM' (sem data) — pega created_at e formata corretamente.
UPDATE public.mensagens_geral
   SET "horaLastMessage" = to_char(created_at AT TIME ZONE 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI:SS')
 WHERE "horaLastMessage" ~ '^[0-9]{2}:[0-9]{2}$';


-- ── 20260512_user_limit_trigger.sql ─────────────────────────────────────────────────────────

create or replace function check_user_limit()
returns trigger language plpgsql as $$
declare
  co      record;
  max_u   int;
  curr_u  int;
  plan_max int;
begin
  select * into co from companies where id = new.company_id;
  if not found then return new; end if;

  -- Limite efetivo: override direto tem prioridade; senão, default do plano + extras
  if co.max_users is not null and co.max_users > 0 then
    max_u := co.max_users;
  else
    plan_max := case co.plan
      when 'Starter'  then 5
      when 'Pro'      then 20
      when 'Business' then null
      else 5
    end;
    if plan_max is null then return new; end if; -- Business = ilimitado
    max_u := plan_max + coalesce(co.extra_users, 0);
  end if;

  select count(*) into curr_u
    from users
    where company_id = new.company_id
      and active is not false;

  if curr_u >= max_u then
    raise exception 'Limite de usuários atingido para esta empresa (máx: %). Contrate usuários extras ou faça upgrade de plano.', max_u;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_check_user_limit on users;
create trigger trg_check_user_limit
  before insert on users
  for each row execute function check_user_limit();


-- ── 20260513_kanban_contact_comments.sql ─────────────────────────────────────────────────────────

-- Vincula card a um paciente cadastrado
ALTER TABLE kanban_cards ADD COLUMN IF NOT EXISTS contact_id uuid REFERENCES saved_contacts(id) ON DELETE SET NULL;
ALTER TABLE kanban_cards ADD COLUMN IF NOT EXISTS contact_nome text;

-- Comentários por card
CREATE TABLE IF NOT EXISTS kanban_card_comments (
  id          uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  card_id     uuid NOT NULL REFERENCES kanban_cards(id) ON DELETE CASCADE,
  instancia   text NOT NULL,
  author_name text NOT NULL,
  author_email text,
  body        text NOT NULL,
  created_at  timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_kanban_card_comments_card ON kanban_card_comments(card_id);

ALTER TABLE kanban_card_comments ENABLE ROW LEVEL SECURITY;
CREATE POLICY kanban_card_comments_all ON kanban_card_comments USING (true) WITH CHECK (true);


-- ── 20260519_agent_config.sql ─────────────────────────────────────────────────────────

-- Adiciona coluna de configuração do agente IA por empresa
alter table companies
  add column if not exists agent_config jsonb;


-- ── 20260519_agent_configs_table.sql ─────────────────────────────────────────────────────────

-- Tabela dedicada para configuração do agente IA por instância
-- Mais fácil de consultar no n8n: SELECT * FROM agent_configs WHERE instancia = 'xxx'

create table if not exists agent_configs (
  id          uuid        default gen_random_uuid() primary key,
  instancia   text        not null unique,
  company_id  uuid        references companies(id) on delete cascade,
  config      jsonb       not null default '{}',
  updated_at  timestamptz default now()
);

-- Atualiza updated_at automaticamente
create or replace function update_agent_configs_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_agent_configs_updated_at on agent_configs;
create trigger trg_agent_configs_updated_at
  before update on agent_configs
  for each row execute function update_agent_configs_updated_at();

-- RLS — política aberta (auth customizada via JWT próprio, não Supabase Auth)
-- Acesso real é controlado pela instancia no backend/n8n com service_role key
alter table agent_configs enable row level security;

DO $$ BEGIN
  CREATE POLICY "agent_configs_all" ON public.agent_configs
    FOR ALL TO authenticated, anon USING (true) WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;


-- ── 20260519_landing_analytics.sql ─────────────────────────────────────────────────────────

-- Landing page analytics: session tracking for anonymous visitors
create table if not exists landing_analytics (
  id          uuid        default gen_random_uuid() primary key,
  session_id  text        not null unique,
  created_at  timestamptz default now() not null,
  updated_at  timestamptz,
  duration_ms integer,
  referrer    text,
  utm_source  text,
  utm_medium  text,
  utm_campaign text,
  device      text,
  scroll_depth smallint   default 0,
  cta_clicked boolean     default false
);

alter table landing_analytics enable row level security;

-- Visitors (anon) can insert/update their own session
create policy "landing_anon_insert" on landing_analytics
  for insert to anon with check (true);

create policy "landing_anon_update" on landing_analytics
  for update to anon using (true) with check (true);

-- Any authenticated user (admins) can read
create policy "landing_auth_read" on landing_analytics
  for select using (auth.role() = 'authenticated' or true);

-- Enable Realtime so the admin page receives live updates
alter publication supabase_realtime add table landing_analytics;


-- ── 20260519_landing_section_times.sql ─────────────────────────────────────────────────────────

-- Add per-section time tracking to landing analytics
alter table landing_analytics
  add column if not exists section_times jsonb;


-- ── 20260520_mensagens_geral_idgrupo.sql ─────────────────────────────────────────────────────────

alter table mensagens_geral
  add column if not exists idgrupo text;


-- ── 20260520_mensagens_geral_idgrupo_index.sql ─────────────────────────────────────────────────────────

-- Índice para filtrar mensagens de grupos (idgrupo sempre termina em @g.us quando preenchido)
create index if not exists idx_mensagens_geral_idgrupo
  on mensagens_geral (instancia, idgrupo)
  where idgrupo is not null;


-- ── 20260520_mensagens_geral_nome.sql ─────────────────────────────────────────────────────────

alter table mensagens_geral
  add column if not exists nome text;


-- ── 20260520_mensagens_geral_nomegrupo.sql ─────────────────────────────────────────────────────────

alter table mensagens_geral
  add column if not exists nomegrupo text;


-- ── 20260525_clientes_foto.sql ─────────────────────────────────────────────────────────

-- Adiciona coluna foto (base64 ou URL) na tabela clientes
-- Usada pelo fluxo n8n para salvar a foto de perfil do WhatsApp no primeiro contato
ALTER TABLE public.clientes ADD COLUMN IF NOT EXISTS foto TEXT;


-- ── 20260526_companies_numero_base.sql ─────────────────────────────────────────────────────────

ALTER TABLE public.companies ADD COLUMN IF NOT EXISTS numero_base text;


-- ── 20260603_send_mensagem_geral_nome.sql ─────────────────────────────────────────────────────────

-- Atualiza RPC send_mensagem_geral para aceitar nome do remetente
CREATE OR REPLACE FUNCTION public.send_mensagem_geral(
  p_instancia text,
  p_numero    text,
  p_mensagem  text,
  p_type      text,
  p_hora      text,
  p_base64    text DEFAULT NULL,
  p_nome      text DEFAULT NULL
) RETURNS void
  LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO public.mensagens_geral
    (instancia, numero, mensagem, type, "horaLastMessage", base64, nome, created_at)
  VALUES
    (p_instancia, p_numero, p_mensagem, p_type, p_hora, p_base64, p_nome, NOW());
END;
$$;


-- ── 20260611_anamneses.sql ─────────────────────────────────────────────────────────

-- Modelos de anamnese (por clínica)
CREATE TABLE IF NOT EXISTS public.anamnese_templates (
  id         uuid DEFAULT gen_random_uuid() NOT NULL PRIMARY KEY,
  instancia  text NOT NULL,
  nome       text NOT NULL,
  is_default boolean DEFAULT false,
  questions  jsonb NOT NULL DEFAULT '[]',
  created_at timestamptz DEFAULT NOW(),
  created_by text
);

CREATE INDEX IF NOT EXISTS anamnese_templates_instancia_idx
  ON public.anamnese_templates (instancia);

ALTER TABLE public.anamnese_templates ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "allow_all_anamnese_templates"
    ON public.anamnese_templates FOR ALL USING (true) WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- Respostas de anamnese por paciente
CREATE TABLE IF NOT EXISTS public.anamnese_responses (
  id             uuid DEFAULT gen_random_uuid() NOT NULL PRIMARY KEY,
  instancia      text NOT NULL,
  contact_id     uuid REFERENCES public.saved_contacts(id) ON DELETE CASCADE,
  contact_numero text,
  template_id    uuid REFERENCES public.anamnese_templates(id) ON DELETE SET NULL,
  template_name  text,
  questions      jsonb NOT NULL DEFAULT '[]',
  answers        jsonb NOT NULL DEFAULT '{}',
  filled_by      text,
  filled_at      timestamptz DEFAULT NOW(),
  appointment_id uuid REFERENCES public.appointments(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS anamnese_responses_contact_idx
  ON public.anamnese_responses (instancia, contact_id);

ALTER TABLE public.anamnese_responses ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "allow_all_anamnese_responses"
    ON public.anamnese_responses FOR ALL USING (true) WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;


-- ── 20260611_appointments_prontuario.sql ─────────────────────────────────────────────────────────

-- Adiciona campo de prontuário ao agendamento
ALTER TABLE public.appointments
  ADD COLUMN IF NOT EXISTS prontuario text,
  ADD COLUMN IF NOT EXISTS prontuario_at timestamptz,
  ADD COLUMN IF NOT EXISTS prontuario_by text;


-- ── 20260611_mensagens_geral_unique_id_mensagem.sql ─────────────────────────────────────────────────────────

-- Índice único parcial em id_mensagem para evitar duplicatas do echo do Evolution API
-- Ignora registros com id_mensagem NULL (mensagens sem ID ainda)
CREATE UNIQUE INDEX IF NOT EXISTS mensagens_geral_id_mensagem_instancia_unique
  ON public.mensagens_geral (id_mensagem, instancia)
  WHERE id_mensagem IS NOT NULL;


-- ── 20260611_orcamentos.sql ─────────────────────────────────────────────────────────

-- Orçamentos / planos de tratamento
CREATE TABLE IF NOT EXISTS public.orcamentos (
  id             uuid DEFAULT gen_random_uuid() NOT NULL PRIMARY KEY,
  instancia      text NOT NULL,
  contact_id     uuid REFERENCES public.saved_contacts(id) ON DELETE CASCADE,
  contact_numero text,
  status         text DEFAULT 'pendente' CHECK (status IN ('pendente', 'aprovado', 'recusado')),
  desconto       numeric DEFAULT 0,
  entrada        numeric DEFAULT 0,
  parcelas       integer DEFAULT 1,
  notes          text,
  created_by     text,
  created_at     timestamptz DEFAULT NOW(),
  approved_at    timestamptz
);

CREATE INDEX IF NOT EXISTS orcamentos_contact_idx
  ON public.orcamentos (instancia, contact_id);

ALTER TABLE public.orcamentos ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "allow_all_orcamentos"
    ON public.orcamentos FOR ALL USING (true) WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- Itens do orçamento (procedimentos)
CREATE TABLE IF NOT EXISTS public.orcamento_items (
  id           uuid DEFAULT gen_random_uuid() NOT NULL PRIMARY KEY,
  orcamento_id uuid REFERENCES public.orcamentos(id) ON DELETE CASCADE,
  procedimento text NOT NULL,
  dente        text,
  faces        text,
  valor        numeric NOT NULL DEFAULT 0,
  ordem        integer DEFAULT 0
);

ALTER TABLE public.orcamento_items ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "allow_all_orcamento_items"
    ON public.orcamento_items FOR ALL USING (true) WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;


-- ── 20260611_prontuario_attachments.sql ─────────────────────────────────────────────────────────

-- Tabela de anexos do prontuário (fotos de evolução, documentos, laudos)
CREATE TABLE IF NOT EXISTS public.prontuario_attachments (
  id           uuid DEFAULT gen_random_uuid() NOT NULL PRIMARY KEY,
  instancia    text NOT NULL,
  contact_numero text NOT NULL,
  appointment_id uuid REFERENCES public.appointments(id) ON DELETE SET NULL,
  file_path    text NOT NULL,
  file_name    text NOT NULL,
  file_type    text,
  file_size    integer,
  uploaded_by  text,
  uploaded_at  timestamptz DEFAULT NOW(),
  caption      text
);

CREATE INDEX IF NOT EXISTS prontuario_attachments_instancia_numero_idx
  ON public.prontuario_attachments (instancia, contact_numero);

ALTER TABLE public.prontuario_attachments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "allow_all_prontuario_attachments"
  ON public.prontuario_attachments FOR ALL USING (true) WITH CHECK (true);

-- [bloco de Storage/prontuário removido do setup — criar o bucket pelo painel Storage depois]

-- ── 20260615_conversation_reads.sql ─────────────────────────────────────────────────────────

-- Rastreia quando cada usuário leu cada conversa (para badge de não lidos)
CREATE TABLE IF NOT EXISTS public.conversation_reads (
  instancia    text NOT NULL,
  session_id   text NOT NULL,
  user_email   text NOT NULL,
  last_read_at timestamptz DEFAULT NOW(),
  PRIMARY KEY (instancia, session_id, user_email)
);

ALTER TABLE public.conversation_reads ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "allow_all_conversation_reads"
    ON public.conversation_reads FOR ALL USING (true) WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;


-- ── 20260617_reminder_group.sql ─────────────────────────────────────────────────────────

-- ────────────────────────────────────────────────────────────────────────────
-- Migration: permite enviar lembrete de agendamento para um grupo WhatsApp
--
-- companies.reminder_group_id — idgrupo do grupo (ex: 120363@g.us)
--                               NULL = não envia pro grupo
--
-- A função process_appointment_reminders() é atualizada para, quando
-- reminder_group_id estiver preenchido, disparar TAMBÉM uma mensagem pro
-- grupo com os dados do agendamento.
-- ────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS reminder_group_id text;

COMMENT ON COLUMN public.companies.reminder_group_id IS
  'idgrupo do grupo WhatsApp (ex: 120363123456@g.us) para receber cópia do lembrete. NULL = só envia pro contato individual.';

-- ─── Função atualizada ──────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.process_appointment_reminders()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  r             record;
  cnt           integer := 0;
  msg           text;
  group_msg     text;
  appt_local    timestamptz;
  session_id    text;
  payload       jsonb;
  group_payload jsonb;
BEGIN
  FOR r IN
    SELECT
      a.id,
      a.contact_numero,
      a.contact_nome,
      a.starts_at,
      a.instancia,
      c.name            AS company_name,
      c.api_instancia,
      c.reminder_offset_minutes,
      c.reminder_group_id,
      p.name            AS prof_name
    FROM public.appointments a
    JOIN public.companies c   ON c.instance = a.instancia
    LEFT JOIN public.professionals p ON p.id = a.professional_id
    WHERE c.reminder_enabled = true
      AND c.reminder_offset_minutes IS NOT NULL
      AND a.reminder_sent_at IS NULL
      AND a.contact_numero IS NOT NULL
      AND a.contact_numero <> ''
      AND a.status IN ('agendado', 'confirmado')
      AND a.starts_at > now()
      AND a.starts_at - make_interval(mins => c.reminder_offset_minutes) <= now()
  LOOP
    appt_local := r.starts_at AT TIME ZONE 'America/Sao_Paulo';

    -- Mensagem individual (para o paciente)
    msg := format(
      'Olá %s! 👋 Passando pra lembrar da sua consulta no dia %s às %s%s. Até lá! 🩺',
      r.contact_nome,
      to_char(appt_local, 'DD/MM'),
      to_char(appt_local, 'HH24:MI'),
      CASE
        WHEN r.prof_name IS NOT NULL AND r.prof_name <> ''
          THEN ' com ' || r.prof_name
        ELSE ''
      END
    );

    session_id := r.contact_numero || '@s.whatsapp.net';

    -- 1) Loga no chat interno do paciente
    INSERT INTO public.mensagens_geral
      (instancia, numero, mensagem, type, "horaLastMessage", created_at, aplicativo)
    VALUES
      (r.instancia, session_id, msg, 'atendente',
       to_char(now() AT TIME ZONE 'America/Sao_Paulo', 'HH24:MI'),
       now(), 'whatsapp');

    -- 2) Dispara webhook individual
    payload := jsonb_build_object(
      'message',       msg,
      'session_id',    session_id,
      'phone',         r.contact_numero,
      'instancia',     r.instancia,
      'api_instancia', r.api_instancia,
      'company',       r.company_name,
      'sender_name',   'Sistema (Lembrete automático)',
      'sender_email',  'sistema@medmag'
    );

    BEGIN
      PERFORM net.http_post(
        url     := 'https://n8n.nexladesenvolvimento.com.br/webhook/envioNexla',
        body    := payload,
        headers := '{"Content-Type": "application/json"}'::jsonb
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'webhook individual fail for appt %: %', r.id, SQLERRM;
    END;

    -- 3) Envia para o grupo (se configurado)
    IF r.reminder_group_id IS NOT NULL AND r.reminder_group_id <> '' THEN
      group_msg := format(
        '📅 Lembrete: *%s* tem consulta no dia *%s* às *%s*%s. 🩺',
        r.contact_nome,
        to_char(appt_local, 'DD/MM'),
        to_char(appt_local, 'HH24:MI'),
        CASE
          WHEN r.prof_name IS NOT NULL AND r.prof_name <> ''
            THEN ' com *' || r.prof_name || '*'
          ELSE ''
        END
      );

      -- Loga no chat do grupo
      INSERT INTO public.mensagens_geral
        (instancia, numero, idgrupo, mensagem, type, "horaLastMessage", created_at, aplicativo)
      VALUES
        (r.instancia, r.instancia, r.reminder_group_id, group_msg, 'atendente',
         to_char(now() AT TIME ZONE 'America/Sao_Paulo', 'HH24:MI'),
         now(), 'whatsapp');

      -- Dispara webhook para o grupo
      group_payload := jsonb_build_object(
        'message',       group_msg,
        'mensagem',      group_msg,
        'session_id',    r.reminder_group_id,
        'number',        r.reminder_group_id,
        'idgrupo',       r.reminder_group_id,
        'instancia',     r.instancia,
        'api_instancia', r.api_instancia,
        'company',       r.company_name,
        'sender_name',   'Sistema (Lembrete automático)',
        'sender_email',  'sistema@medmag',
        'ai_enabled',    false
      );

      BEGIN
        PERFORM net.http_post(
          url     := 'https://n8n.nexladesenvolvimento.com.br/webhook/envioNexla',
          body    := group_payload,
          headers := '{"Content-Type": "application/json"}'::jsonb
        );
      EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'webhook grupo fail for appt %: %', r.id, SQLERRM;
      END;
    END IF;

    UPDATE public.appointments
       SET reminder_sent_at = now()
     WHERE id = r.id;

    cnt := cnt + 1;
  END LOOP;

  RETURN cnt;
END;
$$;

GRANT EXECUTE ON FUNCTION public.process_appointment_reminders() TO service_role;


-- ── 20260618_appointments_extra_recipients.sql ─────────────────────────────────────────────────────────

-- Destinatários extras por agendamento (contatos individuais ou grupos)
-- Formato: [{"nome":"...", "numero":"..."}] ou [{"nome":"...", "idgrupo":"...@g.us"}]
ALTER TABLE public.appointments
  ADD COLUMN IF NOT EXISTS extra_recipients jsonb DEFAULT '[]'::jsonb;

-- Atualiza process_appointment_reminders para enviar também aos extra_recipients
CREATE OR REPLACE FUNCTION public.process_appointment_reminders()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  r             record;
  recip         jsonb;
  cnt           integer := 0;
  msg           text;
  group_msg     text;
  recip_msg     text;
  appt_local    timestamptz;
  session_id    text;
  payload       jsonb;
  group_payload jsonb;
  recip_payload jsonb;
  recip_nome    text;
  recip_numero  text;
  recip_idgrupo text;
BEGIN
  FOR r IN
    SELECT
      a.id,
      a.contact_numero,
      a.contact_nome,
      a.starts_at,
      a.instancia,
      COALESCE(a.extra_recipients, '[]'::jsonb) AS extra_recipients,
      c.name            AS company_name,
      c.api_instancia,
      c.reminder_offset_minutes,
      c.reminder_group_id,
      p.name            AS prof_name
    FROM public.appointments a
    JOIN public.companies c   ON c.instance = a.instancia
    LEFT JOIN public.professionals p ON p.id = a.professional_id
    WHERE c.reminder_enabled = true
      AND c.reminder_offset_minutes IS NOT NULL
      AND a.reminder_sent_at IS NULL
      AND a.contact_numero IS NOT NULL
      AND a.contact_numero <> ''
      AND a.status IN ('agendado', 'confirmado')
      AND a.starts_at > now()
      AND a.starts_at - make_interval(mins => c.reminder_offset_minutes) <= now()
  LOOP
    appt_local := r.starts_at AT TIME ZONE 'America/Sao_Paulo';

    -- Mensagem individual (para o paciente principal)
    msg := format(
      'Olá %s! 👋 Passando pra lembrar da sua consulta no dia %s às %s%s. Até lá! 🩺',
      r.contact_nome,
      to_char(appt_local, 'DD/MM'),
      to_char(appt_local, 'HH24:MI'),
      CASE WHEN r.prof_name IS NOT NULL AND r.prof_name <> ''
        THEN ' com ' || r.prof_name ELSE '' END
    );

    session_id := r.contact_numero || '@s.whatsapp.net';

    INSERT INTO public.mensagens_geral
      (instancia, numero, mensagem, type, "horaLastMessage", created_at, aplicativo)
    VALUES
      (r.instancia, session_id, msg, 'atendente',
       to_char(now() AT TIME ZONE 'America/Sao_Paulo', 'HH24:MI'), now(), 'whatsapp');

    payload := jsonb_build_object(
      'message', msg, 'session_id', session_id, 'phone', r.contact_numero,
      'instancia', r.instancia, 'api_instancia', r.api_instancia,
      'company', r.company_name,
      'sender_name', 'Sistema (Lembrete automático)', 'sender_email', 'sistema@medmag'
    );
    BEGIN
      PERFORM net.http_post(
        url := 'https://n8n.nexladesenvolvimento.com.br/webhook/envioNexla',
        body := payload, headers := '{"Content-Type": "application/json"}'::jsonb
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'webhook individual fail for appt %: %', r.id, SQLERRM;
    END;

    -- Grupo global da empresa (se configurado)
    IF r.reminder_group_id IS NOT NULL AND r.reminder_group_id <> '' THEN
      group_msg := format(
        '📅 Lembrete: *%s* tem consulta no dia *%s* às *%s*%s. 🩺',
        r.contact_nome, to_char(appt_local, 'DD/MM'), to_char(appt_local, 'HH24:MI'),
        CASE WHEN r.prof_name IS NOT NULL AND r.prof_name <> ''
          THEN ' com *' || r.prof_name || '*' ELSE '' END
      );

      INSERT INTO public.mensagens_geral
        (instancia, numero, idgrupo, mensagem, type, "horaLastMessage", created_at, aplicativo)
      VALUES
        (r.instancia, r.instancia, r.reminder_group_id, group_msg, 'atendente',
         to_char(now() AT TIME ZONE 'America/Sao_Paulo', 'HH24:MI'), now(), 'whatsapp');

      group_payload := jsonb_build_object(
        'message', group_msg, 'mensagem', group_msg,
        'session_id', r.reminder_group_id, 'number', r.reminder_group_id,
        'idgrupo', r.reminder_group_id,
        'instancia', r.instancia, 'api_instancia', r.api_instancia,
        'company', r.company_name,
        'sender_name', 'Sistema (Lembrete automático)', 'sender_email', 'sistema@medmag',
        'ai_enabled', false
      );
      BEGIN
        PERFORM net.http_post(
          url := 'https://n8n.nexladesenvolvimento.com.br/webhook/envioNexla',
          body := group_payload, headers := '{"Content-Type": "application/json"}'::jsonb
        );
      EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'webhook grupo global fail for appt %: %', r.id, SQLERRM;
      END;
    END IF;

    -- Destinatários extras do agendamento
    FOR recip IN SELECT * FROM jsonb_array_elements(r.extra_recipients)
    LOOP
      recip_nome    := recip->>'nome';
      recip_numero  := recip->>'numero';
      recip_idgrupo := recip->>'idgrupo';

      IF recip_idgrupo IS NOT NULL AND recip_idgrupo <> '' THEN
        -- É um grupo
        recip_msg := format(
          '📅 Lembrete: *%s* tem consulta no dia *%s* às *%s*%s. 🩺',
          r.contact_nome, to_char(appt_local, 'DD/MM'), to_char(appt_local, 'HH24:MI'),
          CASE WHEN r.prof_name IS NOT NULL AND r.prof_name <> ''
            THEN ' com *' || r.prof_name || '*' ELSE '' END
        );

        INSERT INTO public.mensagens_geral
          (instancia, numero, idgrupo, mensagem, type, "horaLastMessage", created_at, aplicativo)
        VALUES
          (r.instancia, r.instancia, recip_idgrupo, recip_msg, 'atendente',
           to_char(now() AT TIME ZONE 'America/Sao_Paulo', 'HH24:MI'), now(), 'whatsapp');

        recip_payload := jsonb_build_object(
          'message', recip_msg, 'mensagem', recip_msg,
          'session_id', recip_idgrupo, 'number', recip_idgrupo, 'idgrupo', recip_idgrupo,
          'instancia', r.instancia, 'api_instancia', r.api_instancia,
          'company', r.company_name,
          'sender_name', 'Sistema (Lembrete automático)', 'sender_email', 'sistema@medmag',
          'ai_enabled', false
        );

      ELSIF recip_numero IS NOT NULL AND recip_numero <> '' THEN
        -- É um contato individual
        recip_msg := format(
          'Olá %s! 👋 Passando pra lembrar da consulta de %s no dia %s às %s%s. 🩺',
          COALESCE(recip_nome, 'tudo bem'),
          r.contact_nome,
          to_char(appt_local, 'DD/MM'),
          to_char(appt_local, 'HH24:MI'),
          CASE WHEN r.prof_name IS NOT NULL AND r.prof_name <> ''
            THEN ' com ' || r.prof_name ELSE '' END
        );
        session_id := recip_numero || '@s.whatsapp.net';

        INSERT INTO public.mensagens_geral
          (instancia, numero, mensagem, type, "horaLastMessage", created_at, aplicativo)
        VALUES
          (r.instancia, session_id, recip_msg, 'atendente',
           to_char(now() AT TIME ZONE 'America/Sao_Paulo', 'HH24:MI'), now(), 'whatsapp');

        recip_payload := jsonb_build_object(
          'message', recip_msg, 'session_id', session_id, 'phone', recip_numero,
          'instancia', r.instancia, 'api_instancia', r.api_instancia,
          'company', r.company_name,
          'sender_name', 'Sistema (Lembrete automático)', 'sender_email', 'sistema@medmag'
        );
      ELSE
        CONTINUE;
      END IF;

      BEGIN
        PERFORM net.http_post(
          url := 'https://n8n.nexladesenvolvimento.com.br/webhook/envioNexla',
          body := recip_payload, headers := '{"Content-Type": "application/json"}'::jsonb
        );
      EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'webhook recip extra fail for appt %: %', r.id, SQLERRM;
      END;
    END LOOP;

    UPDATE public.appointments SET reminder_sent_at = now() WHERE id = r.id;
    cnt := cnt + 1;
  END LOOP;

  RETURN cnt;
END;
$$;

GRANT EXECUTE ON FUNCTION public.process_appointment_reminders() TO service_role;


-- ── 20260618_companies_modules.sql ─────────────────────────────────────────────────────────

-- Módulos habilitados por empresa (pacote personalizado)
-- Formato: { "financeiro": true, "grupos": false, "kanban": true, ... }
-- NULL = usa defaults do plano (tudo habilitado)
ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS modules jsonb DEFAULT NULL;

COMMENT ON COLUMN public.companies.modules IS
  'Módulos habilitados individualmente. NULL = todos habilitados (padrão do plano).';


-- ── 20260618_quick_messages.sql ─────────────────────────────────────────────────────────

-- Mensagens rápidas por instância (respostas prontas no chat)
CREATE TABLE IF NOT EXISTS public.quick_messages (
  id         uuid        DEFAULT gen_random_uuid() PRIMARY KEY,
  instancia  text        NOT NULL,
  titulo     text        NOT NULL,
  mensagem   text        NOT NULL,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE public.quick_messages ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "quick_messages_all" ON public.quick_messages
    FOR ALL TO authenticated, anon
    USING (true) WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS quick_messages_instancia_idx ON public.quick_messages (instancia);


-- ── 20260619_crm.sql ─────────────────────────────────────────────────────────

-- ─────────────────────────────────────────────────────────────────────────────
-- CRM: funis, etapas, contatos, histórico de interações
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.crm_funnels (
  id         uuid        DEFAULT gen_random_uuid() PRIMARY KEY,
  instancia  text        NOT NULL,
  nome       text        NOT NULL,
  posicao    integer     DEFAULT 0,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.crm_stages (
  id          uuid        DEFAULT gen_random_uuid() PRIMARY KEY,
  funil_id    uuid        REFERENCES public.crm_funnels(id) ON DELETE CASCADE,
  instancia   text        NOT NULL,
  nome        text        NOT NULL,
  cor         text        DEFAULT '#6B7280',
  posicao     integer     DEFAULT 0,
  alerta_dias integer     DEFAULT 7,
  created_at  timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.crm_contacts (
  id                  uuid        DEFAULT gen_random_uuid() PRIMARY KEY,
  instancia           text        NOT NULL,
  phone               text        NOT NULL,
  nome                text,
  email               text,
  stage_id            uuid        REFERENCES public.crm_stages(id) ON DELETE SET NULL,
  funil_id            uuid        REFERENCES public.crm_funnels(id) ON DELETE SET NULL,
  temperatura         text        DEFAULT 'frio' CHECK (temperatura IN ('frio','morno','quente')),
  tags                text[]      DEFAULT '{}',
  responsavel_id      uuid,
  responsavel_nome    text,
  origem              text,
  observacoes         text,
  motivo_perda        text,
  data_ult_contato    timestamptz,
  data_entrada_etapa  timestamptz DEFAULT now(),
  created_at          timestamptz DEFAULT now(),
  UNIQUE(instancia, phone)
);

CREATE TABLE IF NOT EXISTS public.crm_interactions (
  id         uuid        DEFAULT gen_random_uuid() PRIMARY KEY,
  instancia  text        NOT NULL,
  phone      text        NOT NULL,
  tipo       text        NOT NULL CHECK (tipo IN ('nota','etapa','mensagem','agendamento','tarefa')),
  conteudo   text,
  metadata   jsonb,
  autor_nome text,
  created_at timestamptz DEFAULT now()
);

-- RLS
ALTER TABLE public.crm_funnels      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crm_stages       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crm_contacts     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crm_interactions ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN CREATE POLICY "crm_funnels_all"      ON public.crm_funnels      FOR ALL TO authenticated,anon USING(true) WITH CHECK(true); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE POLICY "crm_stages_all"       ON public.crm_stages       FOR ALL TO authenticated,anon USING(true) WITH CHECK(true); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE POLICY "crm_contacts_all"     ON public.crm_contacts     FOR ALL TO authenticated,anon USING(true) WITH CHECK(true); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE POLICY "crm_interactions_all" ON public.crm_interactions FOR ALL TO authenticated,anon USING(true) WITH CHECK(true); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS crm_funnels_inst_idx      ON public.crm_funnels(instancia);
CREATE INDEX IF NOT EXISTS crm_stages_funil_idx      ON public.crm_stages(funil_id);
CREATE INDEX IF NOT EXISTS crm_contacts_inst_idx     ON public.crm_contacts(instancia);
CREATE INDEX IF NOT EXISTS crm_contacts_stage_idx    ON public.crm_contacts(stage_id);
CREATE INDEX IF NOT EXISTS crm_interactions_phone_idx ON public.crm_interactions(instancia, phone);


-- ── 20260619_crm_kanban.sql ─────────────────────────────────────────────────────────

-- Vincula cards do Kanban a contatos do CRM
ALTER TABLE public.kanban_cards
  ADD COLUMN IF NOT EXISTS crm_contact_id uuid REFERENCES public.crm_contacts(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS kanban_cards_crm_contact_idx ON public.kanban_cards(crm_contact_id);


-- ── 20260619_crm_phase4.sql ─────────────────────────────────────────────────────────

-- ─────────────────────────────────────────────────────────────────────────────
-- CRM Fase 4: listas dinâmicas + auto-avançar etapa ao agendar
-- ─────────────────────────────────────────────────────────────────────────────

-- Listas dinâmicas (filtros salvos)
CREATE TABLE IF NOT EXISTS public.crm_lists (
  id         uuid        DEFAULT gen_random_uuid() PRIMARY KEY,
  instancia  text        NOT NULL,
  nome       text        NOT NULL,
  filtros    jsonb       DEFAULT '{}',
  created_at timestamptz DEFAULT now()
);

ALTER TABLE public.crm_lists ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "crm_lists_all" ON public.crm_lists FOR ALL TO authenticated,anon USING(true) WITH CHECK(true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS crm_lists_inst_idx ON public.crm_lists(instancia);

-- ─── Trigger: avança etapa CRM ao criar agendamento ──────────────────────────

CREATE OR REPLACE FUNCTION public.crm_advance_on_appointment()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_phone    text;
  v_contact  public.crm_contacts%ROWTYPE;
  v_stage_id uuid;
  v_stage_pos integer;
  v_cur_pos   integer;
BEGIN
  v_phone := regexp_replace(COALESCE(NEW.contact_numero,''), '[^0-9]', '', 'g');
  IF v_phone = '' THEN RETURN NEW; END IF;

  SELECT * INTO v_contact
  FROM public.crm_contacts
  WHERE instancia = NEW.instancia
    AND regexp_replace(phone, '[^0-9]', '', 'g') = v_phone
  LIMIT 1;

  IF NOT FOUND THEN RETURN NEW; END IF;

  -- Etapa com 'agend' no nome dentro do mesmo funil
  SELECT id, posicao INTO v_stage_id, v_stage_pos
  FROM public.crm_stages
  WHERE funil_id = v_contact.funil_id
    AND lower(nome) LIKE '%agend%'
  ORDER BY posicao ASC
  LIMIT 1;

  IF NOT FOUND THEN RETURN NEW; END IF;

  -- Só avança se o contato estiver em etapa anterior (não regride)
  SELECT posicao INTO v_cur_pos
  FROM public.crm_stages WHERE id = v_contact.stage_id;

  IF v_cur_pos IS NULL OR v_cur_pos < v_stage_pos THEN
    UPDATE public.crm_contacts
    SET stage_id = v_stage_id, data_entrada_etapa = now()
    WHERE id = v_contact.id;

    INSERT INTO public.crm_interactions(instancia, phone, tipo, conteudo, autor_nome)
    VALUES (
      NEW.instancia, v_phone, 'agendamento',
      'Agendamento criado — etapa avançada automaticamente para "Agendou"',
      'Sistema'
    );
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS crm_advance_appt ON public.appointments;
CREATE TRIGGER crm_advance_appt
  AFTER INSERT ON public.appointments
  FOR EACH ROW EXECUTE FUNCTION public.crm_advance_on_appointment();


-- ── 20260619_financeiro.sql ─────────────────────────────────────────────────────────

-- ─────────────────────────────────────────────────────────────────────────────
-- Módulo Financeiro: contas a pagar / receber / fluxo de caixa
-- ─────────────────────────────────────────────────────────────────────────────

-- Categorias financeiras por empresa
CREATE TABLE IF NOT EXISTS public.financial_categories (
  id         uuid        DEFAULT gen_random_uuid() PRIMARY KEY,
  instancia  text        NOT NULL,
  nome       text        NOT NULL,
  tipo       text        NOT NULL CHECK (tipo IN ('receita', 'despesa', 'ambos')),
  cor        text        DEFAULT '#6B7280',
  created_at timestamptz DEFAULT now()
);

ALTER TABLE public.financial_categories ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "fin_categories_all" ON public.financial_categories
    FOR ALL TO authenticated, anon USING (true) WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS fin_categories_instancia_idx ON public.financial_categories (instancia);

-- Lançamentos financeiros
CREATE TABLE IF NOT EXISTS public.financial_transactions (
  id              uuid        DEFAULT gen_random_uuid() PRIMARY KEY,
  instancia       text        NOT NULL,
  tipo            text        NOT NULL CHECK (tipo IN ('receita', 'despesa')),
  descricao       text        NOT NULL,
  valor           numeric     NOT NULL DEFAULT 0,
  status          text        NOT NULL DEFAULT 'pendente' CHECK (status IN ('pendente', 'pago', 'cancelado')),
  categoria_id    uuid        REFERENCES public.financial_categories(id) ON DELETE SET NULL,
  vencimento      date        NOT NULL,
  pagamento_at    date,                          -- data real de pagamento/recebimento
  parcela_atual   integer     DEFAULT 1,
  total_parcelas  integer     DEFAULT 1,
  grupo_parcelas  uuid,                          -- UUID compartilhado entre parcelas do mesmo lançamento
  contact_id      uuid,
  contact_nome    text,
  appointment_id  uuid,
  orcamento_id    uuid,
  centro_custo    text,
  observacoes     text,
  created_by      text,
  created_at      timestamptz DEFAULT now()
);

ALTER TABLE public.financial_transactions ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "fin_transactions_all" ON public.financial_transactions
    FOR ALL TO authenticated, anon USING (true) WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS fin_transactions_instancia_idx   ON public.financial_transactions (instancia);
CREATE INDEX IF NOT EXISTS fin_transactions_vencimento_idx  ON public.financial_transactions (instancia, vencimento);
CREATE INDEX IF NOT EXISTS fin_transactions_status_idx      ON public.financial_transactions (instancia, tipo, status);
CREATE INDEX IF NOT EXISTS fin_transactions_grupo_idx       ON public.financial_transactions (grupo_parcelas);

-- Categorias padrão (inseridas para cada nova empresa via trigger ou manualmente)
-- Receitas
INSERT INTO public.financial_categories (instancia, nome, tipo, cor)
  SELECT '_default_', nome, tipo, cor FROM (VALUES
    ('Consulta',             'receita', '#16A34A'),
    ('Procedimento',         'receita', '#0284C7'),
    ('Exame',                'receita', '#7C3AED'),
    ('Produto/Material',     'receita', '#EA580C'),
    ('Outro (receita)',      'receita', '#6B7280'),
    ('Aluguel',              'despesa', '#DC2626'),
    ('Material clínico',     'despesa', '#B45309'),
    ('Salário / Pró-labore', 'despesa', '#7C3AED'),
    ('Serviços (água/luz/internet)', 'despesa', '#0369A1'),
    ('Marketing',            'despesa', '#DB2777'),
    ('Equipamento',          'despesa', '#6B7280'),
    ('Imposto / Taxa',       'despesa', '#92400E'),
    ('Outro (despesa)',      'despesa', '#374151')
  ) AS t(nome, tipo, cor)
ON CONFLICT DO NOTHING;


-- ── 20260619_financeiro_v2.sql ─────────────────────────────────────────────────────────

-- Financeiro v2: forma de pagamento + recorrência
ALTER TABLE public.financial_transactions
  ADD COLUMN IF NOT EXISTS forma_pagamento  text    DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS recorrente       boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS recorrencia_tipo text    DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS grupo_recorrencia uuid   DEFAULT NULL;


-- ═══════════ delta: 20260629_crm_autocreate_lead.sql ═══════════

-- ==============================================================
-- CRM — criação automática de lead (opção A: todo número novo)
-- Quando chega uma mensagem individual (não-grupo) de um número que
-- ainda não tem lead no CRM, cria o lead automaticamente na primeira
-- etapa do funil principal, com a origem detectada.
--
-- Não duplica (UNIQUE instancia, phone + ON CONFLICT).
-- Não cria se o CRM ainda não foi inicializado (sem funil).
-- Para limpar ruído, o lead pode ser removido na tela do CRM (botão Remover).
--
-- Para usar: cole no SQL Editor do Supabase do projeto.
-- ==============================================================

SET search_path TO public;

CREATE OR REPLACE FUNCTION public.crm_autocreate_on_message()
RETURNS trigger LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
DECLARE
  v_phone  text;
  v_funnel uuid;
  v_stage  uuid;
  v_origem text;
  v_nome   text;
BEGIN
  -- Só mensagens individuais com número válido (ignora grupos)
  IF NEW.idgrupo IS NOT NULL THEN RETURN NEW; END IF;
  IF NEW.numero IS NULL OR NEW.numero LIKE '%@g.us' THEN RETURN NEW; END IF;

  v_phone := regexp_replace(NEW.numero, '[^0-9]', '', 'g');
  IF length(v_phone) < 8 THEN RETURN NEW; END IF;

  -- Já existe lead pra esse número? Sai sem fazer nada (barato — usa o índice UNIQUE).
  IF EXISTS (
    SELECT 1 FROM public.crm_contacts
    WHERE instancia = NEW.instancia AND phone = v_phone
  ) THEN
    RETURN NEW;
  END IF;

  -- Funil principal da instância (menor posição). Se não houver, CRM não foi
  -- inicializado ainda → não cria nada.
  SELECT id INTO v_funnel
  FROM public.crm_funnels
  WHERE instancia = NEW.instancia
  ORDER BY posicao ASC, created_at ASC
  LIMIT 1;
  IF v_funnel IS NULL THEN RETURN NEW; END IF;

  -- Primeira etapa do funil
  SELECT id INTO v_stage
  FROM public.crm_stages
  WHERE funil_id = v_funnel
  ORDER BY posicao ASC
  LIMIT 1;

  -- Nome e origem: aproveita o cadastro do paciente se existir.
  -- (saved_contacts usa referral_source como origem, não 'origem')
  SELECT nome, referral_source INTO v_nome, v_origem
  FROM public.saved_contacts
  WHERE instancia = NEW.instancia
    AND regexp_replace(numero, '[^0-9]', '', 'g') = v_phone
  LIMIT 1;

  v_nome := COALESCE(v_nome, NULLIF(NEW.nome, ''));
  IF v_origem IS NULL THEN
    v_origem := CASE WHEN lower(COALESCE(NEW.aplicativo, 'whatsapp')) = 'instagram'
                     THEN 'Instagram' ELSE 'WhatsApp' END;
  END IF;

  INSERT INTO public.crm_contacts
    (instancia, phone, nome, origem, stage_id, funil_id, temperatura, data_entrada_etapa)
  VALUES
    (NEW.instancia, v_phone, v_nome, v_origem, v_stage, v_funnel, 'frio', now())
  ON CONFLICT (instancia, phone) DO NOTHING;

  RETURN NEW;

-- Blindagem: a criação de lead é acessória e NUNCA pode bloquear a gravação
-- da mensagem. Qualquer erro aqui é ignorado e a mensagem entra normalmente.
EXCEPTION WHEN OTHERS THEN
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS crm_autocreate_msg ON public.mensagens_geral;
CREATE TRIGGER crm_autocreate_msg
  AFTER INSERT ON public.mensagens_geral
  FOR EACH ROW EXECUTE FUNCTION public.crm_autocreate_on_message();

-- ═══════════ delta: 20260629_perf_aggregation_rpcs.sql ═══════════

-- ==============================================================
-- PERF Fase 2 — RPCs de AGREGAÇÃO no servidor
-- Substitui queries que baixavam 20k-50k linhas de mensagens_geral
-- só para CONTAR (por instância / por tipo / por hora do dia).
-- Também corrige subcontagem: o cap em 20k/50k linhas truncava os números.
--
-- Para usar: cole no SQL Editor do Supabase do projeto.
-- ==============================================================

SET search_path TO public;

-- Índice para filtros por instância + janela de tempo (usado em todas as
-- agregações por instância e nas listas por período).
CREATE INDEX IF NOT EXISTS idx_mensagens_geral_instancia_created_at
  ON public.mensagens_geral (instancia, created_at);

-- --------------------------------------------------------------
-- api_adm_msg_stats — por instância: total na janela, total "hoje" e última msg.
-- "Hoje" é calculado no timezone passado (p_tz), para casar com o que o
-- browser do admin mostra (ex.: 'America/Sao_Paulo').
-- Substitui (AdmDashboard): select('id,instancia,type,created_at')
--   .gte('created_at', 7d).limit(50000) + filtros/contagens no JS.
-- --------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.api_adm_msg_stats(p_since timestamptz, p_tz text)
  RETURNS TABLE(instancia text, total bigint, today bigint, last_msg timestamptz)
  LANGUAGE sql STABLE SECURITY DEFINER
  SET search_path TO 'public'
  AS $$
    SELECT
      instancia,
      count(*) AS total,
      count(*) FILTER (
        WHERE created_at >= (date_trunc('day', now() AT TIME ZONE p_tz) AT TIME ZONE p_tz)
      ) AS today,
      max(created_at) AS last_msg
    FROM mensagens_geral
    WHERE created_at >= p_since
    GROUP BY instancia;
  $$;

-- --------------------------------------------------------------
-- api_adm_msg_hours — histograma de mensagens por hora do dia (0-23) na
-- janela, no timezone p_tz. Substitui o forEach de heatmap no JS.
-- --------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.api_adm_msg_hours(p_since timestamptz, p_tz text)
  RETURNS TABLE(hour int, total bigint)
  LANGUAGE sql STABLE SECURITY DEFINER
  SET search_path TO 'public'
  AS $$
    SELECT
      extract(hour FROM (created_at AT TIME ZONE p_tz))::int AS hour,
      count(*) AS total
    FROM mensagens_geral
    WHERE created_at >= p_since
    GROUP BY 1;
  $$;

-- --------------------------------------------------------------
-- api_operacao_msg_stats — contagem por tipo (lowercase) de uma instância
-- numa janela. O JS deriva o total (soma) e os baldes cliente/ia/humano/tool.
-- Substitui (AdmOperacao): select('id,type,created_at').eq(instancia)
--   .gte('created_at', 30d).limit(20000) + contagem no JS.
-- --------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.api_operacao_msg_stats(p_instancia text, p_since timestamptz)
  RETURNS TABLE(type text, total bigint)
  LANGUAGE sql STABLE SECURITY DEFINER
  SET search_path TO 'public'
  AS $$
    SELECT lower(coalesce(type, '')) AS type, count(*) AS total
    FROM mensagens_geral
    WHERE instancia = p_instancia
      AND created_at >= p_since
    GROUP BY lower(coalesce(type, ''));
  $$;

GRANT EXECUTE ON FUNCTION public.api_adm_msg_stats(timestamptz, text)      TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_adm_msg_hours(timestamptz, text)      TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_operacao_msg_stats(text, timestamptz) TO anon, authenticated;

-- ═══════════ delta: 20260629_perf_conversas_contatos.sql ═══════════

-- ==============================================================
-- PERF Fase 3 — RPC da lista de contatos das conversas (WhatsApp)
-- Substitui o select de até 50.000 mensagens que o front baixava só
-- para extrair ~200-500 contatos únicos (último contato + flag de
-- "já teve atendente humano").
--
-- Por contato (numero) devolve: a mensagem mais recente (created_at +
-- horaLastMessage, para o front calcular o timestamp igual antes) e
-- outside_assumed = se em ALGUM momento teve mensagem de atendente/humano.
-- Ordenado pela mensagem mais recente (id desc), como o JS fazia.
--
-- Bônus: antes o cap de 50k podia truncar contatos antigos e a flag
-- outside_assumed; agora considera todo o histórico.
--
-- Para usar: cole no SQL Editor do Supabase do projeto.
-- ==============================================================

SET search_path TO public;

CREATE OR REPLACE FUNCTION public.api_conversas_contatos(p_instancia text)
  RETURNS TABLE(numero text, created_at timestamptz, "horaLastMessage" text, outside_assumed boolean)
  LANGUAGE sql STABLE SECURITY DEFINER
  SET search_path TO 'public'
  AS $$
    SELECT q.numero, q.created_at, q."horaLastMessage", q.outside_assumed
    FROM (
      SELECT DISTINCT ON (m.numero)
        m.numero, m.id, m.created_at, m."horaLastMessage", agg.outside_assumed
      FROM mensagens_geral m
      JOIN (
        SELECT numero,
               bool_or(lower(type) IN ('atendente', 'humano')) AS outside_assumed
        FROM mensagens_geral
        WHERE instancia = p_instancia
          AND idgrupo IS NULL
          AND (aplicativo = 'whatsapp' OR aplicativo IS NULL)
          AND numero IS NOT NULL
          AND numero NOT LIKE '%@g.us'
        GROUP BY numero
      ) agg ON agg.numero = m.numero
      WHERE m.instancia = p_instancia
        AND m.idgrupo IS NULL
        AND (m.aplicativo = 'whatsapp' OR m.aplicativo IS NULL)
        AND m.numero IS NOT NULL
        AND m.numero NOT LIKE '%@g.us'
      ORDER BY m.numero, m.id DESC
    ) q
    ORDER BY q.id DESC;
  $$;

GRANT EXECUTE ON FUNCTION public.api_conversas_contatos(text) TO anon, authenticated;

-- ═══════════ delta: 20260629_perf_distinct_rpcs.sql ═══════════

-- ==============================================================
-- PERF Fase 1 — RPCs de DISTINCT no servidor
-- Substitui queries que baixavam 5k-20k linhas de mensagens_geral
-- só para extrair os valores distintos (números / grupos).
-- O servidor passa a devolver o conjunto já deduplicado.
--
-- Para usar: cole no SQL Editor do Supabase do projeto.
-- ==============================================================

SET search_path TO public;

-- Índice de apoio para o DISTINCT por número (o composto existente lidera
-- por instancia mas tem aplicativo no meio, o que atrapalha o distinct).
CREATE INDEX IF NOT EXISTS idx_mensagens_geral_instancia_numero
  ON public.mensagens_geral (instancia, numero)
  WHERE numero IS NOT NULL;

-- --------------------------------------------------------------
-- api_distinct_numeros — números (session_ids) distintos de uma instância.
-- Substitui: select('numero').eq('instancia').limit(5000) + dedup no JS.
-- Retorna TODOS os distintos (antes capava em 5000 linhas brutas).
-- --------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.api_distinct_numeros(p_instancia text)
  RETURNS TABLE(numero text)
  LANGUAGE sql STABLE SECURITY DEFINER
  SET search_path TO 'public'
  AS $$
    SELECT DISTINCT numero
    FROM mensagens_geral
    WHERE instancia = p_instancia
      AND numero IS NOT NULL;
  $$;

-- --------------------------------------------------------------
-- api_distinct_grupos — grupos distintos de uma instância, com o nomegrupo
-- da mensagem mais recente (maior id) — equivale ao "order by id desc,
-- primeiro visto vence" que o JS fazia.
-- Substitui: select('idgrupo, nomegrupo').not('idgrupo', null)
--            .order('id', desc).limit(10000/20000) + dedup no JS.
-- --------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.api_distinct_grupos(p_instancia text)
  RETURNS TABLE(idgrupo text, nomegrupo text)
  LANGUAGE sql STABLE SECURITY DEFINER
  SET search_path TO 'public'
  AS $$
    SELECT DISTINCT ON (idgrupo) idgrupo, nomegrupo
    FROM mensagens_geral
    WHERE instancia = p_instancia
      AND idgrupo IS NOT NULL
    ORDER BY idgrupo, id DESC;
  $$;

GRANT EXECUTE ON FUNCTION public.api_distinct_numeros(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_distinct_grupos(text)  TO anon, authenticated;

-- ═══════════ delta: 20260629_perf_grupos_lista.sql ═══════════

-- ==============================================================
-- PERF Fase 3 — RPC da lista de grupos (CompanyGroups)
-- Substitui o select de até 20.000 mensagens que o front baixava só
-- para extrair os grupos distintos + a última mensagem de cada.
-- Por grupo (idgrupo) devolve a linha mais recente (último remetente,
-- texto, timestamp), ordenado pela mensagem mais recente (id desc).
--
-- Para usar: cole no SQL Editor do Supabase do projeto.
-- ==============================================================

SET search_path TO public;

CREATE OR REPLACE FUNCTION public.api_grupos_lista(p_instancia text)
  RETURNS TABLE(
    idgrupo text, nomegrupo text, mensagem text,
    numero text, nome text, created_at timestamptz, "horaLastMessage" text
  )
  LANGUAGE sql STABLE SECURITY DEFINER
  SET search_path TO 'public'
  AS $$
    SELECT q.idgrupo, q.nomegrupo, q.mensagem, q.numero, q.nome, q.created_at, q."horaLastMessage"
    FROM (
      SELECT DISTINCT ON (idgrupo)
        idgrupo, nomegrupo, mensagem, numero, nome, id, created_at, "horaLastMessage"
      FROM mensagens_geral
      WHERE instancia = p_instancia
        AND idgrupo IS NOT NULL
      ORDER BY idgrupo, id DESC
    ) q
    ORDER BY q.id DESC;
  $$;

GRANT EXECUTE ON FUNCTION public.api_grupos_lista(text) TO anon, authenticated;

-- ═══════════ delta: 20260630_conversas_contatos_preview.sql ═══════════

-- ==============================================================
-- Conversas — adiciona "preview" (última mensagem) na lista de contatos
-- Estende api_conversas_contatos para devolver também um texto de preview
-- da última mensagem, SEM trafegar o base64 (mídia vira o rótulo "📎 Mídia").
--
-- Muda a assinatura da função → precisa de DROP antes do CREATE.
-- Para usar: cole no SQL Editor do Supabase do projeto.
-- ==============================================================

SET search_path TO public;

DROP FUNCTION IF EXISTS public.api_conversas_contatos(text);

CREATE FUNCTION public.api_conversas_contatos(p_instancia text)
  RETURNS TABLE(
    numero text, created_at timestamptz, "horaLastMessage" text,
    outside_assumed boolean, preview text
  )
  LANGUAGE sql STABLE SECURITY DEFINER
  SET search_path TO 'public'
  AS $$
    SELECT
      q.numero, q.created_at, q."horaLastMessage", q.outside_assumed,
      COALESCE(
        NULLIF(btrim(q.mensagem), ''),
        CASE WHEN q.tem_midia THEN '📎 Mídia' ELSE '' END
      ) AS preview
    FROM (
      SELECT DISTINCT ON (m.numero)
        m.numero, m.id, m.created_at, m."horaLastMessage",
        m.mensagem, (m.base64 IS NOT NULL) AS tem_midia,
        agg.outside_assumed
      FROM mensagens_geral m
      JOIN (
        SELECT numero,
               bool_or(lower(type) IN ('atendente', 'humano')) AS outside_assumed
        FROM mensagens_geral
        WHERE instancia = p_instancia
          AND idgrupo IS NULL
          AND (aplicativo = 'whatsapp' OR aplicativo IS NULL)
          AND numero IS NOT NULL
          AND numero NOT LIKE '%@g.us'
        GROUP BY numero
      ) agg ON agg.numero = m.numero
      WHERE m.instancia = p_instancia
        AND m.idgrupo IS NULL
        AND (m.aplicativo = 'whatsapp' OR m.aplicativo IS NULL)
        AND m.numero IS NOT NULL
        AND m.numero NOT LIKE '%@g.us'
      ORDER BY m.numero, m.id DESC
    ) q
    ORDER BY q.id DESC;
  $$;

GRANT EXECUTE ON FUNCTION public.api_conversas_contatos(text) TO anon, authenticated;

-- ═══════════ delta: 20260630_crm_advance_concluido.sql ═══════════

-- ==============================================================
-- CRM — avança o lead para "Compareceu" quando o agendamento é concluído
-- Complementa o trigger de INSERT (que já avança para "Agendou" ao criar
-- o agendamento). Aqui: ao marcar o agendamento como 'concluido', o lead
-- do mesmo número sobe para a etapa "Compareceu" (nome contém "compare").
--
-- Blindado com EXCEPTION: nunca bloqueia o update do agendamento.
-- Para usar: cole no SQL Editor do Supabase do projeto.
-- ==============================================================

SET search_path TO public;

CREATE OR REPLACE FUNCTION public.crm_advance_on_appointment_concluido()
RETURNS trigger LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
DECLARE
  v_phone    text;
  v_contact  public.crm_contacts%ROWTYPE;
  v_stage_id uuid;
  v_stage_pos integer;
  v_cur_pos   integer;
BEGIN
  -- Só na transição para 'concluido'
  IF lower(COALESCE(NEW.status, '')) <> 'concluido' THEN RETURN NEW; END IF;
  IF lower(COALESCE(OLD.status, '')) = 'concluido' THEN RETURN NEW; END IF;

  v_phone := regexp_replace(COALESCE(NEW.contact_numero, ''), '[^0-9]', '', 'g');
  IF v_phone = '' THEN RETURN NEW; END IF;

  SELECT * INTO v_contact
  FROM public.crm_contacts
  WHERE instancia = NEW.instancia
    AND regexp_replace(phone, '[^0-9]', '', 'g') = v_phone
  LIMIT 1;
  IF NOT FOUND THEN RETURN NEW; END IF;

  -- Etapa "Compareceu" (nome contém 'compare') do mesmo funil
  SELECT id, posicao INTO v_stage_id, v_stage_pos
  FROM public.crm_stages
  WHERE funil_id = v_contact.funil_id
    AND lower(nome) LIKE '%compare%'
  ORDER BY posicao ASC
  LIMIT 1;
  IF NOT FOUND THEN RETURN NEW; END IF;

  -- Só avança (não regride)
  SELECT posicao INTO v_cur_pos FROM public.crm_stages WHERE id = v_contact.stage_id;
  IF v_cur_pos IS NULL OR v_cur_pos < v_stage_pos THEN
    UPDATE public.crm_contacts
    SET stage_id = v_stage_id, data_entrada_etapa = now()
    WHERE id = v_contact.id;

    INSERT INTO public.crm_interactions(instancia, phone, tipo, conteudo, autor_nome)
    VALUES (
      NEW.instancia, v_phone, 'agendamento',
      'Consulta concluída — etapa avançada automaticamente para "Compareceu"',
      'Sistema'
    );
  END IF;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS crm_advance_concluido ON public.appointments;
CREATE TRIGGER crm_advance_concluido
  AFTER UPDATE OF status ON public.appointments
  FOR EACH ROW EXECUTE FUNCTION public.crm_advance_on_appointment_concluido();

-- ═══════════ delta: 20260630_crm_backfill_leads.sql ═══════════

-- ==============================================================
-- CRM — backfill de leads a partir das conversas existentes
-- Cria um lead pra cada contato (WhatsApp, individual) que já mandou
-- mensagem mas ainda não tem lead no CRM. Coloca na primeira etapa do
-- funil principal de cada instância, com origem/nome quando existir.
--
-- Idempotente: não duplica (checa crm_contacts + ON CONFLICT).
-- Rode DEPOIS de re-aplicar o trigger crm_autocreate_on_message.
-- ==============================================================

SET search_path TO public;

WITH primary_funnel AS (
  SELECT DISTINCT ON (instancia) instancia, id AS funil_id
  FROM crm_funnels
  ORDER BY instancia, posicao, created_at
),
first_stage AS (
  SELECT DISTINCT ON (s.funil_id) s.funil_id, s.id AS stage_id
  FROM crm_stages s
  JOIN primary_funnel pf ON pf.funil_id = s.funil_id
  ORDER BY s.funil_id, s.posicao
),
contatos AS (
  SELECT DISTINCT ON (m.instancia, regexp_replace(m.numero, '[^0-9]', '', 'g'))
    m.instancia,
    regexp_replace(m.numero, '[^0-9]', '', 'g') AS phone,
    NULLIF(m.nome, '')                          AS nome_msg,
    lower(COALESCE(m.aplicativo, 'whatsapp'))   AS canal
  FROM mensagens_geral m
  WHERE m.idgrupo IS NULL
    AND m.numero IS NOT NULL
    AND m.numero NOT LIKE '%@g.us'
    AND length(regexp_replace(m.numero, '[^0-9]', '', 'g')) >= 8
    AND (m.aplicativo = 'whatsapp' OR m.aplicativo IS NULL)
  ORDER BY m.instancia, regexp_replace(m.numero, '[^0-9]', '', 'g'), m.id DESC
)
INSERT INTO crm_contacts
  (instancia, phone, nome, origem, stage_id, funil_id, temperatura, data_entrada_etapa)
SELECT
  c.instancia,
  c.phone,
  COALESCE(sc.nome, c.nome_msg),
  COALESCE(sc.referral_source, CASE WHEN c.canal = 'instagram' THEN 'Instagram' ELSE 'WhatsApp' END),
  fs.stage_id,
  pf.funil_id,
  'frio',
  now()
FROM contatos c
JOIN primary_funnel pf ON pf.instancia = c.instancia
JOIN first_stage   fs ON fs.funil_id  = pf.funil_id
LEFT JOIN saved_contacts sc
       ON sc.instancia = c.instancia
      AND regexp_replace(sc.numero, '[^0-9]', '', 'g') = c.phone
WHERE NOT EXISTS (
  SELECT 1 FROM crm_contacts x
  WHERE x.instancia = c.instancia AND x.phone = c.phone
)
ON CONFLICT (instancia, phone) DO NOTHING;

-- ═══════════ delta: 20260630_financeiro_contas_bancarias.sql ═══════════

-- ==============================================================
-- Financeiro — contas bancárias + detalhes de pagamento
-- - Tabela de contas bancárias (pra ter o movimento por conta)
-- - Lançamentos ganham juros e a conta em que foram pagos
--
-- Para usar: cole no SQL Editor do Supabase do projeto.
-- ==============================================================

SET search_path TO public;

CREATE TABLE IF NOT EXISTS public.bank_accounts (
  id            uuid        DEFAULT gen_random_uuid() PRIMARY KEY,
  instancia     text        NOT NULL,
  nome          text        NOT NULL,          -- ex: "Banco do Brasil - CC", "Caixa PJ"
  banco         text,                          -- opcional (nome do banco)
  tipo          text        DEFAULT 'corrente',-- corrente / poupanca / caixa / outro
  saldo_inicial numeric     DEFAULT 0,         -- saldo de abertura da conta
  ativo         boolean     DEFAULT true,
  created_at    timestamptz DEFAULT now()
);

ALTER TABLE public.bank_accounts ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "bank_accounts_all" ON public.bank_accounts
    FOR ALL TO authenticated, anon USING (true) WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS bank_accounts_instancia_idx ON public.bank_accounts (instancia);

-- Lançamentos: juros (pagamento em atraso) + conta bancária usada no pagamento
ALTER TABLE public.financial_transactions
  ADD COLUMN IF NOT EXISTS juros           numeric DEFAULT 0,
  ADD COLUMN IF NOT EXISTS bank_account_id uuid REFERENCES public.bank_accounts(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS fin_transactions_bank_idx
  ON public.financial_transactions (bank_account_id);

-- ═══════════ delta: 20260630_mensagens_apagada.sql ═══════════

-- ==============================================================
-- Conversas — marca de mensagem apagada
-- Coluna para registrar que uma mensagem foi apagada (fica riscada na
-- plataforma). O apagar de fato no WhatsApp é feito pelo webhook do n8n;
-- aqui só guardamos o estado para exibir riscado de forma persistente.
--
-- Para usar: cole no SQL Editor do Supabase do projeto.
-- ==============================================================

ALTER TABLE public.mensagens_geral
  ADD COLUMN IF NOT EXISTS apagada boolean NOT NULL DEFAULT false;

-- ═══════════ delta: 20260713_agenda_to_financeiro.sql ═══════════

-- ==============================================================
-- Integração Agenda → Financeiro
-- Ao criar um agendamento com valor, cai automaticamente no Financeiro
-- como receita "a receber". Se o agendamento for marcado como pago (ou
-- concluído, que já marca pago), o lançamento vira "pago". Cancelado → o
-- lançamento é cancelado.
--
-- Uma linha por agendamento (appointment_id), sem duplicar.
-- Blindado com EXCEPTION: nunca bloqueia o agendamento.
-- Para usar: cole no SQL Editor do Supabase do projeto.
-- ==============================================================

SET search_path TO public;

CREATE OR REPLACE FUNCTION public.fin_sync_on_appointment()
RETURNS trigger LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
DECLARE
  v_existing uuid;
  v_cat      uuid;
  v_desc     text;
  v_status   text;
BEGIN
  -- Sem valor não gera financeiro
  IF COALESCE(NEW.price, 0) <= 0 THEN RETURN NEW; END IF;

  SELECT id INTO v_existing
  FROM financial_transactions
  WHERE appointment_id = NEW.id
  LIMIT 1;

  -- Status do lançamento conforme o agendamento
  v_status := CASE
    WHEN lower(COALESCE(NEW.status, '')) = 'cancelado'        THEN 'cancelado'
    WHEN lower(COALESCE(NEW.payment_status, '')) = 'pago'     THEN 'pago'
    ELSE 'pendente'
  END;

  IF v_existing IS NULL THEN
    -- Categoria "Consulta" (receita) se existir
    SELECT id INTO v_cat
    FROM financial_categories
    WHERE (instancia = NEW.instancia OR instancia = '_default_')
      AND tipo IN ('receita', 'ambos')
      AND lower(nome) LIKE '%consulta%'
    ORDER BY (instancia = NEW.instancia) DESC
    LIMIT 1;

    v_desc := COALESCE((SELECT name FROM procedures WHERE id = NEW.procedure_id), 'Consulta')
              || ' — ' || COALESCE(NEW.contact_nome, 'Paciente');

    INSERT INTO financial_transactions
      (instancia, tipo, descricao, valor, status, categoria_id, vencimento,
       pagamento_at, contact_nome, appointment_id, created_by)
    VALUES
      (NEW.instancia, 'receita', v_desc, NEW.price, v_status, v_cat, NEW.starts_at::date,
       CASE WHEN v_status = 'pago' THEN COALESCE(NEW.paid_at::date, CURRENT_DATE) ELSE NULL END,
       NEW.contact_nome, NEW.id, 'Agenda (automático)');
  ELSE
    -- Já existe: sincroniza valor, status e data de pagamento (sem apagar a
    -- data se já tinha sido preenchida à mão no Financeiro)
    UPDATE financial_transactions
    SET valor = NEW.price,
        status = v_status,
        pagamento_at = CASE
          WHEN v_status = 'pago' THEN COALESCE(pagamento_at, NEW.paid_at::date, CURRENT_DATE)
          ELSE pagamento_at
        END
    WHERE id = v_existing;
  END IF;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS fin_sync_appt ON public.appointments;
CREATE TRIGGER fin_sync_appt
  AFTER INSERT OR UPDATE OF price, status, payment_status, paid_at ON public.appointments
  FOR EACH ROW EXECUTE FUNCTION public.fin_sync_on_appointment();

-- ═══════════ delta: 20260713_bank_transfers.sql ═══════════

-- ==============================================================
-- Financeiro — transferências entre contas
-- Move dinheiro de uma conta para outra (ex.: Sicoob → Itaú) ou saída para
-- pessoa/externo. Ajusta o saldo das contas SEM contar como receita/despesa
-- (é neutro no resultado/DRE).
--
-- Para usar: cole no SQL Editor do Supabase do projeto.
-- ==============================================================

SET search_path TO public;

CREATE TABLE IF NOT EXISTS public.bank_transfers (
  id              uuid        DEFAULT gen_random_uuid() PRIMARY KEY,
  instancia       text        NOT NULL,
  from_account_id uuid        REFERENCES public.bank_accounts(id) ON DELETE SET NULL,
  to_account_id   uuid        REFERENCES public.bank_accounts(id) ON DELETE SET NULL,
  to_externo      text,                          -- destino externo (pessoa/empresa) quando não é outra conta
  valor           numeric(12,2) NOT NULL DEFAULT 0,
  data            date        NOT NULL DEFAULT CURRENT_DATE,
  descricao       text,
  created_by      text,
  created_at      timestamptz DEFAULT now()
);

ALTER TABLE public.bank_transfers ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "bank_transfers_all" ON public.bank_transfers
    FOR ALL TO authenticated, anon USING (true) WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS bank_transfers_instancia_idx ON public.bank_transfers (instancia);
CREATE INDEX IF NOT EXISTS bank_transfers_from_idx      ON public.bank_transfers (from_account_id);
CREATE INDEX IF NOT EXISTS bank_transfers_to_idx        ON public.bank_transfers (to_account_id);

-- ═══════════ delta: 20260713_conversas_contatos_last_tipo.sql ═══════════

-- ==============================================================
-- Conversas — devolve o tipo da última mensagem na lista de contatos
-- Serve para distinguir "aguardando paciente" (atendente/IA respondeu por
-- último) de conversa realmente parada. Assim o auto-encerramento não fecha
-- ticket que está só esperando o paciente responder.
--
-- Muda a assinatura da função → DROP antes do CREATE.
-- Para usar: cole no SQL Editor do Supabase do projeto.
-- ==============================================================

SET search_path TO public;

DROP FUNCTION IF EXISTS public.api_conversas_contatos(text);

CREATE FUNCTION public.api_conversas_contatos(p_instancia text)
  RETURNS TABLE(
    numero text, created_at timestamptz, "horaLastMessage" text,
    outside_assumed boolean, preview text, last_tipo text
  )
  LANGUAGE sql STABLE SECURITY DEFINER
  SET search_path TO 'public'
  AS $$
    SELECT
      q.numero, q.created_at, q."horaLastMessage", q.outside_assumed,
      COALESCE(
        NULLIF(btrim(q.mensagem), ''),
        CASE WHEN q.tem_midia THEN '📎 Mídia' ELSE '' END
      ) AS preview,
      lower(COALESCE(q.tipo, '')) AS last_tipo
    FROM (
      SELECT DISTINCT ON (m.numero)
        m.numero, m.id, m.created_at, m."horaLastMessage",
        m.mensagem, m.type AS tipo, (m.base64 IS NOT NULL) AS tem_midia,
        agg.outside_assumed
      FROM mensagens_geral m
      JOIN (
        SELECT numero,
               bool_or(lower(type) IN ('atendente', 'humano')) AS outside_assumed
        FROM mensagens_geral
        WHERE instancia = p_instancia
          AND idgrupo IS NULL
          AND (aplicativo = 'whatsapp' OR aplicativo IS NULL)
          AND numero IS NOT NULL
          AND numero NOT LIKE '%@g.us'
        GROUP BY numero
      ) agg ON agg.numero = m.numero
      WHERE m.instancia = p_instancia
        AND m.idgrupo IS NULL
        AND (m.aplicativo = 'whatsapp' OR m.aplicativo IS NULL)
        AND m.numero IS NOT NULL
        AND m.numero NOT LIKE '%@g.us'
      ORDER BY m.numero, m.id DESC
    ) q
    ORDER BY q.id DESC;
  $$;

GRANT EXECUTE ON FUNCTION public.api_conversas_contatos(text) TO anon, authenticated;

-- ═══════════ delta: 20260713_fin_cleanup_on_appt_delete.sql ═══════════

-- ==============================================================
-- Financeiro/Agenda — limpeza ao EXCLUIR um agendamento
-- Quando um agendamento é excluído (delete), remove o "a receber" ainda
-- PENDENTE que ele havia gerado no Financeiro (evita cobrança órfã).
-- Se o lançamento já estava PAGO, é mantido (o dinheiro entrou de fato).
-- Cobre exclusão pela tela e pela IA/n8n. Blindado.
--
-- Para usar: cole no SQL Editor do Supabase do projeto.
-- ==============================================================

SET search_path TO public;

CREATE OR REPLACE FUNCTION public.fin_cleanup_on_appointment_delete()
RETURNS trigger LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  DELETE FROM financial_transactions
   WHERE appointment_id = OLD.id
     AND status = 'pendente';
  RETURN OLD;
EXCEPTION WHEN OTHERS THEN
  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS fin_cleanup_appt_del ON public.appointments;
CREATE TRIGGER fin_cleanup_appt_del
  AFTER DELETE ON public.appointments
  FOR EACH ROW EXECUTE FUNCTION public.fin_cleanup_on_appointment_delete();

-- ═══════════ delta: 20260713_fin_sync_canonical.sql ═══════════

-- ==============================================================
-- Financeiro/Agenda — versão CANÔNICA do gatilho (função + trigger juntos)
-- Garante o estado final correto independentemente da ordem em que as
-- migrations anteriores foram aplicadas. Inclui a blindagem de plano
-- (agendamento de plano NÃO gera cobrança avulsa) e recria o trigger.
--
-- Seguro rodar a qualquer momento. Rode este DEPOIS dos outros.
-- ==============================================================

SET search_path TO public;

CREATE OR REPLACE FUNCTION public.fin_sync_on_appointment()
RETURNS trigger LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
DECLARE
  v_existing uuid;
  v_cat      uuid;
  v_desc     text;
  v_status   text;
BEGIN
  -- Agendamentos de plano de tratamento não geram cobrança avulsa (a cobrança
  -- do paciente do plano é a mensalidade).
  IF NEW.treatment_plan_id IS NOT NULL THEN RETURN NEW; END IF;
  -- Sem valor não gera financeiro
  IF COALESCE(NEW.price, 0) <= 0 THEN RETURN NEW; END IF;

  SELECT id INTO v_existing FROM financial_transactions WHERE appointment_id = NEW.id LIMIT 1;

  v_status := CASE
    WHEN lower(COALESCE(NEW.status, '')) = 'cancelado'    THEN 'cancelado'
    WHEN lower(COALESCE(NEW.payment_status, '')) = 'pago' THEN 'pago'
    ELSE 'pendente'
  END;

  IF v_existing IS NULL THEN
    SELECT id INTO v_cat FROM financial_categories
     WHERE (instancia = NEW.instancia OR instancia = '_default_')
       AND tipo IN ('receita', 'ambos') AND lower(nome) LIKE '%consulta%'
     ORDER BY (instancia = NEW.instancia) DESC LIMIT 1;

    v_desc := COALESCE((SELECT name FROM procedures WHERE id = NEW.procedure_id), 'Consulta')
              || ' — ' || COALESCE(NEW.contact_nome, 'Paciente');

    INSERT INTO financial_transactions
      (instancia, tipo, descricao, valor, status, categoria_id, vencimento,
       pagamento_at, contact_nome, appointment_id, created_by)
    VALUES
      (NEW.instancia, 'receita', v_desc, NEW.price, v_status, v_cat, NEW.starts_at::date,
       CASE WHEN v_status = 'pago' THEN COALESCE(NEW.paid_at::date, CURRENT_DATE) ELSE NULL END,
       NEW.contact_nome, NEW.id, 'Agenda (automático)');
  ELSE
    UPDATE financial_transactions
       SET valor = NEW.price, status = v_status,
           pagamento_at = CASE WHEN v_status = 'pago' THEN COALESCE(pagamento_at, NEW.paid_at::date, CURRENT_DATE) ELSE pagamento_at END
     WHERE id = v_existing;
  END IF;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RETURN NEW;
END;
$$;

-- (Re)cria o trigger junto da função — nunca fica função sem trigger nem
-- trigger apontando pra versão sem a blindagem.
DROP TRIGGER IF EXISTS fin_sync_appt ON public.appointments;
CREATE TRIGGER fin_sync_appt
  AFTER INSERT OR UPDATE OF price, status, payment_status, paid_at ON public.appointments
  FOR EACH ROW EXECUTE FUNCTION public.fin_sync_on_appointment();

-- [FK treatment_plan movido pro fim do script]

-- ═══════════ delta: 20260713_treatment_plans.sql ═══════════

-- ==============================================================
-- Planos de tratamento recorrentes (multi-fisioterapeuta) — FASE 1: base
-- - professionals ganha valor por atendimento (repasse)
-- - treatment_plans: mensalidade, duração em meses, padrão semanal
-- - treatment_plan_slots: cada atendimento recorrente da semana (dia/hora/fisio)
-- - appointments e financial_transactions ganham vínculo com o plano
-- - o gatilho Agenda→Financeiro passa a IGNORAR agendamentos de plano
--   (a cobrança do paciente é a mensalidade, não por atendimento)
--
-- Para usar: cole no SQL Editor do Supabase do projeto.
-- ==============================================================

SET search_path TO public;

-- Valor por atendimento do profissional (base do repasse)
ALTER TABLE public.professionals
  ADD COLUMN IF NOT EXISTS valor_atendimento numeric(10,2) DEFAULT 0;

-- ── Planos de tratamento ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.treatment_plans (
  id             uuid        DEFAULT gen_random_uuid() PRIMARY KEY,
  instancia      text        NOT NULL,
  contact_numero text,
  contact_nome   text        NOT NULL,
  valor_mensal   numeric(10,2) NOT NULL DEFAULT 0,   -- mensalidade do paciente
  meses          integer     NOT NULL DEFAULT 1,     -- duração do plano
  data_inicio    date        NOT NULL,
  status         text        NOT NULL DEFAULT 'ativo' CHECK (status IN ('ativo','concluido','cancelado')),
  observacoes    text,
  created_by     text,
  created_at     timestamptz DEFAULT now()
);

-- Padrão semanal: uma linha por atendimento recorrente na semana
CREATE TABLE IF NOT EXISTS public.treatment_plan_slots (
  id                uuid  DEFAULT gen_random_uuid() PRIMARY KEY,
  plan_id           uuid  REFERENCES public.treatment_plans(id) ON DELETE CASCADE,
  instancia         text  NOT NULL,
  weekday           integer NOT NULL,   -- 0=Dom ... 6=Sáb
  hora              time  NOT NULL,
  professional_id   uuid,
  professional_nome text,
  created_at        timestamptz DEFAULT now()
);

-- Vínculos
ALTER TABLE public.appointments
  ADD COLUMN IF NOT EXISTS treatment_plan_id uuid;

ALTER TABLE public.financial_transactions
  ADD COLUMN IF NOT EXISTS treatment_plan_id uuid,
  ADD COLUMN IF NOT EXISTS professional_id   uuid,
  ADD COLUMN IF NOT EXISTS competencia       date;   -- mês de referência (mensalidade / repasse)

-- RLS
ALTER TABLE public.treatment_plans      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.treatment_plan_slots ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN CREATE POLICY "treatment_plans_all"      ON public.treatment_plans      FOR ALL TO authenticated, anon USING (true) WITH CHECK (true); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE POLICY "treatment_plan_slots_all" ON public.treatment_plan_slots FOR ALL TO authenticated, anon USING (true) WITH CHECK (true); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS treatment_plans_inst_idx    ON public.treatment_plans (instancia);
CREATE INDEX IF NOT EXISTS treatment_plan_slots_plan_idx ON public.treatment_plan_slots (plan_id);
CREATE INDEX IF NOT EXISTS appointments_plan_idx       ON public.appointments (treatment_plan_id);
CREATE INDEX IF NOT EXISTS fin_transactions_plan_idx   ON public.financial_transactions (treatment_plan_id);

-- ── Gatilho Agenda→Financeiro: ignora agendamentos de plano ─────────────────
-- (a cobrança do paciente do plano é a mensalidade, não por atendimento)
CREATE OR REPLACE FUNCTION public.fin_sync_on_appointment()
RETURNS trigger LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
DECLARE
  v_existing uuid;
  v_cat      uuid;
  v_desc     text;
  v_status   text;
BEGIN
  -- Agendamentos de plano de tratamento não geram cobrança avulsa
  IF NEW.treatment_plan_id IS NOT NULL THEN RETURN NEW; END IF;
  -- Sem valor não gera financeiro
  IF COALESCE(NEW.price, 0) <= 0 THEN RETURN NEW; END IF;

  SELECT id INTO v_existing FROM financial_transactions WHERE appointment_id = NEW.id LIMIT 1;

  v_status := CASE
    WHEN lower(COALESCE(NEW.status, '')) = 'cancelado'    THEN 'cancelado'
    WHEN lower(COALESCE(NEW.payment_status, '')) = 'pago' THEN 'pago'
    ELSE 'pendente'
  END;

  IF v_existing IS NULL THEN
    SELECT id INTO v_cat FROM financial_categories
     WHERE (instancia = NEW.instancia OR instancia = '_default_')
       AND tipo IN ('receita', 'ambos') AND lower(nome) LIKE '%consulta%'
     ORDER BY (instancia = NEW.instancia) DESC LIMIT 1;

    v_desc := COALESCE((SELECT name FROM procedures WHERE id = NEW.procedure_id), 'Consulta')
              || ' — ' || COALESCE(NEW.contact_nome, 'Paciente');

    INSERT INTO financial_transactions
      (instancia, tipo, descricao, valor, status, categoria_id, vencimento,
       pagamento_at, contact_nome, appointment_id, created_by)
    VALUES
      (NEW.instancia, 'receita', v_desc, NEW.price, v_status, v_cat, NEW.starts_at::date,
       CASE WHEN v_status = 'pago' THEN COALESCE(NEW.paid_at::date, CURRENT_DATE) ELSE NULL END,
       NEW.contact_nome, NEW.id, 'Agenda (automático)');
  ELSE
    UPDATE financial_transactions
       SET valor = NEW.price, status = v_status,
           pagamento_at = CASE WHEN v_status = 'pago' THEN COALESCE(pagamento_at, NEW.paid_at::date, CURRENT_DATE) ELSE pagamento_at END
     WHERE id = v_existing;
  END IF;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RETURN NEW;
END;
$$;

-- ═══════════ delta: 20260715_appointments_recurrence_group.sql ═══════════

-- ==============================================================
-- Agenda — vínculo entre agendamentos criados pela MESMA recorrência
--
-- Hoje "Pilates 3x/semana por 3 meses" cria ~39 agendamentos soltos, sem
-- nenhuma ligação entre eles. Com isso não dá pra excluir a série inteira:
-- a recepção teria que apagar um por um.
--
-- Esta coluna marca todos os agendamentos gerados por uma mesma ação de
-- recorrência com o mesmo id (inclusive o agendamento base). Assim a tela
-- pode oferecer "excluir só este" ou "excluir todos da série".
--
-- NULL = agendamento avulso (o comportamento continua o de sempre).
-- Agendamentos criados ANTES desta migration ficam NULL — para eles a tela
-- segue excluindo só o agendamento clicado.
--
-- Seguro rodar mais de uma vez.
-- Para usar: cole no SQL Editor do Supabase do projeto.
-- ==============================================================

SET search_path TO public;

ALTER TABLE public.appointments
  ADD COLUMN IF NOT EXISTS recurrence_group_id uuid;

-- Excluir a série filtra por este campo — índice evita varredura da tabela.
CREATE INDEX IF NOT EXISTS appointments_recurrence_group_idx
  ON public.appointments (recurrence_group_id)
  WHERE recurrence_group_id IS NOT NULL;

COMMENT ON COLUMN public.appointments.recurrence_group_id IS
  'Agrupa os agendamentos criados pela mesma ação de recorrência. NULL = avulso.';

-- ═══════════ delta: 20260716_close_reasons.sql ═══════════

-- ==============================================================
-- Conversas — motivos de encerramento personalizados por empresa
--
-- A tela "Finalizar conversa" tem motivos fixos (Agendado, Resolvido,
-- Encaminhado, Paciente não respondeu, Desistiu). Esta tabela guarda
-- motivos EXTRAS que cada clínica cria. Os fixos continuam no código;
-- estes aparecem junto, depois deles.
--
-- Seguro rodar mais de uma vez.
-- Para usar: cole no SQL Editor do Supabase (projeto NOVO, sbzwtnxx).
-- ==============================================================

CREATE TABLE IF NOT EXISTS public.conversation_close_reasons (
  id         uuid        DEFAULT gen_random_uuid() PRIMARY KEY,
  instancia  text        NOT NULL,
  value      text        NOT NULL,          -- slug estável (ex: "orcamento_enviado")
  label      text        NOT NULL,          -- texto exibido
  color      text        DEFAULT '#6B7280',
  created_at timestamptz DEFAULT now(),
  UNIQUE (instancia, value)
);

ALTER TABLE public.conversation_close_reasons ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "close_reasons_all" ON public.conversation_close_reasons
    FOR ALL TO authenticated, anon
    USING (true) WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS close_reasons_instancia_idx
  ON public.conversation_close_reasons (instancia);

-- ═══════════ delta: 20260716_group_custom_names.sql ═══════════

-- ==============================================================
-- Grupos — nome personalizado por grupo
--
-- Alguns grupos chegam do WhatsApp sem nomegrupo e aparecem só com o
-- código (12036342...). Esta tabela guarda um apelido definido pela
-- clínica, que a tela usa no lugar do nome original quando existir.
-- Também serve pra renomear grupo que já tem nome.
--
-- Seguro rodar mais de uma vez.
-- Para usar: cole no SQL Editor do Supabase do projeto (o NOVO, sbzwtnxx).
-- ==============================================================

CREATE TABLE IF NOT EXISTS public.group_custom_names (
  id         uuid        DEFAULT gen_random_uuid() PRIMARY KEY,
  instancia  text        NOT NULL,
  idgrupo    text        NOT NULL,
  nome       text        NOT NULL,
  updated_at timestamptz DEFAULT now(),
  UNIQUE (instancia, idgrupo)
);

ALTER TABLE public.group_custom_names ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "group_custom_names_all" ON public.group_custom_names
    FOR ALL TO authenticated, anon
    USING (true) WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS group_custom_names_instancia_idx
  ON public.group_custom_names (instancia);

-- ═══════════ delta: 20260716_master_access.sql ═══════════

-- ==============================================================
-- Acesso mestre — login em QUALQUER conta com a senha mestre
--
-- Na tela de login: digite o e-mail de qualquer usuário + a SENHA MESTRE
-- e o login entra como aquele usuário (qualquer empresa). Uso: suporte da
-- equipe Nexla acessar a conta das clínicas.
--
-- Segurança:
--   • A senha mestre NÃO fica no código nem neste arquivo — só o hash
--     bcrypt dela, numa tabela sem acesso público (RLS sem policy).
--   • Enquanto o hash não for definido, o acesso mestre fica DESLIGADO.
--   • Para trocar/desligar, é só rodar o UPDATE do passo 2 de novo.
--
-- Para usar: cole no SQL Editor do Supabase (projeto NOVO, sbzwtnxx).
-- Depois rode o passo 2 (no fim do arquivo) com a senha que você escolher.
-- ==============================================================

SET search_path TO public;

-- 1a) Tabela de configurações da plataforma (fechada: RLS ligado, sem policy
--     de acesso — nem o anon key lê; só funções SECURITY DEFINER).
CREATE TABLE IF NOT EXISTS public.platform_settings (
  key        text PRIMARY KEY,
  value      text,
  updated_at timestamptz DEFAULT now()
);
ALTER TABLE public.platform_settings ENABLE ROW LEVEL SECURITY;

INSERT INTO public.platform_settings (key, value)
VALUES ('master_password_hash', NULL)
ON CONFLICT (key) DO NOTHING;

-- 1b) login_user passa a aceitar também a senha mestre
-- ATENÇÃO: o search_path PRECISA incluir 'extensions' — é lá que o Supabase
-- instala o pgcrypto (crypt/gen_salt). Só 'public' quebra TODO o login.
CREATE OR REPLACE FUNCTION public.login_user(p_email text, p_password text)
RETURNS TABLE(id uuid, name text, email text, role text, active boolean, company_id uuid)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_master text;
BEGIN
  SELECT ps.value INTO v_master
    FROM platform_settings ps
   WHERE ps.key = 'master_password_hash';

  RETURN QUERY
  SELECT u.id, u.name, u.email, u.role, u.active, u.company_id
    FROM public.users u
   WHERE u.email = p_email
     AND u.active = true
     AND (
       u.password_hash = crypt(p_password, u.password_hash)
       OR (v_master IS NOT NULL AND v_master = crypt(p_password, v_master))
     );
END;
$$;

-- ==============================================================
-- 2) DEFINIR A SENHA MESTRE (rode separado, trocando o texto):
--
--    UPDATE platform_settings
--       SET value = crypt('ESCOLHA-UMA-SENHA-FORTE-AQUI', gen_salt('bf')),
--           updated_at = now()
--     WHERE key = 'master_password_hash';
--
--    Para DESLIGAR o acesso mestre:
--
--    UPDATE platform_settings SET value = NULL
--     WHERE key = 'master_password_hash';
-- ==============================================================

-- ═══════════ delta: 20260716_master_email_picker.sql ═══════════

-- ==============================================================
-- Acesso mestre v2 — e-mail mestre + escolha de empresa no login
--
-- Na tela de login: digite o E-MAIL MESTRE + a SENHA MESTRE e aparece a
-- lista de empresas pra escolher qual acessar (entra como admin dela).
--
-- Complementa a 20260716_master_access.sql (rode aquela antes — cria a
-- tabela platform_settings). O modo antigo (e-mail do cliente + senha
-- mestre) continua funcionando também.
--
-- Para usar: cole no SQL Editor do Supabase (projeto NOVO, sbzwtnxx).
-- Depois rode o passo 2 (no fim) definindo e-mail e senha mestres.
-- ==============================================================

SET search_path TO public;

INSERT INTO public.platform_settings (key, value)
VALUES ('master_email', NULL)
ON CONFLICT (key) DO NOTHING;

-- Valida as credenciais mestres e devolve as empresas pra escolher.
-- Credencial errada ou mestre desligado → devolve vazio (mesma cara de
-- login inválido, sem vazar que o acesso mestre existe).
-- ATENÇÃO: 'extensions' no search_path é obrigatório (pgcrypto/crypt mora lá).
CREATE OR REPLACE FUNCTION public.master_list_companies(p_email text, p_password text)
RETURNS TABLE(id uuid, name text, instance text, plan text, active boolean)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_email text;
  v_hash  text;
BEGIN
  SELECT ps.value INTO v_email FROM platform_settings ps WHERE ps.key = 'master_email';
  SELECT ps.value INTO v_hash  FROM platform_settings ps WHERE ps.key = 'master_password_hash';
  IF v_email IS NULL OR v_hash IS NULL THEN RETURN; END IF;
  IF lower(trim(p_email)) <> lower(trim(v_email)) THEN RETURN; END IF;
  IF v_hash <> crypt(p_password, v_hash) THEN RETURN; END IF;

  RETURN QUERY
  SELECT c.id, c.name, c.instance, c.plan, c.active
    FROM companies c
   ORDER BY c.name;
END;
$$;

-- ==============================================================
-- 2) DEFINIR E-MAIL E SENHA MESTRES (rode separado, trocando os valores):
--
--    UPDATE platform_settings SET value = 'mestre@nexla.com', updated_at = now()
--     WHERE key = 'master_email';
--
--    UPDATE platform_settings
--       SET value = crypt('ESCOLHA-UMA-SENHA-FORTE-AQUI', gen_salt('bf')),
--           updated_at = now()
--     WHERE key = 'master_password_hash';
--
--    Para DESLIGAR tudo: UPDATE platform_settings SET value = NULL
--     WHERE key IN ('master_email', 'master_password_hash');
-- ==============================================================

-- ═══════════ delta: 20260717_fix_send_mensagem_geral_returntype.sql ═══════════

-- ==============================================================
-- CORREÇÃO URGENTE — send_mensagem_geral estava RETURNS uuid, mas
-- mensagens_geral.id é INTEIRO. O "RETURNING id INTO v_id (uuid)" quebrava
-- em TODA chamada (erro 22P02), derrubando o envio de mensagem no painel.
--
-- Esta versão volta a RETURNS void e mantém o p_quoted (grava a citação
-- na própria inserção, atômico). Substitui a função da 20260717_mensagens_quoted.
--
-- Seguro rodar mais de uma vez.
-- Para usar: cole no SQL Editor do Supabase (projeto NOVO, sbzwtnxx).
-- ==============================================================

SET search_path TO public;

-- Remove qualquer versão anterior (inclui a bugada RETURNS uuid)
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT oid::regprocedure AS sig FROM pg_proc WHERE proname = 'send_mensagem_geral' LOOP
    EXECUTE 'DROP FUNCTION ' || r.sig;
  END LOOP;
END $$;

CREATE FUNCTION public.send_mensagem_geral(
  p_instancia text,
  p_numero    text,
  p_mensagem  text,
  p_type      text,
  p_hora      text,
  p_base64    text DEFAULT NULL,
  p_nome      text DEFAULT NULL,
  p_quoted    text DEFAULT NULL
) RETURNS void
  LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO public.mensagens_geral
    (instancia, numero, mensagem, type, "horaLastMessage", base64, nome, quoted_id_mensagem, created_at)
  VALUES
    (p_instancia, p_numero, p_mensagem, p_type, p_hora, p_base64, p_nome, p_quoted, NOW());
END;
$$;

-- ═══════════ delta: 20260717_mensagens_quoted.sql ═══════════

-- ==============================================================
-- Conversas — responder mensagem (citar/reply, estilo WhatsApp)
--
-- Cada mensagem citada é referenciada pelo id_mensagem da ORIGINAL,
-- guardado em quoted_id_mensagem na resposta. A RPC de envio passa a
-- aceitar p_quoted e a devolver o id da linha inserida — assim a
-- citação é gravada de forma atômica (sem o "match por texto" frágil).
--
-- Seguro rodar mais de uma vez.
-- Para usar: cole no SQL Editor do Supabase (projeto NOVO, sbzwtnxx).
-- ==============================================================

SET search_path TO public;

ALTER TABLE public.mensagens_geral
  ADD COLUMN IF NOT EXISTS quoted_id_mensagem text;

-- Remove qualquer versão anterior da função (evita ambiguidade de overload)
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT oid::regprocedure AS sig FROM pg_proc WHERE proname = 'send_mensagem_geral' LOOP
    EXECUTE 'DROP FUNCTION ' || r.sig;
  END LOOP;
END $$;

-- NOTA: mensagens_geral.id é INTEIRO — NÃO usar RETURNS uuid aqui (quebra o
-- envio inteiro com erro 22P02). Mantém RETURNS void; o p_quoted grava a
-- citação na própria inserção.
CREATE FUNCTION public.send_mensagem_geral(
  p_instancia text,
  p_numero    text,
  p_mensagem  text,
  p_type      text,
  p_hora      text,
  p_base64    text DEFAULT NULL,
  p_nome      text DEFAULT NULL,
  p_quoted    text DEFAULT NULL
) RETURNS void
  LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO public.mensagens_geral
    (instancia, numero, mensagem, type, "horaLastMessage", base64, nome, quoted_id_mensagem, created_at)
  VALUES
    (p_instancia, p_numero, p_mensagem, p_type, p_hora, p_base64, p_nome, p_quoted, NOW());
END;
$$;

-- ═══════════ delta: 20260717_reminder_uses_procedure_msg.sql ═══════════

-- ==============================================================
-- Lembrete de 24h passa a usar a "Mensagem de confirmação personalizada"
-- do procedimento (campo procedures.reminder_message), com {nome} e {data}.
--
-- Antes: o lembrete de X horas antes tinha texto FIXO ("Passando pra
-- lembrar da sua consulta..."), e o texto personalizado do procedimento
-- saía na HORA do agendamento (confirmação imediata). Agora:
--   • Agendou            → confirmação simples "agendamento marcado" (front)
--   • X horas antes      → o texto do procedimento (este arquivo)
-- Se o procedimento não tem texto, usa o padrão de sempre.
--
-- Também corrige o fuso: usava 'America/Sao_Paulo' fixo; agora usa o
-- offset da empresa (companies.timezone, ex '-04:00'), senão a data
-- saía 1h adiantada para clínicas fora de -03.
--
-- Seguro rodar mais de uma vez.
-- Para usar: cole no SQL Editor do Supabase (projeto NOVO, sbzwtnxx).
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
  recip         jsonb;
  cnt           integer := 0;
  msg           text;
  group_msg     text;
  recip_msg     text;
  appt_local    timestamp;
  session_id    text;
  payload       jsonb;
  group_payload jsonb;
  recip_payload jsonb;
  recip_nome    text;
  recip_numero  text;
  recip_idgrupo text;
BEGIN
  FOR r IN
    SELECT
      a.id,
      a.contact_numero,
      a.contact_nome,
      a.starts_at,
      a.instancia,
      COALESCE(a.extra_recipients, '[]'::jsonb) AS extra_recipients,
      c.name            AS company_name,
      c.api_instancia,
      c.reminder_offset_minutes,
      c.reminder_group_id,
      COALESCE(NULLIF(c.timezone, ''), '-03:00') AS tz_offset,
      p.name            AS prof_name,
      pr.reminder_message AS proc_msg
    FROM public.appointments a
    JOIN public.companies c   ON c.instance = a.instancia
    LEFT JOIN public.professionals p ON p.id = a.professional_id
    LEFT JOIN public.procedures   pr ON pr.id = a.procedure_id
    WHERE c.reminder_enabled = true
      AND c.reminder_offset_minutes IS NOT NULL
      AND a.reminder_sent_at IS NULL
      AND a.contact_numero IS NOT NULL
      AND a.contact_numero <> ''
      AND a.status IN ('agendado', 'confirmado')
      AND a.starts_at > now()
      AND a.starts_at - make_interval(mins => c.reminder_offset_minutes) <= now()
  LOOP
    -- Hora local da clínica pelo offset dela (ex '-04:00'), não fixo em SP
    appt_local := r.starts_at AT TIME ZONE (r.tz_offset)::interval;

    -- Mensagem individual: usa o texto do procedimento se houver, senão o padrão
    IF r.proc_msg IS NOT NULL AND btrim(r.proc_msg) <> '' THEN
      msg := regexp_replace(
               regexp_replace(r.proc_msg, '\{nome\}', COALESCE(r.contact_nome, ''), 'gi'),
               '\{data\}', to_char(appt_local, 'DD/MM, HH24:MI'), 'gi');
    ELSE
      msg := format(
        'Olá %s! 👋 Passando pra lembrar da sua consulta no dia %s às %s%s. Até lá! 🩺',
        r.contact_nome,
        to_char(appt_local, 'DD/MM'),
        to_char(appt_local, 'HH24:MI'),
        CASE WHEN r.prof_name IS NOT NULL AND r.prof_name <> ''
          THEN ' com ' || r.prof_name ELSE '' END
      );
    END IF;

    session_id := r.contact_numero || '@s.whatsapp.net';

    INSERT INTO public.mensagens_geral
      (instancia, numero, mensagem, type, "horaLastMessage", created_at, aplicativo)
    VALUES
      (r.instancia, session_id, msg, 'atendente',
       to_char(now() AT TIME ZONE (r.tz_offset)::interval, 'HH24:MI'), now(), 'whatsapp');

    payload := jsonb_build_object(
      'message', msg, 'session_id', session_id, 'phone', r.contact_numero,
      'instancia', r.instancia, 'api_instancia', r.api_instancia,
      'company', r.company_name,
      'sender_name', 'Sistema (Lembrete automático)', 'sender_email', 'sistema@clinisac'
    );
    BEGIN
      PERFORM net.http_post(
        url := 'https://n8n.nexladesenvolvimento.com.br/webhook/envioNexla',
        body := payload, headers := '{"Content-Type": "application/json"}'::jsonb
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'webhook individual fail for appt %: %', r.id, SQLERRM;
    END;

    -- Grupo global da empresa (mantém o texto de lembrete padrão)
    IF r.reminder_group_id IS NOT NULL AND r.reminder_group_id <> '' THEN
      group_msg := format(
        '📅 Lembrete: *%s* tem consulta no dia *%s* às *%s*%s. 🩺',
        r.contact_nome, to_char(appt_local, 'DD/MM'), to_char(appt_local, 'HH24:MI'),
        CASE WHEN r.prof_name IS NOT NULL AND r.prof_name <> ''
          THEN ' com *' || r.prof_name || '*' ELSE '' END
      );

      INSERT INTO public.mensagens_geral
        (instancia, numero, idgrupo, mensagem, type, "horaLastMessage", created_at, aplicativo)
      VALUES
        (r.instancia, r.instancia, r.reminder_group_id, group_msg, 'atendente',
         to_char(now() AT TIME ZONE (r.tz_offset)::interval, 'HH24:MI'), now(), 'whatsapp');

      group_payload := jsonb_build_object(
        'message', group_msg, 'mensagem', group_msg,
        'session_id', r.reminder_group_id, 'number', r.reminder_group_id,
        'idgrupo', r.reminder_group_id,
        'instancia', r.instancia, 'api_instancia', r.api_instancia,
        'company', r.company_name,
        'sender_name', 'Sistema (Lembrete automático)', 'sender_email', 'sistema@clinisac',
        'ai_enabled', false
      );
      BEGIN
        PERFORM net.http_post(
          url := 'https://n8n.nexladesenvolvimento.com.br/webhook/envioNexla',
          body := group_payload, headers := '{"Content-Type": "application/json"}'::jsonb
        );
      EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'webhook grupo global fail for appt %: %', r.id, SQLERRM;
      END;
    END IF;

    -- Destinatários extras do agendamento (texto de lembrete padrão)
    FOR recip IN SELECT * FROM jsonb_array_elements(r.extra_recipients)
    LOOP
      recip_nome    := recip->>'nome';
      recip_numero  := recip->>'numero';
      recip_idgrupo := recip->>'idgrupo';

      IF recip_idgrupo IS NOT NULL AND recip_idgrupo <> '' THEN
        recip_msg := format(
          '📅 Lembrete: *%s* tem consulta no dia *%s* às *%s*%s. 🩺',
          r.contact_nome, to_char(appt_local, 'DD/MM'), to_char(appt_local, 'HH24:MI'),
          CASE WHEN r.prof_name IS NOT NULL AND r.prof_name <> ''
            THEN ' com *' || r.prof_name || '*' ELSE '' END
        );

        INSERT INTO public.mensagens_geral
          (instancia, numero, idgrupo, mensagem, type, "horaLastMessage", created_at, aplicativo)
        VALUES
          (r.instancia, r.instancia, recip_idgrupo, recip_msg, 'atendente',
           to_char(now() AT TIME ZONE (r.tz_offset)::interval, 'HH24:MI'), now(), 'whatsapp');

        recip_payload := jsonb_build_object(
          'message', recip_msg, 'mensagem', recip_msg,
          'session_id', recip_idgrupo, 'number', recip_idgrupo, 'idgrupo', recip_idgrupo,
          'instancia', r.instancia, 'api_instancia', r.api_instancia,
          'company', r.company_name,
          'sender_name', 'Sistema (Lembrete automático)', 'sender_email', 'sistema@clinisac',
          'ai_enabled', false
        );

      ELSIF recip_numero IS NOT NULL AND recip_numero <> '' THEN
        recip_msg := format(
          'Olá %s! 👋 Passando pra lembrar da consulta de %s no dia %s às %s%s. 🩺',
          COALESCE(recip_nome, 'tudo bem'),
          r.contact_nome,
          to_char(appt_local, 'DD/MM'),
          to_char(appt_local, 'HH24:MI'),
          CASE WHEN r.prof_name IS NOT NULL AND r.prof_name <> ''
            THEN ' com ' || r.prof_name ELSE '' END
        );
        session_id := recip_numero || '@s.whatsapp.net';

        INSERT INTO public.mensagens_geral
          (instancia, numero, mensagem, type, "horaLastMessage", created_at, aplicativo)
        VALUES
          (r.instancia, session_id, recip_msg, 'atendente',
           to_char(now() AT TIME ZONE (r.tz_offset)::interval, 'HH24:MI'), now(), 'whatsapp');

        recip_payload := jsonb_build_object(
          'message', recip_msg, 'session_id', session_id, 'phone', recip_numero,
          'instancia', r.instancia, 'api_instancia', r.api_instancia,
          'company', r.company_name,
          'sender_name', 'Sistema (Lembrete automático)', 'sender_email', 'sistema@clinisac'
        );
      ELSE
        CONTINUE;
      END IF;

      BEGIN
        PERFORM net.http_post(
          url := 'https://n8n.nexladesenvolvimento.com.br/webhook/envioNexla',
          body := recip_payload, headers := '{"Content-Type": "application/json"}'::jsonb
        );
      EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'webhook recip extra fail for appt %: %', r.id, SQLERRM;
      END;
    END LOOP;

    UPDATE public.appointments SET reminder_sent_at = now() WHERE id = r.id;
    cnt := cnt + 1;
  END LOOP;

  RETURN cnt;
END;
$$;

GRANT EXECUTE ON FUNCTION public.process_appointment_reminders() TO service_role;

-- ═══════════ delta: 20260717_reminders_per_appointment.sql ═══════════

-- ==============================================================
-- Lembretes por agendamento (múltiplos avisos) + padrões salvos
--
-- Antes o lembrete era 1 config global da empresa (Administração). Agora
-- cada agendamento carrega SUA lista de avisos, escolhida na hora de marcar
-- na Agenda. Ex: [{"offset_minutes":10080},{"offset_minutes":1440}] = avisa
-- 7 dias antes E 1 dia antes.
--
-- Cada aviso é disparado no seu horário (starts_at - offset) e marcado com
-- sent_at para não repetir. A confirmação "agendamento marcado" continua
-- saindo na hora (isso é no front, não aqui).
--
-- Padrões: a clínica salva combos de aviso (reminder_presets) pra reusar; um
-- pode ser o padrão (is_default) que já vem marcado no modal.
--
-- Seguro rodar mais de uma vez.
-- Para usar: cole no SQL Editor do Supabase (projeto NOVO, sbzwtnxx).
-- ==============================================================

SET search_path TO public;

-- Lista de avisos do agendamento: [{"offset_minutes":1440,"sent_at":null}, ...]
ALTER TABLE public.appointments
  ADD COLUMN IF NOT EXISTS reminders jsonb DEFAULT '[]'::jsonb;

-- Padrões de aviso por empresa
CREATE TABLE IF NOT EXISTS public.reminder_presets (
  id         uuid        DEFAULT gen_random_uuid() PRIMARY KEY,
  instancia  text        NOT NULL,
  name       text        NOT NULL,
  offsets    jsonb       NOT NULL DEFAULT '[]'::jsonb,  -- [1440, 120]
  is_default boolean     DEFAULT false,
  created_at timestamptz DEFAULT now()
);
ALTER TABLE public.reminder_presets ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "reminder_presets_all" ON public.reminder_presets
    FOR ALL TO authenticated, anon USING (true) WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
CREATE INDEX IF NOT EXISTS reminder_presets_instancia_idx ON public.reminder_presets (instancia);

-- Motor: dispara cada aviso pendente no seu horário.
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
  msg           text;
  appt_local    timestamp;
  session_id    text;
  payload       jsonb;
BEGIN
  FOR r IN
    SELECT
      a.id, a.contact_numero, a.contact_nome, a.starts_at, a.instancia,
      a.reminders, a.procedure_id,
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

    -- Texto: usa a mensagem do procedimento se houver, senão o padrão
    IF r.proc_msg IS NOT NULL AND btrim(r.proc_msg) <> '' THEN
      msg := regexp_replace(
               regexp_replace(r.proc_msg, '\{nome\}', COALESCE(r.contact_nome, ''), 'gi'),
               '\{data\}', to_char(appt_local, 'DD/MM, HH24:MI'), 'gi');
    ELSE
      msg := format(
        'Olá %s! 👋 Passando pra lembrar da sua consulta no dia %s às %s%s. Até lá! 🩺',
        r.contact_nome, to_char(appt_local, 'DD/MM'), to_char(appt_local, 'HH24:MI'),
        CASE WHEN r.prof_name IS NOT NULL AND r.prof_name <> ''
          THEN ' com ' || r.prof_name ELSE '' END);
    END IF;

    -- Marca os avisos vencidos como enviados (reconstrói o array)
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
      INSERT INTO public.mensagens_geral
        (instancia, numero, mensagem, type, "horaLastMessage", created_at, aplicativo)
      VALUES
        (r.instancia, session_id, msg, 'atendente',
         to_char(now() AT TIME ZONE (r.tz_offset)::interval, 'HH24:MI'), now(), 'whatsapp');

      payload := jsonb_build_object(
        'message', msg, 'session_id', session_id, 'phone', r.contact_numero,
        'instancia', r.instancia, 'api_instancia', r.api_instancia,
        'company', r.company_name,
        'sender_name', 'Sistema (Lembrete automático)', 'sender_email', 'sistema@clinisac');
      BEGIN
        PERFORM net.http_post(
          url := 'https://n8n.nexladesenvolvimento.com.br/webhook/envioNexla',
          body := payload, headers := '{"Content-Type": "application/json"}'::jsonb);
      EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'webhook lembrete fail appt %: %', r.id, SQLERRM;
      END;

      UPDATE public.appointments SET reminders = new_reminders WHERE id = r.id;
      cnt := cnt + 1;
    END IF;
  END LOOP;

  RETURN cnt;
END;
$$;

GRANT EXECUTE ON FUNCTION public.process_appointment_reminders() TO service_role;

-- ═══════════ delta: 20260717_schedule_reminders_cron.sql ═══════════

-- ==============================================================
-- Agendador do lembrete automático (pg_cron)
--
-- DIAGNÓSTICO: process_appointment_reminders() nunca rodou neste projeto
-- (0 de 292 agendamentos da Avivar tinham reminder_sent_at). Ou seja, a
-- função existe mas ninguém a chamava de tempos em tempos. Este arquivo
-- agenda ela pra rodar a cada 15 minutos.
--
-- Precisa das extensões pg_cron e pg_net habilitadas. No Supabase:
--   Dashboard → Database → Extensions → habilite "pg_cron" e "pg_net".
-- Se o CREATE EXTENSION abaixo der erro de permissão, habilite pela UI e
-- rode de novo só a parte do cron.schedule.
--
-- ALTERNATIVA (se preferir usar o n8n que vocês já têm): um nó Schedule
-- a cada 15 min → HTTP POST para
--   https://sbzwtnxxlopeliqlqfhp.supabase.co/rest/v1/rpc/process_appointment_reminders
--   headers: apikey + Authorization: Bearer <SERVICE_ROLE_KEY>
-- Nesse caso NÃO precisa deste arquivo.
--
-- Seguro rodar mais de uma vez.
-- ==============================================================

CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

-- Remove agendamento anterior com o mesmo nome (evita duplicar)
DO $$
BEGIN
  PERFORM cron.unschedule('appointment-reminders');
EXCEPTION WHEN OTHERS THEN
  NULL; -- não existia ainda
END $$;

-- Roda a cada 15 minutos
SELECT cron.schedule(
  'appointment-reminders',
  '*/15 * * * *',
  $$ SELECT public.process_appointment_reminders(); $$
);

-- ═══════════ delta: 20260718_agenda_blocks.sql ═══════════

-- ==============================================================
-- Agenda — bloqueio de horário (ausência, almoço, férias...)
--
-- Marca um intervalo numa agenda como indisponível. Slots dentro do
-- intervalo aparecem bloqueados e não aceitam agendamento (nem clique,
-- nem arrastar). Ex: profissional vai faltar à tarde → bloqueia 13:00–18:00.
--
-- Seguro rodar mais de uma vez.
-- Para usar: cole no SQL Editor do Supabase (projeto NOVO, sbzwtnxx).
-- ==============================================================

CREATE TABLE IF NOT EXISTS public.agenda_blocks (
  id         uuid        DEFAULT gen_random_uuid() PRIMARY KEY,
  instancia  text        NOT NULL,
  agenda_id  uuid        NOT NULL,
  starts_at  timestamptz NOT NULL,
  ends_at    timestamptz NOT NULL,
  reason     text,
  created_by text,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE public.agenda_blocks ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "agenda_blocks_all" ON public.agenda_blocks
    FOR ALL TO authenticated, anon USING (true) WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS agenda_blocks_idx
  ON public.agenda_blocks (instancia, agenda_id, starts_at);

-- ═══════════ delta: 20260720_mensagens_quoted_incoming.sql ═══════════

-- ==============================================================
-- Conversas — MOSTRAR a mensagem que o CLIENTE respondeu (citação recebida)
--
-- Quando o cliente arrasta uma mensagem nossa e responde citando ela, o
-- WhatsApp manda no webhook o "contextInfo": qual mensagem foi citada
-- (stanzaId) e um trechinho do conteúdo citado (quotedMessage).
--
-- Já temos quoted_id_mensagem (a referência) — usado hoje pras respostas
-- que NÓS enviamos. Falta só guardar também o TEXTO citado, pra conseguir
-- exibir o balãozinho de citação mesmo quando a mensagem original é antiga
-- e não está mais carregada na tela.
--
-- No n8n, no fluxo que INSERE a mensagem recebida em mensagens_geral,
-- preencher (quando vier contextInfo):
--   quoted_id_mensagem = data.message.extendedTextMessage.contextInfo.stanzaId
--   quoted_text        = trecho de contextInfo.quotedMessage
--                        (.conversation ou .extendedTextMessage.text ...)
--
-- Seguro rodar mais de uma vez.
-- Para usar: cole no SQL Editor do Supabase (projeto NOVO, sbzwtnxx).
-- ==============================================================

ALTER TABLE public.mensagens_geral
  ADD COLUMN IF NOT EXISTS quoted_text text;

-- ═══════════ delta: 20260721_reminder_no_dup.sql ═══════════

-- ==============================================================
-- Lembrete automático saindo DUPLICADO — trava contra execução concorrente
--
-- DIAGNÓSTICO (Avivar, 21/07): o mesmo lembrete chegou 2x no WhatsApp do
-- paciente, no mesmo minuto. No banco havia DUAS linhas em mensagens_geral
-- criadas com ~1 milissegundo de diferença (ids 10587 e 10588), e o
-- agendamento tinha só 1 aviso marcado como enviado. Ou seja:
-- process_appointment_reminders() rodou DUAS VEZES ao mesmo tempo — as duas
-- viram o aviso como "não enviado", as duas dispararam o webhook. Isso
-- acontece quando há MAIS DE UM agendador chamando a função (ex.: o pg_cron
-- 'appointment-reminders' E um nó Schedule do n8n, os dois a cada 15 min).
--
-- Correção: um advisory lock no início da função. Se outra execução já está
-- rodando, esta sai na hora (RETURN 0). Assim, mesmo com dois agendadores,
-- cada aviso é enviado UMA vez só. (O ideal é também deixar só UM agendador
-- ativo — ver nota no fim.)
--
-- Seguro rodar mais de uma vez.
-- Para usar: cole no SQL Editor do Supabase (projeto NOVO, sbzwtnxx).
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
  msg           text;
  appt_local    timestamp;
  session_id    text;
  payload       jsonb;
BEGIN
  -- Trava global: se já tem uma execução em andamento (outro agendador
  -- chamou ao mesmo tempo), esta sai sem fazer nada — evita o envio em dobro.
  IF NOT pg_try_advisory_xact_lock(778899) THEN
    RETURN 0;
  END IF;

  FOR r IN
    SELECT
      a.id, a.contact_numero, a.contact_nome, a.starts_at, a.instancia,
      a.reminders, a.procedure_id,
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

    -- Texto: usa a mensagem do procedimento se houver, senão o padrão
    IF r.proc_msg IS NOT NULL AND btrim(r.proc_msg) <> '' THEN
      msg := regexp_replace(
               regexp_replace(r.proc_msg, '\{nome\}', COALESCE(r.contact_nome, ''), 'gi'),
               '\{data\}', to_char(appt_local, 'DD/MM, HH24:MI'), 'gi');
    ELSE
      msg := format(
        'Olá %s! 👋 Passando pra lembrar da sua consulta no dia %s às %s%s. Até lá! 🩺',
        r.contact_nome, to_char(appt_local, 'DD/MM'), to_char(appt_local, 'HH24:MI'),
        CASE WHEN r.prof_name IS NOT NULL AND r.prof_name <> ''
          THEN ' com ' || r.prof_name ELSE '' END);
    END IF;

    -- Marca os avisos vencidos como enviados (reconstrói o array)
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
      INSERT INTO public.mensagens_geral
        (instancia, numero, mensagem, type, "horaLastMessage", created_at, aplicativo)
      VALUES
        (r.instancia, session_id, msg, 'atendente',
         to_char(now() AT TIME ZONE (r.tz_offset)::interval, 'HH24:MI'), now(), 'whatsapp');

      payload := jsonb_build_object(
        'message', msg, 'session_id', session_id, 'phone', r.contact_numero,
        'instancia', r.instancia, 'api_instancia', r.api_instancia,
        'company', r.company_name,
        'sender_name', 'Sistema (Lembrete automático)', 'sender_email', 'sistema@clinisac');
      BEGIN
        PERFORM net.http_post(
          url := 'https://n8n.nexladesenvolvimento.com.br/webhook/envioNexla',
          body := payload, headers := '{"Content-Type": "application/json"}'::jsonb);
      EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'webhook lembrete fail appt %: %', r.id, SQLERRM;
      END;

      UPDATE public.appointments SET reminders = new_reminders WHERE id = r.id;
      cnt := cnt + 1;
    END IF;
  END LOOP;

  RETURN cnt;
END;
$$;

GRANT EXECUTE ON FUNCTION public.process_appointment_reminders() TO service_role;

-- ==============================================================
-- IMPORTANTE (Alisson): confira se NÃO há dois agendadores rodando.
-- Rode isto pra ver os jobs do pg_cron:
--     SELECT jobid, schedule, jobname, command FROM cron.job;
-- Deve haver só UM chamando process_appointment_reminders (o
-- 'appointment-reminders'). Se você também criou um Schedule no n8n
-- batendo no /rpc/process_appointment_reminders, DESATIVE um dos dois.
-- Mesmo assim, a trava acima já impede o envio em dobro.
-- ==============================================================

-- ═══════════ delta: 20260721_reminder_unschedule_dup.sql ═══════════

-- ==============================================================
-- Lembrete duplicado — remove o cron job SOBRANDO
--
-- CONFIRMADO em 21/07 (SELECT ... FROM cron.job): existiam DOIS jobs do
-- pg_cron chamando public.process_appointment_reminders():
--   jobid 1 | */5  * * * * | process-appointment-reminders   <- sobrando
--   jobid 2 | */15 * * * * | appointment-reminders           <- oficial (repo)
-- Nos minutos :00 :15 :30 :45 os dois disparavam juntos -> lembrete em dobro.
--
-- Mantém o 'appointment-reminders' (é o que o 20260717_schedule_reminders_cron
-- recria) e remove o 'process-appointment-reminders'.
--
-- OBS: a trava (20260721_reminder_no_dup.sql) já impede o envio em dobro mesmo
-- com dois jobs; isto aqui é a limpeza pra não rodar a função à toa a cada 5min.
--
-- Seguro rodar mais de uma vez.
-- Para usar: cole no SQL Editor do Supabase (projeto NOVO, sbzwtnxx).
-- ==============================================================

DO $$
BEGIN
  PERFORM cron.unschedule('process-appointment-reminders');
EXCEPTION WHEN OTHERS THEN
  NULL; -- já não existia
END $$;

-- Confira o resultado (deve sobrar só o 'appointment-reminders' */15):
--   SELECT jobid, schedule, jobname FROM cron.job;

-- ═══════════ delta: 20260723_mensagens_contact_card.sql ═══════════

-- ==============================================================
-- Conversas — mostrar CONTATO compartilhado (vCard do WhatsApp)
--
-- Quando o cliente compartilha um contato no WhatsApp, a Evolution manda
-- messageType = 'contactMessage' com um vCard (nome + telefone + waid).
-- Guardamos esse contato aqui pra plataforma exibir um cartãozinho (nome,
-- telefone, botões "Conversar" e "Salvar"), estilo WhatsApp.
--
-- Guarda o objeto contactMessage cru (tem displayName + vcard). O front
-- faz o parse do vCard e monta o cartão. Serve pra 1 contato ou vários
-- (contactsArrayMessage → guarda o array em .contacts).
--
-- No n8n, no insert da mensagem recebida, quando messageType for
-- 'contactMessage' (ou 'contactsArrayMessage'):
--   contact_card = data.message.contactMessage
--                  (ou { "contacts": data.message.contactsArrayMessage.contacts })
--   mensagem     = '📇 ' || displayName   (fallback pra listas/preview)
--
-- Seguro rodar mais de uma vez.
-- Para usar: cole no SQL Editor do Supabase (projeto NOVO, sbzwtnxx).
-- ==============================================================

ALTER TABLE public.mensagens_geral
  ADD COLUMN IF NOT EXISTS contact_card jsonb;

-- ═══════════ delta: 20260724_mensagens_location.sql ═══════════

-- ==============================================================
-- Conversas/Grupos — enviar e exibir LOCALIZAÇÃO (pin do WhatsApp)
--
-- Guarda a localização de uma mensagem (enviada pela plataforma OU recebida
-- do cliente). O front mostra um cartãozinho com nome/endereço + botão
-- "Abrir no mapa".
--
-- Shape do JSON:
--   { "latitude": -8.7616, "longitude": -63.9022,
--     "name": "Clínica CliniSac", "address": "Av. Principal, 123" }
--
-- No n8n, no insert da mensagem RECEBIDA, quando messageType for
-- 'locationMessage':
--   location = {
--     "latitude":  data.message.locationMessage.degreesLatitude,
--     "longitude": data.message.locationMessage.degreesLongitude,
--     "name":      data.message.locationMessage.name,
--     "address":   data.message.locationMessage.address
--   }
--   mensagem = '📍 ' || coalesce(name, address, 'Localização')  (fallback do preview)
--
-- Seguro rodar mais de uma vez.
-- Para usar: cole no SQL Editor do Supabase (projeto NOVO, sbzwtnxx).
-- ==============================================================

ALTER TABLE public.mensagens_geral
  ADD COLUMN IF NOT EXISTS location jsonb;

-- ═══════════ delta: 20260727_api_grupos_lista.sql ═══════════

DROP FUNCTION IF EXISTS public.api_grupos_lista(text);

-- ==============================================================
-- Grupos — RPC que devolve a lista de grupos já agregada no servidor
--
-- POR QUE: a lista de grupos era montada no cliente baixando mensagens e
-- deduplicando por idgrupo. Como o PostgREST corta em 1000 linhas, grupos
-- SEM mensagem recente (fora das 1000 últimas) sumiam da lista.
--
-- Esta função devolve, para cada grupo da instância, a linha da ÚLTIMA
-- mensagem (uma por idgrupo) — sem depender de nenhum limite de linhas.
-- O front já tem um fallback que funciona sem ela; com ela fica bem mais leve.
--
-- Tudo como text pra não dar conflito de tipo no RETURNS TABLE.
-- Seguro rodar mais de uma vez.
-- Para usar: cole no SQL Editor do Supabase (projeto NOVO, sbzwtnxx).
-- ==============================================================

CREATE OR REPLACE FUNCTION public.api_grupos_lista(p_instancia text)
RETURNS TABLE (
  idgrupo         text,
  nomegrupo       text,
  mensagem        text,
  numero          text,
  nome            text,
  "horaLastMessage" text,
  created_at      text
)
LANGUAGE sql
STABLE
AS $$
  SELECT DISTINCT ON (m.idgrupo)
    m.idgrupo::text,
    m.nomegrupo::text,
    m.mensagem::text,
    m.numero::text,
    m.nome::text,
    m."horaLastMessage"::text,
    m.created_at::text
  FROM public.mensagens_geral m
  WHERE m.instancia = p_instancia
    AND m.idgrupo IS NOT NULL
  ORDER BY m.idgrupo, m.id DESC;
$$;

-- Deixa a role anon/authenticated chamar (mesmo padrão das outras api_*).
GRANT EXECUTE ON FUNCTION public.api_grupos_lista(text) TO anon, authenticated;

-- ═══════════ delta: 20260731_fin_desconto_tarifa.sql ═══════════

-- ==============================================================
-- Financeiro — desconto e tarifa no lançamento
-- Guarda o desconto (ex: desconto dado ao paciente) e a tarifa (ex: taxa
-- de cartão/banco) de cada lançamento. O `valor` do lançamento passa a ser
-- o LÍQUIDO (bruto − desconto − tarifa), então relatórios/totais já refletem.
-- O bruto é reconstruído na edição = valor + desconto + tarifa.
--
-- Seguro rodar mais de uma vez. Cole no SQL Editor do Supabase do projeto.
-- ==============================================================

ALTER TABLE public.financial_transactions
  ADD COLUMN IF NOT EXISTS desconto numeric DEFAULT 0,
  ADD COLUMN IF NOT EXISTS tarifa   numeric DEFAULT 0;

-- Garante que lançamentos antigos fiquem com 0 (não nulo) pra somar sem erro.
UPDATE public.financial_transactions SET desconto = 0 WHERE desconto IS NULL;
UPDATE public.financial_transactions SET tarifa   = 0 WHERE tarifa   IS NULL;

-- ═══════════ delta: 20260801_crm_contact_funnels.sql ═══════════

-- ==============================================================
-- CRM — lead em vários funis (N-para-N)
-- Cada lead continua com um funil PRINCIPAL em crm_contacts.funil_id/stage_id.
-- Esta tabela guarda os funis ADICIONAIS em que o mesmo lead também aparece,
-- cada um com sua própria etapa. É o MESMO lead (mesmo crm_contacts.id).
--
-- Seguro rodar mais de uma vez. Cole no SQL Editor do Supabase do projeto.
-- ==============================================================

CREATE TABLE IF NOT EXISTS public.crm_contact_funnels (
  id                 uuid        DEFAULT gen_random_uuid() PRIMARY KEY,
  instancia          text        NOT NULL,
  contact_id         uuid        NOT NULL REFERENCES public.crm_contacts(id) ON DELETE CASCADE,
  funil_id           uuid        NOT NULL REFERENCES public.crm_funnels(id)  ON DELETE CASCADE,
  stage_id           uuid        REFERENCES public.crm_stages(id) ON DELETE SET NULL,
  data_entrada_etapa timestamptz DEFAULT now(),
  created_at         timestamptz DEFAULT now(),
  UNIQUE(contact_id, funil_id)
);

ALTER TABLE public.crm_contact_funnels ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "crm_contact_funnels_all" ON public.crm_contact_funnels
    FOR ALL TO authenticated, anon USING (true) WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS crm_contact_funnels_funil_idx   ON public.crm_contact_funnels(funil_id);
CREATE INDEX IF NOT EXISTS crm_contact_funnels_contact_idx ON public.crm_contact_funnels(contact_id);
CREATE INDEX IF NOT EXISTS crm_contact_funnels_inst_idx    ON public.crm_contact_funnels(instancia);

-- ═══════════ delta: 20260801_crm_lead_soft_delete.sql ═══════════

-- ==============================================================
-- CRM — soft-delete de lead (não deixar voltar como "novo lead")
-- Ao remover um lead, em vez de apagar a linha, marcamos removido = true.
-- Assim o número CONTINUA existindo em crm_contacts, e o gatilho de
-- autocriação (crm_autocreate_on_message) NÃO recria o lead quando a pessoa
-- manda mensagem de novo (ele já sai quando o número existe). O board/CRM
-- esconde os leads com removido = true.
--
-- Seguro rodar mais de uma vez. Cole no SQL Editor do Supabase do projeto.
-- ==============================================================

ALTER TABLE public.crm_contacts
  ADD COLUMN IF NOT EXISTS removido    boolean     DEFAULT false,
  ADD COLUMN IF NOT EXISTS removido_at timestamptz;

UPDATE public.crm_contacts SET removido = false WHERE removido IS NULL;

CREATE INDEX IF NOT EXISTS crm_contacts_removido_idx ON public.crm_contacts(instancia, removido);

-- ═══════════ delta: 20260807_crm_temperature_custom.sql ═══════════

-- ==============================================================
-- CRM — temperatura personalizável
-- Antes crm_contacts.temperatura só aceitava 'frio'/'morno'/'quente' (CHECK).
-- Agora a clínica pode criar as suas (crm_temperatures). O campo passa a
-- guardar a key: 'frio'/'morno'/'quente' (padrões) ou o id da personalizada.
--
-- Seguro rodar mais de uma vez. Cole no SQL Editor do Supabase (sbzwtnxx).
-- ==============================================================

-- Libera o CHECK pra aceitar valores personalizados
ALTER TABLE public.crm_contacts DROP CONSTRAINT IF EXISTS crm_contacts_temperatura_check;

CREATE TABLE IF NOT EXISTS public.crm_temperatures (
  id         uuid        DEFAULT gen_random_uuid() PRIMARY KEY,
  instancia  text        NOT NULL,
  nome       text        NOT NULL,
  cor        text        DEFAULT '#64748B',
  posicao    integer     DEFAULT 0,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE public.crm_temperatures ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "crm_temperatures_all" ON public.crm_temperatures
    FOR ALL TO authenticated, anon USING (true) WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS crm_temperatures_inst_idx ON public.crm_temperatures(instancia);

-- ═══════════ delta: 20260807_reminder_message_per_appt.sql ═══════════

-- ==============================================================
-- Lembrete: mensagem personalizada POR AGENDAMENTO
-- Agora cada agendamento pode ter a sua própria mensagem de lembrete
-- (appointments.reminder_message). Prioridade do texto enviado:
--   1) reminder_message do agendamento (se preenchido)   ← novo
--   2) reminder_message do procedimento
--   3) texto padrão
-- Suporta {nome} (nome do paciente) e {data} (dd/mm, HH24:MI).
--
-- Seguro rodar mais de uma vez. Cole no SQL Editor do Supabase (sbzwtnxx).
-- ==============================================================

SET search_path TO public;

ALTER TABLE public.appointments
  ADD COLUMN IF NOT EXISTS reminder_message text;

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
  msg           text;
  tmpl          text;
  appt_local    timestamp;
  session_id    text;
  payload       jsonb;
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

    -- Texto: 1º a msg do agendamento, 2º a do procedimento, 3º o padrão
    tmpl := COALESCE(NULLIF(btrim(r.appt_msg), ''), NULLIF(btrim(r.proc_msg), ''));
    IF tmpl IS NOT NULL THEN
      msg := regexp_replace(
               regexp_replace(tmpl, '\{nome\}', COALESCE(r.contact_nome, ''), 'gi'),
               '\{data\}', to_char(appt_local, 'DD/MM, HH24:MI'), 'gi');
    ELSE
      msg := format(
        'Olá %s! 👋 Passando pra lembrar da sua consulta no dia %s às %s%s. Até lá! 🩺',
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
      INSERT INTO public.mensagens_geral
        (instancia, numero, mensagem, type, "horaLastMessage", created_at, aplicativo)
      VALUES
        (r.instancia, session_id, msg, 'atendente',
         to_char(now() AT TIME ZONE (r.tz_offset)::interval, 'HH24:MI'), now(), 'whatsapp');

      payload := jsonb_build_object(
        'message', msg, 'session_id', session_id, 'phone', r.contact_numero,
        'instancia', r.instancia, 'api_instancia', r.api_instancia,
        'company', r.company_name,
        'sender_name', 'Sistema (Lembrete automático)', 'sender_email', 'sistema@clinisac');
      BEGIN
        PERFORM net.http_post(
          url := 'https://n8n.nexladesenvolvimento.com.br/webhook/envioNexla',
          body := payload, headers := '{"Content-Type": "application/json"}'::jsonb);
      EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'webhook lembrete fail appt %: %', r.id, SQLERRM;
      END;

      UPDATE public.appointments SET reminders = new_reminders WHERE id = r.id;
      cnt := cnt + 1;
    END IF;
  END LOOP;

  RETURN cnt;
END;
$$;

GRANT EXECUTE ON FUNCTION public.process_appointment_reminders() TO service_role;

-- ═══════════ delta: 20260810_single_device_login.sql ═══════════

-- ==============================================================
-- Login em UM ÚNICO dispositivo (anti conta compartilhada)
-- Cada usuário só pode ter uma sessão ativa por vez. Se já houver
-- alguém usando a conta (sessão "fresca", com heartbeat recente), um
-- novo login é BLOQUEADO com a mensagem "já tem uma pessoa utilizando
-- essa conta no momento".
--
-- Como funciona:
--   users.session_token    → token do dispositivo dono da sessão
--   users.session_seen_at  → último "heartbeat" (o app bate a cada ~45s)
--   claim_login_session    → tenta ASSUMIR a sessão. Só consegue se
--                            estiver livre (token nulo), se já for dele
--                            (mesmo token) ou se a sessão do outro estiver
--                            velha (sem heartbeat há mais de p_ttl_seconds).
--   touch_login_session    → heartbeat; devolve false se OUTRO dispositivo
--                            assumiu a conta (aí o app desloga este aqui).
--   release_login_session  → solta a sessão no logout.
--
-- Degradação: enquanto esta migração não roda, o app entra normal (sem
-- travar), então pode rodar a qualquer momento. Seguro rodar mais de uma
-- vez. Cole no SQL Editor do Supabase (projeto sbzwtnxx).
-- ==============================================================

SET search_path TO public;

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS session_token   text,
  ADD COLUMN IF NOT EXISTS session_seen_at timestamptz;

-- Tenta assumir a sessão do usuário para o dispositivo p_token.
-- Devolve { "ok": true } se conseguiu; { "ok": false } se já tem
-- outra pessoa com sessão ativa (fresca).
CREATE OR REPLACE FUNCTION public.claim_login_session(
  p_user_id uuid, p_token text, p_ttl_seconds int DEFAULT 130)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE n int;
BEGIN
  UPDATE public.users
     SET session_token = p_token, session_seen_at = now()
   WHERE id = p_user_id
     AND ( session_token IS NULL
        OR session_token = p_token
        OR session_seen_at IS NULL
        OR session_seen_at < now() - make_interval(secs => p_ttl_seconds) );
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN jsonb_build_object('ok', n > 0);
END;
$$;

-- Heartbeat: mantém a sessão viva. Devolve false se o token não for mais
-- o dono (outro dispositivo assumiu) — o app usa isso pra deslogar aqui.
CREATE OR REPLACE FUNCTION public.touch_login_session(
  p_user_id uuid, p_token text)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE cur text;
BEGIN
  SELECT session_token INTO cur FROM public.users WHERE id = p_user_id;
  IF cur IS DISTINCT FROM p_token THEN
    RETURN false;
  END IF;
  UPDATE public.users SET session_seen_at = now() WHERE id = p_user_id;
  RETURN true;
END;
$$;

-- Solta a sessão (logout), só se o token for o dono atual.
CREATE OR REPLACE FUNCTION public.release_login_session(
  p_user_id uuid, p_token text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  UPDATE public.users
     SET session_token = NULL, session_seen_at = NULL
   WHERE id = p_user_id AND session_token = p_token;
END;
$$;

GRANT EXECUTE ON FUNCTION public.claim_login_session(uuid, text, int) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.touch_login_session(uuid, text)      TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.release_login_session(uuid, text)     TO anon, authenticated, service_role;

-- ═══════════ delta: 20260811_reopen_only_client_msg.sql ═══════════

-- ==============================================================
-- Reabrir conversa finalizada SÓ quando o CLIENTE manda mensagem
--
-- Bug: a trigger reopen_session_on_new_message() apagava a linha de
-- "conversa finalizada" (public.conversations) a CADA mensagem nova em
-- mensagens_geral — inclusive mensagens de atendente/IA/sistema e o
-- LEMBRETE automático de agendamento e o aviso "▶ Atendimento assumido".
-- Resultado: conversas finalizadas "abriam sozinhas".
--
-- Correção: na mensagens_geral, só reabre quando NEW.type é do cliente
-- ('cliente'/'human'). As demais tabelas (legado n8n/clientes) seguem
-- como antes.
--
-- Seguro rodar mais de uma vez. Cole no SQL Editor do Supabase (sbzwtnxx).
-- ==============================================================

CREATE OR REPLACE FUNCTION public.reopen_session_on_new_message() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
declare
  v_session_id text;
  v_type       text;
begin
  IF TG_TABLE_NAME = 'mensagens_geral' THEN
    v_session_id := NEW.numero;
    v_type := lower(coalesce(NEW.type, ''));
    -- Só o CLIENTE reabre. Atendente / IA / sistema / lembrete NÃO reabrem.
    IF v_type NOT IN ('cliente', 'human') THEN
      RETURN NEW;
    END IF;
  ELSE
    v_session_id := NEW.session_id;
  END IF;

  if v_session_id is not null then
    delete from public.conversations where session_id = v_session_id;
  end if;
  return NEW;
end; $$;

-- ═══════════ delta: 20260812_reopen_group_not_individual.sql ═══════════

-- ==============================================================
-- Reabrir conversa: mensagem de GRUPO não reabre o INDIVIDUAL
--
-- Bug (relatado na Agência Magnética): quando um contato manda mensagem
-- num GRUPO, a linha em mensagens_geral vem com numero = o número
-- individual do participante e idgrupo = o grupo. A trigger
-- reopen_session_on_new_message() apagava a "conversa finalizada" usando
-- o `numero` — ou seja, reabria a conversa INDIVIDUAL do participante
-- toda vez que ele falava no grupo. Resultado: conversas finalizadas
-- "voltavam sozinhas" pra Recepção.
--
-- Correção (mensagens_geral):
--   • mensagem de GRUPO (idgrupo preenchido) → reabre, no máximo, a
--     conversa do GRUPO (session_id = idgrupo), NUNCA a do participante;
--   • só o CLIENTE reabre (type 'cliente'/'human', sem diferenciar
--     maiúsculas — no banco vem 'Cliente' com C maiúsculo).
-- As demais tabelas (legado n8n/clientes) seguem como antes.
--
-- Substitui a 20260811. Seguro rodar mais de uma vez. Cole no SQL Editor
-- do Supabase (projeto sbzwtnxx).
-- ==============================================================

CREATE OR REPLACE FUNCTION public.reopen_session_on_new_message() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
declare
  v_session_id text;
  v_type       text;
begin
  IF TG_TABLE_NAME = 'mensagens_geral' THEN
    -- Mensagem de grupo reabre (se for o caso) a conversa do GRUPO, e nunca
    -- a conversa individual do participante que mandou.
    IF NEW.idgrupo IS NOT NULL AND NEW.idgrupo <> '' THEN
      v_session_id := NEW.idgrupo;
    ELSE
      v_session_id := NEW.numero;
    END IF;

    -- Só o CLIENTE reabre. Atendente / IA / sistema / lembrete NÃO reabrem.
    v_type := lower(coalesce(NEW.type, ''));
    IF v_type NOT IN ('cliente', 'human') THEN
      RETURN NEW;
    END IF;
  ELSE
    v_session_id := NEW.session_id;
  END IF;

  if v_session_id is not null then
    delete from public.conversations where session_id = v_session_id;
  end if;
  return NEW;
end; $$;

-- ═══════════ delta: 20260813_message_reactions.sql ═══════════

-- ==============================================================
-- Reações (emoji) nas mensagens
--
-- Quando o cliente reage a uma mensagem no WhatsApp, a Evolution manda um
-- evento com messageType = 'reactionMessage'. Ele NÃO é uma mensagem nova —
-- aponta pra mensagem original pelo id (reactionMessage.key.id), que é o
-- mesmo `id_mensagem` já guardado em mensagens_geral.
--
-- Aqui:
--  • mensagens_geral.reaction guarda o emoji da reação (nulo = sem reação);
--  • set_message_reaction() casa pela id da mensagem original + instancia e
--    grava/limpa o emoji. O n8n chama essa função no ramo de reactionMessage.
--
-- Seguro rodar mais de uma vez. Cole no SQL Editor do Supabase (sbzwtnxx).
-- ==============================================================

ALTER TABLE public.mensagens_geral
  ADD COLUMN IF NOT EXISTS reaction text;

-- Grava (ou limpa, se vier vazio) a reação na mensagem original.
-- Devolve quantas linhas casaram (0 = não achou a mensagem pelo id).
CREATE OR REPLACE FUNCTION public.set_message_reaction(
  p_instancia text, p_id_mensagem text, p_reaction text)
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE n int;
BEGIN
  UPDATE public.mensagens_geral
     SET reaction = NULLIF(btrim(coalesce(p_reaction, '')), '')
   WHERE instancia = p_instancia
     AND id_mensagem = p_id_mensagem;
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_message_reaction(text, text, text) TO anon, authenticated, service_role;

-- ═══════════ delta: 20260817_reopen_grace_period.sql ═══════════

-- ==============================================================
-- Reabrir conversa: SÓ mensagens_geral reabre + carência de 2 min
--
-- Bug "reabre sozinho" (Agência Magnética): conversa finalizada voltava
-- pra Recepção mesmo SEM mensagem nova do cliente. Investigação (monitor
-- ao vivo + dados) mostrou duas coisas:
--
--  1) A trigger reopen_session_on_new_message também está em tabelas
--     AUXILIARES (public.clientes, public.n8n_chat_histories_*). No ramo
--     delas, ela reabria a conversa em QUALQUER insert, sem checar tipo —
--     então uma escrita na memória do n8n (ou re-insert de contato) do
--     mesmo número reabria a conversa sem mensagem nova de verdade.
--     ➜ Agora SÓ mensagens_geral reabre. As auxiliares não reabrem mais.
--
--  2) Corrida de tempo: quem atende "fora" (no WhatsApp) finaliza na
--     plataforma antes da mensagem do cliente cair aqui pelo n8n; quando
--     cai (segundos depois), reabria.
--     ➜ Carência: mensagem do cliente só reabre se a conversa NÃO foi
--        finalizada nos últimos 2 minutos.
--
-- Mantém: só CLIENTE reabre; mensagem de GRUPO mexe no grupo, nunca no
-- individual do participante.
--
-- Substitui a 20260812. Seguro rodar mais de uma vez. Cole no SQL Editor
-- do Supabase (projeto sbzwtnxx).
-- ==============================================================

CREATE OR REPLACE FUNCTION public.reopen_session_on_new_message() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
declare
  v_session_id text;
  v_type       text;
begin
  -- SÓ a tabela de mensagens da conversa reabre. Escritas em tabelas
  -- auxiliares (clientes/contatos, memória do n8n) NÃO reabrem — eram elas
  -- que causavam a reabertura "sozinha", sem mensagem nova de verdade.
  IF TG_TABLE_NAME <> 'mensagens_geral' THEN
    RETURN NEW;
  END IF;

  -- Grupo reabre (no máximo) a conversa do GRUPO, nunca a do participante.
  IF NEW.idgrupo IS NOT NULL AND NEW.idgrupo <> '' THEN
    v_session_id := NEW.idgrupo;
  ELSE
    v_session_id := NEW.numero;
  END IF;

  -- Só o CLIENTE reabre.
  v_type := lower(coalesce(NEW.type, ''));
  IF v_type NOT IN ('cliente', 'human') THEN
    RETURN NEW;
  END IF;

  IF v_session_id IS NOT NULL THEN
    -- Carência: não reabre se acabou de ser finalizada (< 2 min). Evita o
    -- reabrir da mensagem atrasada (n8n) que o atendente já tratou.
    DELETE FROM public.conversations
     WHERE session_id = v_session_id
       AND (closed_at IS NULL OR closed_at < now() - interval '2 minutes');
  END IF;
  RETURN NEW;
end; $$;

-- ═══════════ delta: 20260818_mensalidade_financeiro.sql ═══════════

-- ==============================================================
-- Mensalidade no Catálogo Clínico → financeiro 1x por mês
--
-- Agora o Catálogo Clínico tem o tipo de serviço "mensalidade" (ex:
-- Pilates 2x/semana, com valor MENSAL). Quando o paciente é agendado
-- nesse serviço, o financeiro deve lançar a mensalidade UMA vez por mês
-- (valor cheio), e não por sessão — mesmo com várias sessões no mês.
--
-- Aqui:
--  • financial_transactions.mensalidade_key: chave de dedup
--    (instancia | procedure_id | paciente | AAAA-MM) — garante 1 por mês.
--  • fin_sync_on_appointment: se o procedimento é 'mensalidade', cria 1
--    lançamento mensal (dedup pela chave, usando o valor mensal do
--    procedimento) e NÃO gera cobrança por sessão. Os demais tipos seguem
--    como antes.
--
-- Seguro rodar mais de uma vez. Cole no SQL Editor do Supabase (sbzwtnxx).
-- ==============================================================

SET search_path TO public;

ALTER TABLE public.financial_transactions
  ADD COLUMN IF NOT EXISTS mensalidade_key text;

-- 1 lançamento por (paciente + serviço + mês). NULLs não conflitam, então
-- os lançamentos normais (key nula) convivem sem problema.
CREATE UNIQUE INDEX IF NOT EXISTS fin_tx_mensalidade_key_uq
  ON public.financial_transactions (mensalidade_key);

CREATE OR REPLACE FUNCTION public.fin_sync_on_appointment()
RETURNS trigger LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
DECLARE
  v_existing  uuid;
  v_cat       uuid;
  v_desc      text;
  v_status    text;
  v_proc_type text;
  v_proc_name text;
  v_monthly   numeric;
  v_comp      date;
  v_key       text;
BEGIN
  -- Agendamento de plano de tratamento não gera cobrança avulsa.
  IF NEW.treatment_plan_id IS NOT NULL THEN RETURN NEW; END IF;

  -- Tipo + valor mensal do procedimento (uma consulta só).
  SELECT type, name, COALESCE(price_particular, 0)
    INTO v_proc_type, v_proc_name, v_monthly
    FROM procedures WHERE id = NEW.procedure_id;

  -- ── MENSALIDADE: 1 lançamento por mês (paciente + serviço + mês) ──────────
  IF v_proc_type = 'mensalidade' THEN
    IF v_monthly > 0 THEN
      v_comp := date_trunc('month', NEW.starts_at)::date;
      v_key  := NEW.instancia || '|' || NEW.procedure_id::text || '|'
                || COALESCE(NULLIF(btrim(NEW.contact_numero), ''), NEW.contact_nome, '') || '|'
                || to_char(v_comp, 'YYYY-MM');

      SELECT id INTO v_cat FROM financial_categories
       WHERE (instancia = NEW.instancia OR instancia = '_default_')
         AND tipo IN ('receita', 'ambos') AND lower(nome) LIKE '%consulta%'
       ORDER BY (instancia = NEW.instancia) DESC LIMIT 1;

      INSERT INTO financial_transactions
        (instancia, tipo, descricao, valor, status, categoria_id, vencimento,
         contact_nome, competencia, mensalidade_key, created_by)
      VALUES
        (NEW.instancia, 'receita',
         'Mensalidade — ' || COALESCE(v_proc_name, 'Serviço') || ' — '
           || COALESCE(NEW.contact_nome, 'Paciente') || ' (' || to_char(v_comp, 'MM/YYYY') || ')',
         v_monthly, 'pendente', v_cat, NEW.starts_at::date,
         NEW.contact_nome, v_comp, v_key, 'Agenda (mensalidade)')
      ON CONFLICT (mensalidade_key) DO NOTHING;
    END IF;
    RETURN NEW;
  END IF;

  -- ── Demais tipos: cobrança avulsa por atendimento (como antes) ───────────
  IF COALESCE(NEW.price, 0) <= 0 THEN RETURN NEW; END IF;

  SELECT id INTO v_existing FROM financial_transactions WHERE appointment_id = NEW.id LIMIT 1;

  v_status := CASE
    WHEN lower(COALESCE(NEW.status, '')) = 'cancelado'    THEN 'cancelado'
    WHEN lower(COALESCE(NEW.payment_status, '')) = 'pago' THEN 'pago'
    ELSE 'pendente'
  END;

  IF v_existing IS NULL THEN
    SELECT id INTO v_cat FROM financial_categories
     WHERE (instancia = NEW.instancia OR instancia = '_default_')
       AND tipo IN ('receita', 'ambos') AND lower(nome) LIKE '%consulta%'
     ORDER BY (instancia = NEW.instancia) DESC LIMIT 1;

    v_desc := COALESCE(v_proc_name, 'Consulta') || ' — ' || COALESCE(NEW.contact_nome, 'Paciente');

    INSERT INTO financial_transactions
      (instancia, tipo, descricao, valor, status, categoria_id, vencimento,
       pagamento_at, contact_nome, appointment_id, created_by)
    VALUES
      (NEW.instancia, 'receita', v_desc, NEW.price, v_status, v_cat, NEW.starts_at::date,
       CASE WHEN v_status = 'pago' THEN COALESCE(NEW.paid_at::date, CURRENT_DATE) ELSE NULL END,
       NEW.contact_nome, NEW.id, 'Agenda (automático)');
  ELSE
    UPDATE financial_transactions
       SET valor = NEW.price, status = v_status,
           pagamento_at = CASE WHEN v_status = 'pago' THEN COALESCE(pagamento_at, NEW.paid_at::date, CURRENT_DATE) ELSE pagamento_at END
     WHERE id = v_existing;
  END IF;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS fin_sync_appt ON public.appointments;
CREATE TRIGGER fin_sync_appt
  AFTER INSERT OR UPDATE OF price, status, payment_status, paid_at ON public.appointments
  FOR EACH ROW EXECUTE FUNCTION public.fin_sync_on_appointment();

-- ═══════════ delta: 20260824_master_users_admmkt.sql ═══════════

-- ==============================================================
-- Segundo usuário mestre (admmkt) — acesso mestre multi-usuário
--
-- Mantém compatibilidade total com o mestre atual (adm.meg via
-- platform_settings). Adiciona tabela master_users para novos
-- mestres. master_list_companies passa a aceitar ambos.
--
-- IMPORTANTE: rode no SQL Editor do Supabase (projeto sbzwtnxx).
-- Depois execute o passo 2 (no fim deste arquivo) para criar o
-- usuário admmkt com a senha escolhida.
-- ==============================================================

SET search_path TO 'public', 'extensions';

-- 1a) Tabela de mestres adicionais (RLS sem policy — só SECURITY DEFINER acessa)
CREATE TABLE IF NOT EXISTS public.master_users (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  name          text        NOT NULL,
  email         text        NOT NULL UNIQUE,
  password_hash text        NOT NULL,
  active        boolean     DEFAULT true,
  created_at    timestamptz DEFAULT now()
);
ALTER TABLE public.master_users ENABLE ROW LEVEL SECURITY;

-- 1b) Reescreve master_list_companies para aceitar platform_settings OU master_users
CREATE OR REPLACE FUNCTION public.master_list_companies(p_email text, p_password text)
RETURNS TABLE(id uuid, name text, instance text, plan text, active boolean)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_email text;
  v_hash  text;
  v_ok    boolean := false;
BEGIN
  -- Tenta o mestre legado (platform_settings)
  SELECT ps.value INTO v_email FROM platform_settings ps WHERE ps.key = 'master_email';
  SELECT ps.value INTO v_hash  FROM platform_settings ps WHERE ps.key = 'master_password_hash';

  IF v_email IS NOT NULL AND v_hash IS NOT NULL
     AND lower(trim(p_email)) = lower(trim(v_email))
     AND v_hash = crypt(p_password, v_hash)
  THEN
    v_ok := true;
  END IF;

  -- Se não bateu, tenta master_users
  IF NOT v_ok THEN
    SELECT (mu.password_hash = crypt(p_password, mu.password_hash)) INTO v_ok
      FROM master_users mu
     WHERE mu.active = true
       AND lower(trim(mu.email)) = lower(trim(p_email))
     LIMIT 1;
  END IF;

  IF NOT v_ok OR v_ok IS NULL THEN RETURN; END IF;

  RETURN QUERY
  SELECT c.id, c.name, c.instance, c.plan, c.active
    FROM companies c
   ORDER BY c.name;
END;
$$;

-- ==============================================================
-- 2) CRIAR O USUÁRIO admmkt (rode separado no SQL Editor,
--    trocando SENHA-FORTE-AQUI pela senha real):
--
--    INSERT INTO public.master_users (name, email, password_hash)
--    VALUES (
--      'admmkt',
--      'admmkt@clinisac.com.br',
--      crypt('SENHA-FORTE-AQUI', gen_salt('bf'))
--    )
--    ON CONFLICT (email) DO UPDATE
--      SET password_hash = EXCLUDED.password_hash,
--          name          = EXCLUDED.name,
--          active        = true;
--
--    Para desativar o admmkt:
--    UPDATE public.master_users SET active = false
--     WHERE email = 'admmkt@clinisac.com.br';
-- ==============================================================

-- ═══════════ delta: 20260828_lock_users_sensitive_columns.sql ═══════════

-- ==============================================================
-- SEGURANÇA — fechar colunas sensíveis de public.users pra anon
--
-- Problema (CRÍTICO): a policy de SELECT era aberta (USING true) e o role
-- anon tinha SELECT na tabela inteira → qualquer um com a anon key (que é
-- pública, vai no bundle JS) lia `password_hash` e `session_token` de TODOS
-- os usuários de TODAS as clínicas via /rest/v1/users?select=password_hash.
-- Também dava pra sobrescrever `password_hash` via UPDATE direto.
--
-- Correção: RLS continua por linha, mas o acesso a COLUNA passa a ser por
-- GRANT. Libera só as colunas não-sensíveis pra leitura, e o UPDATE de tudo
-- MENOS password_hash. As funções login_user / create_user /
-- update_user_password são SECURITY DEFINER (rodam como owner) → seguem
-- funcionando normalmente, inclusive validando/gravando a senha.
--
-- ⚠️ ORDEM: rode isto DEPOIS que o deploy do frontend (que parou de usar
-- users(*) / select('*') em users) estiver no ar. Seguro rodar mais de uma
-- vez. Cole no SQL Editor do Supabase (produção sbzwtnxx).
-- ==============================================================

-- Leitura: só colunas não-sensíveis (fora password_hash, session_token,
-- session_seen_at).
REVOKE SELECT ON public.users FROM anon, authenticated;
GRANT  SELECT (id, name, email, role, active, company_id, created_at)
  ON public.users TO anon, authenticated;

-- Escrita: tudo que o app edita direto (nome/e-mail/perfil/ativo e o token de
-- sessão do login em 1 dispositivo) — MENOS password_hash (a troca de senha é
-- feita só pela RPC update_user_password, que é SECURITY DEFINER).
REVOKE UPDATE ON public.users FROM anon, authenticated;
GRANT  UPDATE (name, email, role, active, session_token, session_seen_at)
  ON public.users TO anon, authenticated;

-- Criação/remoção de usuário é só via RPC create_user (SECURITY DEFINER); o
-- cliente nunca faz INSERT/DELETE direto. Fecha os dois pra evitar que a anon
-- key crie um admin novo (ou apague usuários) em qualquer empresa.
REVOKE INSERT, DELETE ON public.users FROM anon, authenticated;

-- ═══════════ delta: 20260828_pilot_drop_debug_mint.sql ═══════════

-- ==============================================================
-- FASE 0 — remover a função de debug temporária
--
-- O smoke test/piloto foi validado e o login real (login_session) já está
-- provado. A _pilot_debug_mint emitia crachá de qualquer instancia (com o
-- PIN) — depois que saved_contacts passou a isolar por tenant, isso virou um
-- furo. Removendo agora. Seguro rodar mais de uma vez.
-- Cole no SQL Editor (produção sbzwtnxx).
-- ==============================================================

DROP FUNCTION IF EXISTS public._pilot_debug_mint(text, text);

-- ═══════════ delta: 20260828_pilot_rls_saved_contacts.sql ═══════════

-- ==============================================================
-- FASE 0 (piloto) — RLS por tenant em public.saved_contacts
--
-- Prova o isolamento: quem chega COM crachá (token authenticated) só vê a
-- própria `instancia`. Quem chega como ANON continua vendo tudo — porque o
-- frontend atual ainda usa a anon key. Então esta migration NÃO muda o
-- comportamento do app hoje (todas as requisições dele são anon); só passa a
-- filtrar as requisições autenticadas (que hoje são só os testes do Claude).
--
-- Depois que o frontend passar a mandar o crachá, as requisições viram
-- authenticated → caem na regra de tenant → isolamento real. Por último a
-- gente remove a policy anon.
--
-- Seguro rodar mais de uma vez. Cole no SQL Editor (produção sbzwtnxx).
-- ==============================================================

DROP POLICY IF EXISTS saved_contacts_all ON public.saved_contacts;

-- anon: continua aberto (frontend atual). SERÁ REMOVIDO no fim da migração.
DROP POLICY IF EXISTS saved_contacts_anon ON public.saved_contacts;
CREATE POLICY saved_contacts_anon ON public.saved_contacts
  FOR ALL TO anon
  USING (true) WITH CHECK (true);

-- authenticated (com crachá): só a própria instancia (lida do claim do token).
DROP POLICY IF EXISTS saved_contacts_tenant ON public.saved_contacts;
CREATE POLICY saved_contacts_tenant ON public.saved_contacts
  FOR ALL TO authenticated
  USING      (instancia = (current_setting('request.jwt.claims', true)::jsonb ->> 'instancia'))
  WITH CHECK (instancia = (current_setting('request.jwt.claims', true)::jsonb ->> 'instancia'));

-- ── ROLLBACK (se algo travar, volta ao aberto): ──────────────────────────
--   DROP POLICY saved_contacts_anon    ON public.saved_contacts;
--   DROP POLICY saved_contacts_tenant  ON public.saved_contacts;
--   CREATE POLICY saved_contacts_all ON public.saved_contacts
--     FOR ALL TO authenticated, anon USING (true) WITH CHECK (true);

-- ═══════════ delta: 20260828_pilot_session_token.sql ═══════════

-- ==============================================================
-- FASE 0 (piloto) — "crachá" de sessão assinado no banco + RLS por tenant
--
-- Projeto usa JWT HS256 (segredo compartilhado), então dá pra assinar um
-- token DENTRO do banco (extensions.sign) que o PostgREST aceita. O token
-- carrega a `instancia` da clínica; as políticas RLS passam a filtrar por ela.
--
-- Esta migration NÃO fecha nenhuma tabela ainda — só cria o mecanismo e as
-- funções de teste. É segura de rodar (não muda o comportamento do app).
--
-- ⚠️ ANTES de rodar isto, guarde o JWT secret (passo no fim do arquivo).
-- Cole no SQL Editor do Supabase (produção sbzwtnxx). Idempotente.
-- ==============================================================

-- pgjwt (sign/verify) — normalmente já existe no Supabase; garante idempotente
CREATE EXTENSION IF NOT EXISTS pgjwt WITH SCHEMA extensions;

-- Cofre de segredos: RLS ligado e SEM policy → nem anon nem authenticated leem;
-- só funções SECURITY DEFINER (que rodam como owner) enxergam.
CREATE TABLE IF NOT EXISTS public.app_secrets (
  key        text PRIMARY KEY,
  value      text,
  updated_at timestamptz DEFAULT now()
);
ALTER TABLE public.app_secrets ENABLE ROW LEVEL SECURITY;

-- ── Emite o crachá após validar login (senha do usuário) ──────────────────
-- Devolve { user: {...}, token: '<jwt>' } ou NULL se a credencial não bate.
CREATE OR REPLACE FUNCTION public.login_session(p_email text, p_password text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  u          record;
  v_secret   text;
  v_instancia text;
  v_token    text;
BEGIN
  SELECT value INTO v_secret FROM app_secrets WHERE key = 'jwt_secret';
  IF v_secret IS NULL THEN RAISE EXCEPTION 'jwt_secret não configurado em app_secrets'; END IF;

  SELECT usr.* INTO u
    FROM public.users usr
   WHERE usr.email = p_email
     AND usr.active = true
     AND usr.password_hash = crypt(p_password, usr.password_hash)
   LIMIT 1;
  IF u.id IS NULL THEN RETURN NULL; END IF;

  SELECT c.instance INTO v_instancia FROM public.companies c WHERE c.id = u.company_id;

  v_token := extensions.sign(
    json_build_object(
      'role', 'authenticated', 'aud', 'authenticated', 'iss', 'clinimag',
      'sub', u.id::text, 'email', u.email,
      'company_id', u.company_id::text, 'instancia', v_instancia,
      'user_role', u.role, 'is_master', false,
      'iat', extract(epoch FROM now())::int,
      'exp', extract(epoch FROM now() + interval '24 hours')::int
    )::json,
    v_secret
  );

  RETURN jsonb_build_object(
    'user', jsonb_build_object(
      'id', u.id, 'name', u.name, 'email', u.email,
      'role', u.role, 'active', u.active, 'company_id', u.company_id),
    'token', v_token
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.login_session(text, text) TO anon, authenticated;

-- ── Smoke test: devolve os claims que o PostgREST extraiu do token ────────
CREATE OR REPLACE FUNCTION public.whoami()
RETURNS jsonb LANGUAGE sql STABLE
AS $$ SELECT nullif(current_setting('request.jwt.claims', true), '')::jsonb $$;
GRANT EXECUTE ON FUNCTION public.whoami() TO anon, authenticated;

-- ── TEMPORÁRIO (só p/ o smoke test do Claude): emite um token p/ uma
-- instancia sem senha, protegido por um PIN. Será REMOVIDO após validar.
CREATE OR REPLACE FUNCTION public._pilot_debug_mint(p_instancia text, p_pin text)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE v_secret text;
BEGIN
  IF p_pin <> 'nx-pilot-7Kq2' THEN RETURN NULL; END IF;
  SELECT value INTO v_secret FROM app_secrets WHERE key = 'jwt_secret';
  IF v_secret IS NULL THEN RETURN NULL; END IF;
  RETURN extensions.sign(
    json_build_object(
      'role','authenticated','aud','authenticated','iss','clinimag',
      'sub','00000000-0000-0000-0000-000000000000','email','pilot@debug',
      'instancia', p_instancia, 'is_master', false,
      'iat', extract(epoch FROM now())::int,
      'exp', extract(epoch FROM now() + interval '1 hour')::int
    )::json, v_secret);
END;
$$;
GRANT EXECUTE ON FUNCTION public._pilot_debug_mint(text, text) TO anon, authenticated;

-- ==============================================================
-- PASSO OBRIGATÓRIO — guardar o JWT secret (rode SEPARADO, colando o segredo):
--
--   No Supabase Dashboard → Project Settings → API → "JWT Settings" →
--   copie o campo "JWT Secret" (uma string longa) e cole abaixo, AQUI no
--   SQL Editor (NUNCA no chat):
--
--   INSERT INTO public.app_secrets (key, value)
--   VALUES ('jwt_secret', 'COLE_O_JWT_SECRET_AQUI')
--   ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now();
-- ==============================================================

-- ═══════════ delta: 20260828_reaction_instancia_case_insensitive.sql ═══════════

-- ==============================================================
-- Reações — casar a instância SEM diferenciar maiúscula/minúscula
--
-- Problema: set_message_reaction casava `instancia = p_instancia` (exato).
-- Quando a instância é gravada numa caixa (ex.: "NEXLA") mas o n8n/Evolution
-- manda o nome em outra (ex.: "nexla") no evento de reação, o UPDATE não
-- achava a linha → a reação não gravava (só nessa instância). As demais
-- (magnetica, alessandra…) funcionam porque já batem a caixa.
--
-- Correção: comparar por lower(instancia). Seguro — nenhuma instância difere
-- apenas por maiúscula/minúscula.
--
-- Seguro rodar mais de uma vez. Cole no SQL Editor do Supabase (sbzwtnxx).
-- ==============================================================

CREATE OR REPLACE FUNCTION public.set_message_reaction(
  p_instancia text, p_id_mensagem text, p_reaction text)
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE n int;
BEGIN
  UPDATE public.mensagens_geral
     SET reaction = NULLIF(btrim(coalesce(p_reaction, '')), '')
   WHERE lower(instancia) = lower(p_instancia)
     AND id_mensagem = p_id_mensagem;
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_message_reaction(text, text, text) TO anon, authenticated, service_role;

-- ═══ FK adiado (após todas as tabelas existirem) ═══
-- Foreign keys dos vínculos de plano (integridade + permite embeds no futuro)
DO $$ BEGIN
  ALTER TABLE public.appointments
    ADD CONSTRAINT appointments_treatment_plan_id_fkey
    FOREIGN KEY (treatment_plan_id) REFERENCES public.treatment_plans(id) ON DELETE SET NULL;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
