-- Yangilanish 88: Admin/Kuzatuvchi — sinf kesimida o'quvchilar reytingi:
--   har bir o'quvchining SINFDAGI va MAKTABDAGI o'rni, oylik bali va qaysi TANGA (Oltin/Kumush/Bronza) imkoniyati.
--   Oylik ball 620 dan hisoblanadi (Oltin ≥90%, Kumush ≥80%, Bronza ≥70%).
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing (loyiha: YUKSALISH-REYTING). Qayta ishga tushirish xavfsiz.

create or replace function public.class_standings(p_class bigint, p_month date)
returns table (student_id text, name text, slot int, total int, pct numeric, class_rank int, school_rank int)
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
    select s.id, s.class_id::bigint as class_id, s.full_name::text as full_name, s.slot,
           public.yk_g1(s.class_id) as g1
      from public.students s join public.classes c on c.id = s.class_id
     where c.kind is distinct from 'rep' and coalesce(c.grp, '') = '' and coalesce(c.subject, '') !~* '^(arab|koreys)'
       and coalesce(btrim(s.full_name), '') <> ''),
  tot as (
    select m.id, m.class_id, m.full_name, m.slot,
           coalesce(sum(public.yk_day_total(m.g1, d.att, d.book, d.sport, d.behavior, d.kindness, d.activity))
                    filter (where d.day between a and b), 0)::int as total
      from main m left join public.daily_scores d on d.student_id = m.id
     group by m.id, m.class_id, m.full_name, m.slot),
  rk as (
    select t.*, rank() over (order by t.total desc)::int as school_rank,
           rank() over (partition by t.class_id order by t.total desc)::int as class_rank
      from tot t)
  select rk.id::text, rk.full_name, rk.slot, rk.total,
         round(rk.total * 100.0 / 620, 1), rk.class_rank, rk.school_rank
    from rk where rk.class_id = p_class
   order by rk.class_rank, rk.slot;
end $$;
revoke all on function public.class_standings(bigint, date) from public, anon;
grant execute on function public.class_standings(bigint, date) to authenticated;

notify pgrst, 'reload schema';
select 'Tayyor — class_standings yaratildi' as natija;
