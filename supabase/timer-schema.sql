-- ============================================================
-- СЕРВЕРНЫЙ ТАЙМЕР — миграция
-- Запускать ПОСЛЕ security-schema.sql
-- ============================================================

-- Добавляем временны́е метки UTC вместо time_left (числа)
alter table public.lots
  add column if not exists round_end_at  timestamptz,
  add column if not exists zero_end_at   timestamptz,
  add column if not exists winner_end_at timestamptz,
  add column if not exists max_duration  interval;

-- Лимиты перебитий (нельзя поднять выше стартового времени)
-- Используем как серверные константы
create or replace function public.lot_start_interval(p_lot_id integer)
returns interval language sql immutable as $$
  select case p_lot_id
    when 0 then interval '60 seconds'
    when 1 then interval '120 seconds'
    when 2 then interval '150 seconds'
    when 3 then interval '180 seconds'
    when 4 then interval '300 seconds'
    else         interval '60 seconds'
  end;
$$;

-- Инициализируем все лоты
update public.lots set
  round_end_at = now() + public.lot_start_interval(id),
  max_duration = public.lot_start_interval(id),
  phase        = 'bidding'
where round_end_at is null;

-- Обновляем place_bid_atomic: теперь он двигает round_end_at, а не time_left
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
  v_player    public.players;
  v_lot       public.lots;
  v_new_end   timestamptz;
  v_max_end   timestamptz;
begin
  select * into v_player from public.players where id = p_player_id for update;
  select * into v_lot    from public.lots    where id = p_lot_id    for update;

  if v_player.is_banned              then return '{"success":false,"error":"banned"}'::jsonb; end if;
  if v_player.coins < p_stake        then return '{"success":false,"error":"insufficient"}'::jsonb; end if;
  if v_lot.phase <> 'bidding'        then return '{"success":false,"error":"not_bidding"}'::jsonb; end if;
  if v_lot.round_id <> p_round_id    then return '{"success":false,"error":"stale_round"}'::jsonb; end if;

  -- Двигаем таймер: +2 сек, но не выше стартового времени
  v_max_end := v_lot.updated_at + v_lot.max_duration;   -- потолок = старт раунда + max_duration
  v_new_end := least(v_lot.round_end_at + interval '2 seconds', v_max_end);

  update public.players
    set coins     = coins - p_stake,
        last_seen = now()
    where id = p_player_id;

  insert into public.bids (lot_id, round_id, player_id, player_name, player_av, amount)
    values (p_lot_id, p_round_id, p_player_id, p_player_name, p_player_av, p_stake);

  update public.lots set
    leader_id        = p_player_id,
    leader_player_id = p_player_id,
    leader_name      = p_player_name,
    leader_av        = p_player_av,
    bids             = bids + 1,
    bank             = bank + p_stake,
    round_end_at     = v_new_end,
    updated_at       = now()
    where id = p_lot_id;

  return jsonb_build_object(
    'success',      true,
    'new_balance',  v_player.coins - p_stake,
    'round_end_at', v_new_end
  );
end;
$$;

-- ── Функция завершения раунда (вызывается из Edge Function) ──
create or replace function public.end_round_atomic(
  p_lot_id   integer,
  p_round_id uuid
) returns jsonb
language plpgsql security definer as $$
declare
  v_lot     public.lots;
  v_player  public.players;
  v_prize   numeric;
  v_bids_n  integer;
  v_stake   numeric[] := array[2,4,6,8,10];
begin
  select * into v_lot from public.lots where id = p_lot_id for update;

  -- Уже обработан другим клиентом или сервером
  if v_lot.round_id <> p_round_id then
    return '{"success":false,"error":"stale"}'::jsonb;
  end if;
  if v_lot.phase not in ('bidding','zero') then
    return '{"success":false,"error":"wrong_phase"}'::jsonb;
  end if;

  -- Вычисляем приз: bids * stake + stake/2
  v_bids_n := greatest(1, v_lot.bids);
  v_prize  := v_bids_n * v_stake[p_lot_id + 1] + v_stake[p_lot_id + 1] / 2.0;

  if v_lot.leader_id is not null then
    -- Начисляем победителю
    update public.players
      set coins = coins + v_prize::integer
      where id = v_lot.leader_id;

    -- Пишем в историю побед
    insert into public.win_history
      (lot_id, lot_name, winner_id, winner_name, winner_av, prize, is_player)
    values
      (p_lot_id, '', v_lot.leader_id, v_lot.leader_name, v_lot.leader_av, v_prize, false);
  end if;

  -- Переводим в фазу winner (10 сек), потом новый раунд
  update public.lots set
    phase          = 'winner',
    winner_end_at  = now() + interval '10 seconds',
    updated_at     = now()
    where id = p_lot_id;

  -- Через 10 сек сбрасываем (функция вызывается снова планировщиком)
  return jsonb_build_object('success', true, 'prize', v_prize, 'winner', v_lot.leader_name);
end;
$$;

-- Сброс лота в новый раунд
create or replace function public.start_new_round(p_lot_id integer)
returns void language plpgsql security definer as $$
begin
  update public.lots set
    phase          = 'bidding',
    leader_id      = null,
    leader_player_id = null,
    leader_name    = null,
    leader_av      = null,
    bids           = 0,
    bank           = 0,
    round_id       = gen_random_uuid(),
    round_end_at   = now() + public.lot_start_interval(p_lot_id),
    zero_end_at    = null,
    winner_end_at  = null,
    updated_at     = now()
    where id = p_lot_id;
end;
$$;

-- Realtime для клиентов: слушаем изменения лотов
alter publication supabase_realtime add table public.lots;

-- Индексы для быстрого поиска истёкших лотов
create index if not exists lots_expired
  on public.lots (round_end_at)
  where phase = 'bidding';
create index if not exists lots_winner_expired
  on public.lots (winner_end_at)
  where phase = 'winner';
