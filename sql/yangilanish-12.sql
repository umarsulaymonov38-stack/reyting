-- Yangilanish 12: ota-ona uchun farzandining oylik mezonlar bo'yicha ballari va sinfdagi o'rni (tangalar va "eng yaxshi 3" uchun).
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing. Qayta ishga tushirish xavfsiz.
-- Ota-ona boshqa o'quvchilarning ism yoki ballarini ko'rmaydi — faqat o'z farzandining natijasi va o'rni.

create or replace function public.my_month_stats(p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare kid public.students.id%type; cid bigint; res jsonb;
begin
  select p.student_id into kid from public.profiles p where p.id = auth.uid();
  if kid is null then return null; end if;
  select s.class_id into cid from public.students s where s.id = kid;
  with st as (
    select s.id from public.students s where s.class_id = cid and coalesce(btrim(s.full_name), '') <> ''),
  t as (
    select st.id,
           count(*) filter (where d.att = 1)          as att,
           coalesce(sum(d.book), 0)                   as book,
           coalesce(sum(d.sport), 0)                  as sport,
           coalesce(sum(d.behavior), 0)               as behavior,
           coalesce(sum(d.kindness), 0)               as kindness,
           coalesce(sum(d.activity), 0)               as activity
      from st left join public.daily_scores d on d.student_id = st.id and d.day between p_from and p_to
     group by st.id),
  r as (
    select t.*, att + book + sport + behavior + kindness + activity as total,
           rank() over (order by att desc)      as r_att,
           rank() over (order by book desc)     as r_book,
           rank() over (order by sport desc)    as r_sport,
           rank() over (order by behavior desc) as r_behavior,
           rank() over (order by kindness desc) as r_kindness,
           rank() over (order by activity desc) as r_activity,
           count(*) over ()                     as size
      from t)
  select jsonb_build_object(
           'size', size, 'total', total,
           'v', jsonb_build_object('att', att, 'book', book, 'sport', sport, 'behavior', behavior, 'kindness', kindness, 'activity', activity),
           'r', jsonb_build_object('att', r_att, 'book', r_book, 'sport', r_sport, 'behavior', r_behavior, 'kindness', r_kindness, 'activity', r_activity))
    into res from r where r.id = kid;
  return res;
end $$;
revoke all on function public.my_month_stats(date, date) from public, anon;
grant execute on function public.my_month_stats(date, date) to authenticated;

notify pgrst, 'reload schema';
