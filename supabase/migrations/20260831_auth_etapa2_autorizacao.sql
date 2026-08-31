-- ══════════════════════════════════════════════════════════════════════════
-- Migração para Supabase Auth — ETAPA 2 de 3: as funções passam a autorizar
--
-- O QUE MUDA
--   Até aqui as funções privilegiadas confiavam nos argumentos: quem soubesse
--   um user_id mandava. Agora elas perguntam auth.uid() — que vem de um JWT
--   assinado pelo Supabase e o cliente não consegue forjar.
--
--   Regra de quem administra usuários:
--     • ADM global  → qualquer clínica
--     • admin       → só a própria clínica
--     • viewer/anon → ninguém
--
--   As funções também passam a manter auth.users em dia: criar usuário cria
--   a identidade, trocar senha troca dos dois lados, apagar apaga dos dois.
--   Sem isso, um usuário novo existiria no perfil mas não conseguiria logar.
--
-- ⚠ ESTA ETAPA E O FRONTEND ANDAM JUNTOS
--   Depois de rodar isto, o painel só funciona com o front da etapa 2 (que
--   loga pelo Supabase Auth). Rode e publique o front na sequência.
--
-- Idempotente: pode rodar mais de uma vez.
-- ══════════════════════════════════════════════════════════════════════════

SET search_path TO public, extensions;

-- ─────────────────────────────────────────────────────────────────────────
-- 0) Quem pode administrar usuários de uma clínica
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.auth_can_manage_users(p_company_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $fn$
  SELECT public.auth_is_adm()
      OR ( public.auth_role() = 'admin'
       AND p_company_id IS NOT NULL
       AND p_company_id = public.auth_company_id() );
$fn$;

GRANT EXECUTE ON FUNCTION public.auth_can_manage_users(uuid) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- 1) create_user — agora exige permissão e cria também a identidade de login
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.create_user(
  p_name text, p_email text, p_password text, p_role text, p_company_id uuid)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'extensions'
AS $fn$
DECLARE
  v_id    uuid := gen_random_uuid();
  v_email text := lower(trim(p_email));
  v_hash  text;
BEGIN
  IF NOT public.auth_can_manage_users(p_company_id) THEN
    RAISE EXCEPTION 'create_user: sem permissao para criar usuario nesta clinica'
      USING ERRCODE = '42501';
  END IF;

  IF p_role IS NULL OR p_role NOT IN ('admin','viewer') THEN
    RAISE EXCEPTION 'create_user: perfil nao permitido (%)', p_role
      USING ERRCODE = '42501';
  END IF;

  IF p_company_id IS NULL
     OR NOT EXISTS (SELECT 1 FROM public.companies WHERE id = p_company_id) THEN
    RAISE EXCEPTION 'create_user: empresa inexistente'
      USING ERRCODE = '42501';
  END IF;

  IF p_password IS NULL OR length(p_password) < 8 THEN
    RAISE EXCEPTION 'create_user: a senha precisa ter ao menos 8 caracteres'
      USING ERRCODE = '42501';
  END IF;

  v_hash := crypt(p_password, gen_salt('bf'));

  INSERT INTO public.users (id, name, email, password_hash, role, company_id)
  VALUES (v_id, p_name, v_email, v_hash, p_role, p_company_id);

  INSERT INTO auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at,
    raw_app_meta_data, raw_user_meta_data, is_super_admin,
    confirmation_token, recovery_token, email_change_token_new, email_change)
  VALUES (
    '00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated',
    v_email, v_hash, now(), now(), now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('name', p_name), false, '', '', '', '');

  INSERT INTO auth.identities (
    provider_id, user_id, identity_data, provider, created_at, updated_at)
  VALUES (
    v_id::text, v_id,
    jsonb_build_object('sub', v_id::text, 'email', v_email, 'email_verified', true),
    'email', now(), now());

  RETURN v_id;
END;
$fn$;

-- ─────────────────────────────────────────────────────────────────────────
-- 2) update_user_password — reset feito pelo admin. Exige permissão sobre a
--    clínica do alvo e sincroniza os dois lados.
--    Conta ADM continua fora: ela troca a própria senha (item 4).
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.update_user_password(p_user_id uuid, p_password text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'extensions'
AS $fn$
DECLARE
  v_role    text;
  v_company uuid;
  v_hash    text;
BEGIN
  SELECT role, company_id INTO v_role, v_company
    FROM public.users WHERE id = p_user_id;

  IF v_role IS NULL THEN
    RETURN;
  END IF;

  IF v_role = 'adm' THEN
    RAISE EXCEPTION 'update_user_password: conta ADM troca a senha pela propria tela'
      USING ERRCODE = '42501';
  END IF;

  IF NOT public.auth_can_manage_users(v_company) THEN
    RAISE EXCEPTION 'update_user_password: sem permissao'
      USING ERRCODE = '42501';
  END IF;

  IF p_password IS NULL OR length(p_password) < 8 THEN
    RAISE EXCEPTION 'update_user_password: a senha precisa ter ao menos 8 caracteres'
      USING ERRCODE = '42501';
  END IF;

  v_hash := crypt(p_password, gen_salt('bf'));

  UPDATE public.users SET password_hash = v_hash WHERE id = p_user_id;
  UPDATE auth.users
     SET encrypted_password = v_hash, updated_at = now()
   WHERE id = p_user_id;
END;
$fn$;

-- ─────────────────────────────────────────────────────────────────────────
-- 2b) update_user_profile — editar nome/e-mail/perfil.
--
--     Precisa existir porque o painel editava public.users direto. Agora o
--     login vem de auth.users: trocar o e-mail só no perfil deixaria a pessoa
--     sem conseguir entrar, sem nenhum aviso.
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.update_user_profile(
  p_user_id uuid, p_name text, p_email text, p_role text)
RETURNS json
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE
  v_role    text;
  v_company uuid;
  v_email   text := lower(trim(p_email));
BEGIN
  SELECT role, company_id INTO v_role, v_company
    FROM public.users WHERE id = p_user_id;

  IF v_role IS NULL THEN
    RETURN json_build_object('ok', false, 'error', 'Usuário não encontrado');
  END IF;

  IF NOT public.auth_can_manage_users(v_company) THEN
    RETURN json_build_object('ok', false, 'error', 'Sem permissão para editar este usuário.');
  END IF;

  -- Ninguém promove ninguém a ADM por aqui.
  IF p_role IS NOT NULL AND p_role NOT IN ('admin','viewer') THEN
    RETURN json_build_object('ok', false, 'error', 'Perfil não permitido.');
  END IF;

  IF v_email IS NOT NULL AND v_email <> ''
     AND EXISTS (SELECT 1 FROM public.users WHERE email = v_email AND id <> p_user_id) THEN
    RETURN json_build_object('ok', false, 'error', 'Já existe um usuário com esse e-mail.');
  END IF;

  UPDATE public.users
     SET name       = COALESCE(p_name, name),
         email      = COALESCE(NULLIF(v_email, ''), email),
         role       = COALESCE(p_role, role)
   WHERE id = p_user_id;

  UPDATE auth.users
     SET email      = COALESCE(NULLIF(v_email, ''), email),
         updated_at = now()
   WHERE id = p_user_id;

  UPDATE auth.identities
     SET identity_data = jsonb_set(
           identity_data, '{email}',
           to_jsonb(COALESCE(NULLIF(v_email, ''), identity_data->>'email'))),
         updated_at = now()
   WHERE user_id = p_user_id AND provider = 'email';

  RETURN json_build_object('ok', true);
END;
$fn$;

GRANT EXECUTE ON FUNCTION public.update_user_profile(uuid, text, text, text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- 3) delete_user — exige permissão e remove dos dois lados
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.delete_user(p_user_id uuid)
RETURNS json
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE
  v_email   text;
  v_role    text;
  v_company uuid;
BEGIN
  SELECT email, role, company_id INTO v_email, v_role, v_company
    FROM users WHERE id = p_user_id;

  IF v_email IS NULL THEN
    RETURN json_build_object('ok', false, 'error', 'Usuário não encontrado');
  END IF;

  IF v_role = 'adm' THEN
    RETURN json_build_object('ok', false, 'error', 'Conta ADM não pode ser removida por aqui.');
  END IF;

  IF NOT public.auth_can_manage_users(v_company) THEN
    RETURN json_build_object('ok', false, 'error', 'Sem permissão para remover este usuário.');
  END IF;

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
  DELETE FROM auth.users WHERE id = p_user_id;   -- identities caem por cascade

  RETURN json_build_object('ok', true, 'email', v_email);
END;
$fn$;

-- ─────────────────────────────────────────────────────────────────────────
-- 4) change_own_password — só a própria conta, conferindo a senha atual.
--    Mantém public.users e auth.users em sincronia.
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.change_own_password(
  p_email text, p_current_password text, p_new_password text)
RETURNS json
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'extensions'
AS $fn$
DECLARE
  v_id   uuid;
  v_hash text;
  v_new  text;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN json_build_object('ok', false, 'error', 'Sessão expirada. Entre de novo.');
  END IF;

  IF p_new_password IS NULL OR length(p_new_password) < 8 THEN
    RETURN json_build_object('ok', false, 'error', 'A nova senha precisa ter ao menos 8 caracteres.');
  END IF;

  SELECT id, password_hash INTO v_id, v_hash
    FROM public.users
   WHERE id = auth.uid() AND active = true;

  IF v_id IS NULL THEN
    RETURN json_build_object('ok', false, 'error', 'Sessão inválida.');
  END IF;

  IF v_hash IS NULL OR v_hash <> crypt(p_current_password, v_hash) THEN
    RETURN json_build_object('ok', false, 'error', 'Senha atual incorreta.');
  END IF;

  v_new := crypt(p_new_password, gen_salt('bf'));

  UPDATE public.users SET password_hash = v_new WHERE id = v_id;
  UPDATE auth.users
     SET encrypted_password = v_new, updated_at = now()
   WHERE id = v_id;

  RETURN json_build_object('ok', true);
END;
$fn$;

-- ─────────────────────────────────────────────────────────────────────────
-- 5) ensure_table_setup — só ADM. As travas da Fase 0 continuam valendo.
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.ensure_table_setup(p_table text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
BEGIN
  IF NOT public.auth_is_adm() THEN
    RAISE EXCEPTION 'ensure_table_setup: apenas ADM' USING ERRCODE = '42501';
  END IF;

  IF p_table IS NULL OR p_table !~ '^[a-z][a-z0-9_]{0,62}$' THEN
    RAISE EXCEPTION 'ensure_table_setup: nome de tabela invalido' USING ERRCODE = '42501';
  END IF;

  IF p_table IN ('users','companies','app_secrets','platform_settings',
                 'master_users','sectors','sector_members','invoices',
                 'financial_transactions') THEN
    RAISE EXCEPTION 'ensure_table_setup: tabela protegida (%)', p_table USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.companies c
     WHERE c.history_table = p_table OR c.contacts_table = p_table
  ) THEN
    RAISE EXCEPTION 'ensure_table_setup: tabela nao registrada em companies (%)', p_table
      USING ERRCODE = '42501';
  END IF;

  EXECUTE format('alter table public.%I enable row level security', p_table);

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
     WHERE schemaname = 'public' AND tablename = p_table AND policyname = 'allow_read'
  ) THEN
    EXECUTE format('create policy allow_read on public.%I for select using (true)', p_table);
  END IF;

  BEGIN
    EXECUTE format('alter publication supabase_realtime add table public.%I', p_table);
  EXCEPTION WHEN others THEN NULL;
  END;

  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
     WHERE tgname = 'trg_reopen_session'
       AND tgrelid = (quote_ident(p_table))::regclass
  ) THEN
    EXECUTE format(
      'create trigger trg_reopen_session after insert on public.%I
       for each row execute function reopen_session_on_new_message()', p_table);
  END IF;
END;
$fn$;

-- ─────────────────────────────────────────────────────────────────────────
-- 6) mark_company_paid — só ADM (antes qualquer um dava baixa na mensalidade
--    e desbloqueava a própria clínica)
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.mark_company_paid(
  p_company_id uuid,
  p_amount numeric DEFAULT NULL,
  p_payment_method text DEFAULT NULL,
  p_notes text DEFAULT NULL)
RETURNS json
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE
  v_company record;
  v_amount  numeric;
  v_due     date;
  v_next    date;
BEGIN
  IF NOT public.auth_is_adm() THEN
    RETURN json_build_object('ok', false, 'error', 'Apenas o ADM pode dar baixa na mensalidade.');
  END IF;

  SELECT * INTO v_company FROM companies WHERE id = p_company_id;
  IF v_company IS NULL THEN
    RETURN json_build_object('ok', false, 'error', 'Empresa não encontrada');
  END IF;

  v_amount := COALESCE(p_amount, v_company.billing_amount);
  IF v_amount IS NULL OR v_amount <= 0 THEN
    RETURN json_build_object('ok', false, 'error', 'Valor da mensalidade não definido');
  END IF;

  v_due := COALESCE(
    v_company.next_due_date,
    date_trunc('month', CURRENT_DATE)::date + (COALESCE(v_company.billing_day, 5) - 1)
  );

  v_next := (v_due + INTERVAL '1 month')::date;

  INSERT INTO invoices (company_id, amount, due_date, paid_at, payment_method, notes)
  VALUES (p_company_id, v_amount, v_due, now(), p_payment_method, p_notes);

  UPDATE companies
     SET next_due_date = v_next,
         billing_blocked = false
   WHERE id = p_company_id;

  RETURN json_build_object('ok', true, 'next_due_date', v_next);
END;
$fn$;

-- ─────────────────────────────────────────────────────────────────────────
-- 7) claim_login_session — o crachá só pode ser pego pelo próprio dono.
--    Antes bastava saber um user_id (que é público) para tomar a sessão.
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.claim_login_session(
  p_user_id uuid, p_token text, p_ttl_seconds int DEFAULT 130)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE n int;
BEGIN
  IF auth.uid() IS NULL OR auth.uid() <> p_user_id THEN
    RETURN jsonb_build_object('ok', false);
  END IF;

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
$fn$;

CREATE OR REPLACE FUNCTION public.touch_login_session(p_user_id uuid, p_token text)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE cur text;
BEGIN
  IF auth.uid() IS NULL OR auth.uid() <> p_user_id THEN
    RETURN false;
  END IF;

  SELECT session_token INTO cur FROM public.users WHERE id = p_user_id;
  IF cur IS DISTINCT FROM p_token THEN
    RETURN false;
  END IF;
  UPDATE public.users SET session_seen_at = now() WHERE id = p_user_id;
  RETURN true;
END;
$fn$;

CREATE OR REPLACE FUNCTION public.release_login_session(p_user_id uuid, p_token text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
BEGIN
  IF auth.uid() IS NULL OR auth.uid() <> p_user_id THEN
    RETURN;
  END IF;

  UPDATE public.users
     SET session_token = NULL, session_seen_at = NULL
   WHERE id = p_user_id AND session_token = p_token;
END;
$fn$;

-- ─────────────────────────────────────────────────────────────────────────
-- 8) Fecha as portas para quem não está logado
--
--    Estas funções agora exigem identidade; deixar o GRANT para anon só
--    serviria para dar mensagem de erro a quem não deveria nem alcançá-las.
-- ─────────────────────────────────────────────────────────────────────────
REVOKE EXECUTE ON FUNCTION public.create_user(text, text, text, text, uuid)          FROM anon;
REVOKE EXECUTE ON FUNCTION public.update_user_password(uuid, text)                    FROM anon;
REVOKE EXECUTE ON FUNCTION public.delete_user(uuid)                                   FROM anon;
REVOKE EXECUTE ON FUNCTION public.ensure_table_setup(text)                            FROM anon;
REVOKE EXECUTE ON FUNCTION public.mark_company_paid(uuid, numeric, text, text)        FROM anon;
REVOKE EXECUTE ON FUNCTION public.change_own_password(text, text, text)               FROM anon;
REVOKE EXECUTE ON FUNCTION public.claim_login_session(uuid, text, int)                FROM anon;
REVOKE EXECUTE ON FUNCTION public.touch_login_session(uuid, text)                     FROM anon;
REVOKE EXECUTE ON FUNCTION public.release_login_session(uuid, text)                   FROM anon;

GRANT EXECUTE ON FUNCTION public.create_user(text, text, text, text, uuid)            TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_user_password(uuid, text)                      TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_user(uuid)                                     TO authenticated;
GRANT EXECUTE ON FUNCTION public.ensure_table_setup(text)                              TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_company_paid(uuid, numeric, text, text)          TO authenticated;
GRANT EXECUTE ON FUNCTION public.change_own_password(text, text, text)                 TO authenticated;
GRANT EXECUTE ON FUNCTION public.claim_login_session(uuid, text, int)                  TO authenticated;
GRANT EXECUTE ON FUNCTION public.touch_login_session(uuid, text)                       TO authenticated;
GRANT EXECUTE ON FUNCTION public.release_login_session(uuid, text)                     TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- 9) Aposenta a chave-mestra universal
--
--    A senha mestre abria QUALQUER conta, inclusive a do ADM. Com identidade
--    de verdade isso deixa de ser necessário: o ADM entra em qualquer clínica
--    por permissão (auth_is_adm), não por uma senha que abre tudo.
--
--    login_user volta a ser só e-mail + senha do próprio usuário. Ele ainda
--    existe porque a etapa 3 é quem remove o login antigo de vez.
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.login_user(p_email text, p_password text)
RETURNS TABLE(id uuid, name text, email text, role text, active boolean, company_id uuid)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'extensions'
AS $fn$
BEGIN
  RETURN QUERY
  SELECT u.id, u.name, u.email, u.role, u.active, u.company_id
    FROM public.users u
   WHERE u.email = lower(trim(p_email))
     AND u.active = true
     AND u.password_hash = crypt(p_password, u.password_hash);
END;
$fn$;

UPDATE public.platform_settings
   SET value = NULL, updated_at = now()
 WHERE key IN ('master_email', 'master_password_hash');

-- ─────────────────────────────────────────────────────────────────────────
-- 10) Conferência
-- ─────────────────────────────────────────────────────────────────────────
SELECT 'anon ainda executa create_user?' AS checagem,
       has_function_privilege('anon',
         'public.create_user(text,text,text,text,uuid)', 'EXECUTE') AS resultado
UNION ALL
SELECT 'anon ainda executa delete_user?',
       has_function_privilege('anon', 'public.delete_user(uuid)', 'EXECUTE')
UNION ALL
SELECT 'anon ainda executa ensure_table_setup?',
       has_function_privilege('anon', 'public.ensure_table_setup(text)', 'EXECUTE')
UNION ALL
SELECT 'senha mestre universal desligada?',
       (SELECT value IS NULL FROM public.platform_settings WHERE key = 'master_password_hash');
