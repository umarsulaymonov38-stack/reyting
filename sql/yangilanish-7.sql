-- Yangilanish 7: ota-ona bitta login bilan barcha farzandlarini birga ko'radi (davomat va to'lovlar).
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing. Qayta ishga tushirish xavfsiz.
-- Farzandlar ro'yxati mavjud my_kids() funksiyasidan olinadi (ota-ona telefoniga bog'langan o'quvchilar),
-- shuning uchun ota-ona faqat o'z farzandlarini ko'radi.

create or replace function public.parent_overview(p_from date)
returns table (id bigint, full_name text, class_id bigint, att int, excused boolean, arrived_at timestamptz, pays jsonb, first_day date)
language sql stable security definer set search_path = public as $$
  select k.id::bigint, k.full_name::text, k.class_id::bigint,
         d.att::int,
         coalesce((to_jsonb(d) ->> 'excused')::boolean, false),
         (to_jsonb(d) ->> 'arrived_at')::timestamptz,
         coalesce((select jsonb_agg(jsonb_build_object('month', p.month, 'paid', p.paid, 'paid_on', p.paid_on) order by p.month)
                     from public.payments p where p.student_id = k.id and p.month >= p_from), '[]'::jsonb),
         (select min(s.day) from public.daily_scores s where s.student_id = k.id and s.day >= p_from)
    from public.my_kids() k
    left join public.daily_scores d on d.student_id = k.id and d.day = (now() at time zone 'Asia/Tashkent')::date
   order by k.full_name
$$;
revoke all on function public.parent_overview(date) from public, anon;
grant execute on function public.parent_overview(date) to authenticated;

notify pgrst, 'reload schema';
