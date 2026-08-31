-- ==============================================================
-- Conversas — responder mensagem (citar/reply, estilo WhatsApp)
--
-- Cada mensagem citada é referenciada pelo id_mensagem da ORIGINAL,
-- guardado em quoted_id_mensagem na resposta. A RPC de envio passa a
-- aceitar p_quoted e a devolver o id da linha inserida — assim a
-- citação é gravada de forma atômica (sem o "match por texto" frágil).
--
-- Seguro rodar mais de uma vez.
-- Para usar: cole no SQL Editor do Supabase (projeto NOVO, sbzwtnxx).
-- ==============================================================

SET search_path TO public;

ALTER TABLE public.mensagens_geral
  ADD COLUMN IF NOT EXISTS quoted_id_mensagem text;

-- Remove qualquer versão anterior da função (evita ambiguidade de overload)
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT oid::regprocedure AS sig FROM pg_proc WHERE proname = 'send_mensagem_geral' LOOP
    EXECUTE 'DROP FUNCTION ' || r.sig;
  END LOOP;
END $$;

-- NOTA: mensagens_geral.id é INTEIRO — NÃO usar RETURNS uuid aqui (quebra o
-- envio inteiro com erro 22P02). Mantém RETURNS void; o p_quoted grava a
-- citação na própria inserção.
CREATE FUNCTION public.send_mensagem_geral(
  p_instancia text,
  p_numero    text,
  p_mensagem  text,
  p_type      text,
  p_hora      text,
  p_base64    text DEFAULT NULL,
  p_nome      text DEFAULT NULL,
  p_quoted    text DEFAULT NULL
) RETURNS void
  LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO public.mensagens_geral
    (instancia, numero, mensagem, type, "horaLastMessage", base64, nome, quoted_id_mensagem, created_at)
  VALUES
    (p_instancia, p_numero, p_mensagem, p_type, p_hora, p_base64, p_nome, p_quoted, NOW());
END;
$$;
