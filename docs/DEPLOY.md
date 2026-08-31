# Deploy na Vercel — CliniSac

Front-end estático (Vite + React) servido pela Vercel; o back-end é o Supabase.
Não há servidor Node em produção.

## 1. Conectar o repositório

1. Acesse <https://vercel.com/new> (logue com a conta GitHub que tem acesso à org **nexla-ia**).
2. Em **Import Git Repository**, escolha **nexla-ia/CliniSac** → **Import**.
   - Se o repo não aparecer: **Adjust GitHub App Permissions** → dê acesso da
     Vercel à org `nexla-ia` (ou ao repo CliniSac especificamente).
3. Confirme as configurações de build (a Vercel detecta sozinha):

   | Campo             | Valor           |
   |-------------------|-----------------|
   | Framework Preset  | **Vite**        |
   | Build Command     | `npm run build` |
   | Output Directory  | `dist`          |
   | Install Command   | `npm install`   |
   | Root Directory    | `./`            |

   O `vercel.json` já traz o rewrite de SPA (`/(.*) → /index.html`), necessário
   para o React Router não dar 404 em refresh de rota interna.

## 2. Environment Variables

Ainda na tela de import (ou depois em **Settings → Environment Variables**),
adicione as duas variáveis, marcando os três ambientes
(**Production**, **Preview**, **Development**):

| Name                     | Value                                        |
|--------------------------|----------------------------------------------|
| `VITE_SUPABASE_URL`      | URL do projeto Supabase                      |
| `VITE_SUPABASE_ANON_KEY` | anon/public key do projeto Supabase          |

Os valores são os mesmos do `.env` local — veja `.env.example` para o formato.
Pegue-os em **Supabase → Project Settings → API**.

> A `anon key` é pública por natureza (vai no bundle do navegador); o que protege
> os dados é o RLS/as funções do banco. Ainda assim, **nunca** coloque a
> `service_role` key aqui nem no `.env` — ela não é usada pelo front.

**Importante:** variáveis `VITE_*` são lidas em *build time*. Se você alterar uma
delas depois, precisa **redeployar** para o novo valor entrar no bundle.

## 3. Deploy

- **Deploy** na tela de import dispara o primeiro build.
- Depois disso, todo `git push` para **master** gera deploy de produção
  automaticamente; PRs/outras branches geram Preview Deployments.
- Para forçar um redeploy sem commit: **Deployments** → menu `···` do último
  deploy → **Redeploy** (desmarque "Use existing Build Cache" se mudou env var).

## 4. Primeiro uso em produção

1. Abra a URL da Vercel → **/login**.
2. Aba **ADM Global** → entre com o usuário administrador
   (`adm.clinisac@clinisac.com.br` — senha entregue à parte; troque no primeiro acesso).
3. No painel `/adm` → **Empresas** → cadastre a **primeira clínica** e os
   usuários dela.

## Troubleshooting

| Sintoma                                        | Causa provável                                                        |
|------------------------------------------------|-----------------------------------------------------------------------|
| Tela branca, console: `supabaseUrl is required` | Env vars não configuradas na Vercel (ou faltou redeploy após criá-las) |
| 404 ao dar refresh em `/adm`, `/company/...`    | `vercel.json` ausente/ignorado — confira o rewrite de SPA             |
| "E-mail ou senha incorretos" com senha certa    | Apontando para o Supabase errado — confira `VITE_SUPABASE_URL`        |
| Build falha em `npm install`                    | Node muito antigo — em Settings → General, use Node 20.x              |

## Vercel CLI (alternativa)

Se preferir a linha de comando ao painel:

```bash
npm i -g vercel
vercel login
vercel link                  # associa a pasta ao projeto
vercel env add VITE_SUPABASE_URL production
vercel env add VITE_SUPABASE_ANON_KEY production
vercel --prod                # deploy de produção
```

Mesmo usando a CLI, a conexão com o Git (auto-deploy a cada push) é feita no
painel, em **Settings → Git**.
