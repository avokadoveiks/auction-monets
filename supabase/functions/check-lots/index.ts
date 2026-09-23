// supabase/functions/check-lots/index.ts
// Запускается автоматически каждую минуту через pg_cron
// + вызывается клиентом когда его локальный таймер дошёл до нуля

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const ZERO_SECONDS = 3;  // мигание нулей перед завершением

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  const sb = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  );

  const results: Record<string, unknown>[] = [];

  // ── 1. Найти лоты с истёкшим таймером (bidding → zero) ──────
  const { data: expiredBidding } = await sb
    .from("lots")
    .select("id, round_id, leader_id, leader_name, bids, bank")
    .eq("phase", "bidding")
    .lt("round_end_at", new Date().toISOString());

  for (const lot of (expiredBidding || [])) {
    // Входим в фазу мигающих нулей
    const { error } = await sb
      .from("lots")
      .update({
        phase:       "zero",
        zero_end_at: new Date(Date.now() + ZERO_SECONDS * 1000).toISOString(),
        updated_at:  new Date().toISOString(),
      })
      .eq("id", lot.id)
      .eq("round_id", lot.round_id)   // защита от race condition
      .eq("phase", "bidding");         // только если ещё в bidding

    if (!error) results.push({ lot: lot.id, action: "→ zero" });
  }

  // ── 2. Найти лоты в zero-фазе с истёкшим zero_end_at ────────
  const { data: expiredZero } = await sb
    .from("lots")
    .select("id, round_id")
    .eq("phase", "zero")
    .lt("zero_end_at", new Date().toISOString());

  for (const lot of (expiredZero || [])) {
    const { data, error } = await sb.rpc("end_round_atomic", {
      p_lot_id:   lot.id,
      p_round_id: lot.round_id,
    });

    if (!error) results.push({ lot: lot.id, action: "→ winner", result: data });
  }

  // ── 3. Найти лоты в winner-фазе с истёкшим winner_end_at ────
  const { data: expiredWinner } = await sb
    .from("lots")
    .select("id")
    .eq("phase", "winner")
    .lt("winner_end_at", new Date().toISOString());

  for (const lot of (expiredWinner || [])) {
    await sb.rpc("start_new_round", { p_lot_id: lot.id });
    results.push({ lot: lot.id, action: "→ new round" });
  }

  // ── 4. Возвращаем результат ──────────────────────────────────
  return new Response(
    JSON.stringify({ ok: true, processed: results.length, details: results }),
    { headers: { ...CORS, "Content-Type": "application/json" } }
  );
});
