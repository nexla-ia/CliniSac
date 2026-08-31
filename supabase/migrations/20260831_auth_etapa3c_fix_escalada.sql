-- ══════════════════════════════════════════════════════════════════════════
-- ETAPA 3c — CORREÇÃO URGENTE: escalada de privilégio via UPDATE em users
--
-- O QUE ACONTECEU
--   A policy tenant_write da 3b permitia "id = auth.uid()" no WITH CHECK.
--   Combinada com o GRANT de coluna que já existia (authenticated podia
--   escrever em role, email e active), isso deixava QUALQUER usuário logado
--   gravar role='adm' na própria linha e virar administrador da plataforma.
--
--   Verificado ao vivo: o usuário da clínica virou ADM com um PATCH.
--
--   A policy dizia no comentário que não permitia isso. O comentário
--   descrevia a intenção; o código fazia o contrário.
--
-- POR QUE A POLICY SOZINHA NÃO RESOLVE
--   RLS decide QUAIS LINHAS, não QUAIS COLUNAS. Enquanto `role` estiver no
--   GRANT de UPDATE para authenticated, qualquer policy que deixe a pessoa
--   escrever na própria linha deixa ela escolher o próprio papel.
--   A trava certa é o GRANT de coluna.
--
-- Idempotente.
-- ══════════════════════════════════════════════════════════════════════════

SET search_path TO public, extensions;

-- ─────────────────────────────────────────────────────────────────────────
-- 1) Desfaz a escalada que o teste provocou
-- ─────────────────────────────────────────────────────────────────────────
UPDATE public.users
   SET role = 'admin'
 WHERE email = 'nexla@nexla.com' AND role = 'adm';

-- ─────────────────────────────────────────────────────────────────────────
-- 2) A trava de verdade: authenticated perde a escrita em role/email/active
--
--    Sobram só as colunas que o app precisa gravar direto:
--      name             — edição do próprio nome
--      session_token    — crachá de sessão única
--      session_seen_at
--
--    role, email e active passam a ser exclusividade das RPCs, que checam
--    quem está chamando (update_user_profile, set_user_active).
-- ─────────────────────────────────────────────────────────────────────────
REVOKE UPDATE ON public.users FROM anon, authenticated;
GRANT  UPDATE (name, session_token, session_seen_at)
  ON public.users TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- 3) set_user_active — ativar/desativar usuário, com autorização
--
--    Antes era UPDATE direto na tabela. Agora passa por aqui, que confere
--    permissão, protege a conta ADM e impede alguém de se autodesativar
--    (o que trancaria a pessoa para fora sem ninguém para reverter).
--
--    Desativar também bloqueia a emissão de novo token no Auth: sem isso a
--    pessoa continuaria conseguindo um JWT válido depois de desativada.
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.set_user_active(p_user_id uuid, p_active boolean)
RETURNS json
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE
  v_role    text;
  v_company uuid;
BEGIN
  SELECT role, company_id INTO v_role, v_company
    FROM public.users WHERE id = p_user_id;

  IF v_role IS NULL THEN
    RETURN json_build_object('ok', false, 'error', 'Usuário não encontrado');
  END IF;

  IF v_role = 'adm' THEN
    RETURN json_build_object('ok', false, 'error', 'Conta ADM não pode ser desativada por aqui.');
  END IF;

  IF NOT public.auth_can_manage_users(v_company) THEN
    RETURN json_build_object('ok', false, 'error', 'Sem permissão para alterar este usuário.');
  END IF;

  IF p_user_id = auth.uid() THEN
    RETURN json_build_object('ok', false, 'error', 'Você não pode desativar a própria conta.');
  END IF;

  UPDATE public.users SET active = p_active WHERE id = p_user_id;

  -- Espelha no Auth: conta desativada não emite token novo.
  BEGIN
    IF p_active THEN
      UPDATE auth.users SET banned_until = NULL WHERE id = p_user_id;
    ELSE
      UPDATE auth.users SET banned_until = now() + interval '100 years' WHERE id = p_user_id;
    END IF;
  EXCEPTION WHEN undefined_column THEN NULL;
  END;

  RETURN json_build_object('ok', true);
END;
$fn$;

REVOKE EXECUTE ON FUNCTION public.set_user_active(uuid, boolean) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.set_user_active(uuid, boolean) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- 4) Mesma trava em companies
--
--    A policy adm_write já limita a escrita ao ADM, mas o GRANT de coluna
--    continuava aberto. Duas camadas, como na lição da etapa 2b.
-- ─────────────────────────────────────────────────────────────────────────
REVOKE INSERT, UPDATE, DELETE ON public.companies FROM anon, authenticated;
GRANT  INSERT, UPDATE ON public.companies TO authenticated;  -- a policy adm_write filtra

-- ─────────────────────────────────────────────────────────────────────────
-- 5) Conferência
-- ─────────────────────────────────────────────────────────────────────────
SELECT 'authenticated escreve em users.role?' AS checagem,
       has_column_privilege('authenticated', 'public.users', 'role', 'UPDATE')::text AS resultado
UNION ALL
SELECT 'authenticated escreve em users.active?',
       has_column_privilege('authenticated', 'public.users', 'active', 'UPDATE')::text
UNION ALL
SELECT 'authenticated escreve em users.email?',
       has_column_privilege('authenticated', 'public.users', 'email', 'UPDATE')::text
UNION ALL
SELECT 'authenticated escreve em users.name? (deve ser true)',
       has_column_privilege('authenticated', 'public.users', 'name', 'UPDATE')::text
UNION ALL
SELECT 'authenticated escreve session_token? (deve ser true)',
       has_column_privilege('authenticated', 'public.users', 'session_token', 'UPDATE')::text
UNION ALL
SELECT 'papel do usuario da clinica',
       (SELECT role FROM public.users WHERE email = 'nexla@nexla.com');
