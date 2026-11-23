-- Yangilanish 83: Ota-ona profili — «Reyting va o'rinlar».
--   Farzandning: 1) sinfdagi o'rni, 2) maktabdagi o'rni, 3) har bir guruh/fan (Matematika, Ingliz tili,
--   Arab/Koreys tili, repetitor) bo'yicha o'rni — ustozi, o'rtacha bali va o'tgan haftaga nisbatan o'zgarishi bilan.
--   O'rinlar shu o'quv yili boshidan (1-sentabr) hisoblanadi. O'zgarish — oxirgi 7 kunga nisbatan.
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing (loyiha: YUKSALISH-REYTING). Avval 69 va 82 ishga tushgan bo'lsin.
-- Qayta ishga tushirish xavfsiz.

create or replace function public.parent_ranks(p_sid text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_variable
declare kid text; cid bigint; g1 boolean; cname text; today date; yfrom date; wk date;
        cls jsonb; sch jsonb; subs jsonb; avg5 numeric;
begin
  if p_sid is not null then
    if not public.yk_is_my_kid(p_sid) then raise exception 'Bu sizning farzandingiz emas' using errcode = '42501'; end if;
    kid := p_sid;
  else
    select k.id::text into kid from public.my_kids() k order by k.full_name limit 1;
  end if;
  if kid is null then return null; end if;
  select s.class_id, c.name into cid, cname from public.students s join public.classes c on c.id = s.class_id where s.id::text = kid;
  g1 := public.yk_g1(cid);
  today := (now() at time zone 'Asia/Tashkent')::date;
  yfrom := make_date(case when extract(month from today) >= 9 then extract(year from today)::int else extract(year from today)::int - 1 end, 9, 1);
  wk := today - 7;

  -- 1) Sinfdagi o'rin (asosiy sinf, jami ball bo'yicha)
  with st as (select s.id from public.students s where s.class_id = cid and coalesce(btrim(s.full_name), '') <> ''),
  tot as (
    select st.id,
      coalesce(sum(public.yk_day_total(g1, d.att, d.book, d.sport, d.behavior, d.kindness, d.activity))
               filter (where d.day between yfrom and today), 0) as tnow,
      coalesce(sum(public.yk_day_total(g1, d.att, d.book, d.sport, d.behavior, d.kindness, d.activity))
               filter (where d.day between yfrom and wk), 0) as told,
      count(*) filter (where d.att is not null and d.day between yfrom and today) as days
      from st left join public.daily_scores d on d.student_id = st.id group by st.id),
  rk as (select id, tnow, days, rank() over (order by tnow desc) rn, rank() over (order by told desc) ro, count(*) over () sz from tot)
  select jsonb_build_object('rank', rn, 'size', sz, 'delta', ro - rn),
         case when days > 0 then round(tnow * 5.0 / (days * 51), 1) else null end
    into cls, avg5 from rk where id = kid;

  -- 2) Maktabdagi o'rin (barcha asosiy sinf o'quvchilari)
  with st as (
    select s.id, public.yk_g1(s.class_id) as g1
      from public.students s join public.classes c on c.id = s.class_id
     where c.kind is distinct from 'rep' and coalesce(c.grp, '') = '' and coalesce(c.subject, '') !~* '^(arab|koreys)'
       and coalesce(btrim(s.full_name), '') <> ''),
  tot as (
    select st.id,
      coalesce(sum(public.yk_day_total(st.g1, d.att, d.book, d.sport, d.behavior, d.kindness, d.activity))
               filter (where d.day between yfrom and today), 0) as tnow,
      coalesce(sum(public.yk_day_total(st.g1, d.att, d.book, d.sport, d.behavior, d.kindness, d.activity))
               filter (where d.day between yfrom and wk), 0) as told
      from st left join public.daily_scores d on d.student_id = st.id group by st.id),
  rk as (select id, rank() over (order by tnow desc) rn, rank() over (order by told desc) ro, count(*) over () sz from tot)
  select jsonb_build_object('rank', rn, 'size', sz, 'delta', ro - rn) into sch from rk where id = kid;

  -- 3) Fan va guruhlar bo'yicha o'rin
  with k as (
    select public.yk_norm3((select full_name from public.students where id::text = kid)) as nk,
           public.yk_norm3(public.yk_first2((select full_name from public.students where id::text = kid))) as nk2,
           coalesce((select grade from public.classes where id = cid),
                    nullif(substring(cname from '^\s*(\d+)'), '')::int) as cg),
  links as (  -- kid bog'langan guruh yozuvlari (yk_grades_of bilan bir xil qoida + student_links)
    select distinct g.id as gid, gc.id as gcid, gc.name::text as gname,
           coalesce(nullif(gc.subject, ''), gc.name)::text as subj, gc.kind is not distinct from 'rep' as rep
      from k, public.students g join public.classes gc on gc.id = g.class_id
     where coalesce(btrim(g.full_name), '') <> ''
       and (gc.kind = 'rep' or coalesce(gc.grp, '') <> '' or coalesce(gc.subject, '') ~* '^(arab|koreys)')
       and (public.yk_norm3(g.full_name) = k.nk or public.yk_norm3(public.yk_first2(g.full_name)) = k.nk2)
       and (gc.grade is null or k.cg is null or gc.grade = k.cg or gc.name ~ ('(^|[^0-9])' || k.cg || '([^0-9]|$)'))
    union
    select distinct sl.gid, gc.id, gc.name::text, coalesce(nullif(gc.subject, ''), gc.name)::text, gc.kind is not distinct from 'rep'
      from public.student_links sl join public.students g on g.id::text = sl.gid join public.classes gc on gc.id = g.class_id
     where sl.kid = kid),
  mem as (select l.gcid, l.gname, l.subj, l.rep, s.id as sid from links l
            join public.students s on s.class_id = l.gcid and coalesce(btrim(s.full_name), '') <> ''),
  gsc as (  -- guruh (3/4/6): kunlik att+hw+activity+behavior; repetitor: rep_pct
    select m.gcid, m.sid,
      coalesce(sum(case when (d.att = 1) then 1 else 0 end + coalesce(d.hw, 0) + coalesce(d.activity, 0) + coalesce(d.behavior, 0))
               filter (where d.day between yfrom and today), 0) as gnow,
      coalesce(sum(case when (d.att = 1) then 1 else 0 end + coalesce(d.hw, 0) + coalesce(d.activity, 0) + coalesce(d.behavior, 0))
               filter (where d.day between yfrom and wk), 0) as gold,
      round(avg((coalesce(d.hw, 0) + coalesce(d.activity, 0) + coalesce(d.behavior, 0)) / 3.0)
            filter (where d.day between yfrom and today and d.att is not null), 1) as gavg
      from mem m left join public.daily_scores d on d.student_id = m.sid where not m.rep group by m.gcid, m.sid),
  rsc as (
    select m.gcid, m.sid,
      coalesce(round(avg(public.yk_rep_pct(r.att, r.task)) filter (where r.day between yfrom and today), 1), 0) as gnow,
      coalesce(round(avg(public.yk_rep_pct(r.att, r.task)) filter (where r.day between yfrom and wk), 1), 0) as gold,
      round(avg(r.task) filter (where r.day between yfrom and today), 1) as gavg
      from mem m left join public.rep_daily r on r.student_id = m.sid where m.rep group by m.gcid, m.sid),
  allsc as (select * from gsc union all select * from rsc),
  rkd as (
    select a.*, rank() over (partition by a.gcid order by a.gnow desc) rn,
           rank() over (partition by a.gcid order by a.gold desc) ro, count(*) over (partition by a.gcid) sz
      from allsc a),
  tch as (
    select t.class_id, string_agg(p.full_name::text, ', ' order by p.full_name) as names
      from public.teacher_classes t join public.profiles p on p.id = t.user_id group by t.class_id),
  mine as (
    select l.gcid, l.gname, l.subj, l.rep, r.rn, r.ro, r.sz, r.gavg, l.gid
      from links l join rkd r on r.gcid = l.gcid and r.sid = l.gid)
  select coalesce(jsonb_agg(jsonb_build_object(
           'class_id', mine.gcid, 'name', mine.subj, 'group_name', mine.gname,
           'teacher', (select names from tch where tch.class_id = mine.gcid),
           'kind', case when mine.rep then 'repetitor' else 'guruh' end,
           'rank', mine.rn, 'size', mine.sz, 'delta', mine.ro - mine.rn,
           'avg', mine.gavg, 'medal', case when mine.rn <= 3 then mine.rn else null end)
           order by mine.rn, mine.subj), '[]'::jsonb)
    into subs from mine;

  return jsonb_build_object('sid', kid, 'name', (select full_name from public.students where id::text = kid),
    'class_id', cid, 'class_name', cname, 'avg', avg5, 'class', cls, 'school', sch, 'subjects', subs);
end $$;
revoke all on function public.parent_ranks(text) from public, anon;
grant execute on function public.parent_ranks(text) to authenticated;

notify pgrst, 'reload schema';

-- Tekshiruv uchun (ota-ona sifatida): select public.parent_ranks();
select 'Tayyor — parent_ranks() yaratildi' as natija;
