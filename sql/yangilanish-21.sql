-- Yangilanish 21:
--  1) 1-sinflarda "Kitob o'qish" yo'q: qolgan 4 mezon (0–10) yig'indisi ×1.25 — kunlik maksimal 51, oylik 1020 bo'lib qoladi.
--  2) Sinflar reytingi: A (1–2-guruh), B (3- va 5-guruh), C (4-guruh, repetitor) — har biri o'z maksimaliga nisbatan foizda.
--  3) 5-guruhga 3-, 4- va 7-sinf Arab tili 1/2/3-guruhlari.
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing. Qayta ishga tushirish xavfsiz.

-- Sinf 1-sinf (oddiy sinf, guruh emas) ekanini aniqlash
create or replace function public.yk_g1(p_class bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select c.kind is distinct from 'rep' and coalesce(c.grp, '') = ''
                          and coalesce(c.subject, '') !~* '^(arab|koreys)'
                          and coalesce(c.grade, nullif(substring(c.name from '^\s*(\d+)'), '')::int) = 1
                     from public.classes c where c.id = p_class), false)
$$;

-- Bir kunlik ball (oddiy sinf): 1-sinfda kitobsiz va ×1.25
create or replace function public.yk_day_total(g1 boolean, att int, book int, sport int, behavior int, kindness int, activity int)
returns int language sql immutable as $$
  select (case when att = 1 then 1 else 0 end)
       + case when g1 then round((coalesce(sport, 0) + coalesce(behavior, 0) + coalesce(kindness, 0) + coalesce(activity, 0)) * 1.25)::int
              else coalesce(book, 0) + coalesce(sport, 0) + coalesce(behavior, 0) + coalesce(kindness, 0) + coalesce(activity, 0) end
$$;

-- Oylar kesimida (sinf)
create or replace function public.class_month_totals(p_class bigint, p_from date)
returns table (student_id text, month date, total int, att int, book int, sport int, behavior int, kindness int, activity int)
language plpgsql stable security definer set search_path = public as $$
declare g1 boolean := public.yk_g1(p_class);
begin
  if not (public.yk_role() = 'admin'
          or exists (select 1 from public.teacher_classes t where t.user_id = auth.uid() and t.class_id = p_class)
          or exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'teacher' and p.class_id = p_class)) then
    raise exception 'Bu sinfga ruxsatingiz yo''q' using errcode = '42501';
  end if;
  return query
  select d.student_id::text, date_trunc('month', d.day)::date,
         sum(public.yk_day_total(g1, d.att, d.book, d.sport, d.behavior, d.kindness, d.activity))::int,
         (count(*) filter (where d.att = 1))::int, coalesce(sum(d.book), 0)::int, coalesce(sum(d.sport), 0)::int,
         coalesce(sum(d.behavior), 0)::int, coalesce(sum(d.kindness), 0)::int, coalesce(sum(d.activity), 0)::int
    from public.daily_scores d join public.students s on s.id = d.student_id
   where s.class_id = p_class and d.day >= p_from
   group by 1, 2;
end $$;

-- Oylar kesimida (ota-ona, o'z farzandi)
create or replace function public.my_month_totals(p_from date)
returns table (month date, total int)
language sql stable security definer set search_path = public as $$
  with k as (select s.id, public.yk_g1(s.class_id) g1 from public.students s
              where s.id = (select p.student_id from public.profiles p where p.id = auth.uid()))
  select date_trunc('month', d.day)::date, sum(public.yk_day_total(k.g1, d.att, d.book, d.sport, d.behavior, d.kindness, d.activity))::int
    from public.daily_scores d join k on k.id = d.student_id
   where d.day >= p_from group by 1 order by 1
$$;

-- Ota-ona: oylik mezonlar va sinfdagi o'rin (jami — 1-sinf qoidasi bilan)
create or replace function public.my_month_stats(p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare kid public.students.id%type; cid bigint; g1 boolean; res jsonb;
begin
  select p.student_id into kid from public.profiles p where p.id = auth.uid();
  if kid is null then return null; end if;
  select s.class_id into cid from public.students s where s.id = kid;
  g1 := public.yk_g1(cid);
  with st as (select s.id from public.students s where s.class_id = cid and coalesce(btrim(s.full_name), '') <> ''),
  t as (
    select st.id,
           count(*) filter (where d.att = 1) as att, coalesce(sum(d.book), 0) as book, coalesce(sum(d.sport), 0) as sport,
           coalesce(sum(d.behavior), 0) as behavior, coalesce(sum(d.kindness), 0) as kindness, coalesce(sum(d.activity), 0) as activity,
           coalesce(sum(public.yk_day_total(g1, d.att, d.book, d.sport, d.behavior, d.kindness, d.activity)), 0) as total
      from st left join public.daily_scores d on d.student_id = st.id and d.day between p_from and p_to
     group by st.id),
  r as (
    select t.*, rank() over (order by att desc) r_att, rank() over (order by book desc) r_book, rank() over (order by sport desc) r_sport,
           rank() over (order by behavior desc) r_behavior, rank() over (order by kindness desc) r_kindness,
           rank() over (order by activity desc) r_activity, count(*) over () size
      from t)
  select jsonb_build_object('size', size, 'total', total,
           'v', jsonb_build_object('att', att, 'book', book, 'sport', sport, 'behavior', behavior, 'kindness', kindness, 'activity', activity),
           'r', jsonb_build_object('att', r_att, 'book', r_book, 'sport', r_sport, 'behavior', r_behavior, 'kindness', r_kindness, 'activity', r_activity))
    into res from r where r.id = kid;
  return res;
end $$;

-- 2. Sinflar reytingi (kunlik): har bir sinf o'z turi bo'yicha foizda
--    oddiy sinf: kuniga 51 ball (1-sinf ham 51); 3-/5-guruh: davomat + uyga vazifa + faollik + tartib = 16;
--    repetitor: davomat, uyga vazifa (0–10) va test (0–100) foizlari o'rtachasi.
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
           avg((select avg(v) from unnest(array[case when x.att is null then null else x.att * 100.0 end,
                                               case when x.hw is null then null else x.hw * 10.0 end,
                                               x.test::numeric]) v)) as p
      from public.rep_daily x join public.students s on s.id = x.student_id
     where x.day = p_day group by s.class_id)
  select c.id::bigint, c.n,
         coalesce(case when c.rep then r.m else d.m end, 0),
         case when c.rep then null else coalesce(d.t, 0) end,
         case when c.rep then round(r.p, 1)
              when coalesce(d.m, 0) = 0 or c.n = 0 then null
              else round(d.t * 100.0 / (c.n * case when c.grp then 16 else 51 end), 1) end
    from c left join d on d.class_id = c.id left join r on r.class_id = c.id;
end $$;

revoke all on function public.class_month_totals(bigint, date) from public, anon;
revoke all on function public.my_month_totals(date) from public, anon;
revoke all on function public.my_month_stats(date, date) from public, anon;
revoke all on function public.class_ranking2(date) from public, anon;
grant execute on function public.class_month_totals(bigint, date) to authenticated;
grant execute on function public.my_month_totals(date) to authenticated;
grant execute on function public.my_month_stats(date, date) to authenticated;
grant execute on function public.class_ranking2(date) to authenticated;
grant execute on function public.yk_g1(bigint) to authenticated;

-- 3. 5-guruh: 3-, 4-, 7-sinf Arab tili 1/2/3-guruhlari (har biri 15 o'quvchilik); borlari qayta yaratilmaydi
do $$
declare g int; k int; nm text; cid bigint; cid_auto boolean;
begin
  select column_default is not null or is_identity = 'YES' into cid_auto from information_schema.columns
   where table_schema = 'public' and table_name = 'classes' and column_name = 'id';
  foreach g in array array[3, 4, 7] loop
    for k in 1..3 loop
      nm := g || '-sinf Arab tili ' || k || '-guruh';
      select id into cid from public.classes where lower(name) = lower(nm) limit 1;
      if cid is null then
        if cid_auto then
          insert into public.classes (name, grade, grp, subject) values (nm, g, k || '-guruh', 'Arab tili') returning id into cid;
        else
          insert into public.classes (id, name, grade, grp, subject)
          values ((select coalesce(max(id), 0) + 1 from public.classes), nm, g, k || '-guruh', 'Arab tili') returning id into cid;
        end if;
      end if;
      insert into public.students (class_id, slot, full_name)
      select cid, s, '' from generate_series(1, 15) s
       where not exists (select 1 from public.students x where x.class_id = cid and x.slot = s);
      insert into public.student_private (student_id, code)
      select x.id, upper(substr(md5(random()::text || x.id::text), 1, 6)) from public.students x
       where x.class_id = cid and not exists (select 1 from public.student_private p where p.student_id = x.id);
    end loop;
  end loop;
end $$;

notify pgrst, 'reload schema';
