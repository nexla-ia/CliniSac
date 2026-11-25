-- ============================================================================
-- Segurança: funções novas abertas ao visitante + cron_error_log sem RLS
-- ----------------------------------------------------------------------------
-- Achados da auditoria de 25/11/2026 (testes feitos como visitante, sem login):
--
-- 1) A etapa4 (20260831_auth_etapa4_fecha_api_rpc) fechou TODAS as funções do
--    schema public pro anon. Mas no Supabase toda função CRIADA DEPOIS nasce
--    executável pelo anon (default privileges). Ficaram abertas, sem revoke:
--      process_appointment_followups, process_monthly_review_requests,
--      process_procedure_recall  (SECURITY DEFINER — disparam lembrete/NPS/recall)
--      fin_categoria_for_proc, fin_categoria_especifica, crm_norm_phone
--    Qualquer pessoa com a chave pública do site conseguia chamar as três
--    primeiras e forçar o processamento dos envios fora do cron.
--
-- 2) cron_error_log foi criada sem RLS: o visitante conseguia gravar/apagar.
--
-- Esta migration:
--   a) repete o "nega por padrão" da etapa4 (anon e PUBLIC sem EXECUTE em
--      nenhuma função do public; process_* só pro service_role);
--   b) muda o padrão do projeto: função/tabela criada daqui pra frente NÃO
--      nasce aberta pro anon (quem precisar recebe GRANT explícito);
--   c) liga a RLS na cron_error_log e tira o acesso do anon/authenticated.
--
-- Não muda nada do que o app logado usa (as funções chamadas pelo front
-- continuam com GRANT pro authenticated, dado na etapa4).
-- Idempotente.
-- ============================================================================

SET search_path TO public, extensions;

-- a) Nenhuma função do public executável por visitante ---------------------
DO $deny$
DECLARE f record;
BEGIN
  FOR f IN
    SELECT p.oid::regprocedure AS sig, p.proname
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.prokind = 'f'
       AND p.prorettype <> 'trigger'::regtype
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon', f.sig);
    EXECUTE format('GRANT  EXECUTE ON FUNCTION %s TO service_role', f.sig);
  END LOOP;
END;
$deny$;

-- Rotinas do cron: só o servidor roda (nem usuário logado).
DO $cron$
DECLARE f record;
BEGIN
  FOR f IN
    SELECT p.oid::regprocedure AS sig
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.prokind = 'f'
       AND p.proname IN ('process_appointment_reminders', 'process_appointment_followups',
                         'process_monthly_review_requests', 'process_procedure_recall',
                         'auto_close_inactive_conversations', 'n8n_clear_mensagens')
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM authenticated', f.sig);
  END LOOP;
END;
$cron$;

-- Funções auxiliares puras usadas por gatilhos/sincronizações do app logado.
DO $helpers$
DECLARE f record;
BEGIN
  FOR f IN
    SELECT p.oid::regprocedure AS sig
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.prokind = 'f'
       AND p.proname IN ('fin_categoria_for_proc', 'fin_categoria_especifica', 'crm_norm_phone')
  LOOP
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', f.sig);
  END LOOP;
END;
$helpers$;

-- b) Daqui pra frente nada nasce aberto pro visitante ------------------------
-- (PUBLIC tem EXECUTE em função por padrão do Postgres; o Supabase ainda dá
--  ALL pro anon em função e tabela novas do schema public.)
ALTER DEFAULT PRIVILEGES FOR ROLE postgres REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON TABLES FROM anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON SEQUENCES FROM anon;

-- c) cron_error_log: só o servidor ---------------------------------------
DO $log$
BEGIN
  IF to_regclass('public.cron_error_log') IS NULL THEN RETURN; END IF;
  EXECUTE 'ALTER TABLE public.cron_error_log ENABLE ROW LEVEL SECURITY';
  EXECUTE 'REVOKE ALL ON public.cron_error_log FROM anon, authenticated';
  EXECUTE 'GRANT ALL ON public.cron_error_log TO service_role';
  IF to_regclass('public.cron_error_log_id_seq') IS NOT NULL THEN
    EXECUTE 'REVOKE ALL ON SEQUENCE public.cron_error_log_id_seq FROM anon, authenticated';
  END IF;
END;
$log$;

-- Conferência --------------------------------------------------------------
SELECT 'funcoes que o visitante (anon) ainda executa' AS checagem,
       COALESCE(string_agg(p.proname, ', ' ORDER BY p.proname), 'nenhuma') AS resultado
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.prokind = 'f'
   AND p.prorettype <> 'trigger'::regtype
   AND has_function_privilege('anon', p.oid, 'EXECUTE')
UNION ALL
SELECT 'tabelas do public SEM RLS',
       COALESCE(string_agg(c.relname, ', ' ORDER BY c.relname), 'nenhuma')
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public' AND c.relkind = 'r' AND NOT c.relrowsecurity;
