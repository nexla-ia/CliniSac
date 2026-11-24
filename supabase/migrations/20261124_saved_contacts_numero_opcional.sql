-- ============================================================================
-- Pacientes sem telefone
-- ----------------------------------------------------------------------------
-- saved_contacts.numero era NOT NULL e tem UNIQUE (numero, instancia). Paciente
-- cadastrado sem telefone ia com numero = '' e o SEGUNDO sem telefone da mesma
-- clínica batia na trava de unicidade ("Erro ao salvar").
--
-- Agora numero aceita NULL (sem telefone). O UNIQUE continua valendo pra quem
-- tem número, e vários NULL convivem (NULL não conflita no UNIQUE). O upsert
-- de "Salvar contato" nas Conversas (on conflict numero,instancia) segue igual.
--
-- O front já manda NULL quando o telefone fica vazio e, se esta migration ainda
-- não rodou, cai no comportamento antigo (''). Idempotente.
-- ============================================================================

alter table public.saved_contacts alter column numero drop not null;

update public.saved_contacts set numero = null where numero = '';
