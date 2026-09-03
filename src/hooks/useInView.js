import { useEffect, useRef, useState } from 'react'

// Diz se um elemento entrou na tela. Usado pra disparar animações só quando
// a pessoa rola até elas — senão rodam escondidas no carregamento e ninguém
// vê. Com `once` (padrão), liga uma vez e para de observar.
export function useInView(threshold = 0.3, once = true, initial = false) {
  const ref = useRef(null)
  // `initial` evita um piscar antes da primeira medição — útil pra um
  // sentinela que já nasce visível no topo da página.
  const [inView, setInView] = useState(initial)

  useEffect(() => {
    const el = ref.current
    if (!el || typeof IntersectionObserver === 'undefined') { setInView(true); return }
    const io = new IntersectionObserver(([entry]) => {
      if (entry.isIntersecting) {
        setInView(true)
        if (once) io.disconnect()
      } else if (!once) {
        setInView(false)
      }
    }, { threshold })
    io.observe(el)
    return () => io.disconnect()
  }, [threshold, once])

  return [ref, inView]
}
