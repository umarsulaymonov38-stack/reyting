-- Yangilanish 51: turniket — o'quvchi keyinroq bog'lansa ham davomat qo'yiladi.
--  1) tk_push: o'tish bazada oldin bo'lsa ham (qayta yuklashda) o'quvchiga bog'lanadi va davomat qo'yiladi
--     (bildirishnoma faqat yangi o'tishlar uchun, takrorlanmaydi).
--  2) tk_qayta_hisob(sana): shu sanadan beri bog'lanmay qolgan o'tishlarni o'quvchilarga (turniket ID bo'yicha) bog'lab,
--     davomatni (09:30 gacha — keldi, 16:40 dan — ketish vaqti) qayta hisoblaydi. Avval 2-OQUVCHILARNI-BOGLASH.bat ni ishga tushiring.
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing. Qayta ishga tushirish xavfsiz.

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
     where s.ext_id = e.emp and c.kind is distinct from 'rep' and coalesce(c.grp, '') = '' limit 1;
    insert into public.turnstile_events (emp_no, student_id, ts, door)
    values (e.emp, sid::text, e.ts, coalesce(e.door, ''))
    on conflict (emp_no, ts, door) do update set student_id = coalesce(public.turnstile_events.student_id, excluded.student_id)
    returning id, (xmax = 0) into eid, isnew;
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
      -- xabarlar faqat yangi o'tishlar uchun (ko'prik eski kunlarni keyin yuborsa — xabar ketmaydi)
      if isnew and e.ts > now() - interval '3 hours' then
        kind := case when lt::time < kf then 'keldi' else 'ketdi' end;
        perform public.yk_push_add(kind, sid::text, e.ts);
        if has_sms then
          perform public.yk_sms_add(case when lt::time < coalesce(sf, kf) then 'keldi' else 'ketdi' end, sid::text, e.ts);
        end if;
      end if;
    end if;
    sid := null; cid := null; eid := null;
  end loop;
  return n;
end $$;
revoke all on function public.tk_push(text, jsonb) from public;
grant execute on function public.tk_push(text, jsonb) to anon, authenticated;

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
     and s.ext_id = te.emp_no and c.kind is distinct from 'rep' and coalesce(c.grp, '') = '';
  get diagnostics b = row_count;
  -- 2. Kelish: kunning 09:30 gacha birinchi o'tishi
  with a as (
    select s.id, (te.ts at time zone 'Asia/Tashkent')::date d, min(te.ts) t
      from public.turnstile_events te join public.students s on s.id::text = te.student_id
     where te.ts >= (p_from::timestamp at time zone 'Asia/Tashkent')
       and (te.ts at time zone 'Asia/Tashkent')::time <= time '09:30' and public.yk_tk_class(s.class_id)
     group by 1, 2)
  insert into public.daily_scores (student_id, day, att, excused, arrived_at)
  select id, d, 1, false, t from a
  on conflict (student_id, day) do update
    set att = 1, excused = false, arrived_at = least(coalesce(public.daily_scores.arrived_at, excluded.arrived_at), excluded.arrived_at);
  get diagnostics k = row_count;
  -- 3. Ketish: 16:40 dan keyingi oxirgi o'tish
  with a as (
    select s.id, (te.ts at time zone 'Asia/Tashkent')::date d, max(te.ts) t
      from public.turnstile_events te join public.students s on s.id::text = te.student_id
     where te.ts >= (p_from::timestamp at time zone 'Asia/Tashkent')
       and (te.ts at time zone 'Asia/Tashkent')::time >= time '16:40' and public.yk_tk_class(s.class_id)
     group by 1, 2)
  insert into public.daily_scores (student_id, day, left_at)
  select id, d, t from a
  on conflict (student_id, day) do update
    set left_at = greatest(coalesce(public.daily_scores.left_at, excluded.left_at), excluded.left_at);
  get diagnostics q = row_count;
  return query select b, k, q;
end $$;
revoke all on function public.tk_qayta_hisob(date) from public, anon;
grant execute on function public.tk_qayta_hisob(date) to authenticated;

notify pgrst, 'reload schema';

-- 28-oktabrdan beri qayta hisoblash (2-OQUVCHILARNI-BOGLASH.bat dan keyin bu qatorni yana alohida Run qiling)
select * from public.tk_qayta_hisob('2026-10-28');
