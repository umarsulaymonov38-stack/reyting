-- Yangilanish 36: ota-ona uchun BITTA O'ZGARMAS PAROL — o'quvchining kodi (6 belgi, masalan 3FA9C1).
-- Kod sinf rahbari va adminga ko'rinadi; ota-ona telefon raqami + shu kod bilan kiradi.
-- Akkaunt birinchi kirishda o'zi ochiladi; avval boshqa parol qo'yilgan bo'lsa ham, kod bilan kirganda parol kodga tenglashadi.
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing. Qayta ishga tushirish xavfsiz.
-- Bu fayl o'zi yetarli: yangilanish-30 va 34 ni alohida ishga tushirish shart emas.

create extension if not exists pgcrypto with schema extensions;

-- 0. Yangilanish-34 dagi jadvallar (u ishlamagan bo'lsa ham shu fayl yetarli)
-- 0a. Kimga qaysi sinf varaqasida parol berilgani (yangilanish-30 dagi jadval; u ishga tushirilmagan bo'lsa ham shu yerda yaratiladi)
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

-- 0b. Ota-ona ilovani oxirgi marta qachon ochgani ("hozir onlayn", "bugun kirgan" uchun)
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

-- 1. Har bir o'quvchida kod bo'lsin (yo'q yoki qisqa bo'lsa — yangisi)
do $$ begin
  insert into public.student_private (student_id, code)
  select s.id, upper(substr(md5(random()::text || s.id::text), 1, 6)) from public.students s
   where not exists (select 1 from public.student_private p where p.student_id = s.id);
exception when others then raise notice 'student_private: %', sqlerrm;
end $$;
update public.student_private set code = upper(substr(md5(random()::text || student_id::text), 1, 6))
 where code is null or length(btrim(code)) < 6;

-- 2. Noto'g'ri urinishlar hisobi (bir telefonga soatiga 10 tadan ortiq urinish bloklanadi)
create table if not exists public.parent_code_fail (
  phone text primary key,
  cnt int not null default 0,
  since timestamptz not null default now()
);
alter table public.parent_code_fail enable row level security;
revoke all on public.parent_code_fail from anon, authenticated;

-- 3. Ota-ona telefon + kod bilan kiradi: kod to'g'ri bo'lsa akkaunt paroli kodga tenglashtiriladi
--    natija: {"st":"ok"} — kirish mumkin; {"st":"new","name":"..."} — akkaunt hali yo'q (ilova o'zi ochadi); {"st":"bad"} / {"st":"lock"}
create or replace function public.parent_code_login(p_phone text, p_code text) returns jsonb
language plpgsql security definer set search_path = public, extensions, auth as $$
declare ph text := right(regexp_replace(coalesce(p_phone, ''), '\D', '', 'g'), 9);
        c text := upper(btrim(coalesce(p_code, '')));
        nm text; uid uuid; f public.parent_code_fail;
begin
  if length(ph) <> 9 or length(c) < 6 then return '{"st":"bad"}'; end if;
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
  update auth.users set encrypted_password = extensions.crypt(c, extensions.gen_salt('bf')), updated_at = now()
   where id = uid and case when coalesce(encrypted_password, '') ~ '^\$2' then encrypted_password <> extensions.crypt(c, encrypted_password) else true end;
  return '{"st":"ok"}';
end $$;
revoke all on function public.parent_code_login(text, text) from public;
grant execute on function public.parent_code_login(text, text) to anon, authenticated;

-- 4. Admin "Ota-onalar ulanishi" bo'limi uchun: har bir o'quvchining kodi (paroli) ham qaytadi
drop function if exists public.parent_links();
create function public.parent_links()
returns table (student_id text, class_id bigint, slot int, full_name text, phone text,
               akk boolean, kirgan boolean, last_seen timestamptz, push boolean, pw_class text, opens int, gen boolean, code text)
language plpgsql stable security definer set search_path = public, auth as $$
begin
  if public.yk_role() is distinct from 'admin' then raise exception 'Faqat admin ko''radi' using errcode = '42501'; end if;
  return query
  with s as (
    select st.id, st.class_id, st.slot, st.full_name, sp.claimed_by, sp.code,
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
  ), g as (
    select u.*,
           u.uid is not null and (
             exists (select 1 from public.parent_pw_log pl2 where pl2.phone = u.ph)
             or exists (select 1 from public.profiles pr where pr.id = u.uid and coalesce(to_jsonb(pr) ->> 'full_name', '') like 'Ota-ona:%')
             or (select count(*) from auth.users b where b.email like 'p%@ota.yuksalish.app'
                   and b.created_at between u.ac - interval '2 minutes' and u.ac + interval '2 minutes') >= 3) as gn,
           (select max(se.updated_at) from auth.sessions se where se.user_id = u.uid and se.updated_at > u.ac + interval '5 minutes') as su
      from u
  )
  select u.id::text, u.class_id::bigint, u.slot::int, u.full_name::text, u.ph,
         u.uid is not null,
         -- Kirgan: ilovani ochgan, yoki akkaunt ochilgandan keyin parol bilan kirgan, yoki o'zi ro'yxatdan o'tgan
         u.uid is not null and (ps.user_id is not null or u.ls > u.ac + interval '5 minutes' or u.su is not null or not u.gn),
         case when u.uid is not null then greatest(
           ps.seen_at,
           case when u.ls > u.ac + interval '5 minutes' or not u.gn then u.ls end,
           u.su) end,
         u.uid is not null and exists (select 1 from public.push_subs p where p.user_id = u.uid),
         pl.class_name::text,
         coalesce(ps.opens, 0)::int,
         u.gn,
         upper(btrim(u.code))::text
    from g u
    left join public.parent_seen ps on ps.user_id = u.uid
    left join public.parent_pw_log pl on pl.phone = u.ph
   order by u.class_id, u.slot;
end $$;
revoke all on function public.parent_links() from public, anon;
grant execute on function public.parent_links() to authenticated;

notify pgrst, 'reload schema';
