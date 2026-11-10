-- Yangilanish 53: turniket — bog'lanmagan shaxslarni platformada bog'lash va turniketda yuzi yo'q o'quvchilar ro'yxati.
--  1) tk_unmatched: ko'prik (2-OQUVCHILARNI-BOGLASH yoki doimiy ishlash) bog'lay olmagan turniket shaxslari saqlanadi.
--  2) tk_map: bog'lanmaganlarni shu jadvalga yozadi (qolgan ishi yangilanish-51 dagidek).
--  3) tk_admin_list(): admin uchun — bog'lanmaganlar va turniketga bog'langan o'quvchilar.
--  4) tk_link(emp, o'quvchi): turniket shaxsini o'quvchiga qo'lda bog'lash + so'nggi 60 kunlik davomatni qayta hisoblash.
--  5) tk_ignore(emp, ha/yo'q): "o'quvchi emas" (o'qituvchi, xodim) deb belgilash.
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing. Qayta ishga tushirish xavfsiz.
-- Keyin maktab kompyuterida 2-OQUVCHILARNI-BOGLASH.bat ni bir marta ishga tushiring — ro'yxat platformaga tushadi.

create table if not exists public.tk_unmatched (
  emp text primary key,
  name text not null default '',
  sabab text,
  ignored boolean not null default false,
  seen_at timestamptz not null default now()
);
alter table public.tk_unmatched enable row level security;
revoke all on public.tk_unmatched from anon, authenticated;

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

  -- yangi bog'langanlarning shu kungacha hisobga olinmagan o'tishlari: 09:30 gacha — kelish, 16:40 dan keyin — ketish
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
revoke all on function public.tk_map(text, jsonb) from public;
grant execute on function public.tk_map(text, jsonb) to anon, authenticated;

create or replace function public.tk_admin_list() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if coalesce(public.yk_role(), '') <> 'admin' then
    raise exception 'Faqat admin' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'unmatched', coalesce((select jsonb_agg(jsonb_build_object('emp', u.emp, 'name', u.name, 'sabab', u.sabab,
                                                               'ignored', u.ignored, 'seen', u.seen_at) order by u.name)
                             from public.tk_unmatched u
                            where not exists (select 1 from public.students s where s.ext_id = u.emp)
                              and not exists (select 1 from public.tk_ids t where t.emp = u.emp)), '[]'::jsonb),
    'linked', coalesce((select jsonb_agg(z.id) from (
                          select s.id::text id from public.students s where coalesce(s.ext_id, '') <> ''
                          union select t.student_id from public.tk_ids t) z), '[]'::jsonb));
end $$;
revoke all on function public.tk_admin_list() from public, anon;
grant execute on function public.tk_admin_list() to authenticated;

create or replace function public.tk_link(p_emp text, p_student text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare sid public.students.id%type; cur text; b int; k int; q int;
begin
  if coalesce(public.yk_role(), '') <> 'admin' then
    raise exception 'Faqat admin' using errcode = '42501';
  end if;
  p_emp := trim(coalesce(p_emp, ''));
  if p_emp = '' then raise exception 'Turniket ID bo''sh'; end if;
  if exists (select 1 from public.students s where s.ext_id = p_emp) or exists (select 1 from public.tk_ids t where t.emp = p_emp) then
    raise exception 'Bu turniket ID allaqachon boshqa o''quvchiga bog''langan';
  end if;
  select s.id, s.ext_id into sid, cur from public.students s where s.id::text = p_student;
  if sid is null then raise exception 'O''quvchi topilmadi'; end if;
  if coalesce(cur, '') = '' then
    update public.students set ext_id = p_emp where id = sid;
  else
    insert into public.tk_ids (emp, student_id) values (p_emp, sid::text);  -- o'quvchining qo'shimcha (yangi) ID si
  end if;
  delete from public.tk_unmatched where emp = p_emp;
  -- shu kungacha bog'lanmay qolgan o'tishlar o'quvchiga bog'lanadi, davomat qayta hisoblanadi
  select x.boglandi, x.keldi, x.ketdi into b, k, q from public.tk_qayta_hisob(current_date - 60) x;
  return jsonb_build_object('otish', b, 'keldi', k, 'ketdi', q);
end $$;
revoke all on function public.tk_link(text, text) from public, anon;
grant execute on function public.tk_link(text, text) to authenticated;

create or replace function public.tk_ignore(p_emp text, p_val boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(public.yk_role(), '') <> 'admin' then
    raise exception 'Faqat admin' using errcode = '42501';
  end if;
  update public.tk_unmatched set ignored = coalesce(p_val, true) where emp = p_emp;
end $$;
revoke all on function public.tk_ignore(text, boolean) from public, anon;
grant execute on function public.tk_ignore(text, boolean) to authenticated;

notify pgrst, 'reload schema';
