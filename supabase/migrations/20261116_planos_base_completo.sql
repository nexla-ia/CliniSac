-- ============================================================================
-- Planos novos: Base (R$ 200) e Completo (R$ 359)
-- ----------------------------------------------------------------------------
-- Base:     3 usuários (+R$ 49 por extra), 3 profissionais, 1 agenda.
--           Sem Financeiro, Métricas, NPS pós-consulta e Disparo.
-- Completo: usuários ilimitados, tudo liberado.
-- Business continua (sob medida) e Trial testa como Completo.
--
-- Starter vira Base e Pro vira Completo. O front já entende os nomes antigos
-- (src/lib/planLimits.js), mas o ADM passa a gravar 'Base'/'Completo', por isso
-- esta migration precisa rodar ANTES do deploy (senão a trava de plano recusa).
--
-- Módulos: companies.modules guarda só as exceções do ADM (true = liberado à
-- parte, false = bloqueado à parte). Sem chave = o que o plano inclui.
--
-- Idempotente.
-- ============================================================================

-- 1) Trava de valores do plano (aceita os nomes antigos por segurança)
alter table public.companies drop constraint if exists companies_plan_check;
alter table public.companies add constraint companies_plan_check
  check (plan = any (array['Base','Completo','Business','Trial','Starter','Pro']));

-- 2) Migra os nomes antigos
update public.companies set plan = 'Base'     where plan = 'Starter';
update public.companies set plan = 'Completo' where plan = 'Pro';

alter table public.companies alter column plan set default 'Base';

comment on column public.companies.extra_users
  is 'Add-on de usuários extras (R$49 cada) somados aos inclusos no plano';

-- 3) Limite de usuários no banco (espelha PLAN_DEFAULTS)
create or replace function check_user_limit()
returns trigger language plpgsql as $$
declare
  co      record;
  max_u   int;
  curr_u  int;
  plan_max int;
begin
  select * into co from companies where id = new.company_id;
  if not found then return new; end if;

  -- Limite efetivo: override direto tem prioridade; senão, default do plano + extras
  if co.max_users is not null and co.max_users > 0 then
    max_u := co.max_users;
  else
    plan_max := case co.plan
      when 'Base'     then 3
      when 'Starter'  then 3
      when 'Completo' then null
      when 'Pro'      then null
      when 'Business' then null
      when 'Trial'    then null
      else 3
    end;
    if plan_max is null then return new; end if; -- ilimitado
    max_u := plan_max + coalesce(co.extra_users, 0);
  end if;

  select count(*) into curr_u
    from users
    where company_id = new.company_id
      and active is not false;

  if curr_u >= max_u then
    raise exception 'Limite de usuários atingido para esta empresa (máx: %). Contrate usuários extras ou passe para o Plano Completo.', max_u;
  end if;

  return new;
end;
$$;

-- 4) Módulo ligado pra empresa? Pro n8n checar antes de mandar NPS ou disparo:
--      select public.company_module_on('<instancia>', 'nps')
--    Mesma regra do front (isModuleOn em src/lib/planLimits.js).
create or replace function public.company_module_on(p_instancia text, p_key text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select case
       when c.modules ? p_key and jsonb_typeof(c.modules -> p_key) = 'boolean'
         then (c.modules ->> p_key)::boolean
       when c.plan in ('Base', 'Starter')
         then p_key not in ('financeiro', 'metricas', 'nps', 'disparo')
       else true
     end
     from public.companies c
     where c.instance = p_instancia
     limit 1),
    false)
$$;

revoke all on function public.company_module_on(text, text) from public, anon;
grant execute on function public.company_module_on(text, text) to service_role;
