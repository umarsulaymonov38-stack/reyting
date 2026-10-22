-- Yangilanish 9: turniket ro'yxatini o'quvchilar bilan bog'lashni tezlashtirish (statement timeout xatosi tuzatildi).
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing. Qayta ishga tushirish xavfsiz.
-- Endi har bir o'quvchi ismi bir marta solishtiriladi (avval har bir shaxs uchun butun ro'yxat qayta ko'rilardi).

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
  select distinct on (x.emp) x.emp, x.name, public.yk_norm(x.name)
    from jsonb_to_recordset(p_people) as x(emp text, name text)
   where coalesce(x.emp, '') <> ''
  on conflict do nothing;

  -- allaqachon bog'langanlar
  delete from tk_p p using public.students s where s.ext_id = p.emp;
  get diagnostics already = row_count;

  -- bog'lanmagan asosiy sinf o'quvchilari (ismi bir marta normallashtiriladi)
  create temp table if not exists tk_s (id text, n text) on commit drop;
  truncate tk_s;
  insert into tk_s
  select s.id::text, public.yk_norm(s.full_name)
    from public.students s join public.classes c on c.id = s.class_id
   where c.kind is distinct from 'rep' and coalesce(c.grp, '') = '' and coalesce(s.ext_id, '') = ''
     and coalesce(s.full_name, '') <> '';

  -- moslar: shaxsga aynan bitta o'quvchi va o'quvchiga aynan bitta shaxs to'g'ri kelsa — bog'lanadi
  with m as (select p.emp, s.id from tk_p p join tk_s s on s.n = p.n where p.n <> ''),
       pc as (select emp, count(*) c, min(id) id from m group by emp),
       sc as (select id, count(*) c from m group by id),
       ok as (select pc.emp, pc.id from pc join sc on sc.id = pc.id where pc.c = 1 and sc.c = 1),
       u as (update public.students st set ext_id = ok.emp from ok where st.id::text = ok.id returning ok.emp)
  select count(*) into linked from u;

  select coalesce(jsonb_agg(jsonb_build_object('emp', p.emp, 'name', p.name,
           'sabab', case when coalesce(pc.c, 0) = 0 then 'topilmadi'
                         when pc.c > 1 then 'bir xil ism ' || pc.c || ' ta'
                         else 'turniketda bir xil ism bir necha marta' end)), '[]'::jsonb)
    into miss
    from tk_p p
    left join (select p2.emp, count(*) c from tk_p p2 join tk_s s on s.n = p2.n and p2.n <> '' group by p2.emp) pc on pc.emp = p.emp
   where not exists (select 1 from public.students s where s.ext_id = p.emp);

  return jsonb_build_object('boglandi', linked, 'oldin_boglangan', already, 'boglanmadi', miss);
end $$;
revoke all on function public.tk_map(text, jsonb) from public;
grant execute on function public.tk_map(text, jsonb) to anon, authenticated;

notify pgrst, 'reload schema';
