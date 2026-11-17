-- Yangilanish 77: «Baholanmaganlar» takomillashtirildi + har kuni soat 15:00 da eslatma.
--   1) class_gaps(sinf, kun): SINF RAHBARIGA — qaysi fan/guruh ustozi qaysi o'quvchisini baholamagan
--      (asosiy sinfdagi fan o'qituvchilari, guruhlar — Matematika, Ingliz tili, Arab/Koreys tili, repetitor — va kunlik vazifalar).
--   2) my_gaps(kun): har bir o'qituvchiga — o'zi bugun baholamagan o'quvchilar.
--   3) Har kuni (dushanba–shanba) soat 15:00 da baholamagan o'qituvchi va sinf rahbarlariga telefon eslatmasi
--      (o'qituvchi platformada «Eslatmalarni yoqish» tugmasini bosgan bo'lishi kerak).
--   Dars bo'lgan kun — O'qituvchilar bo'limidagi «Dars kunlari» bo'yicha (sinf rahbari — har ish kuni).
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing (loyiha: YUKSALISH-REYTING). Avval 64, 69 va 75 ishga tushgan bo'lsin.
-- Qayta ishga tushirish xavfsiz.

-- Ichki: barcha o'qituvchilar bo'yicha bir kun
create or replace function public.yk_gaps_all(p_day date)
returns table (user_id uuid, teacher text, phone text, class_id bigint, class_name text, role text, subject text,
               sched boolean, n int, done int, missing text[], missing_ids text[])
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare dw int := extract(isodow from p_day)::int;
begin
  return query
  with tc as (
    select t.user_id, t.class_id::bigint as cid, coalesce(t.role, 'fan')::text as role, t.subject::text as subject, t.days,
           c.name::text as cname, c.kind = 'rep' as rep, (c.kind is distinct from 'rep' and coalesce(c.grp, '') = '') as is_main
      from public.teacher_classes t join public.classes c on c.id = t.class_id),
  st as (select s.id, s.class_id::bigint as class_id, s.full_name::text as full_name, s.slot
           from public.students s where coalesce(btrim(s.full_name), '') <> ''),
  has_rows as (  -- guruhda shu kuni biror baho bormi (jadval kiritilmagan guruhlar uchun)
    select distinct s.class_id::bigint as cid from public.daily_scores d join public.students s on s.id = d.student_id where d.day = p_day
    union
    select distinct s.class_id::bigint from public.rep_daily r join public.students s on s.id = r.student_id where r.day = p_day),
  act as (  -- shu kuni dars/vazifa bo'lgan biriktirishlar
    select tc.* from tc
     where (tc.is_main and tc.role = 'rahbar' and dw <= 5)
        or (tc.is_main and tc.role <> 'rahbar' and tc.days is not null and dw = any(tc.days))
        or (not tc.is_main and tc.days is not null and dw = any(tc.days))
        or (not tc.is_main and tc.days is null and tc.cid in (select cid from has_rows))),
  chk as (
    select a.user_id, a.cid, st.id::text as sid, st.full_name, st.slot,
           case when a.is_main and a.role <> 'rahbar' then
                  exists (select 1 from public.subject_scores ss where ss.student_id = st.id and ss.day = p_day and ss.teacher_id = a.user_id
                                and ss.att is not null and (ss.att = 0 or ss.grade is not null))
                when a.rep then exists (select 1 from public.rep_daily r where r.student_id = st.id and r.day = p_day and r.done_at is not null)
                else exists (select 1 from public.daily_scores d where d.student_id = st.id and d.day = p_day and d.done_at is not null) end as ok
      from act a join st on st.class_id = a.cid)
  select a.user_id, p.full_name::text, p.phone::text, a.cid, a.cname, a.role, a.subject, a.days is not null,
         (select count(*) from chk where chk.user_id = a.user_id and chk.cid = a.cid)::int,
         (select count(*) from chk where chk.user_id = a.user_id and chk.cid = a.cid and chk.ok)::int,
         coalesce((select array_agg(chk.full_name order by chk.slot) from chk where chk.user_id = a.user_id and chk.cid = a.cid and not chk.ok), '{}'::text[]),
         coalesce((select array_agg(chk.sid order by chk.slot) from chk where chk.user_id = a.user_id and chk.cid = a.cid and not chk.ok), '{}'::text[])
    from act a join public.profiles p on p.id = a.user_id
   order by p.full_name, a.cname;
end $$;
revoke all on function public.yk_gaps_all(date) from public, anon, authenticated;

-- O'qituvchi: o'zi bugun baholamaganlar
create or replace function public.my_gaps(p_day date)
returns table (class_id bigint, class_name text, role text, subject text, n int, done int, missing text[])
language sql stable security definer set search_path = public as $$
  select g.class_id, g.class_name, g.role, g.subject, g.n, g.done, g.missing
    from public.yk_gaps_all(p_day) g
   where g.user_id = auth.uid() and g.n > g.done and p_day <= (now() at time zone 'Asia/Tashkent')::date
$$;
revoke all on function public.my_gaps(date) from public, anon;
grant execute on function public.my_gaps(date) to authenticated;

-- Sinf rahbari / admin: sinfdagi o'quvchilar — qaysi ustoz baholamagan
create or replace function public.class_gaps(p_class bigint, p_day date)
returns table (teacher text, subject text, kind text, group_name text, student text, slot int)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not (public.yk_role() = 'admin' or coalesce(public.yk_admin2(), false)
          or exists (select 1 from public.teacher_classes t where t.user_id = auth.uid() and t.class_id = p_class)) then
    raise exception 'Bu sinfga ruxsatingiz yo''q' using errcode = '42501';
  end if;
  return query
  with g as (select * from public.yk_gaps_all(p_day)),
  ms as (
    select s.id::text as id, s.full_name::text as nm, s.slot, public.yk_norm3(s.full_name) as nk,
           public.yk_norm3(public.yk_first2(s.full_name)) as nk2,
           coalesce(c.grade, nullif(substring(c.name from '^\s*(\d+)'), '')::int) as cg
      from public.students s join public.classes c on c.id = s.class_id
     where s.class_id = p_class and coalesce(btrim(s.full_name), '') <> ''),
  lk as (  -- asosiy sinf o'quvchisi ↔ guruhdagi yozuvi
    select ms.id as kid, gs.id::text as gid
      from ms join public.students gs on (public.yk_norm3(gs.full_name) = ms.nk or public.yk_norm3(public.yk_first2(gs.full_name)) = ms.nk2)
      join public.classes gc on gc.id = gs.class_id
     where gs.id::text <> ms.id and (gc.kind = 'rep' or coalesce(gc.grp, '') <> '' or coalesce(gc.subject, '') ~* '^(arab|koreys)')
       and (gc.grade is null or ms.cg is null or gc.grade = ms.cg or gc.name ~ ('(^|[^0-9])' || ms.cg || '([^0-9]|$)'))
    union
    select sl.kid, sl.gid from public.student_links sl join ms on ms.id = sl.kid)
  -- 1. shu sinfning o'zi (sinf rahbari — kunlik vazifalar, fan o'qituvchilari — fan baholari)
  select g.teacher, case when g.role = 'rahbar' then 'Kunlik vazifalar' else coalesce(nullif(g.subject, ''), 'Fan') end,
         case when g.role = 'rahbar' then 'rahbar' else 'fan' end, null::text, x.nm, x.slot
    from g cross join lateral unnest(g.missing_ids) as m(id) join ms x on x.id = m.id
   where g.class_id = p_class
  union all
  -- 2. guruh va repetitor darslari (o'quvchi shu sinfdan)
  select g.teacher, coalesce(nullif(g.subject, ''), g.class_name), 'guruh', g.class_name, x.nm, x.slot
    from g cross join lateral unnest(g.missing_ids) as m(id) join lk on lk.gid = m.id join ms x on x.id = lk.kid
   where g.class_id <> p_class
  order by 3, 2, 1, 6;
end $$;
revoke all on function public.class_gaps(bigint, date) from public, anon;
grant execute on function public.class_gaps(bigint, date) to authenticated;

-- Eslatma (bildirishnoma) turi
alter table public.push_queue drop constraint if exists push_queue_kind_check;
alter table public.push_queue add constraint push_queue_kind_check
  check (kind in ('keldi', 'ketdi', 'kelmadi', 'test', 'yomon', 'yaxshi', 'savol', 'javob', 'eslatma'));

-- Har kuni 15:00: baholamagan o'qituvchilarga eslatma
create or replace function public.yk_teacher_reminders() returns int
language plpgsql security definer set search_path = public as $$
declare t date := (now() at time zone 'Asia/Tashkent')::date; n int;
begin
  if extract(isodow from t) = 7 then return 0; end if;
  insert into public.push_queue (user_id, kind, student_id, title, body, day)
  select x.user_id, 'eslatma', x.user_id::text, '📝 Baho qo''yilmagan o''quvchilar',
         'Bugun baholanmagan: ' || string_agg(x.class_name || ' — ' || (x.n - x.done) || ' ta', ', ' order by x.class_name)
           || '. Iltimos, bugunoq baholang.', t
    from public.yk_gaps_all(t) x
   where x.n > x.done and exists (select 1 from public.push_subs s where s.user_id = x.user_id)
   group by x.user_id
  on conflict do nothing;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.yk_teacher_reminders() from public, anon, authenticated;

-- Jadval: har kuni 15:00 (Toshkent) = 10:00 UTC, dushanba–shanba
do $$ begin
  perform cron.unschedule('yk-baho-eslatma');
exception when others then null;
end $$;
do $$ begin
  perform cron.schedule('yk-baho-eslatma', '0 10 * * 1-6', 'select public.yk_teacher_reminders()');
exception when others then raise notice 'pg_cron topilmadi — eslatma jadvali qo''yilmadi: %', sqlerrm;
end $$;

notify pgrst, 'reload schema';

select jobname as "Jadval", schedule as "vaqt (UTC)" from cron.job where jobname = 'yk-baho-eslatma';
