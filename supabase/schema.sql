-- ==========================================================
-- АУКЦИОН МОНЕТ — схема базы данных Supabase
-- Запусти в Supabase Dashboard → SQL Editor → New Query
-- ==========================================================

-- Профили игроков
create table if not exists public.players (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references auth.users(id) on delete cascade unique,
  username    text not null,
  avatar_key  text not null default 'astronaut',
  coins       integer not null default 9999,
  created_at  timestamptz not null default now()
);

-- Состояние 5 лотов (одна строка на колонку, id = 0..4)
create table if not exists public.lots (
  id           integer primary key check (id between 0 and 4),
  phase        text    not null default 'bidding',  -- bidding | zero | winner
  leader_id    uuid    references public.players(id) on delete set null,
  leader_name  text,
  leader_av    text,
  bids         integer not null default 0,
  bank         numeric not null default 0,
  time_left    integer not null default 60,
  round_id     uuid    not null default gen_random_uuid(),
  updated_at   timestamptz not null default now()
);

-- Заполняем 5 лотов при первом деплое
insert into public.lots (id, time_left) values
  (0, 60), (1, 120), (2, 150), (3, 180), (4, 300)
on conflict (id) do nothing;

-- Ставки
create table if not exists public.bids (
  id           uuid primary key default gen_random_uuid(),
  lot_id       integer not null references public.lots(id),
  round_id     uuid    not null,
  player_id    uuid    references public.players(id) on delete set null,
  player_name  text    not null,
  player_av    text    not null,
  amount       numeric not null,
  created_at   timestamptz not null default now()
);

-- Сообщения общего чата
create table if not exists public.chat_messages (
  id           uuid primary key default gen_random_uuid(),
  player_id    uuid    references public.players(id) on delete set null,
  player_name  text    not null,
  player_av    text    not null,
  message      text    not null check (char_length(message) <= 120),
  created_at   timestamptz not null default now()
);

-- История побед
create table if not exists public.win_history (
  id           uuid primary key default gen_random_uuid(),
  lot_id       integer not null,
  lot_name     text    not null,
  winner_id    uuid    references public.players(id) on delete set null,
  winner_name  text    not null,
  winner_av    text    not null,
  prize        numeric not null,
  is_player    boolean not null default false,
  created_at   timestamptz not null default now()
);

-- ==========================================================
-- RLS (Row Level Security)
-- ==========================================================
alter table public.players      enable row level security;
alter table public.lots         enable row level security;
alter table public.bids         enable row level security;
alter table public.chat_messages enable row level security;
alter table public.win_history  enable row level security;

-- Все видят лоты, ставки, чат, историю
create policy "lots public read"     on public.lots          for select using (true);
create policy "bids public read"     on public.bids          for select using (true);
create policy "chat public read"     on public.chat_messages for select using (true);
create policy "history public read"  on public.win_history   for select using (true);
create policy "players public read"  on public.players       for select using (true);

-- Лоты обновляет аутентифицированный пользователь (позже заменить на Edge Function)
create policy "lots auth update"     on public.lots          for update using (auth.role() = 'authenticated');

-- Ставку пишет сам игрок
create policy "bids insert own"      on public.bids          for insert with check (auth.uid() = player_id
                                                                  or player_id is null);
-- Чат пишет сам игрок
create policy "chat insert own"      on public.chat_messages for insert with check (auth.uid() = player_id
                                                                  or player_id is null);
-- Победа пишет аутентифицированный
create policy "history insert auth"  on public.win_history   for insert with check (auth.role() = 'authenticated');

-- Свой профиль: вставка и обновление
create policy "players insert own"   on public.players       for insert with check (auth.uid() = user_id);
create policy "players update own"   on public.players       for update using  (auth.uid() = user_id);

-- ==========================================================
-- Realtime: включаем публикацию изменений
-- ==========================================================
alter publication supabase_realtime add table public.lots;
alter publication supabase_realtime add table public.bids;
alter publication supabase_realtime add table public.chat_messages;

-- ==========================================================
-- Индексы для производительности
-- ==========================================================
create index if not exists bids_lot_round on public.bids (lot_id, round_id, created_at desc);
create index if not exists chat_recent    on public.chat_messages (created_at desc);
create index if not exists wins_recent    on public.win_history (created_at desc);
create index if not exists wins_player    on public.win_history (winner_id, created_at desc);
