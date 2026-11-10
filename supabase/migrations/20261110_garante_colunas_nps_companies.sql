-- ==============================================================
-- A tela de NPS (CompanyNps.jsx) deu erro ao salvar:
--   "Could not find the 'followup_question_message' column of
--    'companies' in the schema cache"
--
-- As 3 colunas usadas por essa tela (google_review_url,
-- followup_question_message, followup_review_message) foram
-- adicionadas em 20260908_followup_e_avaliacao.sql e
-- 20260909_followup_mensagens_editaveis.sql -- migrations antigas
-- que, pelo visto, nunca rodaram de verdade neste banco.
--
-- Garante as 3 de novo (idempotente, seguro mesmo que já existam) e
-- força o PostgREST a recarregar o cache de schema, já que a tabela
-- pode ter sido alterada por fora de uma migration "reconhecida" por
-- ele.
--
-- Idempotente.
-- ==============================================================

ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS google_review_url text;

ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS followup_question_message text;

ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS followup_review_message text;

NOTIFY pgrst, 'reload schema';
