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

## Decisão pendente — identidade por requisição

Todo item em aberto é o mesmo problema: não existe identidade por requisição.
Dois caminhos:

**A. Supabase Auth (recomendado).** Login emite JWT de verdade; as policies usam
`auth.uid()` e o `company_id` do usuário — que é para isso que o RLS existe.
Custo: reescrever login, acesso mestre e sessão única. Migrar usuários é trivial
enquanto o banco está vazio.

**B. Token próprio endurecido.** Mantém o login atual, mas o token passa a ser
emitido pelo servidor e viaja num header lido pelas policies. Preserva acesso
mestre e sessão única como estão. Custo: menos reescrita de produto, mas é
autenticação feita à mão — que é exatamente onde moram os bugs desta auditoria.

## Pendência operacional

A linha `id = 1` em `mensagens_geral` é um canário da auditoria (campos nulos),
usado para provar a escrita liberada. A remoção foi bloqueada pelo ambiente:

```sql
delete from mensagens_geral where id = 1;
```
