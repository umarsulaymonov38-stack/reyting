-- Yangilanish 62: turniket — o'quvchilarni bog'lash (2-OQUVCHILARNI-BOGLASH) tezlashtirildi.
--   Xato: «tk_map: canceling statement due to statement timeout» — funksiya har safar barcha o'tishlar tarixini
--   sekin usulda qayta ko'rib chiqardi. Endi faqat yangi bog'langanlarning o'tishlari, indeks bo'yicha.
--   Kelish 07:20–09:20, ketish 16:00–17:30 (yangilanish-61 dagidek).
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing (loyiha: YUKSALISH-REYTING). Qayta ishga tushirish xavfsiz.

create index if not exists students_ext_id_idx on public.students (ext_id);
create index if not exists turnstile_events_emp_idx on public.turnstile_events (emp_no) where student_id is null;
create index if not exists turnstile_events_sid_idx on public.turnstile_events (student_id, ts);
create index if not exists tk_ids_sid_idx on public.tk_ids (student_id);

create or replace function public.tk_map(p_token text, p_people jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare linked int; already int; miss jsonb;
begin
  if not exists (select 1 from public.tk_config where token = p_token) then
    raise exception 'Kalit noto''g''ri' using errcode = '28000';
  end if;
  create temp table if not exists tk_p (emp text primary key, name text, n text) on commit drop;
  truncate tk_p;
  insert into tk_p
  select distinct on (x.emp) x.emp, x.name, public.yk_norm3(x.name)
    from jsonb_to_recordset(p_people) as x(emp text, name text)
   where coalesce(x.emp, '') <> ''
  on conflict do nothing;

  -- allaqachon bog'langanlar
  delete from tk_p p where exists (select 1 from public.students s where s.ext_id = p.emp)
                         or exists (select 1 from public.tk_ids t where t.emp = p.emp);
  get diagnostics already = row_count;

  -- bog'lanmagan asosiy sinf o'quvchilari: to'liq ismi va otasining ismisiz ko'rinishi
  create temp table if not exists tk_s (id text, n text) on commit drop;
  truncate tk_s;
  insert into tk_s
  select distinct x.id, x.n from (
    select s.id::text id, public.yk_norm3(s.full_name) n, s.full_name
      from public.students s join public.classes c on c.id = s.class_id
     where c.kind is distinct from 'rep' and coalesce(c.grp, '') = ''
       and coalesce(s.full_name, '') <> ''
    union all
    select s.id::text, public.yk_norm3(public.yk_first2(s.full_name)), s.full_name
      from public.students s join public.classes c on c.id = s.class_id
     where c.kind is distinct from 'rep' and coalesce(c.grp, '') = ''
       and coalesce(s.full_name, '') <> '') x
   where x.n <> '';

  -- moslar: shaxsga aynan bitta o'quvchi va o'quvchiga aynan bitta shaxs to'g'ri kelsa — bog'lanadi
  with m as (select distinct p.emp, s.id from tk_p p join tk_s s on s.n = p.n where p.n <> ''),
       pc as (select emp, count(*) c, min(id) id from m group by emp),
       sc as (select id, count(*) c from m group by id),
       ok as (select pc.emp, pc.id from pc join sc on sc.id = pc.id where pc.c = 1 and sc.c = 1),
       u as (update public.students st set ext_id = ok.emp from ok where st.id::text = ok.id and coalesce(st.ext_id, '') = '' returning ok.emp),
       -- turniket ID si o'zgargan (qayta ro'yxatga olingan) o'quvchi: yangi ID qo'shimcha sifatida yoziladi
       x as (insert into public.tk_ids (emp, student_id)
             select ok.emp, ok.id from ok join public.students st on st.id::text = ok.id and coalesce(st.ext_id, '') <> ''
             on conflict (emp) do nothing returning emp)
  select (select count(*) from u) + (select count(*) from x) into linked;

  -- yangi bog'langanlarning shu kungacha hisobga olinmagan o'tishlari: 07:20–09:20 — kelish, 16:00–17:30 — ketish
  -- (1–2-sinflar turniket bo'yicha hisoblanmaydi — ular turniketsiz binoda o'qiydi)
  if linked > 0 then
    -- tez: faqat shu chaqiruvda bog'langan shaxslarning o'tishlari (turniket ID indeksi bo'yicha)
    update public.turnstile_events e set student_id = m.sid
      from (select s.ext_id as emp, s.id::text as sid from public.students s join public.classes c on c.id = s.class_id
                where coalesce(s.ext_id, '') <> '' and c.kind is distinct from 'rep' and coalesce(c.grp, '') = ''
              union
              select t.emp, t.student_id from public.tk_ids t
                join public.students s on s.id::text = t.student_id join public.classes c on c.id = s.class_id
               where c.kind is distinct from 'rep' and coalesce(c.grp, '') = '') m
     where m.emp in (select emp from tk_p) and e.emp_no = m.emp and e.student_id is null;
    insert into public.daily_scores (student_id, day, att, excused, arrived_at)
    select s.id, (e.ts at time zone 'Asia/Tashkent')::date, 1, false, min(e.ts)
      from public.turnstile_events e
      join public.students s on s.id::text = e.student_id
      join tk_p p on p.emp = e.emp_no
     where public.yk_tk_class(s.class_id) and (e.ts at time zone 'Asia/Tashkent')::time between time '07:20' and time '09:20'
     group by s.id, (e.ts at time zone 'Asia/Tashkent')::date
    on conflict (student_id, day) do update
      set att = 1, excused = false,
          arrived_at = least(coalesce(public.daily_scores.arrived_at, excluded.arrived_at), excluded.arrived_at);
    insert into public.daily_scores (student_id, day, left_at)
    select s.id, (e.ts at time zone 'Asia/Tashkent')::date, max(e.ts)
      from public.turnstile_events e
      join public.students s on s.id::text = e.student_id
      join tk_p p on p.emp = e.emp_no
     where public.yk_tk_class(s.class_id) and (e.ts at time zone 'Asia/Tashkent')::time between time '16:00' and time '17:30'
     group by s.id, (e.ts at time zone 'Asia/Tashkent')::date
    on conflict (student_id, day) do update
      set left_at = greatest(coalesce(public.daily_scores.left_at, excluded.left_at), excluded.left_at);
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('emp', p.emp, 'name', p.name,
           'sabab', case when coalesce(pc.c, 0) = 0 then 'topilmadi'
                         when pc.c > 1 then 'bir xil ism ' || pc.c || ' ta'
                         else 'turniketda bir xil ism bir necha marta' end)), '[]'::jsonb)
    into miss
    from tk_p p
    left join (select p2.emp, count(distinct s.id) c from tk_p p2 join tk_s s on s.n = p2.n and p2.n <> '' group by p2.emp) pc on pc.emp = p.emp
   where not exists (select 1 from public.students s where s.ext_id = p.emp)
     and not exists (select 1 from public.tk_ids t where t.emp = p.emp);

  -- yangi (53): bog'lanmaganlar platformada saqlanadi — admin ularni "Turniket bog'lash" bo'limida bir bosishda bog'laydi
  insert into public.tk_unmatched (emp, name, sabab, seen_at)
  select x->>'emp', coalesce(x->>'name', ''), x->>'sabab', now() from jsonb_array_elements(miss) x
  on conflict (emp) do update set name = excluded.name, sabab = excluded.sabab, seen_at = now();
  delete from public.tk_unmatched u
   where exists (select 1 from public.students s where s.ext_id = u.emp)
      or exists (select 1 from public.tk_ids t where t.emp = u.emp);

  return jsonb_build_object('boglandi', linked, 'oldin_boglangan', already, 'boglanmadi', miss);
end $$;

create or replace function public.tk_qayta_hisob(p_from date) returns table (boglandi int, keldi int, ketdi int)
language plpgsql security definer set search_path = public as $$
declare b int; k int; q int;
begin
  if coalesce(public.yk_role(), '') <> 'admin' and current_user not in ('postgres', 'supabase_admin') then
    raise exception 'Faqat admin' using errcode = '42501';
  end if;
  -- 1. Bog'lanmagan o'tishlarni turniket ID bo'yicha o'quvchiga bog'lash (asosiy sinflar)
  update public.turnstile_events te set student_id = m.sid
    from (select s.ext_id as emp, s.id::text as sid from public.students s join public.classes c on c.id = s.class_id
                where coalesce(s.ext_id, '') <> '' and c.kind is distinct from 'rep' and coalesce(c.grp, '') = ''
              union
              select t.emp, t.student_id from public.tk_ids t
                join public.students s on s.id::text = t.student_id join public.classes c on c.id = s.class_id
               where c.kind is distinct from 'rep' and coalesce(c.grp, '') = '') m
   where te.emp_no = m.emp and te.student_id is null and te.ts >= (p_from::timestamp at time zone 'Asia/Tashkent');
  get diagnostics b = row_count;
  -- 2. Kelish: kunning 07:20–09:20 oralig'idagi birinchi o'tishi
  with a as (
    select s.id, (te.ts at time zone 'Asia/Tashkent')::date d, min(te.ts) t
      from public.turnstile_events te join public.students s on s.id::text = te.student_id
     where te.ts >= (p_from::timestamp at time zone 'Asia/Tashkent')
       and (te.ts at time zone 'Asia/Tashkent')::time between time '07:20' and time '09:20' and public.yk_tk_class(s.class_id)
     group by 1, 2)
  insert into public.daily_scores (student_id, day, att, excused, arrived_at)
  select id, d, 1, false, t from a
  on conflict (student_id, day) do update
    set att = 1, excused = false, arrived_at = least(coalesce(public.daily_scores.arrived_at, excluded.arrived_at), excluded.arrived_at);
  get diagnostics k = row_count;
  -- 3. Ketish: 16:00–17:30 oralig'idagi oxirgi o'tish
  with a as (
    select s.id, (te.ts at time zone 'Asia/Tashkent')::date d, max(te.ts) t
      from public.turnstile_events te join public.students s on s.id::text = te.student_id
     where te.ts >= (p_from::timestamp at time zone 'Asia/Tashkent')
       and (te.ts at time zone 'Asia/Tashkent')::time between time '16:00' and time '17:30' and public.yk_tk_class(s.class_id)
     group by 1, 2)
  insert into public.daily_scores (student_id, day, left_at)
  select id, d, t from a
  on conflict (student_id, day) do update
    set left_at = greatest(coalesce(public.daily_scores.left_at, excluded.left_at), excluded.left_at);
  get diagnostics q = row_count;
  return query select b, k, q;
end $$;

notify pgrst, 'reload schema';
