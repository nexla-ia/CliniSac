-- ==============================================================
-- "Disparo" — tela de mensagem em massa (campanhas), portada do
-- repo irmão NexSac (nexla-ia/NexSac), que já tinha isso pronto e
-- no CliniSac nunca existiu.
--
--   1) disparo_campanhas — rascunho/campanha: nome, lista de
--      mensagens (itens, até 5, texto ou imagem) e lista de
--      destinatários (contatos e/ou grupos), por instância.
--   2) disparo_envios — uma linha por destinatário de uma campanha
--      (status pendente/enviado/erro), pra acompanhar o progresso
--      e não reenviar pra quem já recebeu.
--
-- Diferença do NexSac: lá a RLS das duas tabelas é "allow_all"
-- (USING (true)). Aqui segue o padrão real do CliniSac — isolamento
-- por clínica via auth_can_access_instancia() (igual
-- patient_documents, etc.) — já que esse projeto leva multi-tenant
-- a sério.
--
-- Idempotente.
-- ==============================================================

CREATE TABLE IF NOT EXISTS public.disparo_campanhas (
  id                  uuid        DEFAULT gen_random_uuid() PRIMARY KEY,
  instancia           text        NOT NULL,
  nome                text        NOT NULL,
  itens               jsonb       NOT NULL DEFAULT '[]'::jsonb,
  destinatarios       jsonb       NOT NULL DEFAULT '[]'::jsonb,
  created_by_email    text,
  created_at          timestamptz DEFAULT now(),
  last_disparo_at     timestamptz,
  last_disparo_total  integer
);

ALTER TABLE public.disparo_campanhas ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS tenant_rw ON public.disparo_campanhas;
CREATE POLICY tenant_rw ON public.disparo_campanhas FOR ALL TO authenticated
  USING (public.auth_can_access_instancia(instancia))
  WITH CHECK (public.auth_can_access_instancia(instancia));

CREATE INDEX IF NOT EXISTS idx_disparo_campanhas_instancia ON public.disparo_campanhas(instancia);

CREATE TABLE IF NOT EXISTS public.disparo_envios (
  id          uuid        DEFAULT gen_random_uuid() PRIMARY KEY,
  campanha_id uuid        NOT NULL REFERENCES public.disparo_campanhas(id) ON DELETE CASCADE,
  instancia   text        NOT NULL,
  tipo        text        NOT NULL CHECK (tipo IN ('contato','grupo')),
  destino     text        NOT NULL,
  nome        text,
  status      text        NOT NULL DEFAULT 'pendente' CHECK (status IN ('pendente','enviado','erro')),
  erro_msg    text,
  enviado_em  timestamptz,
  updated_at  timestamptz DEFAULT now(),
  created_at  timestamptz DEFAULT now(),
  UNIQUE (campanha_id, tipo, destino)
);

ALTER TABLE public.disparo_envios ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS tenant_rw ON public.disparo_envios;
CREATE POLICY tenant_rw ON public.disparo_envios FOR ALL TO authenticated
  USING (public.auth_can_access_instancia(instancia))
  WITH CHECK (public.auth_can_access_instancia(instancia));

CREATE INDEX IF NOT EXISTS idx_disparo_envios_campanha  ON public.disparo_envios(campanha_id);
CREATE INDEX IF NOT EXISTS idx_disparo_envios_instancia ON public.disparo_envios(instancia);

ALTER TABLE public.disparo_envios REPLICA IDENTITY FULL;

DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.disparo_envios;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
