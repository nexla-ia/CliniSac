# Auditoria de segurança — 31/08/2026

Auditoria feita **contra o banco de produção**, não só lendo o SQL: cada achado
foi disparado de verdade contra a API REST, usando a mesma `anon key` que vai no
bundle do site.

> Documento interno. O repositório é privado — confirmado: a API do GitHub
> responde 404 sem autenticação. Não tornar público sem antes fechar os itens
> em aberto.

## Veredito

**Não publicar o site antes de aplicar a Fase 0.** Havia quatro caminhos
independentes para um desconhecido virar ADM da plataforma usando só a `anon key`.
A Fase 0 está corrigida no código e falta rodar a migration. O isolamento entre
clínicas continua em aberto e depende de uma decisão de arquitetura.

Na data da auditoria o banco não tinha nenhum paciente cadastrado — por isso o
risco real era zero e por isso este é o momento barato de corrigir.

## Causa raiz

O front conversa direto com o PostgREST usando a `anon key`. Não há servidor no
meio. As operações privilegiadas são funções `SECURITY DEFINER`, que rodam com
poderes de dono do banco — e **nenhuma delas checava quem está chamando**.
Confiavam nos argumentos recebidos.

O comentário em `20260511_security_cleanup.sql` resume o modelo mental que
quebra: *"segurança via anon key + custom auth"*. A `anon key` não autentica
ninguém; ela só diz que a requisição veio de algum navegador. Quem extrai a
chave do bundle fala com o banco como se fosse o app, sem passar pelo login.

## Críticos — corrigidos na Fase 0

Correção em `supabase/migrations/20260831_security_hardening_fase0.sql`.

| # | Achado | Evidência | Estado |
|---|--------|-----------|--------|
| 1 | `create_user` aceitava `p_role: 'adm'` → qualquer um criava administrador global | `HTTP 409` duplicate key: a função executou e chegou ao INSERT (reusei e-mail existente de propósito) | corrigido |
| 2 | `update_user_password` gravava senha nova em qualquer conta, sem autenticação | `HTTP 204` com UUID inexistente: a função executou | corrigido |
| 3 | `ensure_table_setup` rodava DDL com nome de tabela vindo do cliente | `HTTP 404` "relation does not exist" com nome arbitrário meu: aceitou o identificador | corrigido |
| 4 | `delete_user` apagava qualquer conta, inclusive a do ADM | `HTTP 200 {"ok":false,"error":"Usuário não encontrado"}`: resposta de aplicação, não de permissão | corrigido |

**A cadeia do item 2** era a mais direta: `users` é legível pela `anon key`,
então bastava ler o `id` do ADM, gravar uma senha nova e entrar. Três
requisições, nenhuma credencial.

**O item 3** era o mais elegante: apontando `ensure_table_setup` para
`platform_settings` ou `app_secrets`, ela criava `create policy allow_read …
using (true)` **no próprio cofre** — expondo o hash da senha mestre e o
`master_email` em texto puro.

## Altos — em aberto

Dependem de o banco saber quem está chamando (ver "Decisão pendente").

- **Leitura livre de prontuário, agenda e financeiro.** Testei 20 tabelas: todas
  retornaram 200 na leitura; em 15 a escrita também passou. O RLS está ligado,
  mas as políticas são `using (true)`, o que na prática é não ter RLS.
  Escrita liberada em: `mensagens`, `mensagens_geral`, `conversations`,
  `appointments`, `agendas`, `prontuario_attachments`, `anamnese_responses`,
  `financial_transactions`, `invoices`, `orcamentos`, `crm_contacts`,
  `attendances`, `treatment_plans`, `companies`, `professionals`.
  São dados de saúde — dado sensível na LGPD.

- **Credencial da Evolution API exposta.** `companies` é legível e gravável pela
  `anon key`, e `api_instancia` guarda a credencial da instância de WhatsApp
  (confirmado preenchido). A escrita permite ainda reescrever `evolution_url` e
  `instagram_webhook_path` — redirecionar o WhatsApp da clínica — e mexer em
  `billing_blocked`.

- **O crachá não pede senha.** `claim_login_session(p_user_id, p_token)` grava o
  token enviado desde que a sessão esteja livre ou parada há mais de 130s. Não
  confere senha, e o `user_id` é público. **Isso muda o plano da Fase 1:** do
  jeito que está, o crachá é forjável, e construir RLS por clínica em cima dele
  não isola nada. O token precisa ser emitido pelo servidor no login antes de
  virar base de autorização.

- **Lista de usuários aberta.** `users` devolve nome, e-mail, perfil, empresa e
  id de todos. O `password_hash` está protegido por GRANT de coluna (correto),
  mas o resto alimenta os ataques acima.

## Médios

- **A senha mestre é chave-mestra universal.** Por desenho, `login_user` aceita
  a senha mestre junto com o e-mail de qualquer conta ativa, inclusive a do ADM.
  Tratar como segredo de cofre; considerar limitá-la a contas de clínica.
- **Sem limite de tentativas em `login_user`** — porta aberta para força bruta.
- **`master_email` em texto puro** em `platform_settings`. A senha está como
  hash bcrypt (correto); o e-mail não precisa estar legível.

## O que já estava certo

- `password_hash` bloqueado por GRANT de coluna — `select=*` em `users` dá 401.
- `app_secrets` e `platform_settings` com RLS fechado, sem policy.
- Introspecção do PostgREST restrita ao `service_role`.
- Nenhum bucket de storage criado. Quando criarem para anexos de prontuário,
  tem que nascer privado.

## Decisão tomada — Supabase Auth

Todo item em aberto era o mesmo problema: não existia identidade por requisição.
A escolha foi **Supabase Auth**: o login emite JWT de verdade e as policies usam
`auth.uid()` e o `company_id` do usuário — que é para isso que o RLS existe.
Feito enquanto o banco estava vazio, quando migrar usuários custava nada.

### Etapa 1 — identidades (aplicada)

`20260831_auth_etapa1_identidades.sql`. Cada usuário ganhou identidade em
`auth.users` com o **mesmo id** de `public.users` (então `auth.uid()` aponta
direto para o perfil, sem tabela de ligação) e o mesmo hash bcrypt, então as
senhas continuaram valendo. Helpers `auth_role` / `auth_company_id` /
`auth_is_adm` / `auth_can_access_company` como base das policies.

Verificado: JWT emitido com `sub` = id do perfil; `auth_role` devolve `"adm"`
com token e `null` sem token.

### Etapa 2 — autorização (aplicada)

`20260831_auth_etapa2_autorizacao.sql`. As funções privilegiadas passaram a
perguntar `auth.uid()` em vez de confiar nos argumentos, e a manter `auth.users`
em dia (criar usuário cria a identidade, trocar senha troca dos dois lados,
apagar apaga dos dois). A senha mestre universal foi aposentada: o ADM entra em
qualquer clínica por permissão.

### Etapa 2b — correção (aplicada)

`20260831_auth_etapa2b_correcao.sql`. A conferência da etapa 2 acusou "anon
ainda executa create_user? true", e o teste ao vivo confirmou que era real. Duas
falhas somadas, cada uma sozinha suficiente para abrir o buraco:

1. **Lógica de três valores.** `auth_can_manage_users` devolvia `NULL` para quem
   não está logado — `false OR (NULL = 'admin' AND …)` é `NULL` — e
   `IF NOT <null> THEN RAISE` não dispara, porque `NOT NULL` é `NULL`, que não é
   verdadeiro. A função seguia em frente. `auth_is_adm` escapou porque já tinha
   `COALESCE`; por isso `mark_company_paid` bloqueava certo e `create_user` não.
2. **`REVOKE … FROM anon` não tira o privilégio herdado de `PUBLIC`.** Toda
   função nasce com EXECUTE para `PUBLIC`, e `anon` é membro de `PUBLIC`.

Correção: `COALESCE` em todo predicado de autorização (inclusive
`auth_can_access_company`, que tinha o mesmo defeito e vai ser a base das
policies da etapa 3) e `REVOKE … FROM PUBLIC`.

> **Lição de teste:** o probe que descobriu a falha usou o id de um usuário real
> em `delete_user` e apagou a conta. Alvo real só é seguro depois que a
> autorização está provada — e era justamente isso que estava sendo verificado.
> Probes destrutivos vão com UUID inexistente.

### Estado verificado

Com a anon key, as sete funções privilegiadas respondem `permission denied for
function` — a chamada não chega ao corpo. Com JWT: ADM administra qualquer
clínica, `admin` só a própria (barrado ao tentar outra), `viewer` não administra
nada, e nem `admin` nem `viewer` mexem na conta ADM ou na mensalidade. Ciclo
completo testado: ADM cria usuário → o usuário loga na hora → ADM apaga → a
identidade some junto, sem órfão.

### Etapa 3 — pendente

Trocar as policies `using (true)` por `auth_can_access_company(company_id)`. É a
que fecha a leitura livre de prontuário, agenda e financeiro, e a única que pode
quebrar telas se alguma tabela passar despercebida.
