-- Yangilanish 75: Guruh/repetitordagi o'quvchilarni asosiy sinfdagi farzand bilan AVTOMATIK bog'lash (ism o'xshashligi bo'yicha).
--   Ism yozilishidagi farqlar (x/h, o'/ö, ʻ/', qisqartma, otasining ismi, «-10 sinf» kabi qo'shimchalar, ism tartibi)
--   hisobga olinadi; guruh nomidagi sinflar (masalan «5-6-sinf», «(8-9-10)», «9-10») bo'yicha nomzodlar tanlanadi.
--   Faqat ISHONCHLI va YAGONA moslik bog'lanadi (ismlar o'zgartirilmaydi — bog'lanish alohida jadvalda).
--   Natija jadvali: «bog'landi» / «shubhali — tekshiring» / «topilmadi».
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing (loyiha: YUKSALISH-REYTING). Avval 69 va 74 ishga tushgan bo'lsin.
-- Qayta ishga tushirish xavfsiz (yangi qo'shilgan o'quvchilar uchun ham ishlatsa bo'ladi).

create extension if not exists pg_trgm with schema extensions;

create table if not exists public.student_links (
  gid text primary key,            -- guruh/repetitordagi o'quvchi
  kid text not null,               -- asosiy sinfdagi o'quvchi
  score numeric,
  auto boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.student_links enable row level security;
revoke all on public.student_links from anon, authenticated;

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
       and (gc.grade is null or k.cg is null or gc.grade = k.cg or gc.name ~ ('(^|[^0-9])' || k.cg || '([^0-9]|$)'))
    union  -- avtomatik / qo'lda bog'langanlar (student_links)
    select k.id, g.id, gc.id, gc.name::text, gc.kind is not distinct from 'rep', coalesce(nullif(gc.subject, ''), gc.name)::text
      from k join public.student_links sl on sl.kid = k.id::text
      join public.students g on g.id::text = sl.gid join public.classes gc on gc.id = g.class_id),
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

-- Avtomatik bog'lash: p_min — eng kam o'xshashlik (0..1), p_gap — ikkinchi nomzoddan farq
create or replace function public.yk_link_groups(p_min numeric default 0.6, p_gap numeric default 0.1)
returns table (guruh text, guruhdagi_ism text, mos_oquvchi text, sinf text, oxshashlik numeric, holat text)
language plpgsql security definer set search_path = public, extensions as $$
#variable_conflict use_column
begin
  if coalesce(public.yk_role(), '') <> 'admin' and current_user not in ('postgres', 'supabase_admin') then
    raise exception 'Faqat admin' using errcode = '42501';
  end if;
  return query
  with mainst as (
    select s.id::text as sid, s.full_name::text as nm, c.name::text as cn,
           coalesce(c.grade, nullif(substring(c.name from '^\s*(\d+)'), '')::int) as cg,
           translate(public.yk_norm3(s.full_name), 'q', 'k') as n1, translate(public.yk_norm3(public.yk_first2(s.full_name)), 'q', 'k') as n2
      from public.students s join public.classes c on c.id = s.class_id
     where c.kind is distinct from 'rep' and coalesce(c.grp, '') = '' and coalesce(c.subject, '') !~* '^(arab|koreys)'
       and coalesce(btrim(s.full_name), '') <> ''),
  grp as (
    select g.id::text as gid, g.full_name::text as nm, gc.name::text as gn,
           -- guruh nomidagi sinf raqamlari (IELTS 7.0, A1/B1 kabilar hisobga olinmaydi)
           (select array_agg(distinct m[1]::int) from regexp_matches(
              regexp_replace(regexp_replace(gc.name, '\d+\.\d+', '', 'g'), '[A-Za-z]\d+', '', 'g'), '(\d{1,2})', 'g') m
             where m[1]::int between 1 and 11) || case when gc.grade is not null then array[gc.grade] else '{}'::int[] end as gs,
           translate(public.yk_norm3(regexp_replace(g.full_name, '[-\s]*\d+\s*-?\s*sinf\w*', '', 'gi')), 'q', 'k') as n1,
           translate(public.yk_norm3(public.yk_first2(regexp_replace(g.full_name, '[-\s]*\d+\s*-?\s*sinf\w*', '', 'gi'))), 'q', 'k') as n2
      from public.students g join public.classes gc on gc.id = g.class_id
     where coalesce(btrim(g.full_name), '') <> ''
       and (gc.kind = 'rep' or coalesce(gc.grp, '') <> '' or coalesce(gc.subject, '') ~* '^(arab|koreys)')
       and not exists (select 1 from public.student_links sl where sl.gid = g.id::text)
       and not exists (select 1 from public.students s join public.classes c on c.id = s.class_id
                        where c.kind is distinct from 'rep' and coalesce(c.grp, '') = '' and coalesce(c.subject, '') !~* '^(arab|koreys)'
                          and (public.yk_norm3(s.full_name) = public.yk_norm3(g.full_name)
                               or public.yk_norm3(public.yk_first2(s.full_name)) = public.yk_norm3(public.yk_first2(g.full_name))))),
  cand as (
    select g.gid, g.nm as gnm, g.gn, m.sid, m.nm as mnm, m.cn,
           greatest(similarity(g.n1, m.n1), similarity(g.n2, m.n2),
                    case when position(' ' in g.n1) = 0 then word_similarity(g.n1, m.n1) * 0.9 else 0 end)::numeric as sc
      from grp g join mainst m
        on (g.gs is null or cardinality(g.gs) = 0 or m.cg is null or m.cg = any(g.gs))
       and (g.n1 % m.n1 or g.n2 % m.n2 or (position(' ' in g.n1) = 0 and g.n1 <% m.n1))),
  rk as (
    select c.*, row_number() over (partition by c.gid order by c.sc desc) as r,
           lead(c.sc) over (partition by c.gid order by c.sc desc) as sc2
      from cand c),
  best as (select * from rk where r = 1),
  dcs as (
    select b.*, (b.sc >= p_min and (b.sc2 is null or b.sc2 <= b.sc - p_gap)) as ok from best b),
  ins as (
    insert into public.student_links (gid, kid, score)
    select d.gid, d.sid, round(d.sc, 2) from dcs d where d.ok
    on conflict (gid) do nothing
    returning gid)
  select d.gn, d.gnm, d.mnm, d.cn, round(d.sc, 2),
         case when d.ok then '✅ bog''landi' else '⚠️ shubhali — tekshiring' end
    from dcs d
  union all
  select g.gn, g.nm, null, null, null, '❌ topilmadi — ismni asosiy sinfdagidek yozing'
    from grp g where not exists (select 1 from best b where b.gid = g.gid)
  order by 6, 1, 2;
end $$;
revoke all on function public.yk_link_groups(numeric, numeric) from public, anon;
grant execute on function public.yk_link_groups(numeric, numeric) to authenticated;

-- Qo'lda tasdiqlash («shubhali» yoki «topilmadi» holatlar uchun):
--   select public.yk_link_one('10-sinf Matematika Alfa', 'Ahmadjon', 'Ahmadov Ahmadjon');
--   (guruh nomi, guruhdagi ism, asosiy sinfdagi to'liq ism — natija jadvalidagidek)
create or replace function public.yk_link_one(p_group text, p_gname text, p_main text) returns text
language plpgsql security definer set search_path = public as $$
declare g text; m text; n int;
begin
  if coalesce(public.yk_role(), '') <> 'admin' and current_user not in ('postgres', 'supabase_admin') then
    raise exception 'Faqat admin' using errcode = '42501';
  end if;
  select s.id::text into g from public.students s join public.classes c on c.id = s.class_id
   where btrim(c.name) = btrim(p_group) and btrim(s.full_name) = btrim(p_gname) limit 1;
  if g is null then return '❌ guruhda bunday o''quvchi topilmadi'; end if;
  select count(*), min(s.id::text) into n, m from public.students s join public.classes c on c.id = s.class_id
   where c.kind is distinct from 'rep' and coalesce(c.grp, '') = '' and coalesce(c.subject, '') !~* '^(arab|koreys)'
     and btrim(s.full_name) = btrim(p_main);
  if n = 0 then return '❌ asosiy sinfda bunday o''quvchi topilmadi'; end if;
  if n > 1 then return '⚠️ asosiy sinflarda bu ism ' || n || ' ta — aniqlab bo''lmaydi'; end if;
  insert into public.student_links (gid, kid, score, auto) values (g, m, null, false)
  on conflict (gid) do update set kid = excluded.kid, auto = false, created_at = now();
  return '✅ bog''landi: ' || p_gname || ' → ' || p_main;
end $$;
revoke all on function public.yk_link_one(text, text, text) from public, anon;
grant execute on function public.yk_link_one(text, text, text) to authenticated;

notify pgrst, 'reload schema';

-- Bog'lash va natija: ✅ — bog'landi, ⚠️ — o'xshash, lekin ishonchsiz (bog'lanmadi), ❌ — nomzod topilmadi
select * from public.yk_link_groups(0.6, 0.1);
