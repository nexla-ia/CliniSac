// Telas que cada usuário acessa.
//
// Admin vê tudo. Operador (viewer) tem um padrão (abaixo) e o admin da clínica
// pode abrir ou fechar telas uma a uma (users.screens guarda só as exceções:
// { financeiro: true, disparo: false }). O plano da clínica continua valendo
// por cima: tela fora do plano aparece com cadeado pra todo mundo.

export const SCREENS = [
  { key: 'conversas',  label: 'Conversas',        viewer: true },
  { key: 'instagram',  label: 'Instagram',        viewer: true },
  { key: 'grupos',     label: 'Grupos',           viewer: true },
  { key: 'alertas',    label: 'Alertas',          viewer: true },
  { key: 'contatos',   label: 'Pacientes',        viewer: true },
  { key: 'agenda',     label: 'Agenda',           viewer: true },
  { key: 'kanban',     label: 'Kanban',           viewer: true },
  { key: 'crm',        label: 'CRM',              viewer: true },
  { key: 'disparo',    label: 'Disparo',          viewer: true },
  { key: 'financeiro', label: 'Financeiro',       viewer: false },
  { key: 'catalogo',   label: 'Catálogo Clínico', viewer: false },
  { key: 'metricas',   label: 'Métricas',         viewer: false },
  { key: 'nps',        label: 'NPS',              viewer: false },
]

export function screenDefault(role, key) {
  if (role === 'admin') return true
  return SCREENS.find(s => s.key === key)?.viewer ?? true
}

// O usuário pode abrir essa tela? (sem olhar o plano — isso é isModuleOn)
export function canSeeScreen(user, key) {
  if (!user) return false
  if (user.role === 'admin') return true
  const o = user.screens?.[key]
  if (o === true || o === false) return o
  return screenDefault(user.role, key)
}

// Mapa completo { tela: boolean } do que o usuário vê hoje (pra montar o formulário).
export function screensMap(role, screens) {
  const out = {}
  for (const s of SCREENS) {
    const o = screens?.[s.key]
    out[s.key] = (o === true || o === false) ? o : screenDefault(role, s.key)
  }
  return out
}

// Só o que difere do padrão do perfil (é o que vai pro banco).
export function screensOverrides(role, map) {
  const out = {}
  for (const s of SCREENS) {
    if (map[s.key] !== screenDefault(role, s.key)) out[s.key] = !!map[s.key]
  }
  return out
}
