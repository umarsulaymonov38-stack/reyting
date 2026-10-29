// sms-yubor: navbatdagi SMSlarni Eskiz.uz orqali yuboradi.
// Har daqiqada bazadagi jadval (yk_sms_kick) chaqiradi; navbat bo'sh bo'lsa chaqirilmaydi.
// Kerakli maxfiy sozlamalar (Supabase → Edge Functions → Secrets):
//   ESKIZ_EMAIL, ESKIZ_PASSWORD — Eskiz kabinetiga kirish ma'lumotlari
//   ESKIZ_FROM — jo'natuvchi nomi (Eskiz bergan, masalan 4546)
// SUPABASE_URL va SUPABASE_SERVICE_ROLE_KEY Supabase tomonidan o'zi beriladi.
import { createClient } from "jsr:@supabase/supabase-js@2";

const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const API = "https://notify.eskiz.uz/api";

async function login(): Promise<string> {
  const f = new FormData();
  f.append("email", Deno.env.get("ESKIZ_EMAIL") ?? "");
  f.append("password", Deno.env.get("ESKIZ_PASSWORD") ?? "");
  const r = await fetch(API + "/auth/login", { method: "POST", body: f });
  const j = await r.json().catch(() => ({}));
  const t = j?.data?.token;
  if (!t) throw new Error("Eskiz'ga kirib bo'lmadi: " + (j?.message ?? "HTTP " + r.status));
  await sb.rpc("sms_token_set", { p_token: t });
  return t;
}

// Kalit 30 kun amal qiladi — 25 kundan keyin yangilanadi
async function token(): Promise<string> {
  const { data } = await sb.rpc("sms_token_get");
  if (data?.token && Date.now() - new Date(data.token_at).getTime() < 25 * 864e5) return data.token;
  return await login();
}

function send(t: string, phone: string, text: string) {
  const f = new FormData();
  f.append("mobile_phone", phone);
  f.append("message", text);
  f.append("from", Deno.env.get("ESKIZ_FROM") ?? "4546");
  return fetch(API + "/message/sms/send", { method: "POST", headers: { Authorization: "Bearer " + t }, body: f });
}

Deno.serve(async () => {
  const { data: rows, error } = await sb.rpc("sms_claim", { p_limit: 60 });
  if (error) return new Response(error.message, { status: 500 });
  if (!rows?.length) return Response.json({ yuborildi: 0 });

  let t: string;
  try {
    t = await token();
  } catch (e) {
    for (const m of rows) await sb.rpc("sms_done", { p_id: m.id, p_ok: false, p_provider: "", p_error: String(e).slice(0, 300) });
    return new Response(String(e), { status: 502 });
  }

  let ok = 0;
  for (const m of rows) {
    let r = await send(t, m.phone, m.text);
    if (r.status === 401) { t = await login(); r = await send(t, m.phone, m.text); }
    const j = await r.json().catch(() => ({}));
    const good = r.ok && j?.status !== "error";
    await sb.rpc("sms_done", {
      p_id: m.id, p_ok: good, p_provider: String(j?.id ?? ""),
      p_error: good ? null : String(j?.message ?? "HTTP " + r.status).slice(0, 300),
    });
    if (good) ok++;
  }
  return Response.json({ yuborildi: ok, jami: rows.length });
});
