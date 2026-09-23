-- ============================================================
-- ПЛАНИРОВЩИК — вызывает check-lots каждую минуту
-- Запускать в Supabase SQL Editor
-- ============================================================

-- Включаем расширения
create extension if not exists pg_cron;
create extension if not exists pg_net;

-- Каждую минуту проверяем истёкшие лоты
select cron.schedule(
  'check-lots-every-minute',
  '* * * * *',
  $$
  select net.http_post(
    url     := current_setting('app.supabase_url') || '/functions/v1/check-lots',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || current_setting('app.supabase_anon_key')
    ),
    body    := '{}'
  ) as request_id;
  $$
);

-- Сохраняем URL и ключ как настройки БД
-- (замени на свои значения)
alter database postgres set app.supabase_url    = 'https://ТВОЙ-ПРОЕКТ.supabase.co';
alter database postgres set app.supabase_anon_key = 'eyJ...ТВОЙ-ANON-KEY...';

-- Проверить расписание:
-- select * from cron.job;

-- Удалить расписание если нужно:
-- select cron.unschedule('check-lots-every-minute');

-- ── ВАЖНО: минимум pg_cron = 1 минута ───────────────────────
-- Для sub-minute точности клиент сам вызывает check-lots
-- когда его локальный countdown дошёл до 0.
-- Сервер проверяет реальное время (round_end_at < now())
-- и отклоняет преждевременные вызовы.
-- pg_cron служит страховкой если все клиенты офлайн.
