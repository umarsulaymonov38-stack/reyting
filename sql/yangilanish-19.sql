-- Yangilanish 19: o'quvchilarning oylar kesimidagi ballari (o'quv yili davomida har oy alohida saqlanadi va ko'rinadi).
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing. Qayta ishga tushirish xavfsiz.
-- Kunlik ballar bazada kunma-kun saqlanadi; har oy yangi oy 0 dan boshlanadi, o'tgan oylar natijasi o'zgarmay qoladi.

-- Sinf uchun: har bir o'quvchining har oydagi jami bali va mezonlar bo'yicha ballari
create or replace function public.class_month_totals(p_class bigint, p_from date)
returns table (student_id text, month date, total int, att int, book int, sport int, behavior int, kindness int, activity int)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.yk_role() = 'admin'
          or exists (select 1 from public.teacher_classes t where t.user_id = auth.uid() and t.class_id = p_class)
          or exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'teacher' and p.class_id = p_class)) then
    raise exception 'Bu sinfga ruxsatingiz yo''q' using errcode = '42501';
  end if;
  return query
  select d.student_id::text, date_trunc('month', d.day)::date,
         (count(*) filter (where d.att = 1) + coalesce(sum(d.book), 0) + coalesce(sum(d.sport), 0) + coalesce(sum(d.behavior), 0)
          + coalesce(sum(d.kindness), 0) + coalesce(sum(d.activity), 0))::int,
         (count(*) filter (where d.att = 1))::int, coalesce(sum(d.book), 0)::int, coalesce(sum(d.sport), 0)::int,
         coalesce(sum(d.behavior), 0)::int, coalesce(sum(d.kindness), 0)::int, coalesce(sum(d.activity), 0)::int
    from public.daily_scores d join public.students s on s.id = d.student_id
   where s.class_id = p_class and d.day >= p_from
   group by 1, 2;
end $$;

-- Ota-ona uchun: farzandining har oydagi jami bali
create or replace function public.my_month_totals(p_from date)
returns table (month date, total int)
language sql stable security definer set search_path = public as $$
  select date_trunc('month', d.day)::date,
         (count(*) filter (where d.att = 1) + coalesce(sum(d.book), 0) + coalesce(sum(d.sport), 0) + coalesce(sum(d.behavior), 0)
          + coalesce(sum(d.kindness), 0) + coalesce(sum(d.activity), 0))::int
    from public.daily_scores d
   where d.student_id = (select p.student_id from public.profiles p where p.id = auth.uid()) and d.day >= p_from
   group by 1 order by 1
$$;

revoke all on function public.class_month_totals(bigint, date) from public, anon;
revoke all on function public.my_month_totals(date) from public, anon;
grant execute on function public.class_month_totals(bigint, date) to authenticated;
grant execute on function public.my_month_totals(date) to authenticated;

notify pgrst, 'reload schema';
