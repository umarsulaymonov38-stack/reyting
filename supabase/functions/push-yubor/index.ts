// push-yubor: ota-onalar telefoniga push-bildirishnoma yuboradi (bepul, Web Push).
// Har daqiqada bazadagi jadval (yk_push_kick) chaqiradi; navbat bo'sh bo'lsa chaqirilmaydi.
// VAPID kalitlari birinchi ishga tushganda o'zi yaratiladi va bazada (push_secret) saqlanadi — hech narsa sozlash shart emas.
// Supabase'da funksiya sozlamasida "Verify JWT" O'CHIRILGAN bo'lishi kerak (ilova ochiq kalitni olish uchun bir marta chaqiradi).
import webpush from "npm:web-push@3.6.7";
import { createClient } from "jsr:@supabase/supabase-js@2";

const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const CORS = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "*" };

async function keys(): Promise<{ public_key: string; private_key: string }> {
  const { data } = await sb.rpc("push_keys_get");
  if (data?.public_key && data?.private_key) return data;
  const k = webpush.generateVAPIDKeys();
  await sb.rpc("push_keys_set", { p_pub: k.publicKey, p_priv: k.privateKey });
  const { data: d2 } = await sb.rpc("push_keys_get"); // bir vaqtda ikki marta chaqirilsa — birinchisi saqlanadi
  return d2;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS });
  const k = await keys();
  webpush.setVapidDetails("https://umarsulaymonov38-stack.github.io/reyting/", k.public_key, k.private_key);

  const { data: rows, error } = await sb.rpc("push_claim", { p_limit: 200 });
  if (error) return new Response(error.message, { status: 500, headers: CORS });
  let ok = 0, gone = 0;
  for (const m of rows ?? []) {
    const payload = JSON.stringify({ title: m.title, body: m.body, tag: m.tag });
    let sent = false, err = "";
    for (const s of m.subs ?? []) {
      try {
        await webpush.sendNotification({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } }, payload, { TTL: 6 * 3600, urgency: "high" });
        sent = true;
      } catch (e) {
        const code = (e as { statusCode?: number }).statusCode;
        if (code === 404 || code === 410) { await sb.rpc("push_sub_del", { p_endpoint: s.endpoint }); gone++; }
        else err = String((e as { body?: string }).body || e).slice(0, 300);
      }
    }
    // obunasi yo'q bo'lib qolgan bo'lsa — qayta urinmaymiz
    await sb.rpc("push_done", { p_id: m.id, p_ok: sent || !(m.subs ?? []).length, p_error: sent ? null : (err || "obuna topilmadi") });
    if (sent) ok++;
  }
  return Response.json({ yuborildi: ok, jami: (rows ?? []).length, ochirilgan_obuna: gone }, { headers: CORS });
});
