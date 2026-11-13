-- ==============================================================
-- Limitador mensal de disparo, configurável por empresa no ADM.
--
-- Ex: empresa X só pode disparar pra 800 contatos por mês. Ao bater
-- 800 envios confirmados ("enviado") no mês corrente, a tela de
-- Disparo bloqueia novos disparos e avisa o usuário ("limite mensal
-- atingido"), em vez de deixar a empresa continuar disparando.
--
-- NULL = sem limite (comportamento atual, não muda nada em quem já
-- usa o sistema).
--
-- Não precisa de tabela de contagem separada: o uso do mês é contado
-- direto em cima de disparo_envios (status='enviado' E enviado_em no
-- mês corrente), que já existe e já é carregado/realtime na tela.
--
-- Idempotente.
-- ==============================================================

ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS disparo_monthly_limit integer;
