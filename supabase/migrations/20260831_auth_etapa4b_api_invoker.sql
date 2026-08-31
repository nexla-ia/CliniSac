-- ══════════════════════════════════════════════════════════════════════════
-- ETAPA 4b — as api_* do painel param de ignorar a RLS
--
-- O QUE FALTAVA
--   A etapa 4 tirou as api_* do alcance do anon. Mas as 7 que o painel usa
--   continuaram SECURITY DEFINER, e elas recebem a instância como PARÂMETRO
--   sem conferir se ela é sua. Resultado: um usuário logado de uma clínica
--   lia dados de outra passando o nome da instância dela.
--
--   Verificado ao vivo, com o controle ao lado provando que não era falta
--   de dado:
--     leitura direta de mensagens_geral (tem RLS) .... bloqueada, 0 linhas
--     api_conversas_contatos('OUTRACLINICA') ......... vazou o número
--
-- A CORREÇÃO
--   Todas elas leem uma tabela só, mensagens_geral, que desde a etapa 3a tem
--   policy por clínica. Trocando SECURITY DEFINER por SECURITY INVOKER, elas
--   passam a rodar com os direitos de quem chamou e a RLS volta a valer —
--   sem reescrever o corpo de nenhuma.
--
--   É melhor que enfiar um IF de conferência em cada uma: não existe a
--   possibilidade de esquecer uma, e o dia em que a policy mudar, elas
--   acompanham sozinhas.
--
--   O n8n não é afetado: a service_role ignora RLS de qualquer jeito.
--
-- Idempotente.
-- ══════════════════════════════════════════════════════════════════════════

SET search_path TO public, extensions;

DO $inv$
DECLARE
  f record;
  alvo text[] := ARRAY[
    -- leituras do painel (todas só tocam mensagens_geral)
    'api_conversas_contatos','api_distinct_numeros','api_distinct_grupos',
    'api_grupos_lista','api_operacao_msg_stats',
    'api_adm_msg_stats','api_adm_msg_hours',
    -- escrita: com INVOKER, o WITH CHECK da policy impede mandar mensagem
    -- em nome de outra clínica
    'send_mensagem_geral','set_message_reaction'
  ];
BEGIN
  FOR f IN
    SELECT p.oid::regprocedure AS sig
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.prokind = 'f'
       AND p.proname = ANY(alvo)
  LOOP
    EXECUTE format('ALTER FUNCTION %s SECURITY INVOKER', f.sig);
  END LOOP;
END;
$inv$;

-- ─────────────────────────────────────────────────────────────────────────
-- Conferência
-- ─────────────────────────────────────────────────────────────────────────
SELECT p.proname AS funcao,
       CASE WHEN p.prosecdef THEN 'DEFINER (ignora RLS)'
            ELSE 'invoker (respeita RLS)' END AS modo
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('api_conversas_contatos','api_distinct_numeros',
                     'api_distinct_grupos','api_grupos_lista',
                     'api_operacao_msg_stats','api_adm_msg_stats',
                     'api_adm_msg_hours','send_mensagem_geral',
                     'set_message_reaction')
 ORDER BY p.proname;
