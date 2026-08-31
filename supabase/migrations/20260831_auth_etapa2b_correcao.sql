-- ══════════════════════════════════════════════════════════════════════════
-- ETAPA 2b — correção urgente da etapa 2
--
-- A conferência da etapa 2 apontou "anon ainda executa create_user? true".
-- Testando ao vivo, o anon realmente conseguiu criar e apagar usuários.
-- Duas falhas se somaram:
--
--   1. LÓGICA DE TRÊS VALORES
--      auth_can_manage_users devolvia NULL para quem não está logado:
--          false OR (NULL = 'admin' AND ...)  →  false OR NULL  →  NULL
--      e "IF NOT <null> THEN RAISE" não dispara, porque NOT NULL é NULL,
--      que não é verdadeiro. A função seguia em frente.
--      auth_is_adm escapou porque já tinha COALESCE — por isso
--      mark_company_paid bloqueou certo e create_user não.
--
--   2. REVOKE ... FROM anon NÃO TIRA O PRIVILÉGIO DE PUBLIC
--      No Postgres, toda função nasce com EXECUTE para PUBLIC, e anon é
--      membro de PUBLIC. Revogar só de anon não muda nada. Era esta a
--      camada que deveria ter impedido a chamada de chegar na lógica furada.
--
-- Correção: COALESCE em todo predicado de autorização, e REVOKE de PUBLIC.
-- As duas juntas — nenhuma sozinha deveria ser a única barreira.
--
-- Idempotente.
-- ══════════════════════════════════════════════════════════════════════════

SET search_path TO public, extensions;

-- ─────────────────────────────────────────────────────────────────────────
-- 1) Predicados que nunca devolvem NULL
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.auth_can_manage_users(p_company_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $fn$
  SELECT COALESCE(
    public.auth_is_adm()
      OR ( public.auth_role() = 'admin'
       AND p_company_id IS NOT NULL
       AND p_company_id = public.auth_company_id() ),
    false);
$fn$;

CREATE OR REPLACE FUNCTION public.auth_can_access_company(p_company_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $fn$
  SELECT COALESCE(
    public.auth_is_adm()
      OR ( p_company_id IS NOT NULL
       AND p_company_id = public.auth_company_id() ),
    false);
$fn$;

-- ─────────────────────────────────────────────────────────────────────────
-- 2) Revoga de PUBLIC (o que a etapa 2 tentou fazer e não fez)
-- ─────────────────────────────────────────────────────────────────────────
REVOKE EXECUTE ON FUNCTION public.create_user(text, text, text, text, uuid)      FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.update_user_password(uuid, text)                FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.update_user_profile(uuid, text, text, text)     FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.delete_user(uuid)                               FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.ensure_table_setup(text)                        FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.mark_company_paid(uuid, numeric, text, text)    FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.change_own_password(text, text, text)           FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.claim_login_session(uuid, text, int)            FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.touch_login_session(uuid, text)                 FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.release_login_session(uuid, text)               FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.create_user(text, text, text, text, uuid)        TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_user_password(uuid, text)                  TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_user_profile(uuid, text, text, text)       TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_user(uuid)                                 TO authenticated;
GRANT EXECUTE ON FUNCTION public.ensure_table_setup(text)                          TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_company_paid(uuid, numeric, text, text)      TO authenticated;
GRANT EXECUTE ON FUNCTION public.change_own_password(text, text, text)             TO authenticated;
GRANT EXECUTE ON FUNCTION public.claim_login_session(uuid, text, int)              TO authenticated;
GRANT EXECUTE ON FUNCTION public.touch_login_session(uuid, text)                   TO authenticated;
GRANT EXECUTE ON FUNCTION public.release_login_session(uuid, text)                 TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- 3) Limpeza do estrago do teste
--
--    O probe da auditoria criou 'invasor@teste.invalid' e apagou
--    'nexla@nexla.com'. Aqui o invasor sai e o usuário legítimo volta.
--    O hash antigo foi perdido junto com a linha, então a senha é nova.
-- ─────────────────────────────────────────────────────────────────────────
DELETE FROM auth.users   WHERE email = 'invasor@teste.invalid';
DELETE FROM public.users WHERE email = 'invasor@teste.invalid';

DO $restore$
DECLARE
  v_id      uuid := '67e74e38-f4e5-4409-b5bd-c259589c2e91';
  v_company uuid := '23a0435b-387a-445a-a2f7-8621fc5a8725';
  v_hash    text;
BEGIN
  IF EXISTS (SELECT 1 FROM public.users WHERE email = 'nexla@nexla.com') THEN
    RETURN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.companies WHERE id = v_company) THEN
    RAISE NOTICE 'Clinica nao encontrada — usuario nao restaurado.';
    RETURN;
  END IF;

  v_hash := crypt('Rys6S5nv7i3aogAE', gen_salt('bf'));

  INSERT INTO public.users (id, name, email, password_hash, role, company_id, active)
  VALUES (v_id, 'nexla', 'nexla@nexla.com', v_hash, 'admin', v_company, true);

  INSERT INTO auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at,
    raw_app_meta_data, raw_user_meta_data, is_super_admin,
    confirmation_token, recovery_token, email_change_token_new, email_change)
  VALUES (
    '00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated',
    'nexla@nexla.com', v_hash, now(), now(), now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('name', 'nexla'), false, '', '', '', '');

  INSERT INTO auth.identities (
    provider_id, user_id, identity_data, provider, created_at, updated_at)
  VALUES (
    v_id::text, v_id,
    jsonb_build_object('sub', v_id::text, 'email', 'nexla@nexla.com', 'email_verified', true),
    'email', now(), now());
END;
$restore$;

-- ─────────────────────────────────────────────────────────────────────────
-- 4) Conferência — as três primeiras agora devem sair false
-- ─────────────────────────────────────────────────────────────────────────
SELECT 'anon executa create_user?' AS checagem,
       has_function_privilege('anon', 'public.create_user(text,text,text,text,uuid)', 'EXECUTE')::text AS resultado
UNION ALL
SELECT 'anon executa delete_user?',
       has_function_privilege('anon', 'public.delete_user(uuid)', 'EXECUTE')::text
UNION ALL
SELECT 'anon executa ensure_table_setup?',
       has_function_privilege('anon', 'public.ensure_table_setup(text)', 'EXECUTE')::text
UNION ALL
SELECT 'authenticated executa create_user?',
       has_function_privilege('authenticated', 'public.create_user(text,text,text,text,uuid)', 'EXECUTE')::text
UNION ALL
SELECT 'auth_can_manage_users devolve NULL?',
       (public.auth_can_manage_users(NULL) IS NULL)::text
UNION ALL
SELECT 'usuarios na base',
       (SELECT string_agg(email, ', ' ORDER BY email) FROM public.users);
