// ────────────────────────────────────────────────────────────────────────────
// Plan limits — fonte única de verdade
//
// Cada plano tem:
//   - Limites quantitativos (profissionais, usuários, agendas, etc)
//   - Feature flags (métricas avançadas, round-robin, etc)
//   - Módulos que o plano não inclui (locked_modules)
//
// As empresas podem ter overrides individuais em `companies` (ex: extra_users
// pra add-on de R$49/usuário, ou max_professionals customizado pra cliente
// especial). Quando o override for null, cai no default do plano.
// ────────────────────────────────────────────────────────────────────────────

export const UNLIMITED = Infinity

// Defaults por plano. UNLIMITED = sem limite.
// locked_modules: módulos que o plano NÃO inclui (aparecem com cadeado). O ADM
// pode liberar ou bloquear um módulo à parte por empresa (companies.modules).
export const PLAN_DEFAULTS = {
  Base: {
    label: 'Plano Base',
    price: 200,
    professionals: 3,
    users: 3,
    agendas: 1,
    whatsapp_instances: 1,
    instagram_accounts: 0,
    // feature flags
    advanced_metrics: false,    // abas avançadas, histórico completo, exportação
    round_robin: false,
    hsm_templates: false,
    multi_filial_compare: false,
    ia_posts: false,
    ia_laudos: false,
    api_custom: false,
    // Financeiro e as automações da jornada (NPS pós-consulta e Disparo) são do
    // Plano Completo. Métricas entra no Base só com as abas básicas, até o mês
    // atual e sem exportar (advanced_metrics = false).
    locked_modules: ['financeiro', 'nps', 'disparo'],
  },
  Completo: {
    label: 'Plano Completo',
    price: 359,
    professionals: 25,
    users: UNLIMITED,
    agendas: UNLIMITED,
    whatsapp_instances: 1,
    instagram_accounts: 1,
    advanced_metrics: true,
    round_robin: true,
    hsm_templates: true,
    multi_filial_compare: false,
    ia_posts: false,
    ia_laudos: false,
    api_custom: false,
    locked_modules: [],
  },
  Business: {
    label: 'Business',
    price: null, // sob medida
    professionals: UNLIMITED,
    users: UNLIMITED,
    agendas: UNLIMITED,
    whatsapp_instances: UNLIMITED,
    instagram_accounts: UNLIMITED,
    advanced_metrics: true,
    round_robin: true,
    hsm_templates: true,
    multi_filial_compare: true,
    ia_posts: true,        // Em breve
    ia_laudos: true,       // Em breve
    api_custom: true,
    locked_modules: [],
  },
}

export const PLAN_NAMES = ['Base', 'Completo', 'Business']

// Nomes antigos que ainda podem estar gravados em companies.plan.
// Trial (7 dias grátis) testa com tudo liberado.
const PLAN_ALIASES = { Starter: 'Base', Pro: 'Completo', Trial: 'Completo' }

// Chave do plano efetivo (Base / Completo / Business) a partir do valor gravado.
export function resolvePlan(plan) {
  if (plan && PLAN_DEFAULTS[plan]) return plan
  return PLAN_ALIASES[plan] || 'Base'
}

// Nome pra mostrar (Trial continua aparecendo como Trial).
export function planLabel(plan) {
  if (plan === 'Trial') return 'Trial'
  return PLAN_DEFAULTS[resolvePlan(plan)].label
}

// Add-on de usuário extra: R$ 49/mês cada (Plano Base)
export const ADDON_USER_PRICE = 49

// Módulo ligado pra empresa? Override do ADM (true/false em companies.modules)
// vence; sem override, vale o que o plano inclui.
export function planIncludesModule(plan, key) {
  return !PLAN_DEFAULTS[resolvePlan(plan)].locked_modules.includes(key)
}
export function isModuleOn(company, key) {
  const o = company?.modules?.[key]
  if (o === true || o === false) return o
  return planIncludesModule(company?.plan, key)
}

// Resolve os limites efetivos pra uma empresa específica (plano + overrides).
// Retorna sempre um objeto com TODOS os campos resolvidos.
export function getEffectiveLimits(company) {
  if (!company) return { ...PLAN_DEFAULTS.Base, plan: 'Base', extra_users: 0 }
  const plan = resolvePlan(company.plan)
  const defaults = PLAN_DEFAULTS[plan]

  const extraUsers = Number(company.extra_users || 0)
  const overrideMaxUsers = company.max_users != null && company.max_users > 0 ? Number(company.max_users) : null

  return {
    ...defaults,
    plan,
    // max_users: usa override se existir; senão default + extra_users
    users: overrideMaxUsers ?? (defaults.users === UNLIMITED ? UNLIMITED : defaults.users + extraUsers),
    extra_users: extraUsers,
    // overrides opcionais (nullable nas colunas do banco)
    professionals: company.max_professionals ?? defaults.professionals,
    agendas: company.max_agendas ?? defaults.agendas,
  }
}

// Helpers de check
export function reachedLimit(current, limit) {
  if (limit === UNLIMITED) return false
  return Number(current) >= Number(limit)
}

export function formatLimit(limit) {
  return limit === UNLIMITED ? 'ilimitado' : String(limit)
}

// Mensagens de upgrade — usadas no LimitReachedModal
export function upgradeMessage(resource, limit, planName) {
  const messages = {
    professionals: {
      title: 'Limite de profissionais atingido',
      body: `Seu plano cobre até ${formatLimit(limit)} profissionais cadastrados. Pra liberar mais, fale com o time.`,
      cta: 'Falar com o time',
    },
    users: {
      title: 'Limite de usuários atingido',
      body: `Seu plano cobre ${formatLimit(limit)} usuários. Você pode adicionar usuários extras (R$ ${ADDON_USER_PRICE}/mês cada) ou passar pro Plano Completo, com usuários ilimitados.`,
      cta: 'Falar com o time',
    },
    agendas: {
      title: 'Limite de agendas atingido',
      body: `Seu plano cobre ${formatLimit(limit)} agenda${limit > 1 ? 's' : ''}. No Plano Completo elas são ilimitadas. Fale com a gente pra mudar de plano.`,
      cta: 'Falar com o time',
    },
    instagram: {
      title: 'Instagram disponível no Plano Completo',
      body: 'O Instagram unificado está disponível no Plano Completo. Fale com a gente pra ativar.',
      cta: 'Falar com o time',
    },
    advanced_metrics: {
      title: 'Disponível no Plano Completo',
      body: 'No Plano Completo você vê também Equipe, Leads, NPS, a jornada e o valor de cada paciente, o histórico completo (qualquer período) e pode exportar os relatórios em PDF.',
      cta: 'Falar com o time',
    },
  }
  return messages[resource] || {
    title: 'Recurso indisponível no seu plano',
    body: 'Seu plano não inclui esse recurso. Fale com a gente pra mudar de plano.',
    cta: 'Falar com o time',
  }
}
