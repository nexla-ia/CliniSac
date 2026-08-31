-- ══════════════════════════════════════════════════════════════════════════
-- ETAPA 5 — auto-cadastro e limpeza do pentest
--
-- A terceira passada da auditoria (pentest da camada de Auth) encontrou:
--
--   AUTO-CADASTRO ABERTO. O endpoint /auth/v1/signup aceitava qualquer um
--   criando conta. Exige confirmação de e-mail, então o auto-cadastrado NÃO
--   loga sem confirmar — o risco de acesso a dado é baixo. Mas:
--     • é um vetor de abuso: dá para inundar o projeto de contas e disparar
--       e-mails de confirmação em massa (o Supabase pode ratelimitar seu
--       envio ou marcar o domínio);
--     • é superfície desnecessária: no CliniSac quem cria usuário é o ADM,
--       pela RPC create_user. Ninguém se auto-cadastra.
--
-- ⚠ DESLIGAR O SIGNUP É NO PAINEL, não em SQL:
--     Supabase → Authentication → Sign In / Providers → Email
--       → desmarque "Allow new users to sign up"
--   Isso NÃO quebra a criação de usuário pelo ADM: o create_user insere
--   direto em auth.users, não passa pelo signup.
--
-- Esta migration só faz a limpeza que depende do banco.
-- Idempotente.
-- ══════════════════════════════════════════════════════════════════════════

SET search_path TO public, extensions;

-- ─────────────────────────────────────────────────────────────────────────
-- 1) Remove a conta que o pentest criou sondando o signup
--
--    invasor.pentest@mailinator.com nunca confirmou o e-mail e não tem
--    perfil em public.users. Sai limpo.
-- ─────────────────────────────────────────────────────────────────────────
DELETE FROM auth.identities WHERE identity_data->>'email' = 'invasor.pentest@mailinator.com';
DELETE FROM auth.users      WHERE email = 'invasor.pentest@mailinator.com';

-- ─────────────────────────────────────────────────────────────────────────
-- 2) Rede de segurança: qualquer auth.users sem perfil em public.users e
--    sem e-mail confirmado é conta de auto-cadastro que ficou pendente.
--    Remove as pendências (não toca em ninguém confirmado nem com perfil).
--
--    Não mexe na conta ADM nem em usuários de clínica: todos têm perfil.
-- ─────────────────────────────────────────────────────────────────────────
DELETE FROM auth.identities ai
 WHERE ai.provider = 'email'
   AND NOT EXISTS (SELECT 1 FROM public.users u WHERE u.id = ai.user_id)
   AND EXISTS (
     SELECT 1 FROM auth.users au
      WHERE au.id = ai.user_id AND au.email_confirmed_at IS NULL);

DELETE FROM auth.users au
 WHERE NOT EXISTS (SELECT 1 FROM public.users u WHERE u.id = au.id)
   AND au.email_confirmed_at IS NULL;

-- ─────────────────────────────────────────────────────────────────────────
-- 3) Conferência
-- ─────────────────────────────────────────────────────────────────────────
SELECT 'contas de auth sem perfil e nao confirmadas' AS checagem,
       count(*)::text AS resultado
  FROM auth.users au
 WHERE NOT EXISTS (SELECT 1 FROM public.users u WHERE u.id = au.id)
   AND au.email_confirmed_at IS NULL

UNION ALL
SELECT 'total de identidades (deve bater com nº de usuarios reais)',
       count(*)::text FROM auth.users

UNION ALL
SELECT 'usuarios reais (public.users)',
       count(*)::text FROM public.users;
