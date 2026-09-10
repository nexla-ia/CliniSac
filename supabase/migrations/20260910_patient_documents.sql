-- ══════════════════════════════════════════════════════════════════════════
-- IMPRESSOS DA FICHA DO PACIENTE
--
-- Guarda os documentos que o profissional emite na ficha (receituário,
-- solicitação de exames, atestado/declaração). O médico escreve, imprime e
-- carimba/assina no papel pra valer; aqui fica o registro pra reimprimir e
-- pra ter histórico do que foi prescrito, quando e por quem.
--
-- Multi-tenant pela `instancia`, no mesmo padrão da etapa 3 de segurança:
-- RLS por clínica via auth_can_access_instancia(). Só authenticated.
--
-- Idempotente. Cole no SQL Editor do Supabase.
-- ══════════════════════════════════════════════════════════════════════════

SET search_path TO public, extensions;

CREATE TABLE IF NOT EXISTS public.patient_documents (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  instancia     text        NOT NULL,
  contact_id    uuid,                    -- saved_contacts.id
  contact_numero text,                   -- só dígitos, espelha o padrão da ficha
  tipo          text        NOT NULL CHECK (tipo IN ('receituario', 'exames', 'atestado')),
  subtipo       text,                    -- atestado: 'atestado' | 'declaracao'
  titulo        text,
  corpo         text,                    -- texto livre / observações / corpo do atestado
  dados         jsonb       NOT NULL DEFAULT '{}',  -- ex.: { medicamentos:[{nome,posologia}], controle_especial:bool, indicacao:'...' }
  professional_id            uuid,
  professional_nome          text,
  professional_registro      text,       -- CRM / CRO / etc.
  professional_especialidade text,
  created_by    text,
  created_at    timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS patient_documents_contact_idx
  ON public.patient_documents (instancia, contact_id, created_at DESC);

ALTER TABLE public.patient_documents ENABLE ROW LEVEL SECURITY;

-- Só quem é da clínica (ou o ADM) enxerga/mexe. Mesma função da etapa 3a.
DROP POLICY IF EXISTS tenant_rw ON public.patient_documents;
CREATE POLICY tenant_rw ON public.patient_documents FOR ALL TO authenticated
  USING (public.auth_can_access_instancia(instancia))
  WITH CHECK (public.auth_can_access_instancia(instancia));

-- Dados clínicos: nunca pro anon. Só usuário logado (e o service_role, que
-- ignora RLS, pro n8n se um dia precisar).
REVOKE ALL ON public.patient_documents FROM anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.patient_documents TO authenticated;
GRANT ALL ON public.patient_documents TO service_role;

-- Conferência
SELECT 'patient_documents com RLS?' AS checagem, relrowsecurity::text AS resultado
  FROM pg_class WHERE oid = 'public.patient_documents'::regclass
UNION ALL
SELECT 'anon consegue ler?',
  has_table_privilege('anon', 'public.patient_documents', 'SELECT')::text;
