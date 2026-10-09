-- ══════════════════════════════════════════════════════════════════════════
-- CORREÇÃO CRÍTICA — 20260831_security_hardening_fase0.sql desfazia todo o
-- endurecimento de segurança feito nas etapas 1-5 do mesmo dia
--
-- CAUSA RAIZ
--   Supabase aplica supabase/migrations/*.sql em ordem alfabética de nome de
--   arquivo. "security_hardening_fase0.sql" ordena DEPOIS de todos os
--   "auth_etapaN_*.sql" (a letra 's' vem depois de 'a'), mesmo com o mesmo
--   prefixo de data (20260831) e a intenção de rodar ANTES (o nome diz
--   "Fase 0"). Resultado: o CREATE OR REPLACE FUNCTION da fase0 rodava por
--   último e reescrevia de volta as versões SEM as checagens de autorização
--   que as etapas 2, 3a e 4 adicionaram depois.
--
-- O QUE ISSO ABRIA (achado numa auditoria de segurança pedida pelo usuário)
--   • ensure_table_setup: a versão da fase0 não tem `auth_is_adm()` e cria
--     a policy antiga `allow_read using (true)` em vez de `tenant_rw`
--     (etapa3a). Qualquer usuário AUTENTICADO (de qualquer clínica) podia
--     chamar essa função pra reabrir leitura pública numa tabela de
--     histórico de conversa de QUALQUER empresa cadastrada.
--   • create_user / update_user_password / delete_user: a versão da fase0
--     não chama `auth_can_manage_users()` (adicionado na etapa2) — qualquer
--     usuário autenticado podia criar/apagar/resetar senha de usuário de
--     QUALQUER clínica, não só a própria.
--   • change_own_password: além de reverter pra uma versão sem
--     `auth.uid()` (não confere a sessão real) e com um bypass de "senha
--     mestre", a fase0 ainda dá
--     `GRANT EXECUTE ... TO anon, authenticated` — reabrindo a função pra
--     quem nem logou, só com a anon key pública (que vai no bundle do
--     site). A etapa4 já tinha revogado tudo de anon por padrão; essa
--     linha da fase0, por rodar depois, desfazia isso especificamente
--     pra essa função.
--
-- A CORREÇÃO
--   Em vez de apagar/reordenar a migration antiga (mexeria no histórico já
--   aplicado), esta migration — que ordena depois de tudo por causa da
--   data — reaplica as versões corretas (as mesmas de etapa2/etapa3a) por
--   cima, e revoga explicitamente o GRANT a anon que a fase0 tinha
--   adicionado. Resultado final idêntico ao que as etapas 1-5 pretendiam.
--
-- Idempotente: pode rodar mais de uma vez.
-- ══════════════════════════════════════════════════════════════════════════

SET search_path TO public, extensions;

-- ─────────────────────────────────────────────────────────────────────────
-- 1) create_user — volta a exigir auth_can_manage_users() e a criar a
--    identidade em auth.users/auth.identities (sem isso o usuário novo
--    fica sem conseguir logar, já que o login passa pelo GoTrue).
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
-- 2) update_user_password — exige auth_can_manage_users() e sincroniza
--    auth.users (senão a pessoa não loga com a senha nova).
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
-- 3) delete_user — exige auth_can_manage_users() e remove dos dois lados.
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
-- 4) change_own_password — volta a exigir auth.uid() (sessão real do
--    Supabase Auth) em vez de confiar em p_email+senha soltos, e tira o
--    bypass de "senha mestre" que a fase0 tinha.
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

-- A fase0 tinha dado GRANT ... TO anon nessa função especificamente — tira
-- de volta (CREATE OR REPLACE acima não desfaz grant já concedido antes).
REVOKE EXECUTE ON FUNCTION public.change_own_password(text, text, text) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.change_own_password(text, text, text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- 5) ensure_table_setup — volta a exigir auth_is_adm() e a criar a policy
--    tenant_rw (escopada por instancia) em vez de allow_read using(true).
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.ensure_table_setup(p_table text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE
  tem_instancia boolean;
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

  -- Tira qualquer policy permissiva herdada (inclusive a allow_read que a
  -- versão da fase0 recriava).
  EXECUTE format('drop policy if exists allow_read on public.%I', p_table);
  EXECUTE format('drop policy if exists tenant_rw on public.%I', p_table);

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = p_table
       AND column_name = 'instancia'
  ) INTO tem_instancia;

  IF tem_instancia THEN
    EXECUTE format(
      'create policy tenant_rw on public.%I for all to authenticated
         using (public.auth_can_access_instancia(instancia))
         with check (public.auth_can_access_instancia(instancia))', p_table);
  ELSE
    -- Sem instância não dá para dizer de quem é a linha: só ADM.
    EXECUTE format(
      'create policy tenant_rw on public.%I for all to authenticated
         using (public.auth_is_adm()) with check (public.auth_is_adm())', p_table);
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
-- 6) Qualquer tabela que já tenha sido reaberta com allow_read using(true)
--    por alguém explorando o buraco antes desta correção: troca pela
--    policy certa agora, chamando ensure_table_setup (já corrigida acima)
--    pra cada tabela de histórico/contatos registrada em companies.
-- ─────────────────────────────────────────────────────────────────────────
DO $fix$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT DISTINCT t FROM (
      SELECT history_table AS t FROM public.companies WHERE history_table IS NOT NULL
      UNION
      SELECT contacts_table AS t FROM public.companies WHERE contacts_table IS NOT NULL
    ) x WHERE t IS NOT NULL
  LOOP
    BEGIN
      PERFORM public.ensure_table_setup(r.t);
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'ensure_table_setup falhou pra %: %', r.t, SQLERRM;
    END;
  END LOOP;
END;
$fix$;

-- ─────────────────────────────────────────────────────────────────────────
-- 7) Conferência — não deve sobrar allow_read em nenhuma tabela nem anon
--    com EXECUTE nas 5 funções.
-- ─────────────────────────────────────────────────────────────────────────
SELECT 'tabelas com policy allow_read sobrando' AS checagem,
       COALESCE(string_agg(DISTINCT tablename, ', '), 'nenhuma') AS resultado
  FROM pg_policies
 WHERE schemaname = 'public' AND policyname = 'allow_read';

SELECT 'funcoes ainda executaveis por anon' AS checagem,
       COALESCE(string_agg(DISTINCT p.proname, ', '), 'nenhuma') AS resultado
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('create_user','update_user_password','delete_user',
                      'change_own_password','ensure_table_setup')
   AND has_function_privilege('anon', p.oid, 'EXECUTE');
