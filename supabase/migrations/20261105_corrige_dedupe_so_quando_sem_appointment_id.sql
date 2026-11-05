-- ==============================================================
-- Corrige regressão da própria trigger de dedupe de hoje
-- (20261105_trigger_funde_enquete_duplicada.sql / amplia_janela)
--
-- BUG: a trigger casava só por texto (instancia+numero+poll_name),
-- sem considerar qual agendamento a enquete nova é de verdade. Quando
-- dois agendamentos diferentes (ex.: um apagado e um recriado depois,
-- ou um reagendado pro mesmo horário de antes) geram o MESMO texto de
-- enquete pro mesmo paciente dentro da janela de 14 dias, a trigger
-- fundia a inserção nova dentro da linha ANTIGA -- cancelando o INSERT
-- que teria o poll_appointment_id certo. Resultado: a enquete ficava
-- com o poll_appointment_id do agendamento ERRADO (às vezes já
-- apagado), e o voto do paciente nunca atualizava o agendamento
-- certo.
--
-- A function process_appointment_reminders() JÁ tem sua própria trava
-- (ja_mandou, por poll_appointment_id + poll_kind, janela de 2min) pra
-- não reenviar a MESMA enquete do MESMO agendamento. Essa trigger só
-- precisa cobrir o caso que ela foi criada pra resolver: o n8n
-- inserindo uma linha SEM poll_appointment_id (echo da própria
-- mensagem enviada, confirmado no print do usuário -- a linha que o
-- n8n grava não carrega esse campo).
--
-- CORREÇÃO: só funde quando a linha nova NÃO tem poll_appointment_id
-- (NEW.poll_appointment_id IS NULL). Uma linha nova que já chega com
-- poll_appointment_id preenchido (inserida pela function) nunca é
-- fundida por essa trigger -- vira sempre uma linha própria, com o
-- vínculo certo.
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
  -- Só mexe em enquete (poll_name preenchido), mandada pelo sistema
  -- (type='atendente'), e QUE NÃO JÁ TRAZ o vínculo com o agendamento.
  -- Uma linha que já nasce com poll_appointment_id é sempre uma
  -- inserção legítima e nova (a function que a criou já tem sua
  -- própria trava contra reenvio pro MESMO agendamento) -- nunca funde.
  IF NEW.poll_name IS NULL
     OR NEW.type IS DISTINCT FROM 'atendente'
     OR NEW.poll_appointment_id IS NOT NULL THEN
    RETURN NEW;
  END IF;

  SELECT * INTO existing
    FROM public.mensagens_geral
   WHERE instancia = NEW.instancia
     AND numero = NEW.numero
     AND poll_name = NEW.poll_name
     AND type = 'atendente'
     AND created_at > now() - interval '14 days'
   ORDER BY created_at DESC
   LIMIT 1;

  IF NOT FOUND THEN
    RETURN NEW;
  END IF;

  UPDATE public.mensagens_geral SET
    id_mensagem  = COALESCE(NEW.id_mensagem, existing.id_mensagem),
    poll_options = COALESCE(NEW.poll_options, existing.poll_options),
    poll_votes   = COALESCE(NEW.poll_votes, existing.poll_votes),
    delivered_at = COALESCE(NEW.delivered_at, existing.delivered_at),
    read_at      = COALESCE(NEW.read_at, existing.read_at)
  WHERE id = existing.id;

  RAISE NOTICE 'dedupe_mensagem_enquete: enquete duplicada evitada (instancia=%, numero=%, poll=%)',
    NEW.instancia, NEW.numero, NEW.poll_name;

  RETURN NULL;
END;
$$;
