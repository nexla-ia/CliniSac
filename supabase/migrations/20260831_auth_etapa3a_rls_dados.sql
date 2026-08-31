-- ══════════════════════════════════════════════════════════════════════════
-- ETAPA 3a — RLS de verdade nos dados clínicos e financeiros
--
-- Até aqui as policies eram "using (true)": o RLS estava ligado mas não
-- separava nada. Qualquer pessoa com a anon key lia prontuário, agenda,
-- conversa de WhatsApp e financeiro de todas as clínicas.
--
-- Agora cada linha só aparece para quem é daquela clínica — ou para o ADM.
--
-- COMO A LINHA SABE DE QUAL CLÍNICA É
--   A chave de multi-tenancy aqui não é company_id, é a `instancia` do
--   WhatsApp (41 tabelas usam ela). O helper compara em lower(), porque o
--   n8n/Evolution grava a instância em caixa variável — foi o motivo da
--   migration 20260828_reaction_instancia_case_insensitive.
--
-- POR QUE ISTO NÃO QUEBRA AS TELAS
--   O front já filtra por instância em 173 consultas, então para o usuário
--   legítimo a policy é quase um no-op. As telas do ADM que agregam várias
--   clínicas (AdmDashboard) passam por auth_is_adm().
--
-- ESCOPO: só dados. Não toca em users nem companies — se algo aqui der
-- errado, o login continua funcionando e dá para reverter (rollback em
-- 20260831_auth_etapa3_ROLLBACK.sql).
--
-- Idempotente.
-- ══════════════════════════════════════════════════════════════════════════

SET search_path TO public, extensions;

-- ─────────────────────────────────────────────────────────────────────────
-- 1) Helper: a instância pertence à clínica de quem está chamando?
--
--    NULL em qualquer ponto vira false — a lição da etapa 2b. Aqui o efeito
--    de um NULL seria esconder a linha (RLS falha fechado), mas predicado de
--    autorização não deve depender de qual lado ele falha.
--
--    Linha com instancia NULL fica visível só para o ADM: sem instância não
--    há como dizer de quem ela é.
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.auth_can_access_instancia(p_instancia text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $fn$
  SELECT COALESCE(
    public.auth_is_adm()
    OR ( p_instancia IS NOT NULL AND EXISTS (
           SELECT 1 FROM public.companies c
            WHERE c.id = public.auth_company_id()
              AND lower(c.instance) = lower(p_instancia) ) ),
    false);
$fn$;

GRANT EXECUTE ON FUNCTION public.auth_can_access_instancia(text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- 2) Aplica as policies
--
--    Policies permissivas se somam com OR: deixar uma "using (true)" para
--    trás anularia todo o resto. Por isso o passo 1 do bloco apaga TODAS as
--    policies existentes de cada tabela antes de criar a nova.
--
--    "TO authenticated" tira o anon inteiro da jogada. O service_role (n8n,
--    integrações) ignora RLS por definição, então não é afetado.
-- ─────────────────────────────────────────────────────────────────────────
DO $rls$
DECLARE
  t    text;
  pol  record;

  -- Tabelas cuja linha carrega a instância
  inst_tables text[] := ARRAY[
    'agenda_blocks','agendas','agent_configs','alerts','anamnese_responses',
    'anamnese_templates','appointments','attendances','bank_accounts',
    'bank_transfers','clientes','contact_tag_assignments','contact_tags',
    'conversation_close_reasons','conversation_reads','conversations',
    'crm_contact_funnels','crm_contacts','crm_funnels','crm_interactions',
    'crm_lists','crm_stages','crm_temperatures','financial_categories',
    'financial_transactions','group_custom_names','insurance_plans',
    'kanban_cards','kanban_columns','mensagens_geral','orcamentos',
    'procedure_prices','procedures','professionals','prontuario_attachments',
    'quick_messages','reminder_presets','saved_contacts','sectors',
    'treatment_plan_slots','treatment_plans'
  ];

  -- Tabelas que carregam company_id direto
  comp_tables text[] := ARRAY[
    'contacts','feedbacks','invoices','support_tickets'
  ];
BEGIN
  -- 2.1 Limpa as policies antigas de todas as tabelas envolvidas
  FOR pol IN
    SELECT tablename, policyname
      FROM pg_policies
     WHERE schemaname = 'public'
       AND tablename = ANY(inst_tables || comp_tables
                           || ARRAY['orcamento_items','sector_members',
                                    'kanban_card_comments','support_messages',
                                    'messages'])
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, pol.tablename);
  END LOOP;

  -- 2.2 Tabelas com instância
  FOREACH t IN ARRAY inst_tables LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format(
      'CREATE POLICY tenant_rw ON public.%I FOR ALL TO authenticated
         USING (public.auth_can_access_instancia(instancia))
         WITH CHECK (public.auth_can_access_instancia(instancia))', t);
  END LOOP;

  -- 2.3 Tabelas com company_id
  FOREACH t IN ARRAY comp_tables LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format(
      'CREATE POLICY tenant_rw ON public.%I FOR ALL TO authenticated
         USING (public.auth_can_access_company(company_id))
         WITH CHECK (public.auth_can_access_company(company_id))', t);
  END LOOP;
END;
$rls$;

-- ─────────────────────────────────────────────────────────────────────────
-- 3) Tabelas que herdam o dono da tabela-pai
--
--    Não têm chave própria; a clínica vem do registro a que pertencem.
-- ─────────────────────────────────────────────────────────────────────────
ALTER TABLE public.orcamento_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_rw ON public.orcamento_items FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.orcamentos o
                  WHERE o.id = orcamento_id
                    AND public.auth_can_access_instancia(o.instancia)))
  WITH CHECK (EXISTS (SELECT 1 FROM public.orcamentos o
                  WHERE o.id = orcamento_id
                    AND public.auth_can_access_instancia(o.instancia)));

ALTER TABLE public.sector_members ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_rw ON public.sector_members FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.sectors s
                  WHERE s.id = sector_id
                    AND public.auth_can_access_instancia(s.instancia)))
  WITH CHECK (EXISTS (SELECT 1 FROM public.sectors s
                  WHERE s.id = sector_id
                    AND public.auth_can_access_instancia(s.instancia)));

ALTER TABLE public.kanban_card_comments ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_rw ON public.kanban_card_comments FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.kanban_cards k
                  WHERE k.id = card_id
                    AND public.auth_can_access_instancia(k.instancia)))
  WITH CHECK (EXISTS (SELECT 1 FROM public.kanban_cards k
                  WHERE k.id = card_id
                    AND public.auth_can_access_instancia(k.instancia)));

ALTER TABLE public.support_messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_rw ON public.support_messages FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.support_tickets s
                  WHERE s.id = ticket_id
                    AND public.auth_can_access_company(s.company_id)))
  WITH CHECK (EXISTS (SELECT 1 FROM public.support_tickets s
                  WHERE s.id = ticket_id
                    AND public.auth_can_access_company(s.company_id)));

ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_rw ON public.messages FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.contacts c
                  WHERE c.id = contact_id
                    AND public.auth_can_access_company(c.company_id)))
  WITH CHECK (EXISTS (SELECT 1 FROM public.contacts c
                  WHERE c.id = contact_id
                    AND public.auth_can_access_company(c.company_id)));

-- ─────────────────────────────────────────────────────────────────────────
-- 4) ensure_table_setup para de reabrir o buraco
--
--    Ela criava "allow_read using (true)" na tabela de cada clínica nova —
--    ou seja, cada empresa cadastrada reintroduzia leitura pública. Agora
--    cria a policy no mesmo padrão desta migration.
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

  -- Tira qualquer policy permissiva herdada (inclusive a allow_read que esta
  -- propria funcao criava antes desta migration).
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
-- 5) Conferência
-- ─────────────────────────────────────────────────────────────────────────
SELECT 'tabelas com policy permissiva sobrando' AS checagem,
       COALESCE(string_agg(DISTINCT tablename, ', '), 'nenhuma') AS resultado
  FROM pg_policies
 WHERE schemaname = 'public'
   AND (qual = 'true' OR with_check = 'true')
   AND tablename IN (
     'agenda_blocks','agendas','agent_configs','alerts','anamnese_responses',
     'anamnese_templates','appointments','attendances','bank_accounts',
     'bank_transfers','clientes','contact_tag_assignments','contact_tags',
     'conversation_close_reasons','conversation_reads','conversations',
     'crm_contact_funnels','crm_contacts','crm_funnels','crm_interactions',
     'crm_lists','crm_stages','crm_temperatures','financial_categories',
     'financial_transactions','group_custom_names','insurance_plans',
     'kanban_cards','kanban_columns','mensagens_geral','orcamentos',
     'procedure_prices','procedures','professionals','prontuario_attachments',
     'quick_messages','reminder_presets','saved_contacts','sectors',
     'treatment_plan_slots','treatment_plans','contacts','feedbacks',
     'invoices','support_tickets','orcamento_items','sector_members',
     'kanban_card_comments','support_messages','messages')

UNION ALL
SELECT 'tabelas de dados protegidas',
       count(DISTINCT tablename)::text
  FROM pg_policies
 WHERE schemaname = 'public' AND policyname = 'tenant_rw'

UNION ALL
SELECT 'helper devolve NULL?',
       (public.auth_can_access_instancia(NULL) IS NULL)::text;
