// supabase/functions/place-bid/index.ts
// Запускается на сервере Supabase — клиент не может обойти эту проверку

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// Допустимые ставки по колонкам
const STAKES = [2, 4, 6, 8, 10];
// Минимальный интервал между ставками одного игрока на один лот (мс)
const BID_COOLDOWN_MS = 800;

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  try {
    // ── 1. Аутентификация ────────────────────────────────────────
    // Суперважно: без этого любой может делать запросы от чужого имени
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return err(401, "Не авторизован");

    const sbAdmin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")! // Только для серверного использования!
    );
    const sbUser = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } }
    );

    // Получаем реального пользователя из JWT
    const { data: { user }, error: authErr } = await sbUser.auth.getUser();
    if (authErr || !user) return err(401, "Неверный токен");

    // ── 2. Разбираем тело запроса ────────────────────────────────
    const { lot_id } = await req.json();
    if (lot_id === undefined || lot_id < 0 || lot_id > 4)
      return err(400, "Неверный лот");

    const stake = STAKES[lot_id];

    // ── 3. Получаем профиль игрока ───────────────────────────────
    const { data: player, error: playerErr } = await sbAdmin
      .from("players")
      .select("id, username, avatar_key, coins, is_banned")
      .eq("user_id", user.id)
      .single();

    if (playerErr || !player) return err(404, "Профиль не найден");
    if (player.is_banned) return err(403, "Аккаунт заблокирован");

    // ── 4. Проверяем баланс на СЕРВЕРЕ ──────────────────────────
    // Клиент может показывать что угодно — нам важен реальный баланс в БД
    if (player.coins < stake)
      return err(402, `Недостаточно монет: нужно ${stake}, есть ${player.coins}`);

    // ── 5. Проверяем состояние лота ──────────────────────────────
    const { data: lot, error: lotErr } = await sbAdmin
      .from("lots")
      .select("*")
      .eq("id", lot_id)
      .single();

    if (lotErr || !lot) return err(404, "Лот не найден");
    if (lot.phase !== "bidding") return err(409, "Раунд не принимает ставки");
    if (lot.time_left <= 0) return err(409, "Время вышло");

    // ── 6. Проверяем что игрок не лидирует уже ──────────────────
    if (lot.leader_player_id === player.id)
      return err(409, "Ты уже лидируешь в этом лоте");

    // ── 7. Правило Дуэли (лот 3) — только двое ──────────────────
    if (lot_id === 3) {
      const { data: duelPlayers } = await sbAdmin
        .from("bids")
        .select("player_id")
        .eq("lot_id", lot_id)
        .eq("round_id", lot.round_id)
        .order("created_at", { ascending: true });

      const unique = [...new Set((duelPlayers || []).map((b: any) => b.player_id))];
      if (unique.length >= 2 && !unique.includes(player.id))
        return err(409, "Дуэль занята — максимум 2 игрока");
    }

    // ── 8. Rate limiting — защита от флуда ───────────────────────
    const { data: lastBid } = await sbAdmin
      .from("bids")
      .select("created_at")
      .eq("lot_id", lot_id)
      .eq("player_id", player.id)
      .order("created_at", { ascending: false })
      .limit(1)
      .single();

    if (lastBid) {
      const elapsed = Date.now() - new Date(lastBid.created_at).getTime();
      if (elapsed < BID_COOLDOWN_MS)
        return err(429, `Слишком быстро — подожди ${BID_COOLDOWN_MS - elapsed}мс`);
    }

    // ── 9. Атомарная транзакция: списание + ставка ───────────────
    // Используем RPC (хранимую процедуру) чтобы операции не разъехались
    const { data: result, error: rpcErr } = await sbAdmin.rpc("place_bid_atomic", {
      p_player_id:   player.id,
      p_player_name: player.username,
      p_player_av:   player.avatar_key,
      p_lot_id:      lot_id,
      p_round_id:    lot.round_id,
      p_stake:       stake,
    });

    if (rpcErr || !result?.success)
      return err(500, rpcErr?.message || "Ошибка сервера");

    // ── 10. Лог для аудита (не удаляем даже если игрок просит) ──
    await sbAdmin.from("audit_log").insert({
      user_id:    user.id,
      action:     "bid",
      lot_id:     lot_id,
      amount:     stake,
      balance_before: player.coins,
      balance_after:  player.coins - stake,
      ip:         req.headers.get("x-forwarded-for") || "unknown",
    });

    return new Response(JSON.stringify({ ok: true, new_balance: player.coins - stake }), {
      headers: { ...CORS, "Content-Type": "application/json" },
    });

  } catch (e) {
    console.error(e);
    return err(500, "Внутренняя ошибка сервера");
  }
});

function err(status: number, message: string) {
  return new Response(JSON.stringify({ ok: false, error: message }), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}
