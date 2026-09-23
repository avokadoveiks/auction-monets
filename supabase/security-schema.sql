-- ============================================================
-- АУКЦИОН МОНЕТ — Защищённая схема v2
-- Запускай ПОСЛЕ основной схемы (supabase-schema.sql)
-- ============================================================

-- ── Флаги безопасности в профиле ────────────────────────────
alter table public.players
  add column if not exists is_banned       boolean      not null default false,
  add column if not exists ban_reason      text,
  add column if not exists last_seen       timestamptz  default now(),
  add column if not exists suspicious_acts integer      not null default 0;

-- ── Audit log (неизменяемый) ────────────────────────────────
create table if not exists public.audit_log (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid,
  action         text not null,
  lot_id         integer,
  amount         numeric,
  balance_before numeric,
  balance_after  numeric,
  ip             text,
  created_at     timestamptz not null default now()
);
-- Никто кроме сервера не пишет в аудит
alter table public.audit_log enable row level security;
create policy "audit no client write"
  on public.audit_log for all using (false);

-- ── Rate-limit таблица ───────────────────────────────────────
create table if not exists public.rate_limits (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null,
  action     text not null,
  window_end timestamptz not null,
  count      integer not null default 1,
  unique (user_id, action, window_end)
);
alter table public.rate_limits enable row level security;
create policy "rate_limits no client access"
  on public.rate_limits for all using (false);

-- ── Атомарная процедура ставки ───────────────────────────────
-- Вызывается из Edge Function — нельзя частично выполнить
create or replace function public.place_bid_atomic(
  p_player_id   uuid,
  p_player_name text,
  p_player_av   text,
  p_lot_id      integer,
  p_round_id    uuid,
  p_stake       numeric
) returns jsonb
language plpgsql security definer as $$
declare
  v_player       public.players;
  v_lot          public.lots;
  v_new_time     integer;
  v_max_times    integer[] := array[60, 120, 150, 180, 2147483647];
begin
  -- Блокируем строки чтобы два одновременных запроса не прошли оба
  select * into v_player from public.players  where id = p_player_id for update;
  select * into v_lot    from public.lots     where id = p_lot_id    for update;

  -- Повторные проверки уже внутри транзакции
  if v_player.is_banned      then return '{"success":false,"error":"banned"}'::jsonb; end if;
  if v_player.coins < p_stake then return '{"success":false,"error":"insufficient"}'::jsonb; end if;
  if v_lot.phase <> 'bidding' then return '{"success":false,"error":"not_bidding"}'::jsonb; end if;
  if v_lot.round_id <> p_round_id then return '{"success":false,"error":"stale_round"}'::jsonb; end if;

  -- Вычисляем новое время (с потолком)
  v_new_time := least(v_lot.time_left + 2, v_max_times[p_lot_id + 1]);

  -- Списываем монеты
  update public.players
    set coins    = coins - p_stake,
        last_seen = now()
    where id = p_player_id;

  -- Пишем ставку
  insert into public.bids (lot_id, round_id, player_id, player_name, player_av, amount)
    values (p_lot_id, p_round_id, p_player_id, p_player_name, p_player_av, p_stake);

  -- Обновляем лот
  update public.lots
    set leader_id        = p_player_id,
        leader_name      = p_player_name,
        leader_player_id = p_player_id,
        leader_av        = p_player_av,
        bids             = bids + 1,
        bank             = bank + p_stake,
        time_left        = v_new_time,
        updated_at       = now()
    where id = p_lot_id;

  return jsonb_build_object('success', true, 'new_balance', v_player.coins - p_stake);
end;
$$;

-- ── Ограничение: не более 30 монет трат в минуту на клиента ─
create or replace function public.check_spend_rate()
returns trigger language plpgsql security definer as $$
declare
  v_spent numeric;
begin
  select coalesce(sum(amount), 0) into v_spent
    from public.bids
    where player_id = NEW.player_id
      and created_at > now() - interval '60 seconds';

  if v_spent > 150 then  -- 150 монет/мин максимум
    -- Отмечаем подозрительный аккаунт
    update public.players
      set suspicious_acts = suspicious_acts + 1
      where id = NEW.player_id;

    raise exception 'Rate limit exceeded';
  end if;
  return NEW;
end;
$$;

create trigger bids_rate_limit
  before insert on public.bids
  for each row execute function public.check_spend_rate();

-- ── Защита от прямой записи в lots и bids с клиента ─────────
-- (только Edge Function с service role key может писать)
drop policy if exists "lots auth update" on public.lots;
create policy "lots server only"
  on public.lots for update
  using (false);  -- клиент не может UPDATE lots напрямую

-- bids тоже только через функцию
drop policy if exists "bids insert own" on public.bids;
create policy "bids server only"
  on public.bids for insert
  with check (false);  -- клиент не может INSERT bids напрямую

-- win_history тоже
drop policy if exists "history insert auth" on public.win_history;
create policy "history server only"
  on public.win_history for insert
  with check (false);

-- ── Триггер: нельзя обновить монеты в минус ─────────────────
create or replace function public.guard_balance()
returns trigger language plpgsql as $$
begin
  if NEW.coins < 0 then
    raise exception 'Balance cannot go negative';
  end if;
  return NEW;
end;
$$;

create trigger players_balance_guard
  before update on public.players
  for each row execute function public.guard_balance();

-- ── Триггер: история монет ───────────────────────────────────
create table if not exists public.coin_transactions (
  id          uuid primary key default gen_random_uuid(),
  player_id   uuid not null,
  delta       integer not null,
  reason      text not null,
  balance     integer not null,
  created_at  timestamptz not null default now()
);
alter table public.coin_transactions enable row level security;
create policy "coins read own" on public.coin_transactions
  for select using (player_id = (
    select id from public.players where user_id = auth.uid()
  ));
create policy "coins no client write" on public.coin_transactions
  for insert with check (false);

create or replace function public.log_coin_change()
returns trigger language plpgsql security definer as $$
begin
  if OLD.coins <> NEW.coins then
    insert into public.coin_transactions (player_id, delta, reason, balance)
    values (NEW.id, NEW.coins - OLD.coins,
            case when NEW.coins < OLD.coins then 'bid' else 'win' end,
            NEW.coins);
  end if;
  return NEW;
end;
$$;

create trigger players_coin_log
  after update on public.players
  for each row execute function public.log_coin_change();

-- ── Добавляем leader_player_id в lots (если не было) ─────────
alter table public.lots
  add column if not exists leader_player_id uuid;

-- ── Индексы безопасности ─────────────────────────────────────
create index if not exists audit_user_time
  on public.audit_log (user_id, created_at desc);
create index if not exists bids_player_recent
  on public.bids (player_id, created_at desc);
create index if not exists coin_tx_player
  on public.coin_transactions (player_id, created_at desc);

comment on table public.audit_log is
  'Неизменяемый лог всех действий — не удалять даже по запросу пользователя';
