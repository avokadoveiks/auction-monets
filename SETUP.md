# Аукцион Монет — настройка бэкенда

## Шаг 1 — Создать проект Supabase

1. Зайди на **supabase.com** → Sign up (бесплатно)
2. New Project → придумай название, пароль БД, выбери регион (ближайший к игрокам)
3. Подожди ~2 минуты пока проект поднимается

## Шаг 2 — Запустить схему базы данных

1. Sleft sidebar → **SQL Editor** → New Query
2. Открой файл `supabase-schema.sql` (лежит рядом с игрой)
3. Вставь содержимое в редактор → **Run**
4. Должно появиться `Success. No rows returned`

## Шаг 3 — Включить Google Auth

1. Left sidebar → **Authentication** → **Providers**
2. Найди **Google** → включи Enable
3. Тебе нужны Client ID и Client Secret от Google:
   - Открой [console.cloud.google.com](https://console.cloud.google.com)
   - Создай проект → APIs & Services → Credentials
   - Create Credentials → OAuth 2.0 Client ID → Web Application
   - Authorized redirect URIs: вставь URL из Supabase (он показывается прямо на странице провайдера)
   - Скопируй Client ID и Client Secret → вставь в Supabase
4. Save

## Шаг 4 — Получить ключи проекта

1. Supabase Dashboard → Left sidebar → **Settings** → **API**
2. Скопируй:
   - **Project URL** → например `https://abcdefgh.supabase.co`
   - **anon / public key** → длинная строка начинается с `eyJ...`
3. Открой `index.html` в любом редакторе (VS Code, Notepad++)
4. Найди в начале JS-блока:

```js
var SUPABASE_URL = "";   // ← вставь сюда Project URL
var SUPABASE_KEY = "";   // ← вставь сюда anon key
```

5. Сохрани файл

## Шаг 5 — Включить Realtime

1. Supabase Dashboard → **Database** → **Replication**
2. Убедись что таблицы `lots`, `bids`, `chat_messages` отмечены галкой
3. Если нет — добавь вручную

## Шаг 6 — Запустить игру

### Для тестирования в браузере:
Просто открой `index.html` в браузере — игра подключится к Supabase автоматически.  
⚠️ Chrome может заблокировать запросы с локального файла. Используй расширение [Live Server](https://marketplace.visualstudio.com/items?itemName=ritwickdey.LiveServer) для VS Code или простой сервер:
```bash
cd папка-с-игрой
npx serve .
# откроет http://localhost:3000
```

### Для сборки мобильного приложения:

Готовый iOS-проект уже находится в `ios/ios/App`. На Mac из корня репозитория:

```bash
bash ios/setup-ios.sh
```

Подробности и требования: [XCODE-START.md](XCODE-START.md).

## Архитектура

```
┌─────────────────────────────────────────────────┐
│                   КЛИЕНТ                         │
│   index.html (твой HTML с игрой)                 │
│   Supabase JS SDK (загружается с CDN)            │
└─────────────┬───────────────────────────────────┘
              │ HTTPS + WebSocket (Realtime)
┌─────────────▼───────────────────────────────────┐
│                SUPABASE                          │
│  ┌──────────┐ ┌───────────┐ ┌────────────────┐  │
│  │ Auth     │ │ Database  │ │ Realtime       │  │
│  │ (Google  │ │ (Postgres)│ │ (WebSocket)    │  │
│  │  OAuth)  │ │           │ │                │  │
│  └──────────┘ └───────────┘ └────────────────┘  │
└─────────────────────────────────────────────────┘
```

## Что происходит в реальном времени

- Игрок ставит ставку → пишется в таблицу `bids`
- Все остальные клиенты получают INSERT через Realtime WebSocket
- Каждый клиент обновляет UI мгновенно
- Таймеры пока работают на клиенте. В следующей версии — Supabase Edge Functions + pg_cron для серверного управления раундами

## Следующие шаги (после MVP)

- [ ] Edge Functions для серверного управления таймерами
- [ ] Stripe / Apple IAP для покупки монет
- [ ] Push-уведомления (Supabase + APNs/FCM)
- [ ] Антифрод: проверка баланса на сервере перед ставкой
- [ ] Сезонный рейтинг с призами

## Поддержка

Если что-то не работает — проверь:
1. Ключи вставлены правильно (нет лишних пробелов)
2. RLS политики созданы (шаг 2 выполнен полностью)
3. Realtime включён (шаг 5)
4. В консоли браузера нет ошибок CORS (открой F12 → Console)
