-- ==============================================================
-- A trigger trg_dedupe_mensagem_enquete (20261105_trigger_funde_
-- enquete_duplicada.sql) usava janela de 3 minutos pra considerar
-- "é a mesma enquete voltando". Isso cobre o eco imediato do envio,
-- mas o print do usuário mostrou o caso real: as DUAS linhas têm o
-- mesmo texto/horário só que com votos DIFERENTES (0 e depois 1) --
-- ou seja, a segunda linha não é um eco do envio, é o n8n registrando
-- o VOTO do paciente como uma linha NOVA em vez de dar UPDATE na
-- linha original (provavelmente porque o id_mensagem/match que ele
-- usa pra achar a linha original falha). Um voto pode chegar minutos,
-- horas ou até dias depois do envio -- 3 minutos não cobre isso.
--
-- Amplia a janela pra 14 dias (bem mais que qualquer prazo razoável de
-- resposta a um lembrete de consulta) -- risco de colisão falsa é
-- desprezível, já que o match exige instancia+numero+poll_name iguais
-- (poll_name já carrega a data/hora específica do agendamento; duas
-- consultas distintas do mesmo paciente caindo no mesmo texto exato
-- dentro de 14 dias seria, na prática, a própria duplicata que a
-- gente quer travar).
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
  IF NEW.poll_name IS NULL OR NEW.type IS DISTINCT FROM 'atendente' THEN
    RETURN NEW;
  END IF;

  SELECT * INTO existing
    FROM public.mensagens_geral
   WHERE instancia = NEW.instancia
     AND numero = NEW.numero
     AND poll_name = NEW.poll_name
     AND type = 'atendente'
     AND created_at > now() - interval '14 days'
   ORDER BY created_at ASC
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
