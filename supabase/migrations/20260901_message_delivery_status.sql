-- ==============================================================
-- Status de entrega/leitura da mensagem (estilo WhatsApp: ✓ / ✓✓ / ✓✓ azul)
--
-- Hoje só sabemos que uma mensagem foi "enviada" (existe em
-- mensagens_geral). Isso guarda quando ela foi ENTREGUE e LIDA de
-- verdade no aparelho do paciente — útil pra saber se um lembrete ou
-- cobrança realmente chegou, não só se o envio "não deu erro".
--
-- Colunas novas em mensagens_geral (mesma tabela central, sem tabela
-- nova):
--   delivered_at   timestamptz — quando a Evolution confirmou entrega
--   read_at        timestamptz — quando o contato abriu/leu
--
-- Quem preenche isso é o n8n, escutando o evento messages.update da
-- Evolution (dispara quando o status muda: enviado → entregue → lido).
-- Casa pela mesma chave que já existe pro resto do app:
-- (id_mensagem, instancia) — já tem índice único
-- (mensagens_geral_id_mensagem_instancia_unique).
--
-- Baileys/Evolution manda o status como número (WAMessageStatus):
--   0 ERROR, 1 PENDING, 2 SERVER_ACK (enviado), 3 DELIVERY_ACK
--   (entregue), 4 READ (lido), 5 PLAYED (áudio ouvido)
-- O n8n só precisa fazer, quando status >= 3:
--   UPDATE mensagens_geral SET delivered_at = COALESCE(delivered_at, now())
--     WHERE id_mensagem = '<key.id>' AND instancia = '<instancia>';
-- e quando status >= 4 (ou 5), a mesma coisa pra read_at. Sempre com
-- service_role (RLS não bloqueia).
--
-- Idempotente. Cole no SQL Editor do Supabase.
-- ==============================================================

SET search_path TO public;

ALTER TABLE public.mensagens_geral
  ADD COLUMN IF NOT EXISTS delivered_at timestamptz,
  ADD COLUMN IF NOT EXISTS read_at timestamptz;
