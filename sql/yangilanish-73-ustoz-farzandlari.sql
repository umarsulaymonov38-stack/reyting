-- Yangilanish 73: Farzandi shu maktabda o'qiydigan ustozlar — o'qituvchi profilining o'zida «Farzandlarim» bo'limi.
--   Farzand ustozning telefon raqami bo'yicha topiladi: raqam o'quvchining OTA-ONA TELEFONI sifatida yozilgan bo'lsa.
--   Ko'rinadi: bugungi davomat (kelgan/ketgan vaqt), barcha baholar (fan, guruh, repetitor), kunlik vazifalar, to'lovlar.
--   Faqat o'qish uchun. Farzandi yo'q ustozda bo'lim chiqmaydi.
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing (loyiha: YUKSALISH-REYTING). Avval 69 ishga tushgan bo'lsin.
-- Qayta ishga tushirish xavfsiz.

create or replace function public.teacher_kids()
returns table (id text, full_name text, class_id bigint, class_name text)
language sql stable security definer set search_path = public, auth as $$
  with me as (
    select right(regexp_replace(coalesce(p.phone, ''), '\D', '', 'g'), 9) as ph1,
           substring(u.email from '^o(\d{9})@') as ph2
      from public.profiles p join auth.users u on u.id = p.id
     where p.id = auth.uid() and p.role = 'teacher')
  select s.id::text, s.full_name::text, s.class_id::bigint, c.name::text
    from public.student_private sp
    join public.students s on s.id = sp.student_id
    join public.classes c on c.id = s.class_id
    cross join me
   where c.kind is distinct from 'rep' and coalesce(c.grp, '') = '' and coalesce(c.subject, '') !~* '^(arab|koreys)'
     and coalesce(btrim(s.full_name), '') <> ''
     and length(right(regexp_replace(coalesce(sp.parent_phone, ''), '\D', '', 'g'), 9)) = 9
     and right(regexp_replace(coalesce(sp.parent_phone, ''), '\D', '', 'g'), 9) in (me.ph1, me.ph2)
   order by s.full_name
$$;
revoke all on function public.teacher_kids() from public, anon;
grant execute on function public.teacher_kids() to authenticated;

create or replace function public.teacher_kid_data(p_sid text, p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare t date := (now() at time zone 'Asia/Tashkent')::date; sy date;
begin
  if not exists (select 1 from public.teacher_kids() k where k.id = p_sid) then
    raise exception 'Bu sizning farzandingiz emas' using errcode = '42501';
  end if;
  sy := make_date(case when extract(month from t) >= 9 then extract(year from t)::int else extract(year from t)::int - 1 end, 9, 1);
  return jsonb_build_object(
    'today', (select to_jsonb(d) from public.daily_scores d where d.student_id::text = p_sid and d.day = t),
    'daily', coalesce((select jsonb_agg(to_jsonb(d) order by d.day desc) from public.daily_scores d
                        where d.student_id::text = p_sid and d.day between p_from and p_to), '[]'::jsonb),
    'grades', coalesce((select jsonb_agg(to_jsonb(g) order by g.day desc, g.at desc nulls last)
                          from public.yk_grades_of(array[p_sid], p_from, p_to) g), '[]'::jsonb),
    'pays', coalesce((select jsonb_agg(jsonb_build_object('month', p.month, 'paid', p.paid, 'paid_on', p.paid_on) order by p.month)
                        from public.payments p where p.student_id::text = p_sid and p.month >= sy), '[]'::jsonb));
end $$;
revoke all on function public.teacher_kid_data(text, date, date) from public, anon;
grant execute on function public.teacher_kid_data(text, date, date) to authenticated;

notify pgrst, 'reload schema';

-- Tekshiruv: farzandi topilgan ustozlar
select p.full_name as ustoz, s.full_name as farzandi, c.name as sinf
  from public.profiles p
  join public.student_private sp on right(regexp_replace(coalesce(sp.parent_phone, ''), '\D', '', 'g'), 9) = right(regexp_replace(coalesce(p.phone, ''), '\D', '', 'g'), 9)
   and length(right(regexp_replace(coalesce(p.phone, ''), '\D', '', 'g'), 9)) = 9
  join public.students s on s.id = sp.student_id and coalesce(btrim(s.full_name), '') <> ''
  join public.classes c on c.id = s.class_id and c.kind is distinct from 'rep' and coalesce(c.grp, '') = ''
 where p.role = 'teacher'
 order by 1, 2;
