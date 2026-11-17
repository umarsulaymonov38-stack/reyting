-- Yangilanish 74: Ota-onaga fan/guruh baholari — bog'lash kuchaytirildi.
--   1) Guruh nomidagi sinflar oralig'i hisobga olinadi: «5-6-sinf Arab tili» 6-sinf o'quvchisiga ham, «(8-9-10)» — 9/10-sinfga ham.
--   2) Ism solishtirish: to'liq ism YOKI faqat familiya + ism (otasining ismi yozilgan/yozilmaganidan qat'i nazar).
--   3) Oxirida tekshiruv: guruhlardagi qaysi o'quvchilar asosiy sinf bilan bog'lanmayapti (ota-onasi baholarni ko'rmaydi) —
--      ularning ismini guruhda asosiy sinfdagidek yozing.
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing (loyiha: YUKSALISH-REYTING). Avval 69 ishga tushgan bo'lsin.
-- Qayta ishga tushirish xavfsiz.

create or replace function public.yk_grades_of(p_kids text[], p_from date, p_to date)
returns table (student_id text, day date, subject text, teacher text, src text, class_name text,
               att int, excused boolean, hw int, activity int, grade int, behavior int, beh_band int, ss_id bigint, at timestamptz)
language sql stable security definer set search_path = public as $$
  with k as (
    select s.id, s.full_name, public.yk_norm3(s.full_name) as nk, public.yk_norm3(public.yk_first2(s.full_name)) as nk2,
           coalesce(c.grade, nullif(substring(c.name from '^\s*(\d+)'), '')::int) as cg, c.name as cn
      from public.students s join public.classes c on c.id = s.class_id
     where s.id::text = any(p_kids)),
  links as (  -- guruh va repetitor yozuvlari: ism-familiya bir xil, sinf darajasi mos (yoki ko'rsatilmagan)
    select k.id as kid, g.id as gid, gc.id as gcid, gc.name::text as gname, gc.kind is not distinct from 'rep' as rep,
           coalesce(nullif(gc.subject, ''), gc.name)::text as subj
      from k join public.students g
        on g.id <> k.id and coalesce(btrim(g.full_name), '') <> ''
       and (public.yk_norm3(g.full_name) = k.nk or public.yk_norm3(public.yk_first2(g.full_name)) = k.nk2)
      join public.classes gc on gc.id = g.class_id
     where (gc.kind = 'rep' or coalesce(gc.grp, '') <> '' or coalesce(gc.subject, '') ~* '^(arab|koreys)')
       -- sinf darajasi: ko'rsatilmagan, teng yoki guruh nomida bor (masalan «5-6-sinf», «(8-9-10)»)
       and (gc.grade is null or k.cg is null or gc.grade = k.cg or gc.name ~ ('(^|[^0-9])' || k.cg || '([^0-9]|$)'))),
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

notify pgrst, 'reload schema';

-- Tekshiruv: guruh/repetitordagi o'quvchilar — asosiy sinfda mos o'quvchi topilmadi (ota-onasi shu guruh baholarini ko'rmaydi)
select gc.name as "guruh", g.full_name as "guruhdagi ism", 'asosiy sinfda topilmadi — ismni asosiy sinfdagidek yozing' as "holat"
  from public.students g join public.classes gc on gc.id = g.class_id
 where coalesce(btrim(g.full_name), '') <> ''
   and (gc.kind = 'rep' or coalesce(gc.grp, '') <> '' or coalesce(gc.subject, '') ~* '^(arab|koreys)')
   and not exists (
     select 1 from public.students s join public.classes c on c.id = s.class_id
      where c.kind is distinct from 'rep' and coalesce(c.grp, '') = '' and coalesce(c.subject, '') !~* '^(arab|koreys)'
        and (public.yk_norm3(s.full_name) = public.yk_norm3(g.full_name)
             or public.yk_norm3(public.yk_first2(s.full_name)) = public.yk_norm3(public.yk_first2(g.full_name))))
 order by 1, 2;
