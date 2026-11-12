-- Yangilanish 64: «Baho qo'yilmaganlar» — o'qituvchilar bo'yicha, har kunlik, jonli.
--  1) Dars jadvali: har bir o'qituvchi biriktirishiga (o'qituvchi + sinf/guruh) dars kunlari (Du–Sh) belgilanadi.
--  2) teacher_gaps(kun): o'qituvchi → sinf/guruh → baho qo'yilmagan o'quvchilar:
--       sinf rahbari (asosiy sinf) — har ish kuni (Du–Ju): kunlik vazifalar to'liqmi;
--       guruh / repetitor o'qituvchisi — jadvaldagi dars kunlari (jadval kiritilmagan bo'lsa — baho qo'ygan kunlari):
--         davomat va baholar to'liqmi;
--       fan o'qituvchisi (asosiy sinfda) — jadvaldagi dars kunlari: davomat va baho qo'yilganmi (fan baholari).
--  3) yangilanish-63 dagi xato tuzatildi («structure of query does not match function result type»).
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing (loyiha: YUKSALISH-REYTING). Qayta ishga tushirish xavfsiz.

alter table public.teacher_classes add column if not exists days smallint[];

-- 63 dagi funksiya: turlar aniq ko'rsatildi
create or replace function public.grade_gaps(p_from date, p_to date)
returns table (class_id bigint, class_name text, day date, n int, done int, missing text[], teachers text)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not (public.yk_role() = 'admin' or coalesce(public.yk_admin2(), false)) then
    raise exception 'Faqat admin' using errcode = '42501';
  end if;
  p_to := least(p_to, (now() at time zone 'Asia/Tashkent')::date);
  return query
  with cls as (
    select c.id::bigint as id, c.name::text as name, c.kind = 'rep' as rep,
           (c.kind is distinct from 'rep' and coalesce(c.grp, '') = '') as is_main
      from public.classes c),
  st as (select s.id, s.class_id::bigint as class_id, s.full_name::text as full_name, s.slot
           from public.students s where coalesce(btrim(s.full_name), '') <> ''),
  sd as (
    select distinct ds.day from public.daily_scores ds
      join public.students s on s.id = ds.student_id join cls c on c.id = s.class_id and c.is_main
     where ds.day between p_from and p_to and extract(isodow from ds.day) <= 5),
  cday as (
    select c.id as cid, sd.day from cls c join sd on c.is_main
    union
    select s.class_id::bigint, ds.day from public.daily_scores ds join public.students s on s.id = ds.student_id
      join cls c on c.id = s.class_id and not c.is_main and not c.rep
     where ds.day between p_from and p_to
    union
    select s.class_id::bigint, r.day from public.rep_daily r join public.students s on s.id = r.student_id
     where r.day between p_from and p_to),
  rws as (
    select student_id, day, done_at from public.daily_scores where day between p_from and p_to
    union all
    select student_id, day, done_at from public.rep_daily where day between p_from and p_to),
  g as (
    select cd.cid, cd.day, count(st.id)::int as n,
           (count(st.id) filter (where r.done_at is not null))::int as done,
           array_agg(st.full_name order by st.slot) filter (where r.done_at is null) as missing
      from cday cd join st on st.class_id = cd.cid
      left join rws r on r.student_id = st.id and r.day = cd.day
     group by cd.cid, cd.day)
  select g.cid, c.name, g.day, g.n, g.done, coalesce(g.missing, '{}'::text[]),
         (select string_agg(p.full_name::text || case when t.role = 'rahbar' then ' (sinf rahbari)' else '' end, ', '
                            order by t.role = 'rahbar' desc, p.full_name)
            from public.teacher_classes t join public.profiles p on p.id = t.user_id
           where t.class_id = g.cid and (not c.is_main or t.role = 'rahbar'))::text
    from g join cls c on c.id = g.cid
   order by g.day desc, (g.n - g.done) desc, c.name;
end $$;

-- O'qituvchilar bo'yicha: bir kun uchun
create or replace function public.teacher_gaps(p_day date)
returns table (user_id uuid, teacher text, phone text, class_id bigint, class_name text, role text, subject text,
               sched boolean, n int, done int, missing text[])
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare dw int := extract(isodow from p_day)::int;
begin
  if not (public.yk_role() = 'admin' or coalesce(public.yk_admin2(), false)) then
    raise exception 'Faqat admin' using errcode = '42501';
  end if;
  if p_day > (now() at time zone 'Asia/Tashkent')::date then return; end if;
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
    select a.user_id, a.cid, st.full_name, st.slot,
           case when a.is_main and a.role <> 'rahbar' then
                  exists (select 1 from public.subject_scores ss where ss.student_id = st.id and ss.day = p_day and ss.teacher_id = a.user_id
                                and ss.att is not null and (ss.att = 0 or ss.grade is not null))
                when a.rep then exists (select 1 from public.rep_daily r where r.student_id = st.id and r.day = p_day and r.done_at is not null)
                else exists (select 1 from public.daily_scores d where d.student_id = st.id and d.day = p_day and d.done_at is not null) end as ok
      from act a join st on st.class_id = a.cid)
  select a.user_id, p.full_name::text, p.phone::text, a.cid, a.cname, a.role, a.subject, a.days is not null,
         (select count(*) from chk where chk.user_id = a.user_id and chk.cid = a.cid)::int,
         (select count(*) from chk where chk.user_id = a.user_id and chk.cid = a.cid and chk.ok)::int,
         coalesce((select array_agg(chk.full_name order by chk.slot) from chk where chk.user_id = a.user_id and chk.cid = a.cid and not chk.ok), '{}'::text[])
    from act a join public.profiles p on p.id = a.user_id
   order by p.full_name, a.cname;
end $$;
revoke all on function public.teacher_gaps(date) from public, anon;
grant execute on function public.teacher_gaps(date) to authenticated;

notify pgrst, 'reload schema';
