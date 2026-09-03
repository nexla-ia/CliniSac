import { useEffect, useRef } from 'react'
import { supabase } from '../lib/supabase'

function getDevice() {
  const w = window.innerWidth
  if (w < 768) return 'mobile'
  if (w < 1024) return 'tablet'
  return 'desktop'
}

function getUTM(key) {
  try { return new URLSearchParams(window.location.search).get(key) || null }
  catch { return null }
}

// Seções rastreadas: seletor na landing → chave de dado.
// Os seletores apontam pros ids/classes reais de src/pages/LandingPage.jsx;
// as chaves são o que fica salvo em landing_analytics.section_times e o que
// a tela ADM "Landing Page" usa como rótulo (ela importa este array).
const SECTIONS = [
  { selector: '.lp-hero',      key: 'hero',           label: 'Hero' },
  { selector: '.lp-strip',     key: 'stats',          label: 'Faixa de prova' },
  { selector: '#problema',     key: 'problema',       label: 'Problema / solução' },
  { selector: '#recursos',     key: 'recursos',       label: 'A plataforma' },
  { selector: '#automacoes',   key: 'automacoes',     label: 'Automações' },
  { selector: '#como-funciona',key: 'como-funciona',  label: 'Como funciona' },
  { selector: '#pra-quem',     key: 'para-quem',      label: 'Pra quem é' },
  { selector: '#depoimento',   key: 'testimonial',    label: 'Depoimento' },
  { selector: '#planos',       key: 'planos',         label: 'Planos' },
  { selector: '#faq',          key: 'faq',            label: 'Dúvidas' },
  { selector: '.lp-cta',       key: 'cta',            label: 'CTA Final' },
]

export { SECTIONS }

export function useLandingAnalytics() {
  const sessionId   = useRef(
    typeof crypto !== 'undefined' && crypto.randomUUID
      ? crypto.randomUUID()
      : Math.random().toString(36).slice(2)
  )
  const startTime   = useRef(Date.now())
  const scrollDepth = useRef(0)
  const ctaClicked  = useRef(false)
  const inserted    = useRef(false)
  // section key → accumulated ms
  const sectionTimes = useRef({})
  // section key → timestamp when entered viewport
  const sectionEnter = useRef({})

  useEffect(() => {
    // Insert session record
    supabase.from('landing_analytics').insert({
      session_id:   sessionId.current,
      referrer:     document.referrer || null,
      utm_source:   getUTM('utm_source'),
      utm_medium:   getUTM('utm_medium'),
      utm_campaign: getUTM('utm_campaign'),
      device:       getDevice(),
    }).then(() => { inserted.current = true })

    // Scroll depth. Escuta em CAPTURA na window: o evento scroll não borbulha,
    // mas a captura pega o scroll de qualquer elemento — e aqui quem rola é o
    // #root (height:100% + overflow no global.css), não a janela; ler
    // document.documentElement.scrollTop devolveria 0 pra sempre.
    function onScroll(e) {
      const t  = e?.target
      const el = (!t || t === document || t === window) ? document.scrollingElement : t
      if (!el || typeof el.scrollTop !== 'number') return
      const max = el.scrollHeight - el.clientHeight
      if (max <= 0) return
      const pct = Math.round((el.scrollTop / max) * 100)
      if (pct > scrollDepth.current) scrollDepth.current = Math.min(pct, 100)
    }
    window.addEventListener('scroll', onScroll, { passive: true, capture: true })

    // Per-section time tracking via IntersectionObserver
    const observer = new IntersectionObserver(entries => {
      entries.forEach(entry => {
        const key = entry.target.dataset.analyticsSection
        if (!key) return
        if (entry.isIntersecting) {
          sectionEnter.current[key] = Date.now()
        } else if (sectionEnter.current[key]) {
          const elapsed = Date.now() - sectionEnter.current[key]
          sectionTimes.current[key] = (sectionTimes.current[key] || 0) + elapsed
          delete sectionEnter.current[key]
        }
      })
    }, { threshold: 0.3 })

    // Tag and observe each section element
    SECTIONS.forEach(({ selector, key }) => {
      const el = document.querySelector(selector)
      if (el) {
        el.dataset.analyticsSection = key
        observer.observe(el)
      }
    })

    // Flush: accumulate any currently-visible sections before saving
    function flush() {
      if (!inserted.current) return
      const now = Date.now()
      // Finalize any sections still in viewport
      Object.entries(sectionEnter.current).forEach(([key, ts]) => {
        sectionTimes.current[key] = (sectionTimes.current[key] || 0) + (now - ts)
        sectionEnter.current[key] = now // reset so next flush continues accumulating
      })
      supabase.from('landing_analytics').update({
        duration_ms:   now - startTime.current,
        scroll_depth:  scrollDepth.current,
        cta_clicked:   ctaClicked.current,
        section_times: Object.keys(sectionTimes.current).length ? sectionTimes.current : null,
        updated_at:    new Date().toISOString(),
      }).eq('session_id', sessionId.current).then(() => {})
    }

    const iv = setInterval(flush, 30_000)
    window.addEventListener('beforeunload', flush)

    return () => {
      window.removeEventListener('scroll', onScroll, { capture: true })
      window.removeEventListener('beforeunload', flush)
      clearInterval(iv)
      observer.disconnect()
      flush()
    }
  }, [])

  function trackCTA() { ctaClicked.current = true }
  return { trackCTA }
}
