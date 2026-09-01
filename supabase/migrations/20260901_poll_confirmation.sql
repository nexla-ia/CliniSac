-- ==============================================================
-- Confirmação de presença por enquete (poll) do WhatsApp
--
-- Em vez de botões nativos (que a Evolution não expõe de forma
-- confiável), a confirmação usa ENQUETE: "Confirmar" / "Remarcar"
-- como opções. O paciente vota e o n8n atualiza a contagem aqui.
--
-- Colunas novas em mensagens_geral (mesma tabela central — não cria
-- tabela nova, segue o padrão já documentado em docs/plataforma-
-- whatsapp.md §0.1):
--   poll_name              pergunta da enquete
--   poll_options           ["Confirmar","Remarcar"] (ordem = ordem no zap)
--   poll_votes             [{"option":"Confirmar","votes":0}, ...] — o n8n
--                           atualiza isso (UPDATE por id_mensagem) quando
--                           chega voto
--   poll_selectable_count  1 = escolha única
--   poll_appointment_id    liga a enquete ao agendamento de origem
--
-- send_mensagem_geral ganha 4 parâmetros novos (todos opcionais, no
-- final) pra logar a enquete no histórico junto com o envio. Precisa
-- DROP+CREATE (não dá pra "OR REPLACE" mudando a assinatura) — por
-- isso repete explicitamente REVOKE/GRANT pra não reabrir a função
-- pro anon (etapa 4 do hardening revogou default; toda função nova
-- nasce com EXECUTE pra PUBLIC por padrão do Postgres).
--
-- Idempotente.
-- ==============================================================

SET search_path TO public;

ALTER TABLE public.mensagens_geral
  ADD COLUMN IF NOT EXISTS poll_name text,
  ADD COLUMN IF NOT EXISTS poll_options jsonb,
  ADD COLUMN IF NOT EXISTS poll_votes jsonb,
  ADD COLUMN IF NOT EXISTS poll_selectable_count integer,
  ADD COLUMN IF NOT EXISTS poll_appointment_id uuid;

DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT oid::regprocedure AS sig FROM pg_proc WHERE proname = 'send_mensagem_geral' LOOP
    EXECUTE 'DROP FUNCTION ' || r.sig;
  END LOOP;
END $$;

CREATE FUNCTION public.send_mensagem_geral(
  p_instancia             text,
  p_numero                text,
  p_mensagem              text,
  p_type                  text,
  p_hora                  text,
  p_base64                text DEFAULT NULL,
  p_nome                  text DEFAULT NULL,
  p_quoted                text DEFAULT NULL,
  p_poll_name             text DEFAULT NULL,
  p_poll_options          jsonb DEFAULT NULL,
  p_poll_selectable_count integer DEFAULT NULL,
  p_poll_appointment_id   uuid DEFAULT NULL
) RETURNS void
  LANGUAGE plpgsql SECURITY INVOKER
  SET search_path TO 'public'
AS $$
BEGIN
  INSERT INTO public.mensagens_geral
    (instancia, numero, mensagem, type, "horaLastMessage", base64, nome,
     quoted_id_mensagem, poll_name, poll_options, poll_votes,
     poll_selectable_count, poll_appointment_id, created_at)
  VALUES
    (p_instancia, p_numero, p_mensagem, p_type, p_hora, p_base64, p_nome,
     p_quoted, p_poll_name, p_poll_options,
     CASE WHEN p_poll_options IS NOT NULL THEN (
       SELECT jsonb_agg(jsonb_build_object('option', v, 'votes', 0))
         FROM jsonb_array_elements_text(p_poll_options) v
     ) ELSE NULL END,
     p_poll_selectable_count, p_poll_appointment_id, NOW());
END;
$$;

-- send_mensagem_geral roda SECURITY INVOKER (RLS de quem chama vale) desde a
-- etapa 4b — não regredir pra DEFINER aqui.
REVOKE ALL ON FUNCTION public.send_mensagem_geral(
  text, text, text, text, text, text, text, text, text, jsonb, integer, uuid
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.send_mensagem_geral(
  text, text, text, text, text, text, text, text, text, jsonb, integer, uuid
) TO authenticated;
