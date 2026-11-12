-- Yangilanish 65: Kunlik vazifalar — bir kunlik maksimal ball 51 o'rniga 31, oylik 1020 o'rniga 620 (20 ish kuni × 31).
--   Davomat — 1 ball; mezonlar yig'indisi 30 ballga keltiriladi:
--     2–10-sinf: kitob + odoblar + yaxshilik (har biri 0–10) ×1; yaxshilik belgilanmagan bo'lsa kitob + odoblar ×1.5;
--     1-sinf:    odoblar + yaxshilik ×1.5; yaxshilik belgilanmagan bo'lsa odoblar ×3;
--     eski yozuvlar (sport bor kunlar): 4 mezon ×0.75 (1-sinfda 3 mezon ×1).
--   Barcha oylar (o'tganlari ham) yangi o'lchovda ko'rsatiladi. Sinflar reytingi foizi 31 ballga nisbatan.
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing (loyiha: YUKSALISH-REYTING). Qayta ishga tushirish xavfsiz.

create or replace function public.yk_day_total(g1 boolean, att int, book int, sport int, behavior int, kindness int, activity int)
returns int language sql immutable as $$
  select (case when att = 1 then 1 else 0 end)
       + case when g1 and sport is null then
                   case when kindness is null then coalesce(behavior, 0) * 3
                        else round((coalesce(behavior, 0) + kindness) * 1.5)::int end
              when g1 then coalesce(sport, 0) + coalesce(behavior, 0) + coalesce(kindness, 0)
              when g1 is null and sport is null then
                   case when kindness is null then round((coalesce(book, 0) + coalesce(behavior, 0)) * 1.5)::int
                        else coalesce(book, 0) + coalesce(behavior, 0) + kindness end
              else round((coalesce(book, 0) + coalesce(sport, 0) + coalesce(behavior, 0) + coalesce(kindness, 0)) * 0.75)::int end
$$;

-- Sinflar reytingi: asosiy sinf — o'quvchi boshiga kuniga 31 ball
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
              else round(d.t * 100.0 / (c.n * case when c.grp then 16 else 31 end), 1) end
    from c left join d on d.class_id = c.id left join r on r.class_id = c.id;
end $$;

notify pgrst, 'reload schema';
