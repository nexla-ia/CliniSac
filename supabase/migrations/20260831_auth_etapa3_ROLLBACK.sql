-- ══════════════════════════════════════════════════════════════════════════
-- ROLLBACK da etapa 3 — devolve as policies permissivas
--
-- Use SÓ se a etapa 3a esvaziar telas e você precisar do sistema de volta
-- enquanto a causa é investigada.
--
-- ⚠ Isto REABRE a leitura dos dados clínicos para quem tem a anon key.
--   É um retorno ao estado anterior à etapa 3, que era o estado vulnerável.
--   Não deixe assim: me diga qual tela quebrou e a policy certa vem no lugar.
--
-- Não desfaz as etapas 1, 2 e 2b — aquelas não mexeram em policy, e os
-- caminhos de takeover continuam fechados depois deste rollback.
-- ══════════════════════════════════════════════════════════════════════════

SET search_path TO public, extensions;

DO $rb$
DECLARE
  t text;
  alvo text[] := ARRAY[
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
    'kanban_card_comments','support_messages','messages'
  ];
BEGIN
  FOREACH t IN ARRAY alvo LOOP
    EXECUTE format('DROP POLICY IF EXISTS tenant_rw ON public.%I', t);
    EXECUTE format(
      'CREATE POLICY allow_read ON public.%I FOR ALL USING (true) WITH CHECK (true)', t);
  END LOOP;
END;
$rb$;

SELECT 'policies permissivas restauradas' AS estado,
       count(DISTINCT tablename)::text AS tabelas
  FROM pg_policies
 WHERE schemaname = 'public' AND policyname = 'allow_read';
