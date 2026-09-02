-- ==============================================================
-- Quem fechou o ticket — resolve o ranking de atendentes quebrado
--
-- O QUE TAVA QUEBRADO
--   attendances só guarda quem tá atendendo AGORA — a linha é
--   apagada assim que o ticket fecha (api_conversation_close E o
--   handler de fechar no front fazem DELETE FROM attendances). O
--   ranking de atendentes (CompanyMetrics.jsx, aba Equipe) tentava
--   reconstruir "quem finalizou" olhando essa mesma tabela DEPOIS do
--   fechamento — impossível por definição, sempre batia ~0.
--
-- A CORREÇÃO
--   Grava quem tava atendendo NO MOMENTO do fechamento direto em
--   conversations, antes de apagar attendances. Só vale dali pra
--   frente — não reconstrói ticket já fechado antes dessa migration
--   (não tem como saber quem foi depois que a linha já sumiu).
--
-- Colunas novas em conversations:
--   closed_by_email        text
--   closed_by_name         text
--   closed_by_sector_id    uuid
--   closed_by_sector_name  text
-- Ficam NULL quando ninguém tinha assumido (ex.: IA resolveu sozinha,
-- ou ticket fechado direto da Recepção sem passar por atendimento).
--
-- Idempotente. Cole no SQL Editor do Supabase.
-- ==============================================================

SET search_path TO public;

ALTER TABLE public.conversations
  ADD COLUMN IF NOT EXISTS closed_by_email text,
  ADD COLUMN IF NOT EXISTS closed_by_name text,
  ADD COLUMN IF NOT EXISTS closed_by_sector_id uuid,
  ADD COLUMN IF NOT EXISTS closed_by_sector_name text;

CREATE OR REPLACE FUNCTION public.api_conversation_close(
  p_session_id text,
  p_instancia  text,
  p_reason     text
)
RETURNS conversations
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_row conversations;
  v_att attendances;
BEGIN
  SELECT * INTO v_att FROM attendances
   WHERE numero = p_session_id AND instancia = p_instancia LIMIT 1;

  INSERT INTO conversations
    (session_id, instancia, reason, closed_at,
     closed_by_email, closed_by_name, closed_by_sector_id, closed_by_sector_name)
  VALUES
    (p_session_id, p_instancia, p_reason, now(),
     v_att.attendant_email, v_att.attendant_name, v_att.sector_id, v_att.sector_name)
  RETURNING * INTO v_row;

  BEGIN
    DELETE FROM attendances WHERE numero = p_session_id AND instancia = p_instancia;
  EXCEPTION WHEN undefined_table THEN NULL;
  END;
  RETURN v_row;
END $$;
