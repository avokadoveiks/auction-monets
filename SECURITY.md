# БЕЗОПАСНОСТЬ — Аукцион Монет

## Главный принцип

> Клиент всегда врёт. Верь только серверу.

Любой JS в браузере или мобильном приложении можно вскрыть —
DevTools, Frida, jadx, Charles Proxy, память процесса.
**Настоящая защита живёт только в Edge Function и БД.**

---

## Карта угроз и защит

### 🔴 Критические (ломают игру моментально без защиты)

| Атака | Как ломают | Наша защита |
|-------|-----------|-------------|
| Подмена баланса | `balance = 999999` в консоли | Edge Function читает баланс из БД, не верит клиенту |
| Прямой вызов placeBid() | `placeBid(4, PLAYER)` в консоли | Bid принимается только через Edge Function с JWT |
| Повтор запроса (Replay) | Отправить bid-запрос 100 раз | Round_id в каждом запросе, атомарная транзакция в БД |
| Одновременные запросы | 2 запроса за 1мс чтобы обойти баланс | `FOR UPDATE` блокировка строки в PostgreSQL |
| Отрицательный баланс | Manipulate stake amount | `guard_balance()` триггер запрещает coins < 0 |

### 🟠 Серьёзные (фарм и злоупотребление)

| Атака | Как ломают | Наша защита |
|-------|-----------|-------------|
| Флуд ставками | Бот отправляет 100 ставок/сек | Rate limit 800мс в Edge Function + триггер 150 монет/мин |
| Многоаккаунтность | Сотни Google аккаунтов для фарма | Device fingerprint (Capacitor), IP лог в audit_log |
| Снифинг трафика | Charles/mitmproxy смотрит запросы | HTTPS везде, данные не чувствительны (bid = 2 монеты) |
| Модификация памяти | Frida/GameGuardian меняют coins в памяти | Сервер не верит client-side balance — всегда БД |

### 🟡 Средние (неприятно, но не критично)

| Атака | Как ломают | Наша защита |
|-------|-----------|-------------|
| XSS в чате | `<script>alert(1)</script>` в сообщении | escapeHtml() + max 120 символов |
| Таймер-манипуляция | Заморозить/ускорить JavaScript таймер | Серверный time_left в lots таблице (следующая версия) |
| DevTools читает секреты | Ищут API ключи в исходнике | Используем anon key (публичный), не service role! |

### 🟢 Уже решённые

| Защита | Что делает |
|--------|-----------|
| JWT токены | Каждый запрос подписан — нельзя делать запросы от чужого имени |
| RLS (Row Level Security) | Каждый видит только свои данные, direct SQL с клиента блокирован |
| Audit log | Неизменяемый лог всех ставок — видно кто когда что делал |
| coin_transactions | История каждого изменения баланса — нельзя тихо накрутить |
| ban система | Подозрительный аккаунт блокируется без удаления данных |

---

## Порядок развёртывания

```bash
# 1. Основная схема
supabase db push --file supabase-schema.sql

# 2. Защитная схема (поверх основной)
supabase db push --file security-schema.sql

# 3. Деплой Edge Function
supabase functions deploy place-bid
supabase functions deploy end-round

# 4. Переменные окружения для Edge Function
supabase secrets set SUPABASE_URL=https://xxx.supabase.co
supabase secrets set SUPABASE_SERVICE_ROLE_KEY=eyJ...  # НЕ anon key!
```

---

## Что добавить перед App Store

### Обязательно
- [ ] **Серверный таймер** — Edge Function + pg_cron управляет `time_left`
  Без этого хакер может заморозить таймер на клиенте
- [ ] **Валидация выигрыша на сервере** — `end-round` Edge Function
  Сейчас endRound() работает на клиенте
- [ ] **Stripe/Apple IAP** — покупка монет через официальные каналы
  Прямые платёжные системы нарушают правила App Store

### Рекомендуется  
- [ ] **Jailbreak/root detection** — Capacitor плагин `@capacitor-community/device-security`
  Взломанные устройства легче использовать для читов
- [ ] **Certificate pinning** — `@ionic-native/http`
  Блокирует MITM-атаки даже с установленным CA
- [ ] **Code obfuscation** — `javascript-obfuscator` в сборке
  Усложняет реверс-инжиниринг JS (не останавливает, но замедляет)
- [ ] **Analytics на аномалии** — Supabase + Grafana
  Если игрок выиграл 1000 лотов за час — автобан

### Для роста аудитории (против ботов)
- [ ] **reCAPTCHA v3** при регистрации
- [ ] **Device fingerprint** — `@fingerprintjs/fingerprintjs-pro`
- [ ] **Email верификация** перед первой ставкой

---

## Мониторинг

Подключи в Supabase Dashboard → Logs:

```sql
-- Топ подозрительных игроков
select p.username, p.suspicious_acts, p.coins, count(b.id) bids_today
from players p
left join bids b on b.player_id = p.id and b.created_at > now() - interval '24h'
group by p.id
order by p.suspicious_acts desc
limit 20;

-- Аномально большие трат
select player_id, sum(amount) spent, count(*) bids
from bids
where created_at > now() - interval '1h'
group by player_id
having sum(amount) > 500
order by spent desc;
```

---

## Файлы проекта

```
auction-game.html        — Игра с клиентской защитой
supabase-schema.sql      — Основная схема БД
security-schema.sql      — Защитный слой: триггеры, audit, rate limit
place-bid.ts             — Edge Function: сервер-сайд валидация ставок
SETUP.md                 — Инструкция по настройке
SECURITY.md              — Этот файл
```
