import { createClient } from '@supabase/supabase-js'

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY

// ─── Sessão que venceu sem renovar ────────────────────────────────────────
// O crachá (JWT) do login vale 1h e o supabase-js renova sozinho — calculando
// a hora pelo RELÓGIO DO COMPUTADOR. Com o relógio errado (ou a renovação
// falhando), o crachá vence no servidor e toda consulta volta 401: a tela fica
// só com o layout, sem dado nenhum, e recarregar não resolve (só sair/entrar).
//
// Aqui: ao receber 401 de crachá inválido/vencido, renova a sessão UMA vez
// (compartilhada entre as consultas que falharem juntas) e repete a consulta
// com o crachá novo. Se nem a renovação der certo, avisa o app pra deslogar.
let client = null
let refreshing = null

function refreshOnce() {
  if (!refreshing) {
    refreshing = client.auth.refreshSession()
      .catch(error => ({ data: null, error }))
      .finally(() => { setTimeout(() => { refreshing = null }, 2000) })
  }
  return refreshing
}

async function resilientFetch(input, init = {}) {
  const res = await fetch(input, init)
  if (res.status !== 401 || !client) return res
  const url = typeof input === 'string' ? input : (input?.url || '')
  if (url.includes('/auth/v1/')) return res            // a própria renovação
  const body = await res.clone().text().catch(() => '')
  if (!/PGRST30\d|JWT/i.test(body)) return res          // 401 por outro motivo
  const { data, error } = await refreshOnce()
  const token = data?.session?.access_token
  if (error || !token) {
    try { window.dispatchEvent(new CustomEvent('nx-auth-expired')) } catch {}
    return res
  }
  const headers = new Headers(init.headers || (typeof input !== 'string' ? input?.headers : undefined))
  headers.set('Authorization', `Bearer ${token}`)
  return fetch(input, { ...init, headers })
}

export const supabase = client = createClient(supabaseUrl, supabaseAnonKey, {
  global: { fetch: resilientFetch },
})
