-- Yangilanish 35: 5-guruh (Repetitor) — "Uyga vazifa" va "Kunlik test" o'rniga
-- "Topshiriqlarni bajarish" bo'yicha 5 ballik baho (0–5). Eski uyga vazifa/test ma'lumotlari bazada qoladi, lekin hisobga olinmaydi.
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing. Qayta ishga tushirish xavfsiz.

alter table public.rep_daily add column if not exists task smallint;
alter table public.rep_daily drop constraint if exists rep_daily_task_chk;
alter table public.rep_daily add constraint rep_daily_task_chk check (task between 0 and 5);

-- Bir kunlik foiz: davomat (keldi = 100%) va topshiriq (5 ball = 100%) o'rtachasi; to'ldirilmagani hisobga olinmaydi
create or replace function public.yk_rep_pct(p_att numeric, p_task numeric) returns numeric
language sql immutable as $$
  select avg(v) from unnest(array[p_att * 100.0, p_task * 20.0]) v
$$;

-- Sinflar reytingi: repetitor guruhi foizi endi davomat + topshiriq bo'yicha
create or replace function public.class_ranking2(p_day date)
returns table (class_id bigint, students int, marked int, total int, pct numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  if coalesce(public.yk_role(), '') not in ('admin', 'teacher') then
    raise exception 'Ruxsat yo''q' using errcode = '42501';
  end if;
  return query
  with c as (
    select cl.id, cl.kind = 'rep' as rep, coalesce(cl.grp, '') <> '' or coalesce(cl.subject, '') ~* '^(arab|koreys)' as grp,
           public.yk_g1(cl.id) as g1,
           (select count(*) from public.students s where s.class_id = cl.id and coalesce(btrim(s.full_name), '') <> '')::int as n
      from public.classes cl),
  d as (
    select s.class_id, count(*)::int as m,
           sum(case when c.grp then (case when x.att = 1 then 1 else 0 end) + coalesce(x.hw, 0) + coalesce(x.activity, 0) + coalesce(x.behavior, 0)
                    else public.yk_day_total(c.g1, x.att, x.book, x.sport, x.behavior, x.kindness, x.activity) end)::int as t
      from public.daily_scores x join public.students s on s.id = x.student_id join c on c.id = s.class_id
     where x.day = p_day and not c.rep group by s.class_id),
  r as (
    select s.class_id, count(*)::int as m,
           avg(public.yk_rep_pct(x.att, x.task)) as p
      from public.rep_daily x join public.students s on s.id = x.student_id
     where x.day = p_day group by s.class_id)
  select c.id::bigint, c.n,
         coalesce(case when c.rep then r.m else d.m end, 0),
         case when c.rep then null else coalesce(d.t, 0) end,
         case when c.rep then round(r.p, 1)
              when coalesce(d.m, 0) = 0 or c.n = 0 then null
              else round(d.t * 100.0 / (c.n * case when c.grp then 16 else 51 end), 1) end
    from c left join d on d.class_id = c.id left join r on r.class_id = c.id;
end $$;

-- Ota-ona: farzandining repetitor guruhidagi oylik natijasi va o'rni
drop function if exists public.rep_my_rank(date, date);
create function public.rep_my_rank(p_from date, p_to date)
returns table (present int, days int, avg_task numeric, pct numeric, rank int, size int)
language plpgsql stable security definer set search_path = public as $$
declare kid public.students.id%type; cid bigint;
begin
  select p.student_id into kid from public.profiles p where p.id = auth.uid();
  if kid is null then return; end if;
  select s.class_id into cid from public.students s where s.id = kid;
  return query
  with st as (select s.id from public.students s where s.class_id = cid and coalesce(btrim(s.full_name), '') <> ''),
  t as (
    select st.id,
           (count(*) filter (where x.att = 1))::int as pr,
           (count(*) filter (where x.att is not null))::int as dy,
           round(avg(x.task), 1) as tk,
           round(avg(public.yk_rep_pct(x.att, x.task)), 1) as p
      from st left join public.rep_daily x on x.student_id = st.id and x.day between p_from and p_to
     group by st.id),
  r as (select t.*, (rank() over (order by t.p desc nulls last))::int as rk, (count(*) over ())::int as n from t)
  select r.pr, r.dy, r.tk, r.p, r.rk, r.n from r where r.id = kid;
end $$;
revoke all on function public.rep_my_rank(date, date) from public, anon;
grant execute on function public.rep_my_rank(date, date) to authenticated;

-- Repetitor guruhlari reytingi (oylik): davomat + topshiriq foizi
drop function if exists public.rep_group_ranking(date, date);
create function public.rep_group_ranking(p_from date, p_to date)
returns table (class_id bigint, subject text, students int, pct numeric, has boolean)
language plpgsql stable security definer set search_path = public as $$
begin
  if coalesce(public.yk_role(), '') not in ('admin', 'teacher') then
    raise exception 'Ruxsat yo''q' using errcode = '42501';
  end if;
  return query
  select c.id::bigint, coalesce(nullif(c.subject, ''), c.name)::text,
         (select count(*) from public.students s2 where s2.class_id = c.id and coalesce(btrim(s2.full_name), '') <> '')::int,
         round(avg(public.yk_rep_pct(x.att, x.task)), 1),
         count(public.yk_rep_pct(x.att, x.task)) > 0
    from public.classes c
    left join public.students s on s.class_id = c.id
    left join public.rep_daily x on x.student_id = s.id and x.day between p_from and p_to
   where c.kind = 'rep'
   group by c.id, c.subject, c.name
   order by 5 desc, 4 desc nulls last, 2;
end $$;
revoke all on function public.rep_group_ranking(date, date) from public, anon;
grant execute on function public.rep_group_ranking(date, date) to authenticated;

notify pgrst, 'reload schema';
