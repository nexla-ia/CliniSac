-- ══════════════════════════════════════════════════════════════════════════
-- ETAPA 3b — RLS em identidade, legado e limpeza final
--
-- A 3a fechou os dados clínicos. Faltam as tabelas de identidade (users,
-- companies), o lixo do banco antigo e as portas que ninguém usa mais.
--
-- ⚠ ESTA É A ÚNICA ETAPA QUE PODE DERRUBAR O LOGIN
--   As policies de `users` e `companies` são consultadas durante o login.
--   Elas se apoiam nos helpers auth_* que são SECURITY DEFINER — e por isso
--   não passam por RLS ao consultar `users`, o que evitaria recursão. Se
--   ainda assim o login quebrar, reverta SÓ estas duas com:
--
--     drop policy if exists tenant_rw on public.users;
--     create policy tenant_rw on public.users for all using (true) with check (true);
--     drop policy if exists tenant_rw on public.companies;
--     create policy tenant_rw on public.companies for all using (true) with check (true);
--
--   Isso devolve o login sem desfazer a 3a (os dados clínicos seguem isolados).
--
-- Idempotente.
-- ══════════════════════════════════════════════════════════════════════════

SET search_path TO public, extensions;

-- ─────────────────────────────────────────────────────────────────────────
-- 1) users — cada um enxerga a si mesmo e os colegas da própria clínica
--
--    O "id = auth.uid()" é o que sustenta o login: no primeiro instante o
--    app precisa ler o próprio perfil para descobrir papel e clínica, e
--    nesse momento ele ainda não sabe de qual clínica é.
--
--    Escrita não inclui a si mesmo de propósito: trocar o próprio papel ou
--    a própria clínica seria escalar privilégio. Isso passa pelas RPCs.
-- ─────────────────────────────────────────────────────────────────────────
DO $u$
DECLARE pol record;
BEGIN
  FOR pol IN SELECT policyname FROM pg_policies
              WHERE schemaname='public' AND tablename='users'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.users', pol.policyname);
  END LOOP;
END;
$u$;

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_read ON public.users FOR SELECT TO authenticated
  USING ( id = auth.uid()
       OR public.auth_is_adm()
       OR ( company_id IS NOT NULL AND company_id = public.auth_company_id() ) );

CREATE POLICY tenant_write ON public.users FOR UPDATE TO authenticated
  USING ( id = auth.uid()
       OR public.auth_can_manage_users(company_id) )
  WITH CHECK ( id = auth.uid()
       OR public.auth_can_manage_users(company_id) );

-- ─────────────────────────────────────────────────────────────────────────
-- 2) companies — a própria clínica; o ADM vê todas (é o que faz o seletor
--    de clínicas funcionar sem senha mestre)
-- ─────────────────────────────────────────────────────────────────────────
DO $c$
DECLARE pol record;
BEGIN
  FOR pol IN SELECT policyname FROM pg_policies
              WHERE schemaname='public' AND tablename='companies'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.companies', pol.policyname);
  END LOOP;
END;
$c$;

ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_read ON public.companies FOR SELECT TO authenticated
  USING ( public.auth_is_adm() OR id = public.auth_company_id() );

-- Só o ADM mexe em cadastro de clínica: era por aqui que dava para reescrever
-- evolution_url e billing_blocked de qualquer empresa.
CREATE POLICY adm_write ON public.companies FOR ALL TO authenticated
  USING (public.auth_is_adm()) WITH CHECK (public.auth_is_adm());

-- ─────────────────────────────────────────────────────────────────────────
-- 3) landing_analytics — caso especial
--
--    Quem grava aqui é o visitante anônimo da landing page, então o INSERT
--    precisa continuar aberto. O que não pode é qualquer um LER as métricas.
-- ─────────────────────────────────────────────────────────────────────────
DO $la$
DECLARE pol record;
BEGIN
  IF to_regclass('public.landing_analytics') IS NULL THEN RETURN; END IF;
  FOR pol IN SELECT policyname FROM pg_policies
              WHERE schemaname='public' AND tablename='landing_analytics'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.landing_analytics', pol.policyname);
  END LOOP;

  EXECUTE 'ALTER TABLE public.landing_analytics ENABLE ROW LEVEL SECURITY';
  EXECUTE 'CREATE POLICY visitante_insere ON public.landing_analytics
             FOR INSERT TO anon, authenticated WITH CHECK (true)';
  EXECUTE 'CREATE POLICY visitante_atualiza ON public.landing_analytics
             FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true)';
  EXECUTE 'CREATE POLICY adm_le ON public.landing_analytics
             FOR SELECT TO authenticated USING (public.auth_is_adm())';
END;
$la$;

-- ─────────────────────────────────────────────────────────────────────────
-- 4) Legado do banco antigo — fecha para ADM
--
--    Tabelas herdadas da plataforma anterior, sem chave de clínica e sem uso
--    no CliniSac. Não dá para dizer de quem é cada linha, então ficam só com
--    o ADM até alguém decidir se elas ainda servem para alguma coisa.
-- ─────────────────────────────────────────────────────────────────────────
DO $leg$
DECLARE
  t   text;
  pol record;
  legado text[] := ARRAY[
    'mensagens','nexla_historico','master_users',
    'n8n_chat_histories_barbara','n8n_chat_histories_gastroimagem',
    'b2b-controleCliente','b2b-controlecliente','pagou_NexlaDaily'
  ];
BEGIN
  FOREACH t IN ARRAY legado LOOP
    IF to_regclass(format('public.%I', t)) IS NULL THEN CONTINUE; END IF;

    FOR pol IN SELECT policyname FROM pg_policies
                WHERE schemaname='public' AND tablename = t
    LOOP
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, t);
    END LOOP;

    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format(
      'CREATE POLICY adm_only ON public.%I FOR ALL TO authenticated
         USING (public.auth_is_adm()) WITH CHECK (public.auth_is_adm())', t);
  END LOOP;
END;
$leg$;

-- ─────────────────────────────────────────────────────────────────────────
-- 5) Fecha as portas que o app não usa mais
--
--    login_user e master_list_companies eram o login antigo. O front agora
--    entra pelo Supabase Auth. Deixar login_user aberto ao anon manteria um
--    alvo de força bruta que devolve dados do usuário quando acerta.
--
--    Revoke em vez de DROP: reversível se alguma integração ainda usar.
-- ─────────────────────────────────────────────────────────────────────────
REVOKE EXECUTE ON FUNCTION public.login_user(text, text)              FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.master_list_companies(text, text)   FROM PUBLIC, anon;

-- ─────────────────────────────────────────────────────────────────────────
-- 6) Limpa o canário do teste de isolamento
-- ─────────────────────────────────────────────────────────────────────────
DELETE FROM public.mensagens_geral WHERE instancia = 'OUTRACLINICA';

-- ─────────────────────────────────────────────────────────────────────────
-- 7) Conferência
-- ─────────────────────────────────────────────────────────────────────────
SELECT 'tabelas em public SEM RLS' AS checagem,
       COALESCE(string_agg(c.relname, ', ' ORDER BY c.relname), 'nenhuma') AS resultado
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public' AND c.relkind = 'r' AND NOT c.relrowsecurity

UNION ALL
SELECT 'tabelas com policy permissiva (using true)',
       COALESCE(string_agg(DISTINCT tablename, ', '), 'nenhuma')
  FROM pg_policies
 WHERE schemaname = 'public' AND qual = 'true'
   AND tablename <> 'landing_analytics'

UNION ALL
SELECT 'anon ainda executa login_user?',
       has_function_privilege('anon', 'public.login_user(text,text)', 'EXECUTE')::text

UNION ALL
SELECT 'canario do teste removido?',
       (NOT EXISTS (SELECT 1 FROM public.mensagens_geral WHERE instancia = 'OUTRACLINICA'))::text;
