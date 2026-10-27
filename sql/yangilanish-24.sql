-- Yangilanish 24: turniket davomati qoidalari, kech kelganlar va maktabdan ketish.
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing. Qayta ishga tushirish xavfsiz.
-- (yangilanish-22.sql dan keyin ishga tushiriladi; uning ism moslashtirish yaxshilanishlari saqlanadi)
--  1) 1- va 2-sinflar turniket bo'yicha davomatga kirmaydi (ular turniketsiz ikkinchi binoda o'qiydi).
--  2) Kelish: faqat 09:30 gacha bo'lgan o'tishlar "keldi" (birinchi o'tish vaqti — kelgan vaqt; 08:30 dan keyin — kech kelgan).
--     09:30 – 16:40 oralig'idagi o'tishlar (binolar orasida yurish) davomatga ta'sir qilmaydi, faqat jurnalga yoziladi.
--  3) Ketish: 16:40 dan keyingi oxirgi o'tish — maktabdan ketgan vaqt (daily_scores.left_at).

alter table public.daily_scores add column if not exists left_at timestamptz;

-- Turniket davomati hisoblanadigan sinf: oddiy sinf (guruh/repetitor emas) va 1–2-sinf emas
create or replace function public.yk_tk_class(p_class bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select c.kind is distinct from 'rep' and coalesce(c.grp, '') = ''
                          and coalesce(c.subject, '') !~* '^(arab|koreys)'
                          and coalesce(c.grade, nullif(substring(c.name from '^\s*(\d+)'), '')::int, 0) not in (1, 2)
                     from public.classes c where c.id = p_class), false)
$$;

create or replace function public.tk_push(p_token text, p_events jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare e record; sid public.students.id%type; cid bigint; eid bigint; lt timestamp; n int := 0;
begin
  if not exists (select 1 from public.tk_config where token = p_token) then
    raise exception 'Kalit noto''g''ri' using errcode = '28000';
  end if;
  for e in select * from jsonb_to_recordset(p_events) as x(emp text, ts timestamptz, door text) loop
    continue when coalesce(e.emp, '') = '' or e.ts is null;
    select s.id, s.class_id into sid, cid from public.students s join public.classes c on c.id = s.class_id
     where s.ext_id = e.emp and c.kind is distinct from 'rep' and coalesce(c.grp, '') = '' limit 1;
    insert into public.turnstile_events (emp_no, student_id, ts, door)
    values (e.emp, sid::text, e.ts, coalesce(e.door, '')) on conflict do nothing returning id into eid;
    if eid is not null and sid is not null and public.yk_tk_class(cid) then
      lt := e.ts at time zone 'Asia/Tashkent';
      if lt::time <= time '09:30' then
        insert into public.daily_scores (student_id, day, att, excused, arrived_at) values (sid, lt::date, 1, false, e.ts)
        on conflict (student_id, day) do update
          set att = 1, excused = false, arrived_at = least(coalesce(public.daily_scores.arrived_at, excluded.arrived_at), excluded.arrived_at);
        n := n + 1;
      elsif lt::time >= time '16:40' then
        insert into public.daily_scores (student_id, day, left_at) values (sid, lt::date, e.ts)
        on conflict (student_id, day) do update
          set left_at = greatest(coalesce(public.daily_scores.left_at, excluded.left_at), excluded.left_at);
        n := n + 1;
      end if;
    end if;
    sid := null; cid := null; eid := null;
  end loop;
  return n;
end $$;
revoke all on function public.tk_push(text, jsonb) from public;
grant execute on function public.tk_push(text, jsonb) to anon, authenticated;

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
  delete from tk_p p using public.students s where s.ext_id = p.emp;
  get diagnostics already = row_count;

  -- bog'lanmagan asosiy sinf o'quvchilari: to'liq ismi va otasining ismisiz ko'rinishi
  create temp table if not exists tk_s (id text, n text) on commit drop;
  truncate tk_s;
  insert into tk_s
  select distinct x.id, x.n from (
    select s.id::text id, public.yk_norm3(s.full_name) n, s.full_name
      from public.students s join public.classes c on c.id = s.class_id
     where c.kind is distinct from 'rep' and coalesce(c.grp, '') = '' and coalesce(s.ext_id, '') = ''
       and coalesce(s.full_name, '') <> ''
    union all
    select s.id::text, public.yk_norm3(public.yk_first2(s.full_name)), s.full_name
      from public.students s join public.classes c on c.id = s.class_id
     where c.kind is distinct from 'rep' and coalesce(c.grp, '') = '' and coalesce(s.ext_id, '') = ''
       and coalesce(s.full_name, '') <> '') x
   where x.n <> '';

  -- moslar: shaxsga aynan bitta o'quvchi va o'quvchiga aynan bitta shaxs to'g'ri kelsa — bog'lanadi
  with m as (select distinct p.emp, s.id from tk_p p join tk_s s on s.n = p.n where p.n <> ''),
       pc as (select emp, count(*) c, min(id) id from m group by emp),
       sc as (select id, count(*) c from m group by id),
       ok as (select pc.emp, pc.id from pc join sc on sc.id = pc.id where pc.c = 1 and sc.c = 1),
       u as (update public.students st set ext_id = ok.emp from ok where st.id::text = ok.id returning ok.emp)
  select count(*) into linked from u;

  -- yangi bog'langanlarning shu kungacha hisobga olinmagan o'tishlari: 09:30 gacha — kelish, 16:40 dan keyin — ketish
  -- (1–2-sinflar turniket bo'yicha hisoblanmaydi — ular turniketsiz binoda o'qiydi)
  if linked > 0 then
    update public.turnstile_events e set student_id = s.id::text
      from public.students s join public.classes c on c.id = s.class_id
     where e.student_id is null and s.ext_id = e.emp_no
       and c.kind is distinct from 'rep' and coalesce(c.grp, '') = '';
    insert into public.daily_scores (student_id, day, att, excused, arrived_at)
    select s.id, (e.ts at time zone 'Asia/Tashkent')::date, 1, false, min(e.ts)
      from public.turnstile_events e
      join public.students s on s.id::text = e.student_id
      join tk_p p on p.emp = e.emp_no
     where public.yk_tk_class(s.class_id) and (e.ts at time zone 'Asia/Tashkent')::time <= time '09:30'
     group by s.id, (e.ts at time zone 'Asia/Tashkent')::date
    on conflict (student_id, day) do update
      set att = 1, excused = false,
          arrived_at = least(coalesce(public.daily_scores.arrived_at, excluded.arrived_at), excluded.arrived_at);
    insert into public.daily_scores (student_id, day, left_at)
    select s.id, (e.ts at time zone 'Asia/Tashkent')::date, max(e.ts)
      from public.turnstile_events e
      join public.students s on s.id::text = e.student_id
      join tk_p p on p.emp = e.emp_no
     where public.yk_tk_class(s.class_id) and (e.ts at time zone 'Asia/Tashkent')::time >= time '16:40'
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
   where not exists (select 1 from public.students s where s.ext_id = p.emp);

  return jsonb_build_object('boglandi', linked, 'oldin_boglangan', already, 'boglanmadi', miss);
end $$;
revoke all on function public.tk_map(text, jsonb) from public;
grant execute on function public.tk_map(text, jsonb) to anon, authenticated;

notify pgrst, 'reload schema';
