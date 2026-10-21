-- Yangilanish 8: ota-ona sahifasi — farzandning barcha sinf/guruhlari, bugungi davomat va so'nggi 3 kunlik baholar (ogohlantirishlar uchun).
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing. Qayta ishga tushirish xavfsiz.
-- Ota-ona faqat o'z telefoniga bog'langan o'quvchilarni ko'radi (my_kids()).

drop function if exists public.parent_overview(date);
create or replace function public.parent_overview(p_from date)
returns table (id text, full_name text, class_id text, today jsonb, recent jsonb, pays jsonb, first_day date)
language sql stable security definer set search_path = public as $$
  with t as (select (now() at time zone 'Asia/Tashkent')::date as d)
  select k.id::text, k.full_name::text, k.class_id::text,
         coalesce((select to_jsonb(s) from public.daily_scores s where s.student_id = k.id and s.day = t.d),
                  (select to_jsonb(r) from public.rep_daily r where r.student_id = k.id and r.day = t.d)),
         coalesce((select jsonb_agg(to_jsonb(s) order by s.day desc) from public.daily_scores s where s.student_id = k.id and s.day between t.d - 2 and t.d), '[]'::jsonb)
         || coalesce((select jsonb_agg(to_jsonb(r) order by r.day desc) from public.rep_daily r where r.student_id = k.id and r.day between t.d - 2 and t.d), '[]'::jsonb),
         coalesce((select jsonb_agg(jsonb_build_object('month', p.month, 'paid', p.paid, 'paid_on', p.paid_on) order by p.month)
                     from public.payments p where p.student_id = k.id and p.month >= p_from), '[]'::jsonb),
         (select min(s.day) from public.daily_scores s where s.student_id = k.id and s.day >= p_from)
    from public.my_kids() k, t
   order by k.full_name
$$;
revoke all on function public.parent_overview(date) from public, anon;
grant execute on function public.parent_overview(date) to authenticated;

notify pgrst, 'reload schema';
