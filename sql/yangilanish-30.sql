-- Yangilanish 30: ota-onalar uchun parol varaqalari (admin sinf bo'yicha akkaunt ochib, PDF yuklab oladi).
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing. Qayta ishga tushirish xavfsiz.
-- Parolning o'zi HECH QAYERDA saqlanmaydi — faqat qaysi telefon uchun qaysi sinf varaqasida parol berilgani yoziladi
-- (keyingi safar "parol 3-A varaqasida berilgan" deb ko'rsatish uchun).

create table if not exists public.parent_pw_log (
  phone text primary key,
  class_id bigint,
  class_name text,
  created_at timestamptz not null default now()
);
alter table public.parent_pw_log enable row level security;
grant select, insert, update on public.parent_pw_log to authenticated;
drop policy if exists parent_pw_log_admin on public.parent_pw_log;
create policy parent_pw_log_admin on public.parent_pw_log for all to authenticated
  using (public.yk_role() = 'admin') with check (public.yk_role() = 'admin');

notify pgrst, 'reload schema';
