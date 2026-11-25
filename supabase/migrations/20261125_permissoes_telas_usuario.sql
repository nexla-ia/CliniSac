-- ============================================================================
-- Permissão de telas por usuário
-- ----------------------------------------------------------------------------
-- O admin da clínica escolhe, por operador, quais telas ele acessa (ex.: só um
-- operador vê o Financeiro). users.screens guarda só as EXCEÇÕES ao padrão do
-- perfil: { "financeiro": true, "disparo": false }. Sem chave = padrão.
-- Admin sempre vê tudo (o front ignora screens pra admin).
--
-- Gravação só pela RPC set_user_screens, que confere auth_can_manage_users:
-- a coluna NÃO entra no GRANT UPDATE do authenticated (etapa3c), então o
-- operador não consegue se dar acesso sozinho.
--
-- Idempotente.
-- ============================================================================

ALTER TABLE public.users ADD COLUMN IF NOT EXISTS screens jsonb;

COMMENT ON COLUMN public.users.screens IS
  'Exceções de acesso a telas por usuário ({tela: true/false}). NULL = padrão do perfil.';

CREATE OR REPLACE FUNCTION public.set_user_screens(p_user_id uuid, p_screens jsonb)
RETURNS json
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE
  v_company uuid;
  v_clean   jsonb := '{}'::jsonb;
  k         text;
  v         jsonb;
  telas     text[] := ARRAY['conversas','instagram','grupos','alertas','contatos','agenda',
                            'kanban','crm','disparo','financeiro','catalogo','metricas','nps'];
BEGIN
  SELECT company_id INTO v_company FROM public.users WHERE id = p_user_id;
  IF v_company IS NULL THEN
    RETURN json_build_object('ok', false, 'error', 'Usuário não encontrado');
  END IF;
  IF NOT public.auth_can_manage_users(v_company) THEN
    RETURN json_build_object('ok', false, 'error', 'Sem permissão para editar este usuário.');
  END IF;

  IF p_screens IS NOT NULL AND jsonb_typeof(p_screens) = 'object' THEN
    FOR k, v IN SELECT * FROM jsonb_each(p_screens) LOOP
      IF k = ANY(telas) AND jsonb_typeof(v) = 'boolean' THEN
        v_clean := v_clean || jsonb_build_object(k, v);
      END IF;
    END LOOP;
  END IF;

  UPDATE public.users SET screens = NULLIF(v_clean, '{}'::jsonb) WHERE id = p_user_id;
  RETURN json_build_object('ok', true);
END
$fn$;

REVOKE ALL ON FUNCTION public.set_user_screens(uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_user_screens(uuid, jsonb) TO authenticated, service_role;
