-- Yangilanish 38: ota-onaga baho bo'yicha push-bildirishnoma (ovozli):
--   ⚠️ "Past baho"  — 10 ballik mezonda 0–4, 5 ballikda 1–2, tartib-intizom bandi, fan bahosi 2 va past, repetitor topshirig'i 0–2;
--   ⭐ "Yaxshi baho" — 10 ballikda 9–10, 5 ballikda 5 (fan o'qituvchisida — faqat baho 5).
-- Bir kunda bitta o'quvchi bo'yicha bir nechta baho bitta xabarga yig'iladi va 10 daqiqadan keyin yuboriladi
-- (o'qituvchi xatoni tuzatishga ulgursin; tuzatilgan baho xabardan o'chadi).
-- yangilanish-31 (push) dan keyin. Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing. Qayta ishga tushirish xavfsiz.

alter table public.push_config add column if not exists on_baho boolean not null default true;
alter table public.push_queue add column if not exists meta jsonb;
alter table public.push_queue drop constraint if exists push_queue_kind_check;
alter table public.push_queue add constraint push_queue_kind_check check (kind in ('keldi', 'ketdi', 'kelmadi', 'test', 'yomon', 'yaxshi'));
alter table public.push_queue drop constraint if exists push_queue_status_check;
alter table public.push_queue add constraint push_queue_status_check check (status in ('navbat', 'yuborilmoqda', 'yuborildi', 'xato', 'bekor'));

-- Bitta baho bo'yicha qayd: p_label = null — shu baho endi past/yaxshi emas (xabardan o'chadi)
create or replace function public.yk_grade_note(p_sid text, p_kind text, p_key text, p_label text) returns void
language plpgsql security definer set search_path = public as $$
declare t date := (now() at time zone 'Asia/Tashkent')::date; u uuid; r public.push_queue; m jsonb; nm text; n int;
begin
  if not coalesce((select on_baho from public.push_config where id = 1), false) then return; end if;
  select array_to_string((regexp_split_to_array(btrim(s.full_name), '\s+'))[1:2], ' ') into nm from public.students s where s.id::text = p_sid;
  for u in select x.uid from (select sp.claimed_by uid from public.student_private sp where sp.student_id::text = p_sid and sp.claimed_by is not null
                               union select p.id from public.profiles p where p.role = 'parent' and p.student_id::text = p_sid) x
            where exists (select 1 from public.push_subs s where s.user_id = x.uid) loop
    select * into r from public.push_queue q
     where q.user_id = u and q.kind = p_kind and q.day = t and q.status = 'navbat' and q.student_id like p_sid || '#%'
     order by q.id desc limit 1 for update;
    if r.id is not null then
      m := case when p_label is null then coalesce(r.meta, '{}'::jsonb) - p_key else coalesce(r.meta, '{}'::jsonb) || jsonb_build_object(p_key, p_label) end;
      update public.push_queue set meta = m, created_at = now(),
             status = case when m = '{}'::jsonb then 'bekor' else 'navbat' end,
             body = coalesce(left(nm || ': ' || (select string_agg(v, '; ' order by k) from jsonb_each_text(m) e(k, v)), 300), r.body)
       where id = r.id;
    elsif p_label is not null then
      select count(*) + 1 into n from public.push_queue q where q.user_id = u and q.kind = p_kind and q.day = t and q.student_id like p_sid || '#%';
      insert into public.push_queue (user_id, kind, student_id, title, body, day, meta)
      values (u, p_kind, p_sid || '#' || n,
              case p_kind when 'yomon' then '⚠️ Past baho' else '⭐ Yaxshi baho' end,
              left(nm || ': ' || p_label, 300), t, jsonb_build_object(p_key, p_label))
      on conflict (user_id, kind, student_id, day) do nothing;
    end if;
    r := null;
  end loop;
end $$;
revoke all on function public.yk_grade_note(text, text, text, text) from public, anon, authenticated;

-- Bitta ustun bo'yicha: past bo'lsa — "yomon" ga qo'shiladi, yaxshi bo'lsa — "yaxshi" ga, aks holda ikkalasidan o'chadi
create or replace function public.yk_grade_mark(p_sid text, p_key text, p_val numeric, p_bad numeric, p_good numeric, p_text text) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public.yk_grade_note(p_sid, 'yomon', p_key, case when p_val is not null and p_val <= p_bad then p_text end);
  perform public.yk_grade_note(p_sid, 'yaxshi', p_key, case when p_val is not null and p_good is not null and p_val >= p_good then p_text end);
end $$;
revoke all on function public.yk_grade_mark(text, text, numeric, numeric, numeric, text) from public, anon, authenticated;

-- Kunlik baholar (sinf rahbari / guruh o'qituvchisi)
create or replace function public.yk_push_daily() returns trigger
language plpgsql security definer set search_path = public as $$
declare g boolean; sid text := new.student_id::text; c record;
begin
  if new.day <> (now() at time zone 'Asia/Tashkent')::date then return new; end if;
  select coalesce(cl.grp, '') <> '' into g from public.students s join public.classes cl on cl.id = s.class_id where s.id = new.student_id;
  g := coalesce(g, false);
  for c in select * from (values ('book', 'Kitob o''qish', 10), ('sport', 'Sport', 10), ('behavior', case when g then 'Tartib-intizom' else 'Kunlik odoblar' end, case when g then 5 else 10 end),
                                 ('kindness', 'Ota-onaga yaxshilik', 10), ('hw', 'Uyga vazifa', 5), ('activity', 'Sinfdagi faollik', 5)) v(k, t, m) loop
    continue when (case when g then c.k not in ('hw', 'activity', 'behavior') else c.k not in ('book', 'sport', 'behavior', 'kindness') end);
    if tg_op = 'INSERT' or (to_jsonb(new) ->> c.k) is distinct from (to_jsonb(old) ->> c.k) then
      perform public.yk_grade_mark(sid, 'd:' || c.k, (to_jsonb(new) ->> c.k)::numeric,
                                   case when c.m = 5 then 2 else 4 end, case when c.m = 5 then 5 else 9 end,
                                   c.t || ' ' || (to_jsonb(new) ->> c.k) || '/' || c.m);
    end if;
  end loop;
  if g and (tg_op = 'INSERT' or (to_jsonb(new) ->> 'beh_band') is distinct from (to_jsonb(old) ->> 'beh_band')) then
    perform public.yk_grade_note(sid, 'yomon', 'd:band', case (to_jsonb(new) ->> 'beh_band')
      when '1' then 'tartib qoidaga amal qilmadi' when '2' then 'atrofdagilar va ustozlarni hurmat qilmadi'
      when '3' then 'o''z joyini toza saqlamadi' end);
  end if;
  return new;
exception when others then
  raise warning 'push baho: %', sqlerrm;  -- bildirishnomadagi xato baho saqlanishiga to'sqinlik qilmasin
  return new;
end $$;
drop trigger if exists yk_push_daily on public.daily_scores;
create trigger yk_push_daily after insert or update on public.daily_scores for each row execute function public.yk_push_daily();

-- Fan o'qituvchisi baholari
create or replace function public.yk_push_subject() returns trigger
language plpgsql security definer set search_path = public as $$
declare sid text := new.student_id::text; s text := coalesce(nullif(new.subject, ''), 'Fan');
begin
  if new.day <> (now() at time zone 'Asia/Tashkent')::date then return new; end if;
  if tg_op = 'INSERT' or new.grade is distinct from old.grade then
    perform public.yk_grade_mark(sid, 'f:' || s || ':g', new.grade, 2, 5, s || ' — baho ' || new.grade);
  end if;
  if tg_op = 'INSERT' or new.hw is distinct from old.hw then
    perform public.yk_grade_mark(sid, 'f:' || s || ':h', new.hw, 2, null, s || ' — uyga vazifa ' || new.hw || '/5');
  end if;
  return new;
exception when others then
  raise warning 'push fan: %', sqlerrm;
  return new;
end $$;
drop trigger if exists yk_push_subject on public.subject_scores;
create trigger yk_push_subject after insert or update on public.subject_scores for each row execute function public.yk_push_subject();

-- Repetitor: topshiriqlarni bajarish (0–5)
create or replace function public.yk_push_rep() returns trigger
language plpgsql security definer set search_path = public as $$
declare v text := to_jsonb(new) ->> 'task';
begin
  if new.day <> (now() at time zone 'Asia/Tashkent')::date then return new; end if;
  if tg_op = 'INSERT' or v is distinct from (to_jsonb(old) ->> 'task') then
    perform public.yk_grade_mark(new.student_id::text, 'r:task', v::numeric, 2, 5, 'Repetitor topshirig''i ' || v || '/5');
  end if;
  return new;
exception when others then
  raise warning 'push rep: %', sqlerrm;
  return new;
end $$;
drop trigger if exists yk_push_rep on public.rep_daily;
create trigger yk_push_rep after insert or update on public.rep_daily for each row execute function public.yk_push_rep();

-- Navbat: baho xabarlari 10 daqiqa kutib yuboriladi; kechagi yuborilmaganlari eskiradi
create or replace function public.push_claim(p_limit int default 200) returns jsonb
language plpgsql security definer set search_path = public as $$
declare t date := (now() at time zone 'Asia/Tashkent')::date; r jsonb;
begin
  update public.push_queue set status = 'xato', error = 'eskirgan'
   where status in ('navbat', 'yuborilmoqda') and kind <> 'test' and day < t;
  with q as (
    update public.push_queue q set status = 'yuborilmoqda', tries = q.tries + 1, claimed_at = now()
     where q.id in (select x.id from public.push_queue x
                     where (x.status = 'navbat' or (x.status = 'yuborilmoqda' and x.claimed_at < now() - interval '10 minutes'))
                       and x.tries < 3
                       and (x.kind not in ('yomon', 'yaxshi') or x.created_at < now() - interval '10 minutes')
                     order by x.id limit p_limit for update skip locked)
    returning q.*)
  select coalesce(jsonb_agg(jsonb_build_object('id', q.id, 'title', q.title, 'body', q.body, 'tag', q.kind || '-' || coalesce(q.student_id, ''),
           'subs', (select coalesce(jsonb_agg(jsonb_build_object('endpoint', s.endpoint, 'p256dh', s.p256dh, 'auth', s.auth)), '[]'::jsonb)
                      from public.push_subs s where s.user_id = q.user_id))), '[]'::jsonb)
    into r from q;
  return r;
end $$;
revoke all on function public.push_claim(int) from public, anon, authenticated;
grant execute on function public.push_claim(int) to service_role;

-- Sinov xabari: endi baholar haqida ham aytadi
create or replace function public.push_test() returns void
language sql security definer set search_path = public as $$
  insert into public.push_queue (user_id, kind, student_id, title, body)
  values (auth.uid(), 'test', gen_random_uuid()::text, '🔔 Samarqand Yuksalish',
          'Bildirishnomalar ishlayapti! Farzandingiz maktabga kelganda, ketganda, past yoki yaxshi baho olganda xabar olasiz.')
$$;
revoke all on function public.push_test() from public, anon;
grant execute on function public.push_test() to authenticated;

notify pgrst, 'reload schema';
