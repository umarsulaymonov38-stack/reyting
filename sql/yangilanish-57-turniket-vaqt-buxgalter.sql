-- Yangilanish 57:
--  1) Turniket davomati faqat belgilangan vaqtlarda hisoblanadi:
--       KELISH — har kuni 07:40 dan 09:20 gacha (shu oraliqdagi birinchi o'tish);
--       KETISH — 16:00 dan 17:30 gacha (shu oraliqdagi oxirgi o'tish).
--     Boshqa vaqtdagi o'tishlar saqlanadi, lekin davomatga ham, ota-onaga xabarga ham ta'sir qilmaydi.
--  2) Buxgalter: o'qituvchi akkauntiga «Buxgalter» belgisi (bosh admin «O'qituvchilar» bo'limida qo'yadi).
--     Buxgalter profilida faqat «To'lov» bo'limi: barcha sinflar kesimida o'quvchilar, to'lov belgilash,
--     kunlik to'lovlar ro'yxati (PDF) va statistika. Belgilangan to'lov ota-ona profilida ko'rinadi.
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing (loyiha: YUKSALISH-REYTING). Qayta ishga tushirish xavfsiz.

-- ============ 1. Turniket vaqt oraliqlari ============
create or replace function public.tk_push(p_token text, p_events jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare e record; sid public.students.id%type; cid bigint; eid bigint; isnew boolean; lt timestamp; n int := 0; kind text;
        has_sms boolean := to_regclass('public.sms_config') is not null;
        kf time := coalesce((select ketdi_from from public.push_config where id = 1), time '16:45');
        sf time;
begin
  if not exists (select 1 from public.tk_config where token = p_token) then
    raise exception 'Kalit noto''g''ri' using errcode = '28000';
  end if;
  if has_sms then execute 'select ketdi_from from public.sms_config where id = 1' into sf; end if;
  for e in select * from jsonb_to_recordset(p_events) as x(emp text, ts timestamptz, door text) loop
    continue when coalesce(e.emp, '') = '' or e.ts is null;
    select s.id, s.class_id into sid, cid from public.students s join public.classes c on c.id = s.class_id
     where (s.ext_id = e.emp or s.id::text = (select t.student_id from public.tk_ids t where t.emp = e.emp))
       and c.kind is distinct from 'rep' and coalesce(c.grp, '') = '' limit 1;
    insert into public.turnstile_events (emp_no, student_id, ts, door)
    values (e.emp, sid::text, e.ts, coalesce(e.door, ''))
    on conflict (emp_no, ts, door) do update set student_id = coalesce(public.turnstile_events.student_id, excluded.student_id)
    returning id, (xmax = 0) into eid, isnew;
    if eid is not null and sid is not null and public.yk_tk_class(cid) then
      lt := e.ts at time zone 'Asia/Tashkent';
      if lt::time between time '07:40' and time '09:20' then
        insert into public.daily_scores (student_id, day, att, excused, arrived_at) values (sid, lt::date, 1, false, e.ts)
        on conflict (student_id, day) do update
          set att = 1, excused = false, arrived_at = least(coalesce(public.daily_scores.arrived_at, excluded.arrived_at), excluded.arrived_at);
        n := n + 1;
      elsif lt::time between time '16:00' and time '17:30' then
        insert into public.daily_scores (student_id, day, left_at) values (sid, lt::date, e.ts)
        on conflict (student_id, day) do update
          set left_at = greatest(coalesce(public.daily_scores.left_at, excluded.left_at), excluded.left_at);
        n := n + 1;
      end if;
      -- xabarlar faqat yangi o'tishlar uchun (ko'prik eski kunlarni keyin yuborsa — xabar ketmaydi)
      -- xabar faqat hisoblanadigan oraliqdagi o'tishlar uchun: 07:40–09:20 — «keldi», 16:00–17:30 — «ketdi»
      kind := case when lt::time between time '07:40' and time '09:20' then 'keldi' when lt::time between time '16:00' and time '17:30' then 'ketdi' end;
      if isnew and kind is not null and e.ts > now() - interval '3 hours' then
        perform public.yk_push_add(kind, sid::text, e.ts);
        if has_sms then perform public.yk_sms_add(kind, sid::text, e.ts); end if;
      end if;
    end if;
    sid := null; cid := null; eid := null;
  end loop;
  return n;
end $$;

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

  -- yangi bog'langanlarning shu kungacha hisobga olinmagan o'tishlari: 07:40–09:20 — kelish, 16:00–17:30 — ketish
  -- (1–2-sinflar turniket bo'yicha hisoblanmaydi — ular turniketsiz binoda o'qiydi)
  if linked > 0 then
    update public.turnstile_events e set student_id = s.id::text
      from public.students s join public.classes c on c.id = s.class_id
     where e.student_id is null and (s.ext_id = e.emp_no or s.id::text = (select t.student_id from public.tk_ids t where t.emp = e.emp_no))
       and c.kind is distinct from 'rep' and coalesce(c.grp, '') = '';
    insert into public.daily_scores (student_id, day, att, excused, arrived_at)
    select s.id, (e.ts at time zone 'Asia/Tashkent')::date, 1, false, min(e.ts)
      from public.turnstile_events e
      join public.students s on s.id::text = e.student_id
      join tk_p p on p.emp = e.emp_no
     where public.yk_tk_class(s.class_id) and (e.ts at time zone 'Asia/Tashkent')::time between time '07:40' and time '09:20'
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
  update public.turnstile_events te set student_id = s.id::text
    from public.students s join public.classes c on c.id = s.class_id
   where te.student_id is null and te.ts >= (p_from::timestamp at time zone 'Asia/Tashkent')
     and (s.ext_id = te.emp_no or s.id::text = (select t.student_id from public.tk_ids t where t.emp = te.emp_no))
     and c.kind is distinct from 'rep' and coalesce(c.grp, '') = '';
  get diagnostics b = row_count;
  -- 2. Kelish: kunning 07:40–09:20 oralig'idagi birinchi o'tishi
  with a as (
    select s.id, (te.ts at time zone 'Asia/Tashkent')::date d, min(te.ts) t
      from public.turnstile_events te join public.students s on s.id::text = te.student_id
     where te.ts >= (p_from::timestamp at time zone 'Asia/Tashkent')
       and (te.ts at time zone 'Asia/Tashkent')::time between time '07:40' and time '09:20' and public.yk_tk_class(s.class_id)
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

-- ============ 2. Buxgalter ============
alter table public.profiles add column if not exists bux boolean not null default false;

create or replace function public.yk_bux() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select p.bux from public.profiles p where p.id = auth.uid() and p.role = 'teacher'), false)
$$;
grant execute on function public.yk_bux() to authenticated;

create or replace function public.set_bux(p_id uuid, p_on boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if public.yk_role() is distinct from 'admin' then raise exception 'Faqat bosh admin' using errcode = '42501'; end if;
  update public.profiles set bux = coalesce(p_on, false) where id = p_id and role = 'teacher';
  if not found then raise exception 'O''qituvchi topilmadi'; end if;
end $$;
revoke all on function public.set_bux(uuid, boolean) from public, anon;
grant execute on function public.set_bux(uuid, boolean) to authenticated;

-- O'qituvchi o'z belgisini o'zi o'zgartira olmasin
create or replace function public.yk_bux_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.bux is distinct from old.bux and public.yk_role() is distinct from 'admin' and current_user not in ('postgres', 'supabase_admin', 'service_role') then
    new.bux := old.bux;
  end if;
  return new;
end $$;
drop trigger if exists yk_bux_guard on public.profiles;
create trigger yk_bux_guard before update on public.profiles for each row execute function public.yk_bux_guard();

-- Huquqlar: to'lovlar — o'qish va yozish; o'quvchilar va sinflar — faqat o'qish (parollar/kodlar ko'rinmaydi)
grant select, insert, update on public.payments to authenticated;
drop policy if exists bux_all on public.payments;
create policy bux_all on public.payments for all to authenticated using (public.yk_bux()) with check (public.yk_bux());
drop policy if exists bux_read on public.students;
create policy bux_read on public.students for select to authenticated using (public.yk_bux());
drop policy if exists bux_read on public.classes;
create policy bux_read on public.classes for select to authenticated using (public.yk_bux());

-- Ota-ona telefoni (kod/parolsiz) — buxgalter va admin uchun
create or replace function public.bux_phones() returns table (student_id text, parent_phone text)
language sql stable security definer set search_path = public as $$
  select sp.student_id::text, sp.parent_phone from public.student_private sp
   where public.yk_bux() or public.yk_role() = 'admin'
$$;
revoke all on function public.bux_phones() from public, anon;
grant execute on function public.bux_phones() to authenticated;

notify pgrst, 'reload schema';

select full_name as "O'qituvchilar", case when bux then '💰 buxgalter' else '' end as belgi
  from public.profiles where role = 'teacher' and bux;
