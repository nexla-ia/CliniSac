-- ============================================================================
-- Financeiro: recebimento PARCIAL + VÁRIAS FORMAS (ex.: R$100 dinheiro + R$100 pix)
-- ----------------------------------------------------------------------------
-- Antes: cada lançamento tinha 1 forma/1 conta e status pendente|pago.
-- Agora: um lançamento pode ter VÁRIOS recebimentos (cada um com valor, forma,
-- conta, data). O status passa a ter "parcial" quando o recebido é menor que o
-- total. `valor_pago` guarda a soma recebida (pra lista/KPIs sem join).
--
-- Portado do clinimag (d36cd47). Diferença: a tabela nova segue o isolamento
-- por clínica do CliniSac (policy tenant_rw por instância, igual etapa 3a) em
-- vez do "allow all" do clinimag, e o anon não tem acesso.
--
-- Seguro rodar mais de uma vez.
-- ============================================================================

SET search_path TO public;

-- O CliniSac criou financial_transactions (clinisac_setup.sql) com
-- CHECK (status IN ('pendente','pago','cancelado')) — sem isto o status
-- "parcial" seria recusado. Troca a trava (qualquer nome) por uma que aceita.
DO $$
DECLARE c record;
BEGIN
  FOR c IN
    SELECT conname FROM pg_constraint
     WHERE conrelid = 'public.financial_transactions'::regclass
       AND contype = 'c'
       AND pg_get_constraintdef(oid) ILIKE '%status%pendente%'
  LOOP
    EXECUTE format('ALTER TABLE public.financial_transactions DROP CONSTRAINT %I', c.conname);
  END LOOP;
END $$;
ALTER TABLE public.financial_transactions
  ADD CONSTRAINT financial_transactions_status_check
  CHECK (status IN ('pendente', 'parcial', 'pago', 'cancelado'));

-- Quanto já foi recebido/pago do lançamento (soma dos recebimentos).
ALTER TABLE public.financial_transactions
  ADD COLUMN IF NOT EXISTS valor_pago numeric(12,2) NOT NULL DEFAULT 0;

-- Histórico de recebimentos/pagamentos (1 lançamento → N linhas).
CREATE TABLE IF NOT EXISTS public.financial_payments (
  id              uuid primary key default gen_random_uuid(),
  instancia       text not null,
  transaction_id  uuid not null references public.financial_transactions(id) on delete cascade,
  valor           numeric(12,2) not null,
  juros           numeric(12,2) not null default 0,
  forma_pagamento text,
  bank_account_id uuid,
  pagamento_at    date not null default current_date,
  created_by      text,
  created_at      timestamptz not null default now()
);
CREATE INDEX IF NOT EXISTS financial_payments_tx_idx   ON public.financial_payments(transaction_id);
CREATE INDEX IF NOT EXISTS financial_payments_inst_idx ON public.financial_payments(instancia);

ALTER TABLE public.financial_payments ENABLE ROW LEVEL SECURITY;

-- Só quem é da clínica (ou o ADM) lê/grava — mesmo critério de financial_transactions.
DROP POLICY IF EXISTS "allow all" ON public.financial_payments;
DROP POLICY IF EXISTS tenant_rw ON public.financial_payments;
CREATE POLICY tenant_rw ON public.financial_payments FOR ALL TO authenticated
  USING (public.auth_can_access_instancia(instancia))
  WITH CHECK (public.auth_can_access_instancia(instancia));

REVOKE ALL ON public.financial_payments FROM anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.financial_payments TO authenticated;
GRANT ALL ON public.financial_payments TO service_role;

-- Backfill: lançamentos já PAGOS passam a ter valor_pago = valor (pra "parcial"
-- começar do estado certo). Os pendentes ficam com 0.
UPDATE public.financial_transactions
   SET valor_pago = valor
 WHERE status = 'pago' AND COALESCE(valor_pago, 0) = 0;
