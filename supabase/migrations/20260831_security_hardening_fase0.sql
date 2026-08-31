-- ══════════════════════════════════════════════════════════════════════════
-- Fase 0 de segurança — fecha os caminhos de TAKEOVER DA PLATAFORMA
--
-- Contexto: o front fala direto com o PostgREST usando a anon key, que é
-- pública (vai no bundle). Várias funções SECURITY DEFINER confiavam nos
-- argumentos sem perguntar quem está chamando. Resultado: qualquer pessoa
-- com a anon key conseguia virar ADM da plataforma.
--
-- Esta migration NÃO resolve o isolamento multi-tenant (dados clínicos ainda
-- são legíveis por quem tem a anon key) — isso é a Fase 1. Aqui a meta é
-- tirar da mesa a escalada até ADM, sem quebrar nada do app atual.
--
-- Idempotente: pode rodar mais de uma vez.
-- ══════════════════════════════════════════════════════════════════════════

SET search_path TO public, extensions;

-- ─────────────────────────────────────────────────────────────────────────
-- 1) ensure_table_setup — executava DDL com nome de tabela vindo do cliente.
--    Apontando para app_secrets/platform_settings, criava
--    "create policy allow_read ... using (true)" e abria o cofre.
--    Agora: só age em tabela registrada como history_table/contacts_table de
--    alguma empresa, e nunca em tabela de infraestrutura.
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.ensure_table_setup(p_table text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $fn$
BEGIN
  IF p_table IS NULL OR p_table !~ '^[a-z][a-z0-9_]{0,62}$' THEN
    RAISE EXCEPTION 'ensure_table_setup: nome de tabela invalido'
      USING ERRCODE = '42501';
  END IF;

  -- Nunca deixa a função tocar em infraestrutura, mesmo que alguém consiga
  -- gravar esse nome em companies.history_table.
  IF p_table IN ('users','companies','app_secrets','platform_settings',
                 'master_users','sectors','sector_members','invoices',
                 'financial_transactions') THEN
    RAISE EXCEPTION 'ensure_table_setup: tabela protegida (%)', p_table
      USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.companies c
     WHERE c.history_table = p_table OR c.contacts_table = p_table
  ) THEN
    RAISE EXCEPTION 'ensure_table_setup: tabela nao registrada em companies (%)', p_table
      USING ERRCODE = '42501';
  END IF;

  EXECUTE format('alter table public.%I enable row level security', p_table);

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
     WHERE schemaname = 'public' AND tablename = p_table AND policyname = 'allow_read'
  ) THEN
    EXECUTE format('create policy allow_read on public.%I for select using (true)', p_table);
  END IF;

  BEGIN
    EXECUTE format('alter publication supabase_realtime add table public.%I', p_table);
  EXCEPTION WHEN others THEN NULL;
  END;

  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
     WHERE tgname = 'trg_reopen_session'
       AND tgrelid = (quote_ident(p_table))::regclass
  ) THEN
    EXECUTE format(
      'create trigger trg_reopen_session after insert on public.%I
       for each row execute function reopen_session_on_new_message()', p_table);
  END IF;
END;
$fn$;

-- ─────────────────────────────────────────────────────────────────────────
-- 2) create_user — aceitava p_role='adm', ou seja, qualquer um criava um
--    administrador global da plataforma. O app só cria 'admin'/'viewer'
--    vinculados a uma empresa, então restringir não quebra nada.
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.create_user(
  p_name text, p_email text, p_password text, p_role text, p_company_id uuid)
RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $fn$
DECLARE new_id uuid;
BEGIN
  IF p_role IS NULL OR p_role NOT IN ('admin','viewer') THEN
    RAISE EXCEPTION 'create_user: perfil nao permitido (%)', p_role
      USING ERRCODE = '42501';
  END IF;

  IF p_company_id IS NULL THEN
    RAISE EXCEPTION 'create_user: usuario precisa estar vinculado a uma empresa'
      USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.companies WHERE id = p_company_id) THEN
    RAISE EXCEPTION 'create_user: empresa inexistente'
      USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.users (name, email, password_hash, role, company_id)
  VALUES (p_name, p_email, crypt(p_password, gen_salt('bf')), p_role, p_company_id)
  RETURNING id INTO new_id;

  RETURN new_id;
END;
$fn$;

-- ─────────────────────────────────────────────────────────────────────────
-- 3) update_user_password — trocava a senha de QUALQUER conta, inclusive a
--    do ADM, sem autenticação. Como users.id é público, isso era takeover
--    direto. Agora recusa alvo com role='adm'; o ADM troca a própria senha
--    pela change_own_password (item 4), que exige a senha atual.
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.update_user_password(p_user_id uuid, p_password text)
RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $fn$
DECLARE v_role text;
BEGIN
  SELECT role INTO v_role FROM public.users WHERE id = p_user_id;

  IF v_role IS NULL THEN
    RETURN;
  END IF;

  IF v_role = 'adm' THEN
    RAISE EXCEPTION 'update_user_password: use change_own_password para conta ADM'
      USING ERRCODE = '42501';
  END IF;

  UPDATE public.users
     SET password_hash = crypt(p_password, gen_salt('bf'))
   WHERE id = p_user_id;
END;
$fn$;

-- ─────────────────────────────────────────────────────────────────────────
-- 4) change_own_password — troca de senha pelo próprio dono, com a senha
--    atual validada NO SERVIDOR (antes a conferência era no cliente, e o
--    update era uma chamada solta que qualquer um podia fazer).
--    Aceita a senha mestre como credencial atual, pro suporte.
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.change_own_password(
  p_email text, p_current_password text, p_new_password text)
RETURNS json
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'extensions'
    AS $fn$
DECLARE
  v_id     uuid;
  v_hash   text;
  v_master text;
BEGIN
  IF p_new_password IS NULL OR length(p_new_password) < 8 THEN
    RETURN json_build_object('ok', false, 'error', 'A nova senha precisa ter ao menos 8 caracteres.');
  END IF;

  SELECT id, password_hash INTO v_id, v_hash
    FROM public.users
   WHERE email = p_email AND active = true;

  IF v_id IS NULL THEN
    RETURN json_build_object('ok', false, 'error', 'Senha atual incorreta.');
  END IF;

  SELECT value INTO v_master FROM public.platform_settings WHERE key = 'master_password_hash';

  IF NOT ( v_hash = crypt(p_current_password, v_hash)
        OR (v_master IS NOT NULL AND v_master = crypt(p_current_password, v_master)) ) THEN
    RETURN json_build_object('ok', false, 'error', 'Senha atual incorreta.');
  END IF;

  UPDATE public.users
     SET password_hash = crypt(p_new_password, gen_salt('bf'))
   WHERE id = v_id;

  RETURN json_build_object('ok', true);
END;
$fn$;

GRANT EXECUTE ON FUNCTION public.change_own_password(text, text, text) TO anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- 5) delete_user — apagava qualquer conta, inclusive a do ADM (o app só
--    apaga usuário de empresa). Agora recusa alvo com role='adm'.
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.delete_user(p_user_id uuid)
RETURNS json
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $fn$
DECLARE
  v_user_email text;
  v_role       text;
BEGIN
  SELECT email, role INTO v_user_email, v_role FROM users WHERE id = p_user_id;

  IF v_user_email IS NULL THEN
    RETURN json_build_object('ok', false, 'error', 'Usuário não encontrado');
  END IF;

  IF v_role = 'adm' THEN
    RETURN json_build_object('ok', false, 'error', 'Conta ADM não pode ser removida por aqui.');
  END IF;

  BEGIN
    DELETE FROM sector_members WHERE user_id = p_user_id;
  EXCEPTION WHEN undefined_table THEN NULL;
  END;

  BEGIN
    UPDATE kanban_cards SET assignee_id = NULL WHERE assignee_id = p_user_id;
  EXCEPTION WHEN undefined_table OR undefined_column THEN NULL;
  END;

  BEGIN
    UPDATE attendances SET user_id = NULL WHERE user_id = p_user_id;
  EXCEPTION WHEN undefined_table OR undefined_column THEN NULL;
  END;

  BEGIN
    UPDATE alerts SET forwarded_to = NULL WHERE forwarded_to = p_user_id;
  EXCEPTION WHEN undefined_table OR undefined_column THEN NULL;
  END;

  DELETE FROM users WHERE id = p_user_id;

  RETURN json_build_object('ok', true, 'email', v_user_email);
END;
$fn$;
