-- ==============================================================
-- Lembrete duplicado DE NOVO — reaplica a limpeza de cron de forma
-- incondicional (não depende de nenhuma migration anterior ter rodado)
--
-- HISTÓRICO
--   20260511_appointment_reminders.sql criou o job 'process-appointment-
--   reminders' (a cada 5min). 20260717_schedule_reminders_cron.sql,
--   sem saber que o primeiro já existia, criou outro job com nome
--   diferente, 'appointment-reminders' (a cada 15min) — os dois chamando
--   a MESMA function. Em 21/07 isso foi confirmado ao vivo (SELECT * FROM
--   cron.job) causando envio em dobro, e corrigido por duas migrations
--   (20260721_reminder_no_dup.sql — trava advisory lock na function —
--   e 20260721_reminder_unschedule_dup.sql — remove o job sobrando).
--
--   O mesmo sintoma (a mesma enquete de confirmação chegou 2x, mesmo
--   minuto) voltou a acontecer em 05/11. Como não dá pra confirmar por
--   aqui se aquelas duas migrations de julho chegaram a rodar neste
--   projeto Supabase especificamente (eram endereçadas a "projeto NOVO,
--   sbzwtnxx" — se o projeto trocou de novo depois, elas podem ter
--   ficado só no projeto antigo), esta migration reaplica a correção
--   inteira de um jeito que não depende de nada ter rodado antes:
--
--   1) Remove os dois nomes de job possíveis (não dá erro se não
--      existirem).
--   2) Confere se a function ainda tem a trava de advisory lock — ela
--      já tem desde 20260721_reminder_no_dup.sql e continuou tendo em
--      20261009_fix_regexp_replace_backreference_dos.sql, então aqui só
--      recria o schedule por cima, sem mexer no corpo da function.
--   3) Cria UM schedule só, 'appointment-reminders', a cada 5 minutos
--      (intervalo mais curto do que o de 15min pra não perder precisão
--      nos lembretes de offset curto).
--
-- ⚠ SE EXISTIR UM NÓ "SCHEDULE" NO N8N QUE TAMBÉM CHAMA
--   /rpc/process_appointment_reminders diretamente (bate a apontada no
--   comentário de 20260721_reminder_no_dup.sql), DESATIVE ELE — a trava
--   de advisory lock impede o envio em dobro mesmo com dois chamadores,
--   mas o ideal mesmo é só UM agendador ativo. Isso não dá pra verificar
--   nem corrigir por uma migration SQL; precisa olhar direto no n8n.
--
-- Seguro rodar mais de uma vez.
-- ==============================================================

DO $$
BEGIN
  PERFORM cron.unschedule('process-appointment-reminders');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$
BEGIN
  PERFORM cron.unschedule('appointment-reminders');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

SELECT cron.schedule(
  'appointment-reminders',
  '*/5 * * * *',
  $cron$SELECT public.process_appointment_reminders();$cron$
);

-- Conferência: deve aparecer EXATAMENTE UMA linha chamando
-- process_appointment_reminders.
SELECT jobid, schedule, jobname, command
  FROM cron.job
 WHERE command ILIKE '%process_appointment_reminders%';
