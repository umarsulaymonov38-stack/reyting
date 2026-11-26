-- Yangilanish 90: O'quvchilar reytingi — MAKTAB BO'YICHA TOP-10 va SINFLAR KESIMIDA statistika (admin va kuzatuvchi).
--   Oylik ball 620 dan; tanga: Oltin ≥90%, Kumush ≥80%, Bronza ≥70%.
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing (loyiha: YUKSALISH-REYTING). Avval 88 ishga tushgan bo'lsin. Qayta ishga tushirish xavfsiz.

create or replace function public.yk_month_tot(p_month date)
returns table (sid uuid, cid bigint, fname text, total int)
language plpgsql stable security definer set search_path = public as $$
declare a date; b date;
begin
  if not (public.yk_role() = 'admin' or coalesce(public.yk_admin2(), false)) then
    raise exception 'Faqat admin yoki kuzatuvchi' using errcode = '42501';
  end if;
  a := date_trunc('month', p_month)::date;
  b := (date_trunc('month', p_month) + interval '1 month - 1 day')::date;
  return query
  with main as (
    select s.id, s.class_id::bigint as class_id, s.full_name::text as full_name, public.yk_g1(s.class_id) as g1
      from public.students s join public.classes c on c.id = s.class_id
     where c.kind is distinct from 'rep' and coalesce(c.grp, '') = '' and coalesce(c.subject, '') !~* '^(arab|koreys)'
       and coalesce(btrim(s.full_name), '') <> '')
  select m.id, m.class_id, m.full_name,
         coalesce(sum(public.yk_day_total(m.g1, d.att, d.book, d.sport, d.behavior, d.kindness, d.activity))
                  filter (where d.day between a and b), 0)::int
    from main m left join public.daily_scores d on d.student_id = m.id
   group by m.id, m.class_id, m.full_name;
end $$;
revoke all on function public.yk_month_tot(date) from public, anon;
grant execute on function public.yk_month_tot(date) to authenticated;

-- Maktab bo'yicha eng yaxshi o'quvchilar (TOP-N, teng ballar bir xil o'rin oladi)
create or replace function public.school_top(p_month date, p_n int default 10)
returns table (student_id text, name text, class_id bigint, total int, pct numeric, school_rank int)
language plpgsql stable security definer set search_path = public as $$
begin
  return query
  select r.sid::text, r.fname, r.cid, r.total, round(r.total * 100.0 / 620, 1), r.rk
    from (select t.*, rank() over (order by t.total desc)::int as rk from public.yk_month_tot(p_month) t) r
   where r.rk <= greatest(p_n, 1) and r.total > 0
   order by r.rk, r.fname;
end $$;
revoke all on function public.school_top(date, int) from public, anon;
grant execute on function public.school_top(date, int) to authenticated;

-- Sinflar kesimida statistika: o'quvchi soni, o'rtacha ball, tanga olganlar soni
create or replace function public.class_stats(p_month date)
returns table (class_id bigint, n int, avg_total numeric, avg_pct numeric, max_total int, gold int, silver int, bronze int, class_rank int)
language plpgsql stable security definer set search_path = public as $$
begin
  return query
  with t as (select * from public.yk_month_tot(p_month)),
  g as (select t.cid as cid, count(*)::int as n, round(avg(t.total), 1) as av, max(t.total)::int as mx,
               count(*) filter (where t.total * 100.0 / 620 >= 90)::int as go,
               count(*) filter (where t.total * 100.0 / 620 >= 80 and t.total * 100.0 / 620 < 90)::int as si,
               count(*) filter (where t.total * 100.0 / 620 >= 70 and t.total * 100.0 / 620 < 80)::int as br
          from t group by t.cid)
  select g.cid, g.n, g.av, round(g.av * 100.0 / 620, 1), g.mx, g.go, g.si, g.br,
         rank() over (order by g.av desc)::int
    from g order by g.av desc;
end $$;
revoke all on function public.class_stats(date) from public, anon;
grant execute on function public.class_stats(date) to authenticated;

notify pgrst, 'reload schema';
select 'Tayyor — school_top va class_stats yaratildi' as natija;
