-- ==============================================================
-- Status de entrega/leitura — parte 2: ERROR assíncrono
--
-- Complementa 20260901_message_delivery_status.sql. Aquela migration
-- cobre SERVER_ACK/DELIVERY_ACK/READ (delivered_at/read_at). Falta o
-- ERROR (status 0 do WAMessageStatus) — quando a Evolution reporta
-- falha de entrega DEPOIS do envio (assíncrono, via messages.update),
-- não no HTTP de resposta do envio em si.
--
-- Sem essa coluna, uma mensagem que deu ERROR fica "presa" no ✓
-- simples pra sempre — igual uma que só ainda não confirmou entrega.
-- Não dá pra diferenciar "vai chegar, só demorou" de "não vai chegar
-- nunca".
--
-- Coluna nova em mensagens_geral:
--   send_error_at   timestamptz — quando a Evolution reportou ERROR
--
-- SQL que o node do n8n deve rodar quando o evento vier com status
-- ERROR (mesma chave de sempre, id_mensagem + instancia):
--
--   UPDATE mensagens_geral
--   SET send_error_at = COALESCE(send_error_at, now())
--   WHERE id_mensagem = '<key.id>' AND instancia = '<instancia>';
--
-- NÃO precisa (e não deve) mexer em delivered_at/read_at nesse caso —
-- eles continuam NULL, o que já é correto (nunca entregou/leu).
--
-- COMO O FRONT MOSTRA (já pronto): reaproveita o aviso vermelho que já
-- existia pra falha de envio na hora ("❗ não entregue no WhatsApp") —
-- agora ele também acende quando send_error_at vem preenchido depois,
-- via realtime, mesmo que o envio em si não tenha dado erro nenhum na
-- hora. Enquanto isso, o checkmark de entrega/leitura some (não faz
-- sentido mostrar ✓ de uma mensagem que deu erro).
--
-- Idempotente. Cole no SQL Editor do Supabase.
-- ==============================================================

SET search_path TO public;

ALTER TABLE public.mensagens_geral
  ADD COLUMN IF NOT EXISTS send_error_at timestamptz;
