-- ══════════════════════════════════════════════════════════════════════════
-- ETAPA 4 — URGENTE: as funções api_* contornavam todo o RLS
--
-- O QUE FOI ENCONTRADO (segunda passada da auditoria)
--   As ~37 funções api_*/n8n são SECURITY DEFINER, ou seja, IGNORAM RLS por
--   definição — e estavam executáveis pelo anon. Todo o isolamento da etapa 3
--   passava ao largo delas.
--
--   Verificado ao vivo, só com a anon key e sem nenhum login:
--     api_pacientes_list('NEXLA')     -> paciente real, com telefone
--     api_paciente_by_phone(...)      -> ficha do paciente
--     api_messages_by_phone(...)      -> conversas de WhatsApp
--     api_paciente_delete(...)        -> executou (apaga paciente por id)
--     n8n_clear_mensagens()           -> executou (expurga mensagens)
--
--   Elas nasceram como "API para o n8n chamar", e o jeito de chamar era a
--   anon key. Só que a anon key é pública: vai no bundle do site.
--
-- A CORREÇÃO
--   Quem chama do servidor (n8n, integrações) usa a service_role key, que é
--   secreta e nunca sai do servidor. O anon não executa função nenhuma —
--   ele não precisa: o app autentica antes de fazer qualquer coisa, e o
--   login em si passa pelo GoTrue (/auth/v1), não por função do banco.
--
--   Default-deny: revoga de PUBLIC e anon TODAS as funções chamáveis do
--   público (exceto as de trigger, que não são invocadas por usuário) e
--   devolve, nominalmente, só o que o front usa.
--
-- ⚠ QUANDO LIGAR O n8n, use a service_role key nessas chamadas.
--   Ela está em Supabase → Project Settings → API → service_role. NUNCA
--   coloque essa chave no frontend nem no .env do Vite.
--
-- Idempotente.
-- ══════════════════════════════════════════════════════════════════════════

SET search_path TO public, extensions;

-- ─────────────────────────────────────────────────────────────────────────
-- 1) Default-deny: nenhuma função do schema public executável pelo anon
-- ─────────────────────────────────────────────────────────────────────────
DO $deny$
DECLARE f record;
BEGIN
  FOR f IN
    SELECT p.oid::regprocedure AS sig
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.prokind = 'f'
       AND p.prorettype <> 'trigger'::regtype   -- triggers não são chamadas por usuário
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon', f.sig);
    EXECUTE format('GRANT  EXECUTE ON FUNCTION %s TO service_role', f.sig);
  END LOOP;
END;
$deny$;

-- ─────────────────────────────────────────────────────────────────────────
-- 2) Devolve, nominalmente, só o que o app logado usa
--
--    A lista saiu de um levantamento das chamadas supabase.rpc() no front.
--    Qualquer função fora daqui só responde para service_role.
-- ─────────────────────────────────────────────────────────────────────────
DO $allow$
DECLARE
  f record;
  permitidas text[] := ARRAY[
    -- helpers de identidade (as policies de RLS chamam estes)
    'auth_profile','auth_role','auth_company_id','auth_is_adm',
    'auth_can_access_company','auth_can_access_instancia','auth_can_manage_users',
    -- gestão de usuários (todas checam quem está chamando)
    'create_user','update_user_password','update_user_profile','delete_user',
    'set_user_active','change_own_password',
    -- sessão única
    'claim_login_session','touch_login_session','release_login_session',
    -- operações do painel
    'ensure_table_setup','mark_company_paid','send_mensagem_geral',
    'set_message_reaction',
    -- leituras agregadas usadas pelas telas
    'api_conversas_contatos','api_distinct_numeros','api_distinct_grupos',
    'api_grupos_lista','api_adm_msg_stats','api_adm_msg_hours',
    'api_operacao_msg_stats'
  ];
BEGIN
  FOR f IN
    SELECT p.oid::regprocedure AS sig
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.prokind = 'f'
       AND p.proname = ANY(permitidas)
  LOOP
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', f.sig);
  END LOOP;
END;
$allow$;

-- ─────────────────────────────────────────────────────────────────────────
-- 3) Remove a função de debug que sobrou do piloto
--
--    _pilot_debug_mint(p_instancia, p_pin) não tem uso no CliniSac e é, pelo
--    nome, uma porta de diagnóstico com PIN. Não fica.
-- ─────────────────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS public._pilot_debug_mint(text, text);

-- ─────────────────────────────────────────────────────────────────────────
-- 4) Conferência
-- ─────────────────────────────────────────────────────────────────────────
SELECT 'funcoes public que o anon ainda executa' AS checagem,
       COALESCE(string_agg(p.proname, ', ' ORDER BY p.proname), 'nenhuma') AS resultado
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.prokind = 'f'
   AND p.prorettype <> 'trigger'::regtype
   AND has_function_privilege('anon', p.oid, 'EXECUTE')

UNION ALL
SELECT 'funcoes liberadas para o app logado',
       count(*)::text
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.prokind = 'f'
   AND p.prorettype <> 'trigger'::regtype
   AND has_function_privilege('authenticated', p.oid, 'EXECUTE')

UNION ALL
SELECT 'api_pacientes_list ainda aberta ao anon?',
       has_function_privilege('anon',
         'public.api_pacientes_list(text,text,integer,integer)', 'EXECUTE')::text;
