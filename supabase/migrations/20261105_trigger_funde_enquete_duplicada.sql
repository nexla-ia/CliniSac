-- ==============================================================
-- Causa real do poll duplicado (achada com prints do usuário):
--
--   O flow do n8n que recebe os webhooks do Evolution API tem um ramo
--   "Mensagem Enquete" que também grava em mensagens_geral (visto no
--   print: linha com poll_appointment_id NULL, mas com id_mensagem
--   real e poll_options já com voters — ou seja, não é a linha que o
--   process_appointment_reminders() insere, é OUTRA linha, inserida
--   pelo n8n). Isso bate com um padrão clássico do Baileys/Evolution:
--   o evento de webhook de "mensagem enviada" (upsert) dispara TANTO
--   pra mensagem recebida quanto pra mensagem que o PRÓPRIO sistema
--   acabou de mandar (fromMe) — se esse ramo do n8n não filtra isso,
--   ele "recebe de volta" a enquete que ele mesmo mandou e, em vez de
--   atualizar a linha que já existe (a que o Postgres inseriu), cria
--   uma linha nova. Resultado: 2 linhas em mensagens_geral pra mesma
--   enquete → 2 balões no CliniSac.
--
--   A trava anterior (20261105_trava_dedupe_mensagem_igual.sql) olha
--   só de dentro das functions do Postgres (reminders/followups/
--   review), comparando por poll_appointment_id — não pega esse caso,
--   porque a linha que o n8n insere não tem poll_appointment_id.
--
-- CORREÇÃO: trigger BEFORE INSERT em mensagens_geral. Se já existe uma
-- enquete (mesma instancia+numero+poll_name) do PRÓPRIO sistema
-- (type='atendente') inserida há menos de 3 minutos, não cria outra
-- linha — funde os dados novos (id_mensagem, poll_options/poll_votes
-- reais que vieram da enquete-echo do n8n) na linha original e cancela
-- essa inserção. Funciona não importa quem está inserindo (Postgres
-- OU n8n), então cobre esse caso e qualquer outro caminho futuro de
-- duplicação pelo mesmo padrão.
--
-- O ideal ainda é arrumar o filtro de fromMe no n8n (pra não processar
-- como "recebida" uma mensagem que o próprio número mandou), mas isso
-- não dá pra fazer por aqui — essa trigger é a rede de segurança no
-- banco, que funciona independente disso ser corrigido no n8n ou não.
--
-- Idempotente.
-- ==============================================================

CREATE OR REPLACE FUNCTION public.dedupe_mensagem_enquete_antes_insert()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  existing record;
BEGIN
  -- só mexe em enquete (poll_name preenchido) mandada pelo próprio
  -- sistema/clínica (type='atendente') — nunca mexe em mensagem normal
  -- nem em mensagem recebida do paciente (type='cliente').
  IF NEW.poll_name IS NULL OR NEW.type IS DISTINCT FROM 'atendente' THEN
    RETURN NEW;
  END IF;

  SELECT * INTO existing
    FROM public.mensagens_geral
   WHERE instancia = NEW.instancia
     AND numero = NEW.numero
     AND poll_name = NEW.poll_name
     AND type = 'atendente'
     AND created_at > now() - interval '3 minutes'
   ORDER BY created_at ASC
   LIMIT 1;

  IF NOT FOUND THEN
    RETURN NEW;
  END IF;

  -- já existe enquete igual recém-criada pra esse contato: é a mesma
  -- enquete voltando (echo do n8n, ou qualquer outra duplicata) — funde
  -- o que a linha nova trouxe de novo (id_mensagem real, voto/options
  -- atualizados) na linha original, e cancela esta inserção duplicada.
  UPDATE public.mensagens_geral SET
    id_mensagem  = COALESCE(NEW.id_mensagem, existing.id_mensagem),
    poll_options = COALESCE(NEW.poll_options, existing.poll_options),
    poll_votes   = COALESCE(NEW.poll_votes, existing.poll_votes),
    delivered_at = COALESCE(NEW.delivered_at, existing.delivered_at),
    read_at      = COALESCE(NEW.read_at, existing.read_at)
  WHERE id = existing.id;

  RAISE NOTICE 'dedupe_mensagem_enquete: enquete duplicada evitada (instancia=%, numero=%, poll=%)',
    NEW.instancia, NEW.numero, NEW.poll_name;

  RETURN NULL; -- cancela o INSERT duplicado
END;
$$;

DROP TRIGGER IF EXISTS trg_dedupe_mensagem_enquete ON public.mensagens_geral;
CREATE TRIGGER trg_dedupe_mensagem_enquete
  BEFORE INSERT ON public.mensagens_geral
  FOR EACH ROW
  EXECUTE FUNCTION public.dedupe_mensagem_enquete_antes_insert();
