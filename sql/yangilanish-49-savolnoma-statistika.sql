-- Yangilanish 49: ota-onalar savolnomasi endi kuniga BITTA savol (har kuni boshqasi).
-- Admin statistikasi: har bir yo'nalish bo'yicha «Ha» foizi — faqat o'sha kuni shu yo'nalishdagi savolga javob berganlar orasidan.
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing. Qayta ishga tushirish xavfsiz.

create or replace function public.checkin_stats(p_days int default 14)
returns table (day date, javob int, talk int, kun int, qiziqish int, orzu int)
language plpgsql stable security definer set search_path = public as $$
begin
  if public.yk_role() is distinct from 'admin' and not coalesce((select public.yk_admin2()), false) then
    raise exception 'Faqat admin' using errcode = '42501';
  end if;
  return query
  select c.day, count(*)::int,
         round(100.0 * count(*) filter (where c.q_talk)     / nullif(count(c.q_talk), 0))::int,
         round(100.0 * count(*) filter (where c.q_day)      / nullif(count(c.q_day), 0))::int,
         round(100.0 * count(*) filter (where c.q_interest) / nullif(count(c.q_interest), 0))::int,
         round(100.0 * count(*) filter (where c.q_dream)    / nullif(count(c.q_dream), 0))::int
    from public.parent_checkin c
   where c.day > (now() at time zone 'Asia/Tashkent')::date - greatest(p_days, 1)
   group by c.day order by c.day desc;
end $$;
revoke all on function public.checkin_stats(int) from public, anon;
grant execute on function public.checkin_stats(int) to authenticated;

notify pgrst, 'reload schema';
