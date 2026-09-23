# 🪙 Аукцион Монет

Мобильная аукцион-игра — HTML + Capacitor iOS.

## Стек
- Vanilla JS + HTML/CSS (один файл)
- Supabase (PostgreSQL + Realtime + Auth)
- Capacitor для iOS/Android
- Edge Functions для серверной логики

## Быстрый старт
1. Открой `auction-game.html` в браузере — сразу работает в локальном режиме с ботами
2. Для мультиплеера: создай проект на [supabase.com](https://supabase.com), вставь URL и ключ в начало JS
3. Для iOS: смотри `SETUP.md`

## Файлы
| Файл | Описание |
|------|----------|
| `auction-game.html` | Основной файл игры |
| `supabase/schema.sql` | Схема базы данных |
| `supabase/security-schema.sql` | Защита и аудит |
| `supabase/timer-schema.sql` | Серверный таймер |
| `supabase/cron-setup.sql` | pg_cron планировщик |
| `supabase/functions/place-bid/index.ts` | Edge Function: валидация ставок |
| `supabase/functions/check-lots/index.ts` | Edge Function: проверка лотов |
| `ios/capacitor.config.ts` | Capacitor конфиг |
| `ios/package.json` | npm зависимости |
| `ios/setup-ios.sh` | Скрипт сборки для Mac |
| `SETUP.md` | Инструкция по настройке |
| `SECURITY.md` | Архитектура безопасности |

## Механики игры
- 5 колонок: Новичок(2), Любитель(4), Опытный(6), Дуэль(8), Профессионал(10)
- Приз = ставки × цена + цена/2
- Таймер на сервере (round_end_at UTC)
- Дуэль: максимум 2 игрока
- Ежедневный бонус: 7-дневная серия
- Сезонный рейтинг: каждые 14 дней, призы топ-3

## Автор
[@avokadoveiks](https://github.com/avokadoveiks)
