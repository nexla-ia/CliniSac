import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// URL pública do site, usada nas tags Open Graph do index.html
// (%VITE_SITE_URL%). Configure em Vercel → Environment Variables. Sem ela,
// cai em vazio e as tags viram caminho relativo (/og.png) — funciona na
// maioria dos scrapers, mas a absoluta é a garantida.
process.env.VITE_SITE_URL ??= ''

export default defineConfig({
  plugins: [react()],
  optimizeDeps: {
    include: ['recharts', 'recharts/es6/index'],
  },
  build: {
    commonjsOptions: {
      include: [/recharts/, /node_modules/],
    },
    rollupOptions: {
      output: {
        // Separa as libs pesadas em chunks próprios: melhora cache de longo
        // prazo e tira peso do bundle inicial (login).
        manualChunks: {
          react: ['react', 'react-dom', 'react-router-dom'],
          charts: ['recharts'],
          emoji: ['emoji-picker-react'],
          supabase: ['@supabase/supabase-js'],
        },
      },
    },
  },
})
