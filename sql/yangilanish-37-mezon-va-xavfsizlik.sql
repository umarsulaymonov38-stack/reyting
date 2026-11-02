-- Yangilanish 37:
--  1) 1–2-guruh: «Fanlardagi faollik» olib tashlandi; qolgan mezonlar ×1.25 (1-sinfda ×5/3) — kuniga 51, oyiga 1020 ball saqlanadi.
--  2) 3-, 4-, 6-guruh: tartib-intizom bandi (1 — tartib qoidaga amal qilmaslik, 2 — hurmat qilmaslik, 3 — joyini toza saqlamaslik).
--  3) Xavfsizlik: sinf rahbari / o'qituvchi ota-ona nomidan kira olmasin va fikr yoza olmasin:
--     - ota-ona birinchi kirishda (o'quvchi kodi bilan) O'Z PAROLINI o'rnatadi; shundan keyin kod bilan kirib bo'lmaydi;
--     - o'qituvchi kirgan qurilmadan ota-ona sifatida kirish va fikr yozish taqiqlanadi;
--     - parolini unutgan ota-ona uchun faqat admin parolni kodga qaytaradi.
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing. Qayta ishga tushirish xavfsiz.

create extension if not exists pgcrypto with schema extensions;

-- 1. Kunlik ball (1–2-guruh): davomat 1 + mezonlar yig'indisi 50 ga keltiriladi; «activity» endi hisobga olinmaydi
create or replace function public.yk_day_total(g1 boolean, att int, book int, sport int, behavior int, kindness int, activity int)
returns int language sql immutable as $$
  select (case when att = 1 then 1 else 0 end)
       + case when g1 then round((coalesce(sport, 0) + coalesce(behavior, 0) + coalesce(kindness, 0)) * 5 / 3.0)::int
              else round((coalesce(book, 0) + coalesce(sport, 0) + coalesce(behavior, 0) + coalesce(kindness, 0)) * 1.25)::int end
$$;

-- 2. Tartib-intizom bandi (3-, 4-, 6-guruh)
alter table public.daily_scores add column if not exists beh_band smallint;
alter table public.daily_scores drop constraint if exists daily_scores_beh_band_chk;
alter table public.daily_scores add constraint daily_scores_beh_band_chk check (beh_band between 1 and 3);

-- 3a. O'qituvchilar ishlatgan qurilmalar (brauzer belgisi)
create table if not exists public.staff_devices (
  dev text primary key,
  user_id uuid,
  seen_at timestamptz not null default now()
);
alter table public.staff_devices enable row level security;
revoke all on public.staff_devices from anon, authenticated;

create or replace function public.staff_device(p_dev text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(length(p_dev), 0) < 10 or public.yk_role() is distinct from 'teacher' then return; end if;
  insert into public.staff_devices (dev, user_id) values (p_dev, auth.uid())
  on conflict (dev) do update set user_id = excluded.user_id, seen_at = now();
end $$;
revoke all on function public.staff_device(text) from public, anon;
grant execute on function public.staff_device(text) to authenticated;

-- Ota-ona kirganda: shu qurilmada o'qituvchi ishlaganmi
create or replace function public.parent_dev_ok(p_dev text) returns boolean
language sql stable security definer set search_path = public as $$
  select not exists (select 1 from public.staff_devices where dev = p_dev)
$$;
revoke all on function public.parent_dev_ok(text) from public;
grant execute on function public.parent_dev_ok(text) to anon, authenticated;

-- 3b. O'z parolini o'rnatgan ota-onalar (shundan keyin o'quvchi kodi bilan kirib bo'lmaydi)
create table if not exists public.parent_pw_set (
  user_id uuid primary key,
  set_at timestamptz not null default now(),
  dev text
);
alter table public.parent_pw_set enable row level security;
revoke all on public.parent_pw_set from anon, authenticated;

create or replace function public.parent_pw_status() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.parent_pw_set where user_id = auth.uid())
$$;
revoke all on function public.parent_pw_status() from public, anon;
grant execute on function public.parent_pw_status() to authenticated;

-- Ota-ona yangi parolni o'rnatgach chaqiradi. Parol o'quvchi kodi bilan bir xil bo'lsa — qabul qilinmaydi.
create or replace function public.parent_pw_mark(p_dev text) returns text
language plpgsql security definer set search_path = public, extensions, auth as $$
declare uid uuid := auth.uid(); ph text; pw text;
begin
  if uid is null or public.yk_role() is distinct from 'parent' then return 'rol'; end if;
  select substring(email from '^p(\d{9})@'), encrypted_password into ph, pw from auth.users where id = uid;
  if exists (select 1 from public.student_private sp
              where right(regexp_replace(coalesce(sp.parent_phone, ''), '\D', '', 'g'), 9) = ph
                and coalesce(pw, '') ~ '^\$2' and pw = extensions.crypt(upper(btrim(sp.code)), pw)) then
    return 'kod';
  end if;
  insert into public.parent_pw_set (user_id, dev) values (uid, p_dev)
  on conflict (user_id) do update set set_at = now(), dev = excluded.dev;
  return 'ok';
end $$;
revoke all on function public.parent_pw_mark(text) from public, anon;
grant execute on function public.parent_pw_mark(text) to authenticated;

-- Admin: parolini unutgan ota-ona — paroli yana o'quvchi kodiga qaytadi (keyingi kirishda yangisini o'rnatadi)
create or replace function public.admin_parent_unlock(p_phone text) returns void
language plpgsql security definer set search_path = public, auth as $$
declare ph text := right(regexp_replace(coalesce(p_phone, ''), '\D', '', 'g'), 9);
begin
  if public.yk_role() is distinct from 'admin' then raise exception 'Faqat admin' using errcode = '42501'; end if;
  delete from public.parent_pw_set where user_id in (select id from auth.users where email = 'p' || ph || '@ota.yuksalish.app');
  delete from public.parent_code_fail where phone = ph;
end $$;
revoke all on function public.admin_parent_unlock(text) from public, anon;
grant execute on function public.admin_parent_unlock(text) to authenticated;

-- 3c. Kod bilan kirish: o'z parolini o'rnatgan bo'lsa yoki o'qituvchi qurilmasi bo'lsa — rad etiladi
drop function if exists public.parent_code_login(text, text);
create or replace function public.parent_code_login(p_phone text, p_code text, p_dev text default null) returns jsonb
language plpgsql security definer set search_path = public, extensions, auth as $$
declare ph text := right(regexp_replace(coalesce(p_phone, ''), '\D', '', 'g'), 9);
        c text := upper(btrim(coalesce(p_code, '')));
        nm text; uid uuid; f public.parent_code_fail;
begin
  if length(ph) <> 9 or length(c) < 6 then return '{"st":"bad"}'; end if;
  if p_dev is not null and exists (select 1 from public.staff_devices where dev = p_dev) then return '{"st":"staff"}'; end if;
  select * into f from public.parent_code_fail where phone = ph;
  if f.phone is not null and f.since > now() - interval '1 hour' and f.cnt >= 10 then return '{"st":"lock"}'; end if;
  select s.full_name into nm
    from public.student_private sp join public.students s on s.id = sp.student_id
   where right(regexp_replace(coalesce(sp.parent_phone, ''), '\D', '', 'g'), 9) = ph and upper(btrim(sp.code)) = c
   limit 1;
  if nm is null then
    insert into public.parent_code_fail (phone, cnt, since) values (ph, 1, now())
    on conflict (phone) do update set
      cnt = case when public.parent_code_fail.since < now() - interval '1 hour' then 1 else public.parent_code_fail.cnt + 1 end,
      since = case when public.parent_code_fail.since < now() - interval '1 hour' then now() else public.parent_code_fail.since end;
    return '{"st":"bad"}';
  end if;
  delete from public.parent_code_fail where phone = ph;
  select au.id into uid from auth.users au where au.email = 'p' || ph || '@ota.yuksalish.app';
  if uid is null then return jsonb_build_object('st', 'new', 'name', nm); end if;
  if exists (select 1 from public.parent_pw_set where user_id = uid) then return '{"st":"own"}'; end if;
  update auth.users set encrypted_password = extensions.crypt(c, extensions.gen_salt('bf')), updated_at = now()
   where id = uid and case when coalesce(encrypted_password, '') ~ '^\$2' then encrypted_password <> extensions.crypt(c, encrypted_password) else true end;
  return '{"st":"ok"}';
end $$;
revoke all on function public.parent_code_login(text, text, text) from public;
grant execute on function public.parent_code_login(text, text, text) to anon, authenticated;

-- 3d. Fikr-mulohaza: o'qituvchi qurilmasidan yozib bo'lmaydi
alter table public.feedback add column if not exists dev text;
create or replace function public.yk_feedback_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if public.yk_role() is distinct from 'parent' then
    raise exception 'Fikrni faqat ota-ona yozadi' using errcode = '42501';
  end if;
  if new.dev is null or exists (select 1 from public.staff_devices where dev = new.dev) then
    raise exception 'Bu qurilmada o''qituvchi akkaunti ishlatilgan — ota-ona nomidan fikr yozib bo''lmaydi' using errcode = '42501';
  end if;
  return new;
end $$;
drop trigger if exists yk_feedback_guard on public.feedback;
create trigger yk_feedback_guard before insert on public.feedback for each row execute function public.yk_feedback_guard();

notify pgrst, 'reload schema';
