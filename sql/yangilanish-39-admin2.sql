-- Yangilanish 39: 2-darajali admin (kuzatuvchi).
-- U o'qituvchi akkaunti (telefon + parol bilan kiradi), o'ziga biriktirilgan sinflarda oddiy o'qituvchi kabi ishlaydi,
-- qo'shimcha ravishda butun platformani KO'RADI (kuzatadi), lekin o'zgartira olmaydi:
-- o'zgartirish huquqlari (baho, to'lov, sozlama, parollar) faqat bosh adminda qoladi.
-- Bosh admin «O'qituvchilar» bo'limida o'qituvchiga «2-darajali admin» belgisini qo'yadi.
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing. Qayta ishga tushirish xavfsiz.

alter table public.profiles add column if not exists admin2 boolean not null default false;

create or replace function public.yk_admin2() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select p.admin2 from public.profiles p where p.id = auth.uid() and p.role = 'teacher'), false)
$$;
grant execute on function public.yk_admin2() to authenticated;

-- Bosh admin belgilaydi
create or replace function public.set_admin2(p_id uuid, p_on boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if public.yk_role() is distinct from 'admin' then raise exception 'Faqat bosh admin' using errcode = '42501'; end if;
  update public.profiles set admin2 = coalesce(p_on, false) where id = p_id and role = 'teacher';
  if not found then raise exception 'O''qituvchi topilmadi'; end if;
end $$;
revoke all on function public.set_admin2(uuid, boolean) from public, anon;
grant execute on function public.set_admin2(uuid, boolean) to authenticated;

-- O'qituvchi o'z profilidagi admin2 belgisini o'zi o'zgartira olmasin
create or replace function public.yk_admin2_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.admin2 is distinct from old.admin2 and public.yk_role() is distinct from 'admin' and current_user not in ('postgres', 'supabase_admin', 'service_role') then
    new.admin2 := old.admin2;
  end if;
  return new;
end $$;
drop trigger if exists yk_admin2_guard on public.profiles;
create trigger yk_admin2_guard before update on public.profiles for each row execute function public.yk_admin2_guard();

-- Faqat O'QISH huquqi: barcha jadvallarga (maxfiylari bundan mustasno) 2-darajali admin uchun "select" qoidasi
do $$
declare t text;
begin
  for t in select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'public' and c.relkind = 'r' and c.relrowsecurity
              and c.relname not in ('student_private', 'class_codes', 'tk_config', 'push_secret', 'push_subs', 'staff_devices',
                                    'parent_code_fail', 'parent_pw_set', 'sms_config', 'sms_settings', 'sms_secret', 'parent_checkin') loop
    execute format('drop policy if exists admin2_read on public.%I', t);
    execute format('create policy admin2_read on public.%I for select to authenticated using (public.yk_admin2())', t);
  end loop;
end $$;

-- O'qituvchilar reytingi: 2-darajali admin ham barcha o'qituvchilarni ko'radi
create or replace function public.teacher_rating(p_from date, p_to date)
returns table (user_id uuid, full_name text, phone text, classes text, class_days int, on_time int, late int, missed int, score int)
language sql stable security definer set search_path = public as $$
with nowt as (select (now() at time zone 'Asia/Tashkent') t),
cut as (  -- bugungi kun faqat 21:00 dan keyin hisoblanadi
  select case when (select t from nowt)::time >= time '21:00' then (select t from nowt)::date
              else (select t from nowt)::date - 1 end as last_day
),
cls as (
  select c.id, c.name, (c.kind is distinct from 'rep' and coalesce(c.grp, '') = '') as is_main from public.classes c
),
st as (select s.id, s.class_id from public.students s where coalesce(btrim(s.full_name), '') <> ''),
sd as (  -- maktab ish kunlari: asosiy sinflarning birortasida baho bor kunlar
  select distinct ds.day from public.daily_scores ds
    join public.students s on s.id = ds.student_id join cls c on c.id = s.class_id and c.is_main
   where ds.day between p_from and least(p_to, (select last_day from cut))
),
cday as (
  select c.id as class_id, sd.day from cls c join sd on c.is_main
  union
  select s.class_id, ds.day from public.daily_scores ds join public.students s on s.id = ds.student_id
    join cls c on c.id = s.class_id and not c.is_main
   where ds.day between p_from and least(p_to, (select last_day from cut))
  union
  select s.class_id, r.day from public.rep_daily r join public.students s on s.id = r.student_id
   where r.day between p_from and least(p_to, (select last_day from cut))
),
rws as (
  select student_id, day, done_at from public.daily_scores where day between p_from and p_to
  union all
  select student_id, day, done_at from public.rep_daily where day between p_from and p_to
),
cstat as (
  select cd.class_id, cd.day, count(st.id) as n,
         count(r.student_id) filter (where r.done_at is not null) as done,
         count(r.student_id) filter (where r.done_at <= ((cd.day + time '21:00') at time zone 'Asia/Tashkent')) as ok
    from cday cd join st on st.class_id = cd.class_id
    left join rws r on r.student_id = st.id and r.day = cd.day
   group by cd.class_id, cd.day
),
tc as (
  select t.user_id, t.class_id from public.teacher_classes t
   where public.yk_role() = 'admin' or public.yk_admin2() or t.user_id = auth.uid()
)
select p.id, p.full_name, p.phone,
       (select string_agg(c.name, ', ' order by c.name) from tc t2 join public.classes c on c.id = t2.class_id where t2.user_id = p.id),
       count(cs.class_id)::int,
       (count(cs.class_id) filter (where cs.ok = cs.n))::int,
       (count(cs.class_id) filter (where cs.done = cs.n and cs.ok < cs.n))::int,
       (count(cs.class_id) filter (where cs.done < cs.n))::int,
       greatest(0, 100 - 2 * (count(cs.class_id) filter (where cs.done = cs.n and cs.ok < cs.n))
                       - 5 * (count(cs.class_id) filter (where cs.done < cs.n)))::int
  from public.profiles p
  join (select distinct user_id from tc) u on u.user_id = p.id
  left join tc on tc.user_id = p.id
  left join cstat cs on cs.class_id = tc.class_id
 group by p.id, p.full_name, p.phone
 order by 9 desc, 6 desc, 2
$$;

-- Ota-onalar ulanishi: 2-darajali admin ham ko'radi, lekin parollarni (kodlarni) — yo'q
drop function if exists public.parent_links();
create function public.parent_links()
returns table (student_id text, class_id bigint, slot int, full_name text, phone text,
               akk boolean, kirgan boolean, last_seen timestamptz, push boolean, pw_class text, opens int, gen boolean, code text)
language plpgsql stable security definer set search_path = public, auth as $$
begin
  if public.yk_role() is distinct from 'admin' and not public.yk_admin2() then raise exception 'Faqat admin ko''radi' using errcode = '42501'; end if;
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
         case when public.yk_role() = 'admin' then upper(btrim(u.code)) end::text  -- parol (kod) faqat bosh adminga
    from g u
    left join public.parent_seen ps on ps.user_id = u.uid
    left join public.parent_pw_log pl on pl.phone = u.ph
   order by u.class_id, u.slot;
end $$;
revoke all on function public.parent_links() from public, anon;
grant execute on function public.parent_links() to authenticated;

-- Ota-onalar savolnomasi natijasi
create or replace function public.checkin_stats(p_days int default 14)
returns table (day date, javob int, talk int, kun int, qiziqish int, orzu int)
language plpgsql stable security definer set search_path = public as $$
begin
  if public.yk_role() is distinct from 'admin' and not public.yk_admin2() then raise exception 'Faqat admin' using errcode = '42501'; end if;
  return query
  select c.day, count(*)::int,
         round(100.0 * count(*) filter (where c.q_talk) / count(*))::int,
         round(100.0 * count(*) filter (where c.q_day) / count(*))::int,
         round(100.0 * count(*) filter (where c.q_interest) / count(*))::int,
         round(100.0 * count(*) filter (where c.q_dream) / count(*))::int
    from public.parent_checkin c
   where c.day > (now() at time zone 'Asia/Tashkent')::date - greatest(p_days, 1)
   group by c.day order by c.day desc;
end $$;

notify pgrst, 'reload schema';
