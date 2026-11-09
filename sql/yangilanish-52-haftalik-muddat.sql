-- Yangilanish 52: 1–2-guruh sinflarida kunlik vazifalarning HAMMA bandini sinf rahbari belgilaydi
-- (Kitob o'qish, Sport, Maktabdagi odoblar, Ota-onaga yaxshilik) — ota-ona endi belgilamaydi.
-- Muddat: dushanbadan juma kunigacha. O'qituvchi xohlasa har kuni, xohlasa juma kuni butun 5 kunlikni belgilaydi.
-- O'qituvchilar reytingi har JUMA soat 20:00 da chiqadi: haftaning har bir kuni juma 20:00 gacha to'liq belgilangan bo'lsa — o'z vaqtida.
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing. Qayta ishga tushirish xavfsiz.

-- 1. «Baho to'liq qo'yildi»: asosiy sinfda davomat va barcha mezonlar (1-sinfda kitob o'qishsiz)
create or replace function public.yk_mark_done() returns trigger
language plpgsql security definer set search_path = public as $$
declare g text; cid bigint; done boolean; j jsonb := to_jsonb(new);
begin
  new.updated_at := now();
  if tg_table_name = 'rep_daily' then
    done := new.att is not null and (new.att = 0 or j ->> 'task' is not null);
  else
    select c.grp, c.id into g, cid from public.students s join public.classes c on c.id = s.class_id where s.id = new.student_id;
    if coalesce(g, '') <> '' then
      done := new.att is not null and (new.att = 0 or (new.hw is not null and new.activity is not null and new.behavior is not null));
    else
      done := new.att is not null and (new.att = 0 or (new.sport is not null and new.behavior is not null and new.kindness is not null
              and (new.book is not null or coalesce(public.yk_g1(cid), false))));
    end if;
  end if;
  if not done then new.done_at := null;
  elsif new.done_at is null then new.done_at := now();
  end if;
  return new;
end $$;

-- 2. Ota-ona endi baho qo'ymaydi
do $$ begin
  revoke all on function public.parent_set_score(text, text, int) from public, anon, authenticated;
exception when undefined_function then null;
end $$;

-- 3. O'qituvchilar reytingi: haftalik muddat (juma 20:00)
create or replace function public.teacher_rating(p_from date, p_to date)
returns table (user_id uuid, full_name text, phone text, classes text, class_days int, on_time int, late int, missed int, score int)
language sql stable security definer set search_path = public as $$
with nowt as (select (now() at time zone 'Asia/Tashkent') t),
cut as (  -- reyting haftalik: shu haftaning juma kuni soat 20:00 dan keyin chiqadi, undan oldin — o'tgan haftagacha
  select case when (select t from nowt) >= (date_trunc('week', (select t from nowt))::date + 4) + time '20:00'
              then date_trunc('week', (select t from nowt))::date + 4
              else date_trunc('week', (select t from nowt))::date - 3 end as last_day
),
cls as (
  select c.id, c.name, (c.kind is distinct from 'rep' and coalesce(c.grp, '') = '') as is_main from public.classes c
),
st as (select s.id, s.class_id from public.students s where coalesce(btrim(s.full_name), '') <> ''),
sd as (  -- maktab ish kunlari: asosiy sinflarning birortasida baho bor kunlar
  select distinct ds.day from public.daily_scores ds
    join public.students s on s.id = ds.student_id join cls c on c.id = s.class_id and c.is_main
   where ds.day between p_from and least(p_to, (select last_day from cut))
),
cday as (
  select c.id as class_id, sd.day from cls c join sd on c.is_main
  union
  select s.class_id, ds.day from public.daily_scores ds join public.students s on s.id = ds.student_id
    join cls c on c.id = s.class_id and not c.is_main
   where ds.day between p_from and least(p_to, (select last_day from cut))
  union
  select s.class_id, r.day from public.rep_daily r join public.students s on s.id = r.student_id
   where r.day between p_from and least(p_to, (select last_day from cut))
),
rws as (
  select student_id, day, done_at from public.daily_scores where day between p_from and p_to
  union all
  select student_id, day, done_at from public.rep_daily where day between p_from and p_to
),
cstat as (
  select cd.class_id, cd.day, count(st.id) as n,
         count(r.student_id) filter (where r.done_at is not null) as done,
         count(r.student_id) filter (where r.done_at <= (greatest(date_trunc('week', cd.day)::date + 4, cd.day) + time '20:00') at time zone 'Asia/Tashkent') as ok
    from cday cd join st on st.class_id = cd.class_id
    left join rws r on r.student_id = st.id and r.day = cd.day
   group by cd.class_id, cd.day
),
tc as (
  select t.user_id, t.class_id from public.teacher_classes t
   where public.yk_role() = 'admin' or public.yk_admin2() or t.user_id = auth.uid()
)
select p.id, p.full_name, p.phone,
       (select string_agg(c.name, ', ' order by c.name) from tc t2 join public.classes c on c.id = t2.class_id where t2.user_id = p.id),
       count(cs.class_id)::int,
       (count(cs.class_id) filter (where cs.ok = cs.n))::int,
       (count(cs.class_id) filter (where cs.done = cs.n and cs.ok < cs.n))::int,
       (count(cs.class_id) filter (where cs.done < cs.n))::int,
       greatest(0, 100 - 2 * (count(cs.class_id) filter (where cs.done = cs.n and cs.ok < cs.n))
                       - 5 * (count(cs.class_id) filter (where cs.done < cs.n)))::int
  from public.profiles p
  join (select distinct user_id from tc) u on u.user_id = p.id
  left join tc on tc.user_id = p.id
  left join cstat cs on cs.class_id = tc.class_id
 group by p.id, p.full_name, p.phone
 order by 9 desc, 6 desc, 2
$$;

-- 4. Baho bildirishnomalari: sinf rahbari qo'ygan barcha mezonlar bo'yicha (faqat bugungi kun uchun)
create or replace function public.yk_push_daily() returns trigger
language plpgsql security definer set search_path = public as $$
declare g boolean; sid text := new.student_id::text; c record;
begin
  if new.day <> (now() at time zone 'Asia/Tashkent')::date then return new; end if;
  select coalesce(cl.grp, '') <> '' into g from public.students s join public.classes cl on cl.id = s.class_id where s.id = new.student_id;
  g := coalesce(g, false);
  for c in select * from (values ('book', 'Kitob o''qish', 10), ('sport', 'Sport', 10), ('behavior', case when g then 'Tartib-intizom' else 'Maktabdagi odoblar' end, case when g then 5 else 10 end),
                                 ('kindness', 'Ota-onaga yaxshilik', 10), ('hw', 'Uyga vazifa', 5), ('activity', 'Sinfdagi faollik', 5)) v(k, t, m) loop
    continue when (case when g then c.k not in ('hw', 'activity', 'behavior') else c.k not in ('book', 'sport', 'behavior', 'kindness') end);
    if tg_op = 'INSERT' or (to_jsonb(new) ->> c.k) is distinct from (to_jsonb(old) ->> c.k) then
      perform public.yk_grade_mark(sid, 'd:' || c.k, (to_jsonb(new) ->> c.k)::numeric,
                                   case when c.m = 5 then 2 else 4 end, case when c.m = 5 then 5 else 9 end,
                                   c.t || ' ' || (to_jsonb(new) ->> c.k) || '/' || c.m);
    end if;
  end loop;
  if g and (tg_op = 'INSERT' or (to_jsonb(new) ->> 'beh_band') is distinct from (to_jsonb(old) ->> 'beh_band')) then
    perform public.yk_grade_note(sid, 'yomon', 'd:band', case (to_jsonb(new) ->> 'beh_band')
      when '1' then 'tartib qoidaga amal qilmadi' when '2' then 'atrofdagilar va ustozlarni hurmat qilmadi'
      when '3' then 'o''z joyini toza saqlamadi' end);
  end if;
  return new;
exception when others then
  raise warning 'push baho: %', sqlerrm;  -- bildirishnomadagi xato baho saqlanishiga to'sqinlik qilmasin
  return new;
end $$;
drop trigger if exists yk_push_daily on public.daily_scores;

notify pgrst, 'reload schema';
