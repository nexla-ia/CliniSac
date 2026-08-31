/**
 * BrandMark — Logo CliniSac
 * Balão de conversa (o SAC/atendimento) com a cruz de saúde (a clínica),
 * em degradê teal→azul. Props 'color'/'strokeWidth' são ignoradas (mantidas
 * só por compat com chamadas antigas).
 */
export default function BrandMark({ size = 32 }) {
  return (
    <svg width={size} height={size} viewBox="0 0 64 64" fill="none" aria-label="CliniSac">
      <defs>
        <linearGradient id="cs-brand" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#13B7A6" />
          <stop offset="1" stopColor="#2C6BEF" />
        </linearGradient>
      </defs>
      {/* Balão de conversa (com a cauda no canto inferior esquerdo) */}
      <path
        d="M17 8 H47 A11 11 0 0 1 58 19 V33 A11 11 0 0 1 47 44 H30 L20 53 V44 H17 A11 11 0 0 1 6 33 V19 A11 11 0 0 1 17 8 Z"
        fill="url(#cs-brand)"
      />
      {/* Cruz de saúde */}
      <rect x="28.5" y="14" width="7" height="24" rx="3.5" fill="#fff" />
      <rect x="20" y="22.5" width="24" height="7" rx="3.5" fill="#fff" />
    </svg>
  )
}
