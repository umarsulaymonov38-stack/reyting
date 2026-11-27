-- Yangilanish 93: Ota-ona parolini unutsa — TIKLASH (Yurt School'dagi kabi).
--   1) Ota-ona kirish oynasida «Parolni unutdingizmi?» → telefon raqamini yozib so'rov yuboradi.
--   2) Admin (yoki «parol» ruxsati bor xodim, yoki farzandining sinf rahbari) «Parol tiklash» bo'limida
--      6 xonali TIKLASH KODINI beradi (24 soat amal qiladi, 5 ta noto'g'ri urinishdan keyin bekor bo'ladi).
--   3) Ota-ona telefon + kod bilan o'zi YANGI parol qo'yadi. Kod faqat shifrlangan holda saqlanadi.
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing (loyiha: YUKSALISH-REYTING). Avval 92 ishga tushgan bo'lsin. Qayta ishga tushirish xavfsiz.

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.parent_pw_reset (
  phone text primary key, user_id uuid not null, code_hash text, expires_at timestamptz, tries int not null default 0,
  issued_by uuid, issued_name text, issued_at timestamptz, requested_at timestamptz, req_n int not null default 0, done_at timestamptz
);
alter table public.parent_pw_reset enable row level security;
revoke all on public.parent_pw_reset from anon, authenticated;

create or replace function public.yk_ph9(p text) returns text language sql immutable as $$
  select case when length(d) >= 9 then right(d, 9) end from (select regexp_replace(coalesce(p, ''), '\D', '', 'g') d) x
$$;

create or replace function public.yk_parent_uid(p_phone text) returns uuid
language sql stable security definer set search_path = public, auth as $$
  select u.id from auth.users u join public.profiles pr on pr.id = u.id and pr.role = 'parent'
   where u.email = 'p' || public.yk_ph9(p_phone) || '@ota.yuksalish.app' limit 1
$$;
revoke all on function public.yk_parent_uid(text) from public, anon, authenticated;

-- Ota-ona: «Parolni unutdim» so'rovi. Javob: ok | none (raqam ro'yxatda yo'q) | noacc (hali kirmagan) | bad
create or replace function public.pw_request(p_phone text) returns text
language plpgsql security definer set search_path = public as $$
declare ph text := public.yk_ph9(p_phone); uid uuid;
begin
  if ph is null then return 'bad'; end if;
  uid := public.yk_parent_uid(ph);
  if uid is null then
    return case when exists (select 1 from public.student_private where public.yk_ph9(parent_phone) = ph) then 'noacc' else 'none' end;
  end if;
  insert into public.parent_pw_reset as r (phone, user_id, requested_at, req_n) values (ph, uid, now(), 1)
  on conflict (phone) do update set user_id = excluded.user_id, requested_at = now(), done_at = null,
    req_n = case when r.requested_at > now() - interval '2 minutes' then r.req_n else least(r.req_n + 1, 99) end;
  return 'ok';
end $$;
revoke all on function public.pw_request(text) from public;
grant execute on function public.pw_request(text) to anon, authenticated;

-- Kod berish huquqi: bosh admin, «parol» ruxsati bor xodim yoki farzandining sinf rahbari
create or replace function public.yk_pw_can(p_phone text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.yk_perm('parol') or exists (
    select 1 from public.student_private sp join public.students s on s.id = sp.student_id
      join public.teacher_classes t on t.class_id = s.class_id and t.user_id = auth.uid() and t.role = 'rahbar'
     where public.yk_ph9(sp.parent_phone) = public.yk_ph9(p_phone))
$$;
revoke all on function public.yk_pw_can(text) from public, anon, authenticated;

create or replace function public.pw_requests()
returns table (phone text, requested_at timestamptz, req_n int, kids text, issued_at timestamptz, issued_name text, active boolean)
language sql stable security definer set search_path = public as $$
  select r.phone, r.requested_at, r.req_n,
         (select string_agg(s.full_name || ' (' || c.name || ')', ', ' order by c.id, s.slot)
            from public.student_private sp join public.students s on s.id = sp.student_id join public.classes c on c.id = s.class_id
           where public.yk_ph9(sp.parent_phone) = r.phone and btrim(s.full_name) <> ''
             and coalesce(c.grp, '') = '' and c.kind is distinct from 'rep'),
         r.issued_at, r.issued_name, (r.code_hash is not null and r.expires_at > now())
    from public.parent_pw_reset r
   where r.requested_at > now() - interval '14 days' and r.done_at is null and public.yk_pw_can(r.phone)
   order by r.requested_at desc
$$;
revoke all on function public.pw_requests() from public, anon;
grant execute on function public.pw_requests() to authenticated;

-- 6 xonali tiklash kodi (24 soat). Kod faqat shu javobda bir marta ko'rinadi.
create or replace function public.pw_issue_code(p_phone text)
returns table (code text, kids text, expires_at timestamptz)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare ph text := public.yk_ph9(p_phone); uid uuid; c text; nm text;
begin
  if ph is null then raise exception 'Telefon raqam noto''g''ri (9 ta raqam)'; end if;
  if not public.yk_pw_can(ph) then raise exception 'Bu ota-onaga kod berishga ruxsatingiz yo''q' using errcode = '42501'; end if;
  uid := public.yk_parent_uid(ph);
  if uid is null then raise exception 'Bu raqam bilan ota-ona hali platformaga kirmagan — unga o''quvchi kodi bilan birinchi marta kirishni ayting'; end if;
  c := lpad(((('x' || encode(extensions.gen_random_bytes(4), 'hex'))::bit(32)::bigint) % 1000000)::text, 6, '0');
  select full_name into nm from public.profiles where id = auth.uid();
  insert into public.parent_pw_reset as r (phone, user_id, code_hash, expires_at, tries, issued_by, issued_name, issued_at, done_at)
  values (ph, uid, extensions.crypt(c, extensions.gen_salt('bf')), now() + interval '24 hours', 0, auth.uid(), nm, now(), now())
  on conflict (phone) do update set user_id = excluded.user_id, code_hash = excluded.code_hash, expires_at = excluded.expires_at,
    tries = 0, issued_by = excluded.issued_by, issued_name = excluded.issued_name, issued_at = now(), done_at = now();
  return query select c,
    (select string_agg(s.full_name, ', ' order by s.class_id, s.slot) from public.student_private sp join public.students s on s.id = sp.student_id
      join public.classes cl on cl.id = s.class_id
     where public.yk_ph9(sp.parent_phone) = ph and btrim(s.full_name) <> '' and coalesce(cl.grp, '') = '' and cl.kind is distinct from 'rep'),
    now() + interval '24 hours';
end $$;
revoke all on function public.pw_issue_code(text) from public, anon;
grant execute on function public.pw_issue_code(text) to authenticated;

-- Ota-ona: telefon + kod + yangi parol. Javob: ok yoki xato matni
create or replace function public.pw_reset(p_phone text, p_code text, p_pw text) returns text
language plpgsql security definer set search_path = public as $$
declare ph text := public.yk_ph9(p_phone); r public.parent_pw_reset;
begin
  if ph is null then return 'Telefon raqam noto''g''ri (9 ta raqam)'; end if;
  if length(coalesce(p_pw, '')) < 6 then return 'Yangi parol kamida 6 belgidan iborat bo''lsin'; end if;
  select * into r from public.parent_pw_reset where phone = ph for update;
  if not found or r.code_hash is null then return 'Bu raqamga tiklash kodi berilmagan. Avval so''rov yuboring va maktabdan kod oling'; end if;
  if r.expires_at < now() then update public.parent_pw_reset set code_hash = null where phone = ph;
    return 'Kod muddati tugagan (24 soat). Maktabdan yangi kod oling'; end if;
  if r.tries >= 5 then update public.parent_pw_reset set code_hash = null where phone = ph;
    return 'Juda ko''p noto''g''ri urinish. Maktabdan yangi kod oling'; end if;
  if extensions.crypt(btrim(coalesce(p_code, '')), r.code_hash) <> r.code_hash then
    update public.parent_pw_reset set tries = tries + 1 where phone = ph;
    return 'Kod noto''g''ri. Yana ' || (4 - r.tries) || ' marta urinish mumkin';
  end if;
  update auth.users set encrypted_password = extensions.crypt(p_pw, extensions.gen_salt('bf')), updated_at = now() where id = r.user_id;
  update public.parent_pw_reset set code_hash = null, tries = 0, done_at = now() where phone = ph;
  -- Ota-ona o'z parolini o'rnatdi: o'quvchi kodi bilan kirish yopiladi
  insert into public.parent_pw_set (user_id, dev) values (r.user_id, 'tiklash') on conflict (user_id) do update set set_at = now();
  delete from public.parent_code_fail where phone = ph;
  return 'ok';
end $$;
revoke all on function public.pw_reset(text, text, text) from public;
grant execute on function public.pw_reset(text, text, text) to anon, authenticated;

notify pgrst, 'reload schema';
select to_regprocedure('public.pw_reset(text,text,text)') is not null as parol_tiklash_tayyor;
