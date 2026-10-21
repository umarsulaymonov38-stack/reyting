-- Yangilanish 6: davomatda uchinchi holat — 🟡 "Sababli" (kasal yoki uzrli sabab bilan kelmagan).
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing. Qayta ishga tushirish xavfsiz.
-- Bazada: att = 0 (kelmagan) va excused = true (sababli). Ballar va reytinglarda o'zgarish yo'q: sababli ham 0 ball.

alter table public.daily_scores add column if not exists excused boolean not null default false;
alter table public.rep_daily    add column if not exists excused boolean not null default false;

-- Turniketdan o'tgan o'quvchi "keldi" bo'ladi va "sababli" belgisi olib tashlanadi
create or replace function public.tk_push(p_token text, p_events jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare e record; sid bigint; eid bigint; d date; n int := 0;
begin
  if not exists (select 1 from public.tk_config where token = p_token) then
    raise exception 'Kalit noto''g''ri' using errcode = '28000';
  end if;
  for e in select * from jsonb_to_recordset(p_events) as x(emp text, ts timestamptz, door text) loop
    continue when coalesce(e.emp, '') = '' or e.ts is null;
    select s.id into sid from public.students s join public.classes c on c.id = s.class_id
     where s.ext_id = e.emp and c.kind is distinct from 'rep' and coalesce(c.grp, '') = '' limit 1;
    insert into public.turnstile_events (emp_no, student_id, ts, door)
    values (e.emp, sid, e.ts, coalesce(e.door, '')) on conflict do nothing returning id into eid;
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

notify pgrst, 'reload schema';
