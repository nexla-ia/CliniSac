-- ══════════════════════════════════════════════════════════════════════════
-- Migração para Supabase Auth — ETAPA 1 de 3: criar as identidades
--
-- O QUE ESTA ETAPA FAZ
--   Cria em auth.users uma identidade para cada usuário já existente em
--   public.users, reaproveitando o MESMO id e o MESMO hash de senha.
--   Como os dois lados usam bcrypt, as senhas atuais continuam valendo —
--   ninguém precisa redefinir nada.
--
-- O QUE ESTA ETAPA **NÃO** FAZ
--   Não mexe em policy, não mexe em função de login, não mexe no front.
--   Depois de rodar, o app continua entrando pelo login_user, igual a hoje.
--   Isso é de propósito: se algo der errado aqui, nada quebra.
--
-- COMO CONFERIR SE DEU CERTO
--   O SELECT no fim lista os usuários e se cada um ganhou identidade.
--   Toda linha deve mostrar auth_ok = true.
--
-- Idempotente: pode rodar mais de uma vez.
-- ══════════════════════════════════════════════════════════════════════════

SET search_path TO public, extensions;

-- ─────────────────────────────────────────────────────────────────────────
-- 1) Identidades em auth.users
--
--    Reusa public.users.id como auth.users.id — assim o perfil e a
--    identidade são a mesma chave, e auth.uid() já aponta direto para o
--    perfil, sem tabela de ligação.
--
--    email_confirmed_at vem preenchido: são contas criadas pelo ADM, não
--    auto-cadastro, então não faz sentido pedir confirmação por e-mail.
-- ─────────────────────────────────────────────────────────────────────────
INSERT INTO auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  created_at,
  updated_at,
  raw_app_meta_data,
  raw_user_meta_data,
  is_super_admin,
  confirmation_token,
  recovery_token,
  email_change_token_new,
  email_change
)
SELECT
  '00000000-0000-0000-0000-000000000000',
  u.id,
  'authenticated',
  'authenticated',
  lower(trim(u.email)),
  u.password_hash,           -- bcrypt dos dois lados: a senha atual continua valendo
  now(),
  COALESCE(u.created_at, now()),
  now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  jsonb_build_object('name', u.name),
  false,
  '', '', '', ''
FROM public.users u
WHERE u.password_hash IS NOT NULL
ON CONFLICT (id) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────
-- 2) Linhas em auth.identities
--
--    O GoTrue moderno exige uma identity do provider 'email' para aceitar
--    signInWithPassword. Sem isso o usuário existe mas não consegue logar.
-- ─────────────────────────────────────────────────────────────────────────
INSERT INTO auth.identities (
  provider_id,
  user_id,
  identity_data,
  provider,
  last_sign_in_at,
  created_at,
  updated_at
)
SELECT
  au.id::text,
  au.id,
  jsonb_build_object('sub', au.id::text, 'email', au.email, 'email_verified', true),
  'email',
  NULL,
  now(),
  now()
FROM auth.users au
WHERE EXISTS (SELECT 1 FROM public.users pu WHERE pu.id = au.id)
  AND NOT EXISTS (
    SELECT 1 FROM auth.identities ai
     WHERE ai.user_id = au.id AND ai.provider = 'email'
  );

-- ─────────────────────────────────────────────────────────────────────────
-- 3) Helpers de identidade
--
--    São a base das policies da etapa 3. SECURITY DEFINER de propósito:
--    rodando como dono, eles não passam por RLS, o que evita recursão
--    infinita quando uma policy de public.users precisar consultar
--    public.users.
--
--    STABLE: o Postgres avalia uma vez por statement em vez de por linha.
--    Numa policy isso é a diferença entre uma consulta e milhares.
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.auth_profile()
RETURNS public.users
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $fn$
  SELECT u.* FROM public.users u WHERE u.id = auth.uid() AND u.active = true;
$fn$;

CREATE OR REPLACE FUNCTION public.auth_role()
RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $fn$
  SELECT u.role FROM public.users u WHERE u.id = auth.uid() AND u.active = true;
$fn$;

CREATE OR REPLACE FUNCTION public.auth_company_id()
RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $fn$
  SELECT u.company_id FROM public.users u WHERE u.id = auth.uid() AND u.active = true;
$fn$;

-- ADM global: enxerga todas as clínicas. É o que substitui a senha mestre
-- universal — permissão ligada a uma identidade, não uma senha que abre tudo.
CREATE OR REPLACE FUNCTION public.auth_is_adm()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $fn$
  SELECT COALESCE(
    (SELECT u.role = 'adm' FROM public.users u
      WHERE u.id = auth.uid() AND u.active = true),
    false);
$fn$;

-- Acesso à clínica: ou é o ADM, ou é usuário daquela clínica.
CREATE OR REPLACE FUNCTION public.auth_can_access_company(p_company_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $fn$
  SELECT public.auth_is_adm()
      OR (p_company_id IS NOT NULL AND p_company_id = public.auth_company_id());
$fn$;

GRANT EXECUTE ON FUNCTION public.auth_role()                      TO authenticated;
GRANT EXECUTE ON FUNCTION public.auth_company_id()                TO authenticated;
GRANT EXECUTE ON FUNCTION public.auth_is_adm()                    TO authenticated;
GRANT EXECUTE ON FUNCTION public.auth_can_access_company(uuid)    TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- 4) Conferência — toda linha deve sair com auth_ok = true
-- ─────────────────────────────────────────────────────────────────────────
SELECT
  u.email,
  u.role,
  (au.id IS NOT NULL)                                   AS auth_ok,
  (ai.user_id IS NOT NULL)                              AS identity_ok,
  (au.encrypted_password = u.password_hash)             AS senha_preservada
FROM public.users u
LEFT JOIN auth.users au ON au.id = u.id
LEFT JOIN auth.identities ai ON ai.user_id = u.id AND ai.provider = 'email'
ORDER BY u.role, u.email;
