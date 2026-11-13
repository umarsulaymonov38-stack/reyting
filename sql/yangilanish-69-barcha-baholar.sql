-- Yangilanish 69: Ota-ona va sinf rahbariga BARCHA baholar — qaysi fandan, kim, qachon qo'ygan:
--   1) fan o'qituvchilari (asosiy sinfdagi fan baholari);
--   2) guruhlar — 3-guruh (Matematika), 4-guruh (Ingliz tili), 6-guruh (Arab/Koreys tili): davomat, uyga vazifa, faollik, tartib;
--   3) repetitor guruhlari: davomat va topshiriq bahosi.
--   Guruhlarda o'quvchi alohida yozilgan — u asosiy sinfdagi farzand bilan ISM-FAMILIYASI bo'yicha (va sinf darajasi mos kelsa) bog'lanadi.
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing (loyiha: YUKSALISH-REYTING). Qayta ishga tushirish xavfsiz.

create index if not exists students_norm_idx on public.students (public.yk_norm3(full_name));

-- Asosiy sinfdagi o'quvchilar (kids) uchun barcha baholar — ichki yordamchi
create or replace function public.yk_grades_of(p_kids text[], p_from date, p_to date)
returns table (student_id text, day date, subject text, teacher text, src text, class_name text,
               att int, excused boolean, hw int, activity int, grade int, behavior int, beh_band int, ss_id bigint, at timestamptz)
language sql stable security definer set search_path = public as $$
  with k as (
    select s.id, s.full_name, public.yk_norm3(s.full_name) as nk, c.grade as cg, c.name as cn
      from public.students s join public.classes c on c.id = s.class_id
     where s.id::text = any(p_kids)),
  links as (  -- guruh va repetitor yozuvlari: ism-familiya bir xil, sinf darajasi mos (yoki ko'rsatilmagan)
    select k.id as kid, g.id as gid, gc.id as gcid, gc.name::text as gname, gc.kind is not distinct from 'rep' as rep,
           coalesce(nullif(gc.subject, ''), gc.name)::text as subj
      from k join public.students g on public.yk_norm3(g.full_name) = k.nk and g.id <> k.id
      join public.classes gc on gc.id = g.class_id
     where (gc.kind = 'rep' or coalesce(gc.grp, '') <> '' or coalesce(gc.subject, '') ~* '^(arab|koreys)')
       and (gc.grade is null or k.cg is null or gc.grade = k.cg)),
  tch as (
    select t.class_id, string_agg(p.full_name::text, ', ' order by p.full_name) as names
      from public.teacher_classes t join public.profiles p on p.id = t.user_id group by t.class_id)
  -- 1. fan baholari
  select ss.student_id::text, ss.day, coalesce(nullif(ss.subject, ''), p.full_name, 'Fan')::text, p.full_name::text, 'fan', null::text,
         ss.att, ss.excused, ss.hw, ss.activity, ss.grade, null::int, null::int, ss.id, ss.updated_at
    from public.subject_scores ss join k on k.id = ss.student_id
    left join public.profiles p on p.id = ss.teacher_id
   where ss.day between p_from and p_to
  union all
  -- 2. guruh baholari (3-, 4-, 6-guruh)
  select l.kid::text, d.day, l.subj, tch.names, 'guruh', l.gname,
         d.att, d.excused, d.hw, d.activity, null::int, d.behavior, d.beh_band::int, null::bigint, d.updated_at
    from links l join public.daily_scores d on d.student_id = l.gid
    left join tch on tch.class_id = l.gcid
   where not l.rep and d.day between p_from and p_to
  union all
  -- 3. repetitor
  select l.kid::text, r.day, l.subj, tch.names, 'rep', l.gname,
         r.att::int, null::boolean, null::int, null::int, (to_jsonb(r) ->> 'task')::int, null::int, null::int, null::bigint, (to_jsonb(r) ->> 'updated_at')::timestamptz
    from links l join public.rep_daily r on r.student_id = l.gid
    left join tch on tch.class_id = l.gcid
   where l.rep and r.day between p_from and p_to
$$;
revoke all on function public.yk_grades_of(text[], date, date) from public, anon, authenticated;

-- Ota-ona: o'z farzandlari
create or replace function public.parent_grades(p_from date, p_to date)
returns table (student_id text, day date, subject text, teacher text, src text, class_name text,
               att int, excused boolean, hw int, activity int, grade int, behavior int, beh_band int, ss_id bigint, at timestamptz)
language sql stable security definer set search_path = public as $$
  select * from public.yk_grades_of(array(select k.id::text from public.my_kids() k), p_from, p_to)
   order by 2 desc, 15 desc nulls last
$$;
revoke all on function public.parent_grades(date, date) from public, anon;
grant execute on function public.parent_grades(date, date) to authenticated;

-- Sinf rahbari / admin: sinfdagi barcha o'quvchilar
create or replace function public.class_grades(p_class bigint, p_from date, p_to date)
returns table (student_id text, day date, subject text, teacher text, src text, class_name text,
               att int, excused boolean, hw int, activity int, grade int, behavior int, beh_band int, ss_id bigint, at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.yk_role() = 'admin' or coalesce(public.yk_admin2(), false)
          or exists (select 1 from public.teacher_classes t where t.user_id = auth.uid() and t.class_id = p_class)) then
    raise exception 'Bu sinfga ruxsatingiz yo''q' using errcode = '42501';
  end if;
  return query select * from public.yk_grades_of(array(select s.id::text from public.students s where s.class_id = p_class), p_from, p_to);
end $$;
revoke all on function public.class_grades(bigint, date, date) from public, anon;
grant execute on function public.class_grades(bigint, date, date) to authenticated;

notify pgrst, 'reload schema';
