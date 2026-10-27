-- Yangilanish 22: turniket bog'lash yozuv farqlariga chidamli bo'ldi + kechikib bog'langanlarga davomat.
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing. Qayta ishga tushirish xavfsiz.
--  1) Ism solishtirishda yozuv farqlari bir xil deb olinadi: Dj/J, X/H, Kh/H, Sh/Ş, Ch/Ç, o'/ò/õ/ö/u, g'/ģ/ğ,
--     turli tutuq belgilari (' ` ’ ʻ), Yi/I, Ya/A, Yu/U. Otasining ismi yozilgan bo'lsa ham mos keladi.
--  2) Yangi o'quvchi platformaga kiritilgach, ko'prik uni keyingi o'tishda o'zi bog'laydi va shu kungi
--     (oldin hisobga olinmagan) o'tishlari bo'yicha davomatni ham qo'yadi.

create or replace function public.yk_norm3(t text) returns text language sql immutable as $$
  select public.yk_norm(
    replace(replace(replace(replace(replace(replace(replace(replace(replace(
    replace(replace(replace(
      regexp_replace(regexp_replace(
        translate(lower(coalesce(t,'')), 'şçòõöóıüğģёʻʼ’`‘''', 'SCUUUUiuggeAAAAAA'),
        'oA', 'U', 'g'), 'gA', 'g', 'g'),
      'A',''), 'S','sh'), 'C','ch'), 'U','u'), 'dj','j'), 'kh','h'), 'x','h'),
      'yi','i'), 'iy','i'), 'ya','a'), 'yu','u'), '''', ''))
$$;

-- Ismning faqat familiya va ism qismi (otasining ismisiz)
create or replace function public.yk_first2(t text) returns text language sql immutable as $$
  select array_to_string((regexp_split_to_array(trim(coalesce(t,'')), '\s+'))[1:2], ' ')
$$;

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

  -- yangi bog'langanlarning oldin kelgan, lekin hisobga olinmagan o'tishlariga davomat
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
     group by s.id, (e.ts at time zone 'Asia/Tashkent')::date
    on conflict (student_id, day) do update
      set att = 1, excused = false,
          arrived_at = least(coalesce(public.daily_scores.arrived_at, excluded.arrived_at), excluded.arrived_at);
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
