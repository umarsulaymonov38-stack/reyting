-- Yangilanish 7: ota-ona bitta login bilan barcha farzandlarini birga ko'radi (davomat va to'lovlar).
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing. Qayta ishga tushirish xavfsiz.
-- Farzandlar ro'yxati mavjud my_kids() funksiyasidan olinadi (ota-ona telefoniga bog'langan o'quvchilar),
-- shuning uchun ota-ona faqat o'z farzandlarini ko'radi.

drop function if exists public.parent_overview(date);
create or replace function public.parent_overview(p_from date)
returns table (id text, full_name text, class_id text, att int, excused boolean, arrived_at timestamptz, pays jsonb, first_day date)
language sql stable security definer set search_path = public as $$
  select k.id::text, k.full_name::text, k.class_id::text,
         d.att::int,
         coalesce((to_jsonb(d) ->> 'excused')::boolean, false),
         (to_jsonb(d) ->> 'arrived_at')::timestamptz,
         coalesce((select jsonb_agg(jsonb_build_object('month', p.month, 'paid', p.paid, 'paid_on', p.paid_on) order by p.month)
                     from public.payments p where p.student_id = k.id and p.month >= p_from), '[]'::jsonb),
         (select min(s.day) from public.daily_scores s where s.student_id = k.id and s.day >= p_from)
    from public.my_kids() k
    left join public.daily_scores d on d.student_id = k.id and d.day = (now() at time zone 'Asia/Tashkent')::date
   order by k.full_name
$$;
revoke all on function public.parent_overview(date) from public, anon;
grant execute on function public.parent_overview(date) to authenticated;

-- O'quvchi id si bazada uuid bo'lgani uchun avvalgi yangilanishlardagi turlarni moslash
do $$ begin
  if to_regclass('public.feedback') is not null then
    alter table public.feedback alter column student_id type text using student_id::text;
  end if;
  if to_regclass('public.turnstile_events') is not null then
    alter table public.turnstile_events alter column student_id type text using student_id::text;
  end if;
end $$;

-- Turniket funksiyalari (o'quvchi id turi students.id dan olinadi)
create or replace function public.tk_push(p_token text, p_events jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare e record; sid public.students.id%type; eid bigint; d date; n int := 0;
begin
  if not exists (select 1 from public.tk_config where token = p_token) then
    raise exception 'Kalit noto''g''ri' using errcode = '28000';
  end if;
  for e in select * from jsonb_to_recordset(p_events) as x(emp text, ts timestamptz, door text) loop
    continue when coalesce(e.emp, '') = '' or e.ts is null;
    select s.id into sid from public.students s join public.classes c on c.id = s.class_id
     where s.ext_id = e.emp and c.kind is distinct from 'rep' and coalesce(c.grp, '') = '' limit 1;
    insert into public.turnstile_events (emp_no, student_id, ts, door)
    values (e.emp, sid::text, e.ts, coalesce(e.door, '')) on conflict do nothing returning id into eid;
    if eid is not null and sid is not null then
      d := (e.ts at time zone 'Asia/Tashkent')::date;
      insert into public.daily_scores (student_id, day, att, arrived_at) values (sid, d, 1, e.ts)
      on conflict (student_id, day) do update
        set att = 1, excused = false, arrived_at = least(coalesce(public.daily_scores.arrived_at, excluded.arrived_at), excluded.arrived_at);
      n := n + 1;
    end if;
    sid := null; eid := null;
  end loop;
  return n;
end $$;
revoke all on function public.tk_push(text, jsonb) from public;
grant execute on function public.tk_push(text, jsonb) to anon, authenticated;

create or replace function public.tk_map(p_token text, p_people jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare p record; sid public.students.id%type; cnt int; linked int := 0; already int := 0; miss jsonb := '[]'::jsonb;
begin
  if not exists (select 1 from public.tk_config where token = p_token) then
    raise exception 'Kalit noto''g''ri' using errcode = '28000';
  end if;
  for p in select * from jsonb_to_recordset(p_people) as x(emp text, name text) loop
    continue when coalesce(p.emp, '') = '';
    if exists (select 1 from public.students where ext_id = p.emp) then already := already + 1; continue; end if;
    select count(*), (array_agg(s.id))[1] into cnt, sid from public.students s join public.classes c on c.id = s.class_id
     where c.kind is distinct from 'rep' and coalesce(c.grp, '') = '' and coalesce(s.ext_id, '') = ''
       and public.yk_norm(s.full_name) = public.yk_norm(p.name) and public.yk_norm(p.name) <> '';
    if cnt = 1 then
      update public.students set ext_id = p.emp where id = sid; linked := linked + 1;
    else
      miss := miss || jsonb_build_object('emp', p.emp, 'name', p.name, 'sabab', case when cnt = 0 then 'topilmadi' else 'bir xil ism ' || cnt || ' ta' end);
    end if;
  end loop;
  return jsonb_build_object('boglandi', linked, 'oldin_boglangan', already, 'boglanmadi', miss);
end $$;
revoke all on function public.tk_map(text, jsonb) from public;
grant execute on function public.tk_map(text, jsonb) to anon, authenticated;

notify pgrst, 'reload schema';
