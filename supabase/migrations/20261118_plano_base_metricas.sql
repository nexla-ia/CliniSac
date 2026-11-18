-- ============================================================================
-- Plano Base passa a ter Métricas (só as abas básicas, até o mês atual e sem
-- exportar; o resto continua no Plano Completo). Financeiro, NPS e Disparo
-- seguem travados no Base.
--
-- Atualiza company_module_on (usada pelo n8n) pra mesma regra do front
-- (locked_modules em src/lib/planLimits.js). Idempotente.
-- ============================================================================

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
         then p_key not in ('financeiro', 'nps', 'disparo')
       else true
     end
     from public.companies c
     where c.instance = p_instancia
     limit 1),
    false)
$$;

revoke all on function public.company_module_on(text, text) from public, anon;
grant execute on function public.company_module_on(text, text) to service_role;
