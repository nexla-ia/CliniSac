# CliniSac — SAC inteligente para clínicas

Plataforma de atendimento e gestão para clínicas: WhatsApp com IA, agenda, CRM,
prontuário e financeiro num painel só.

**Stack:** React 18 + Vite · React Router v6 · Supabase (Postgres + RPC) ·
Recharts · Lucide · CSS puro com variáveis (sem Tailwind, sem UI lib externa).
Deploy na Vercel.

## Estrutura de acesso

- **ADM Global** (`/adm`) — gerencia todas as clínicas, usuários, planos e billing
- **Usuário Empresa** (`/company/...`) — acessa somente os dados da clínica vinculada
- **Acesso mestre** — suporte entra numa clínica específica para dar apoio

## Rodando localmente

```bash
# 1. Variáveis de ambiente
cp .env.example .env      # preencha VITE_SUPABASE_URL e VITE_SUPABASE_ANON_KEY

# 2. Dependências
npm install

# 3. Dev server
npm run dev               # http://localhost:5173
```

O `.env` está no `.gitignore` — **nunca comite**. Os valores saem de
**Supabase → Project Settings → API**.

Outros scripts: `npm run build` (gera `dist/`) e `npm run preview`
(serve o build local).

## Banco de dados

O schema fica em [`supabase/`](supabase/). O ambiente de produção **já está
montado** — `clinisac_setup.sql` e as migrations são para provisionar um
projeto Supabase **novo do zero**; não rode contra um banco já configurado.

Autenticação não usa o Supabase Auth: é feita por RPC própria (`login_user`),
com hash de senha fechado no banco e controle de sessão única por usuário
(`login_session`).

## Deploy

Passo a passo (import na Vercel, environment variables, redeploy e
troubleshooting): [`docs/DEPLOY.md`](docs/DEPLOY.md).

Resumo: push em `master` → deploy de produção automático. As variáveis
`VITE_*` são lidas em build time, então mudança de env var exige redeploy.

## Primeiro uso

Após o deploy: logar na aba **ADM Global** com o usuário administrador e
cadastrar a **primeira clínica** em `/adm → Empresas`. As credenciais do ADM são
entregues fora do repositório.

## Documentação

- [`docs/DEPLOY.md`](docs/DEPLOY.md) — deploy na Vercel
- [`docs/API.md`](docs/API.md) — endpoints e integrações
- [`docs/plataforma-whatsapp.md`](docs/plataforma-whatsapp.md) — visão da plataforma

## Pendências conhecidas

- **Isolamento multi-tenant (Fase 1 de segurança):** ligar o `login_session`
  ("crachá") no front para RLS por clínica — passo separado e delicado.
- **Webhooks n8n / Evolution API:** as URLs no código ainda apontam para a
  infraestrutura antiga; trocar quando o CliniSac tiver as suas.
