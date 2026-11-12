-- Yangilanish 63: Admin uchun «Baho qo'yilmaganlar» — tanlangan davrda (kun/hafta) har bir sinf/guruh bo'yicha
-- qaysi kuni qaysi o'quvchilarga baho to'liq qo'yilmagan va mas'ul o'qituvchi kim.
--   Asosiy sinflar (1–10): maktab ish kunlari (dushanba–juma, birorta sinfda baho bor kunlar) — har bir kun tekshiriladi;
--   guruhlar (3-, 4-, 6-guruh) va repetitor guruhlari: dars bo'lgan kunlar (o'qituvchi kamida bitta baho qo'ygan kunlar).
--   «To'liq» — o'qituvchilar reytingidagi kabi: davomat va barcha mezonlar qo'yilgan (kelmagan bo'lsa — faqat davomat).
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing (loyiha: YUKSALISH-REYTING). Qayta ishga tushirish xavfsiz.

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
    select c.id, c.name, c.kind = 'rep' as rep, (c.kind is distinct from 'rep' and coalesce(c.grp, '') = '') as is_main
      from public.classes c),
  st as (select s.id, s.class_id, s.full_name, s.slot from public.students s where coalesce(btrim(s.full_name), '') <> ''),
  sd as (  -- maktab ish kunlari
    select distinct ds.day from public.daily_scores ds
      join public.students s on s.id = ds.student_id join cls c on c.id = s.class_id and c.is_main
     where ds.day between p_from and p_to and extract(isodow from ds.day) <= 5),
  cday as (
    select c.id as cid, sd.day from cls c join sd on c.is_main
    union
    select s.class_id, ds.day from public.daily_scores ds join public.students s on s.id = ds.student_id
      join cls c on c.id = s.class_id and not c.is_main and not c.rep
     where ds.day between p_from and p_to
    union
    select s.class_id, r.day from public.rep_daily r join public.students s on s.id = r.student_id
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
  select g.cid, c.name, g.day, g.n, g.done, coalesce(g.missing, '{}'),
         (select string_agg(p.full_name || case when t.role = 'rahbar' then ' (sinf rahbari)' else '' end, ', '
                            order by t.role = 'rahbar' desc, p.full_name)
            from public.teacher_classes t join public.profiles p on p.id = t.user_id
           where t.class_id = g.cid and (not c.is_main or t.role = 'rahbar'))
    from g join cls c on c.id = g.cid
   order by g.day desc, (g.n - g.done) desc, c.name;
end $$;
revoke all on function public.grade_gaps(date, date) from public, anon;
grant execute on function public.grade_gaps(date, date) to authenticated;

notify pgrst, 'reload schema';
