-- ============================================================================
-- CRM: não recriar como "Novo Lead" quem já passou pelo funil
-- ----------------------------------------------------------------------------
-- Portado do clinimag (70f7320), adaptado ao CliniSac.
--
-- Problema: quem insere em crm_contacts (o gatilho crm_autocreate_on_message
-- e o n8n) compara o telefone EXATO. O mesmo cliente gravado noutra grafia
-- (com/sem o 9º dígito, com/sem o 55) passa batido e vira um card duplicado
-- como "Novo Lead", mesmo já tendo sido atendido/movido/removido.
--
-- Solução: gatilho BEFORE INSERT que, se já existir card com o mesmo telefone
-- normalizado na mesma instância — em QUALQUER etapa, inclusive removido —
-- cancela o INSERT silenciosamente (0 linhas, sem erro). O card existente
-- fica onde está.
--
-- Não interfere no fluxo manual: "Adicionar Lead" já deduplica pela mesma
-- normalização (crmNormPhone, lib/phoneBR) e trata 0 linhas como "já existe";
-- mover/reviver usa UPDATE, que o gatilho não toca.
--
-- OBS n8n: se algum nó insere em crm_contacts lendo a linha de volta
-- (Prefer: return=representation + single), quando o lead for bloqueado ele
-- recebe 0 linhas. Prefira return=minimal nesse nó pra não logar "erro".
--
-- Idempotente.
-- ============================================================================

SET search_path TO public;

-- Mesma regra do frontend (lib/phoneBR.normalizePhoneDigits): só dígitos,
-- garante o 55 no BR, remove o 9º dígito do celular; número ESTRANGEIRO de 11
-- dígitos (3º dígito diferente de 9: EUA, Bolívia, Bélgica...) fica como veio,
-- e o "55"+estrangeiro gravado por engano volta pro número real.
CREATE OR REPLACE FUNCTION public.crm_norm_phone(p text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE d text;
BEGIN
  d := regexp_replace(coalesce(p, ''), '[^0-9]', '', 'g');
  IF d = '' THEN
    RETURN '';
  END IF;
  -- "55" + estrangeiro de 11 díg (gravado por engano) -> número real.
  -- (celular BR com 55 tem 13 díg e o 5º é sempre 9; fixo BR com 55 tem 12)
  IF length(d) = 13 AND left(d, 2) = '55' AND substr(d, 5, 1) <> '9' THEN
    d := substr(d, 3);
  END IF;
  -- número local BR (DDD + fone) sem o país -> prefixa 55
  IF length(d) = 10 OR (length(d) = 11 AND substr(d, 3, 1) = '9') THEN
    d := '55' || d;
  END IF;
  -- 55 + DDD(2) + 9 + 8 dígitos -> tira o 9 (canônico sem o 9)
  IF length(d) = 13 AND left(d, 2) = '55' AND substr(d, 5, 1) = '9' THEN
    d := '55' || substr(d, 3, 2) || substr(d, 6);
  END IF;
  RETURN d;
END;
$$;

CREATE OR REPLACE FUNCTION public.crm_block_reinsert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_norm text := public.crm_norm_phone(NEW.phone);
BEGIN
  IF v_norm = '' THEN
    RETURN NEW;
  END IF;
  IF EXISTS (
    SELECT 1
    FROM public.crm_contacts c
    WHERE c.instancia = NEW.instancia
      -- pré-filtro barato (os 8 últimos dígitos não mudam com 9/55) antes de
      -- normalizar, pra não rodar a função na tabela inteira a cada INSERT
      AND right(regexp_replace(coalesce(c.phone, ''), '[^0-9]', '', 'g'), 8) = right(v_norm, 8)
      AND public.crm_norm_phone(c.phone) = v_norm
  ) THEN
    -- Já passou pelo funil: não recria como novo lead.
    RETURN NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_crm_block_reinsert ON public.crm_contacts;
CREATE TRIGGER trg_crm_block_reinsert
  BEFORE INSERT ON public.crm_contacts
  FOR EACH ROW
  EXECUTE FUNCTION public.crm_block_reinsert();
