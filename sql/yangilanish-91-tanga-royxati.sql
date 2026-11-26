-- Yangilanish 91: Qaysi o'quvchi qaysi tangani (Oltin / Kumush / Bronza) olishi mumkin — maktab bo'yicha ro'yxat (admin va kuzatuvchi).
--   Oylik ball 620 dan; Oltin ≥90%, Kumush ≥80%, Bronza ≥70%. Bronzaga yaqinlar (≥60%) ham qaytariladi.
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing. Avval 90 ishga tushgan bo'lsin. Qayta ishga tushirish xavfsiz.

create or replace function public.school_coins(p_month date)
returns table (student_id text, name text, class_id bigint, total int, pct numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  return query
  select t.sid::text, t.fname, t.cid, t.total, round(t.total * 100.0 / 620, 1)
    from public.yk_month_tot(p_month) t
   where t.total * 100.0 / 620 >= 60
   order by t.total desc, t.fname;
end $$;
revoke all on function public.school_coins(date) from public, anon;
grant execute on function public.school_coins(date) to authenticated;

notify pgrst, 'reload schema';
select 'Tayyor — school_coins yaratildi' as natija;
