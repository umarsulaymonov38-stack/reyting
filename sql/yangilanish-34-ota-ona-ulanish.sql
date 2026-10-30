-- Yangilanish 34: ota-onalar platformaga ulanishi (admin uchun jonli tahlil) va ota-onaga yangi parol berish.
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing. Qayta ishga tushirish xavfsiz.
-- Parollar bu yerda ham saqlanmaydi: yangi parol faqat shifrlangan (bcrypt) holda auth.users ga yoziladi.

-- 0. Kimga qaysi sinf varaqasida parol berilgani (yangilanish-30 dagi jadval; u ishga tushirilmagan bo'lsa ham shu yerda yaratiladi)
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

-- 1. Ota-ona ilovani oxirgi marta qachon ochgani ("hozir onlayn", "bugun kirgan" uchun)
create table if not exists public.parent_seen (
  user_id uuid primary key,
  seen_at timestamptz not null default now(),
  opens int not null default 1
);
alter table public.parent_seen enable row level security;
revoke all on public.parent_seen from anon, authenticated;

create or replace function public.parent_ping() returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or public.yk_role() is distinct from 'parent' then return; end if;
  insert into public.parent_seen (user_id) values (auth.uid())
  on conflict (user_id) do update
    set opens = public.parent_seen.opens + case when public.parent_seen.seen_at < now() - interval '30 minutes' then 1 else 0 end,
        seen_at = now();
end $$;
revoke all on function public.parent_ping() from public, anon;
grant execute on function public.parent_ping() to authenticated;

-- 2. Har bir o'quvchi bo'yicha: telefon bormi, ota-onaning akkaunti bormi, kirganmi, oxirgi faolligi, bildirishnoma
create or replace function public.parent_links()
returns table (student_id text, class_id bigint, slot int, full_name text, phone text,
               akk boolean, kirgan boolean, last_seen timestamptz, push boolean, pw_class text, opens int)
language plpgsql stable security definer set search_path = public, auth as $$
begin
  if public.yk_role() is distinct from 'admin' then raise exception 'Faqat admin ko''radi' using errcode = '42501'; end if;
  return query
  with s as (
    select st.id, st.class_id, st.slot, st.full_name, sp.claimed_by,
           case when length(d.v) = 9 then d.v end as ph
      from public.students st
      left join public.student_private sp on sp.student_id = st.id
      cross join lateral (select right(regexp_replace(coalesce(sp.parent_phone, ''), '\D', '', 'g'), 9) as v) d
     where btrim(coalesce(st.full_name, '')) <> ''
  ), u as (
    select s.*, coalesce(a1.id, a2.id) as uid, coalesce(a1.created_at, a2.created_at) as ac,
           coalesce(a1.last_sign_in_at, a2.last_sign_in_at) as ls
      from s
      left join auth.users a1 on a1.id = s.claimed_by
      left join auth.users a2 on a1.id is null and s.ph is not null and a2.email = 'p' || s.ph || '@ota.yuksalish.app'
  )
  select u.id::text, u.class_id::bigint, u.slot::int, u.full_name::text, u.ph,
         u.uid is not null,
         -- Kirgan: o'zi ro'yxatdan o'tgan, yoki admin bergan parol bilan keyinroq kirgan, yoki ilovani ochgan
         u.uid is not null and (
           ps.user_id is not null
           or pl.phone is null
           or u.ls > u.ac + interval '5 minutes'
           or exists (select 1 from auth.sessions se where se.user_id = u.uid and se.updated_at > u.ac + interval '5 minutes')),
         case when u.uid is not null then greatest(
           ps.seen_at,
           case when u.ls > u.ac + interval '5 minutes' or pl.phone is null then u.ls end,
           (select max(se.updated_at) from auth.sessions se where se.user_id = u.uid and se.updated_at > u.ac + interval '5 minutes')) end,
         u.uid is not null and exists (select 1 from public.push_subs p where p.user_id = u.uid),
         pl.class_name::text,
         coalesce(ps.opens, 0)::int
    from u
    left join public.parent_seen ps on ps.user_id = u.uid
    left join public.parent_pw_log pl on pl.phone = u.ph
   order by u.class_id, u.slot;
end $$;
revoke all on function public.parent_links() from public, anon;
grant execute on function public.parent_links() to authenticated;

-- 3. Admin ota-onaga yangi parol beradi (varaqani yo'qotgan yoki hali kirmagan ota-ona uchun)
create extension if not exists pgcrypto with schema extensions;
create or replace function public.admin_parent_pw(p_phone text, p_pw text) returns void
language plpgsql security definer set search_path = public, extensions, auth as $$
declare ph text := right(regexp_replace(coalesce(p_phone, ''), '\D', '', 'g'), 9); uid uuid;
begin
  if public.yk_role() is distinct from 'admin' then raise exception 'Faqat admin o''zgartiradi' using errcode = '42501'; end if;
  if length(ph) <> 9 then raise exception 'Telefon raqam noto''g''ri'; end if;
  if length(coalesce(p_pw, '')) < 6 then raise exception 'Parol kamida 6 belgidan iborat bo''lsin'; end if;
  select au.id into uid from auth.users au where au.email = 'p' || ph || '@ota.yuksalish.app';
  if uid is null then raise exception 'Bu telefonda ota-ona akkaunti yo''q'; end if;
  if exists (select 1 from public.profiles p where p.id = uid and p.role is distinct from 'parent') then
    raise exception 'Bu akkaunt ota-onaniki emas';
  end if;
  update auth.users set encrypted_password = extensions.crypt(p_pw, extensions.gen_salt('bf')), updated_at = now() where id = uid;
end $$;
revoke all on function public.admin_parent_pw(text, text) from public, anon;
grant execute on function public.admin_parent_pw(text, text) to authenticated;

notify pgrst, 'reload schema';
