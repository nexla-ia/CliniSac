-- ==============================================================
-- Enquete de confirmação → muda o status do agendamento sozinho
--
-- Quando o n8n grava o voto (UPDATE em mensagens_geral — no poll_votes
-- OU direto em poll_options com "voters" embutido, os dois formatos
-- que a plataforma já lê, ver docs/plataforma-whatsapp.md §3.7), este
-- trigger confere qual das 3 opções FIXAS (Confirmar/Remarcar/Cancelar)
-- tem voto e avança o agendamento vinculado (poll_appointment_id):
--   "Confirmar" → status = 'confirmado'
--   "Cancelar"  → status = 'cancelado'
--   "Remarcar"  → não muda status sozinho (sem destino óbvio; fica só
--                 registrado no voto — dá pra ligar um alerta pra
--                 recepção depois, com api_alert_create)
--
-- Reavalia do zero a cada UPDATE (não incremental), então cobre o
-- paciente TROCAR o voto (ex.: confirmou e depois cancelou) — o
-- pollUpdates da Evolution já manda o estado atual completo por opção.
-- Só mexe se o status atual ainda for 'agendado'/'confirmado'/
-- 'cancelado' (não sobrescreve 'concluido'/'faltou', que são decisão
-- da clínica). Blindado com EXCEPTION: nunca trava o UPDATE da
-- mensagem.
--
-- Idempotente. Cole no SQL Editor do Supabase.
-- ==============================================================

SET search_path TO public;

CREATE OR REPLACE FUNCTION public.apply_poll_vote_to_appointment()
RETURNS trigger LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
DECLARE
  confirm_votes integer;
  cancel_votes  integer;
  target_status text;
BEGIN
  IF NEW.poll_appointment_id IS NULL THEN RETURN NEW; END IF;
  IF NEW.poll_votes IS NOT DISTINCT FROM OLD.poll_votes
     AND NEW.poll_options IS NOT DISTINCT FROM OLD.poll_options THEN
    RETURN NEW;
  END IF;

  -- Soma os votos (em poll_votes OU poll_options) de cada opção fixa.
  -- Aceita voters:[...] (Evolution) ou votes:N (formato que a RPC
  -- send_mensagem_geral inicializa).
  SELECT
    COALESCE(SUM(CASE WHEN lower(btrim(COALESCE(x ->> 'option', x ->> 'optionName', x ->> 'name', ''))) = 'confirmar'
      THEN (CASE WHEN jsonb_typeof(x -> 'voters') = 'array' THEN jsonb_array_length(x -> 'voters')
                 WHEN (x ->> 'votes') ~ '^\d+$' THEN (x ->> 'votes')::int ELSE 0 END)
      ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN lower(btrim(COALESCE(x ->> 'option', x ->> 'optionName', x ->> 'name', ''))) = 'cancelar'
      THEN (CASE WHEN jsonb_typeof(x -> 'voters') = 'array' THEN jsonb_array_length(x -> 'voters')
                 WHEN (x ->> 'votes') ~ '^\d+$' THEN (x ->> 'votes')::int ELSE 0 END)
      ELSE 0 END), 0)
  INTO confirm_votes, cancel_votes
  FROM jsonb_array_elements(
    COALESCE(NEW.poll_votes, '[]'::jsonb) || COALESCE(NEW.poll_options, '[]'::jsonb)
  ) x;

  target_status := CASE
    WHEN cancel_votes > 0 AND confirm_votes = 0 THEN 'cancelado'
    WHEN confirm_votes > 0 AND cancel_votes = 0 THEN 'confirmado'
    ELSE NULL
  END;

  IF target_status IS NOT NULL THEN
    UPDATE public.appointments
       SET status = target_status
     WHERE id = NEW.poll_appointment_id
       AND status IN ('agendado', 'confirmado', 'cancelado');
  END IF;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_poll_vote_to_appointment ON public.mensagens_geral;
CREATE TRIGGER trg_poll_vote_to_appointment
  AFTER UPDATE OF poll_votes, poll_options ON public.mensagens_geral
  FOR EACH ROW
  WHEN (NEW.poll_appointment_id IS NOT NULL)
  EXECUTE FUNCTION public.apply_poll_vote_to_appointment();
