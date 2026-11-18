-- Yangilanish 78: Turniket nazorati — har kuni kuzatib yurish shart emas.
--   1) Ko'prik har daqiqada holatini yuboradi (ko'prik ishlayapti, har bir eshik javob beryaptimi, oxirgi o'tish).
--   2) Admin bosh sahifasida «Turniket holati»: 🟢/🔴 har bir eshik, ko'prik, bugungi raqamlar.
--   3) Ogohlantirish (telefon bildirishnomasi adminga): ko'prik yoki eshik 10 daqiqa jim qolsa
--      (07:00–18:00, dushanba–shanba; bir xil muammo bo'yicha soatiga bir marta).
--   4) Har kuni 09:30 da adminga qisqa hisobot: turniketdan o'tganlar, bog'lanmaganlar, 1–2-sinflar.
-- Ko'prikning yangi versiyasi kerak (turniket_bridge.py, 2026-11-18).
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing (loyiha: YUKSALISH-REYTING). Qayta ishga tushirish xavfsiz.

create table if not exists public.tk_beat (
  id int primary key default 1 check (id = 1),
  seen_at timestamptz,
  version text,
  doors jsonb
);
alter table public.tk_beat enable row level security;
revoke all on public.tk_beat from anon, authenticated;

create table if not exists public.tk_alert (key text primary key, sent_at timestamptz);
alter table public.tk_alert enable row level security;
revoke all on public.tk_alert from anon, authenticated;

-- Ko'prik chaqiradi (turniket kaliti bilan)
create or replace function public.tk_heartbeat(p_token text, p_doors jsonb, p_ver text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.tk_config where token = p_token) then
    raise exception 'Kalit noto''g''ri' using errcode = '28000';
  end if;
  insert into public.tk_beat (id, seen_at, version, doors) values (1, now(), left(p_ver, 40), p_doors)
  on conflict (id) do update set seen_at = now(), version = excluded.version, doors = excluded.doors;
end $$;
revoke all on function public.tk_heartbeat(text, jsonb, text) from public;
grant execute on function public.tk_heartbeat(text, jsonb, text) to anon, authenticated;

-- Bugungi raqamlar (ichki)
create or replace function public.yk_tk_today() returns jsonb
language sql stable security definer set search_path = public as $$
  with t as (select (now() at time zone 'Asia/Tashkent')::date d),
  st as (
    select s.id, s.ext_id, public.yk_tk_class(s.class_id) as tk
      from public.students s join public.classes c on c.id = s.class_id
     where c.kind is distinct from 'rep' and coalesce(c.grp, '') = '' and coalesce(c.subject, '') !~* '^(arab|koreys)'
       and coalesce(btrim(s.full_name), '') <> '')
  select jsonb_build_object(
    'jami', (select count(*) from st),
    'turniketsiz', (select count(*) from st where not tk),
    'turniketli', (select count(*) from st where tk),
    'boglangan', (select count(*) from st where tk and (coalesce(ext_id, '') <> ''
                     or exists (select 1 from public.tk_ids i where i.student_id = st.id::text))),
    'otgan', (select count(distinct e.student_id) from public.turnstile_events e, t
               where (e.ts at time zone 'Asia/Tashkent')::date = t.d and e.student_id is not null),
    'boglanmagan_otgan', (select count(distinct e.emp_no) from public.turnstile_events e, t
               where (e.ts at time zone 'Asia/Tashkent')::date = t.d and e.student_id is null
                 and not exists (select 1 from public.tk_unmatched u where u.emp = e.emp_no and coalesce(u.ignored, false))),
    'keldi', (select count(*) from public.daily_scores d, t join st on true where d.day = t.d and d.att = 1 and d.student_id = st.id),
    'oxirgi_otish', (select max(e.ts) from public.turnstile_events e))
$$;
revoke all on function public.yk_tk_today() from public, anon, authenticated;

-- Admin: turniket holati
create or replace function public.tk_health() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.yk_role() = 'admin' or coalesce(public.yk_admin2(), false)) then
    raise exception 'Faqat admin' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'beat', (select to_jsonb(b) from public.tk_beat b where id = 1),
    'now', now(),
    'today', public.yk_tk_today());
end $$;
revoke all on function public.tk_health() from public, anon;
grant execute on function public.tk_health() to authenticated;

-- Bildirishnoma turi
alter table public.push_queue drop constraint if exists push_queue_kind_check;
alter table public.push_queue add constraint push_queue_kind_check
  check (kind in ('keldi', 'ketdi', 'kelmadi', 'test', 'yomon', 'yaxshi', 'savol', 'javob', 'eslatma', 'tk'));

-- Adminlarga xabar (ichki)
create or replace function public.yk_admin_push(p_key text, p_title text, p_body text) returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  insert into public.push_queue (user_id, kind, student_id, title, body)
  select p.id, 'tk', p_key, p_title, p_body
    from public.profiles p
   where (p.role = 'admin' or coalesce(p.admin2, false))
     and exists (select 1 from public.push_subs s where s.user_id = p.id)
  on conflict do nothing;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.yk_admin_push(text, text, text) from public, anon, authenticated;

-- Har 10 daqiqada: muammo bo'lsa — ogohlantirish (bir xil muammo bo'yicha soatiga bir marta)
create or replace function public.yk_tk_watch() returns int
language plpgsql security definer set search_path = public as $$
declare b public.tk_beat; lt timestamp := now() at time zone 'Asia/Tashkent'; d jsonb; n int := 0; k text;
begin
  if extract(isodow from lt) = 7 or lt::time < time '07:00' or lt::time > time '18:00' then return 0; end if;
  select * into b from public.tk_beat where id = 1;
  if b.id is null then return 0; end if;  -- ko'prik hali yangi versiyada emas
  if b.seen_at < now() - interval '10 minutes' then
    k := 'tk:bridge';
    if not exists (select 1 from public.tk_alert a where a.key = k and a.sent_at > now() - interval '1 hour') then
      n := n + public.yk_admin_push(k || ':' || to_char(lt, 'HH24'), '⚠️ Turniket ko''prigi to''xtadi',
             'Ko''prik ' || to_char(b.seen_at at time zone 'Asia/Tashkent', 'HH24:MI') ||
             ' dan beri jim. Davomat platformaga tushmayapti — ko''prik kompyuterini tekshiring (yoqilganmi, internet bormi).');
      insert into public.tk_alert values (k, now()) on conflict (key) do update set sent_at = now();
    end if;
    return n;
  end if;
  for d in select * from jsonb_array_elements(coalesce(b.doors, '[]'::jsonb)) loop
    continue when coalesce((d ->> 'ok')::boolean, true)
              and coalesce((d ->> 'ok_at')::timestamptz, now()) > now() - interval '10 minutes';
    k := 'tk:door:' || coalesce(d ->> 'name', '?');
    if not exists (select 1 from public.tk_alert a where a.key = k and a.sent_at > now() - interval '1 hour') then
      n := n + public.yk_admin_push(k || ':' || to_char(lt, 'HH24'), '⚠️ ' || coalesce(d ->> 'name', 'Eshik') || ' javob bermayapti',
             coalesce(d ->> 'name', 'Eshik') || ' (' || coalesce(d ->> 'host', '') || ') bilan aloqa yo''q — shu eshikdan o''tganlar platformaga tushmayapti. '
             || 'Turniket tokini, tarmoq kabelini va IP manzilini tekshiring.');
      insert into public.tk_alert values (k, now()) on conflict (key) do update set sent_at = now();
    end if;
  end loop;
  return n;
end $$;
revoke all on function public.yk_tk_watch() from public, anon, authenticated;

-- Har kuni 09:30: qisqa hisobot
create or replace function public.yk_tk_morning() returns int
language plpgsql security definer set search_path = public as $$
declare j jsonb := public.yk_tk_today(); b public.tk_beat; bad text;
begin
  if extract(isodow from now() at time zone 'Asia/Tashkent') = 7 then return 0; end if;
  select * into b from public.tk_beat where id = 1;
  select string_agg(d ->> 'name', ', ') into bad from jsonb_array_elements(coalesce(b.doors, '[]'::jsonb)) d
   where not coalesce((d ->> 'ok')::boolean, true);
  return public.yk_admin_push('tk:hisobot', '📊 Turniket — ertalabki hisobot',
    'Turniketdan o''tdi: ' || (j ->> 'otgan') || ' / ' || (j ->> 'turniketli') || ' (bog''langan: ' || (j ->> 'boglangan') || '). '
    || 'Bog''lanmagan shaxslar: ' || (j ->> 'boglanmagan_otgan') || '. 1–2-sinflar (qo''lda): ' || (j ->> 'turniketsiz') || '. '
    || 'Platformada keldi: ' || (j ->> 'keldi') || '.'
    || case when bad is not null then ' ⚠️ Ishlamayotgan eshik: ' || bad || '.' else ' Barcha eshiklar ishlayapti.' end);
end $$;
revoke all on function public.yk_tk_morning() from public, anon, authenticated;

-- Jadval: har 10 daqiqada (07:00–18:59 Toshkent = 02–13 UTC) va 09:30 hisobot (04:30 UTC), dushanba–shanba
do $$ begin perform cron.unschedule('yk-tk-watch'); exception when others then null; end $$;
do $$ begin perform cron.unschedule('yk-tk-morning'); exception when others then null; end $$;
do $$ begin
  perform cron.schedule('yk-tk-watch', '*/10 2-13 * * 1-6', 'select public.yk_tk_watch()');
  perform cron.schedule('yk-tk-morning', '30 4 * * 1-6', 'select public.yk_tk_morning()');
exception when others then raise notice 'pg_cron topilmadi — jadval qo''yilmadi: %', sqlerrm;
end $$;

notify pgrst, 'reload schema';

select jobname as "Jadval", schedule as "vaqt (UTC)" from cron.job where jobname in ('yk-tk-watch', 'yk-tk-morning', 'yk-baho-eslatma');
