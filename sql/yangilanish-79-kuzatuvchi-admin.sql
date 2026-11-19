-- Yangilanish 79: «Kuzatuvchi admin» — butun platformani KO'RADI, hech narsani O'ZGARTIRA OLMAYDI.
--   * Bosh admin «O'qituvchilar» bo'limida yangi akkaunt ochadi (ism, telefon, parol) va unga
--     «👁 Kuzatuvchi» belgisini qo'yadi. Akkauntga sinf biriktirish shart emas.
--   * Kuzatuvchi ko'radi: bosh sahifa va statistika, barcha sinflar (baholar, reytinglar, infografika),
--     davomat (kelmaganlar, kech kelganlar, ketish), turniket holati, baho qo'yilmaganlar,
--     o'qituvchilar va ularning reytingi, ota-onalar ulanishi, fikr-mulohazalar, to'lovlar va hisobotlar,
--     xarajatlar, taomnoma.
--   * Ko'rmaydi: parollar va kirish kodlari, turniket/SMS/bildirishnoma kalitlari, zaxira nusxa.
--   * O'zgartira olmaydi: baza darajasida yozish taqiqlangan (har bir jadvalga cheklovchi qoida).
--     Belgi qo'yilganda akkaunt sinflardan ajratiladi — u baho qo'ya olmaydi.
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing (loyiha: YUKSALISH-REYTING). Qayta ishga tushirish xavfsiz.

alter table public.profiles add column if not exists obs boolean not null default false;

create or replace function public.yk_obs() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select p.obs from public.profiles p where p.id = auth.uid() and p.role = 'teacher'), false)
$$;
grant execute on function public.yk_obs() to authenticated;

-- Kuzatuvchi ham 2-darajali admin kabi barcha O'QISH huquqlarini oladi (yozish huquqi — yo'q).
create or replace function public.yk_admin2() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select p.admin2 or p.obs from public.profiles p where p.id = auth.uid() and p.role = 'teacher'), false)
$$;
grant execute on function public.yk_admin2() to authenticated;

-- Bosh admin belgilaydi
create or replace function public.set_obs(p_id uuid, p_on boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if public.yk_role() is distinct from 'admin' then raise exception 'Faqat bosh admin' using errcode = '42501'; end if;
  update public.profiles set obs = coalesce(p_on, false) where id = p_id and role = 'teacher';
  if not found then raise exception 'Akkaunt topilmadi'; end if;
  -- Kuzatuvchi faqat ko'radi: sinf biriktirishlari (va ular bilan birga baho qo'yish huquqi) olib tashlanadi
  if coalesce(p_on, false) then delete from public.teacher_classes where user_id = p_id; end if;
end $$;
revoke all on function public.set_obs(uuid, boolean) from public, anon;
grant execute on function public.set_obs(uuid, boolean) to authenticated;

-- Hech kim o'z profilidagi «kuzatuvchi» belgisini o'zi o'zgartira olmasin
create or replace function public.yk_obs_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.obs is distinct from old.obs and public.yk_role() is distinct from 'admin'
     and current_user not in ('postgres', 'supabase_admin', 'service_role') then
    new.obs := old.obs;
  end if;
  return new;
end $$;
drop trigger if exists yk_obs_guard on public.profiles;
create trigger yk_obs_guard before update on public.profiles for each row execute function public.yk_obs_guard();

-- Faqat O'QISH: keyin qo'shilgan jadvallarga ham (maxfiylari bundan mustasno) «select» qoidasi
do $$
declare t text;
begin
  for t in select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'public' and c.relkind = 'r' and c.relrowsecurity
              and c.relname not in ('student_private', 'class_codes', 'tk_config', 'push_secret', 'push_subs', 'push_queue',
                                    'staff_devices', 'parent_code_fail', 'parent_pw_set', 'sms_config', 'sms_settings',
                                    'sms_secret', 'sms_queue', 'parent_checkin', 'tk_alert')
              and c.relname !~ '(secret|token|config)' loop
    execute format('drop policy if exists admin2_read on public.%I', t);
    execute format('create policy admin2_read on public.%I for select to authenticated using (public.yk_admin2())', t);
  end loop;
end $$;

-- Kafolat: kuzatuvchining HAR QANDAY yozish urinishini baza rad etadi (cheklovchi qoidalar)
do $$
declare t text;
begin
  for t in select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'public' and c.relkind = 'r' and c.relrowsecurity loop
    execute format('drop policy if exists obs_no_ins on public.%I', t);
    execute format('drop policy if exists obs_no_upd on public.%I', t);
    execute format('drop policy if exists obs_no_del on public.%I', t);
    execute format('create policy obs_no_ins on public.%I as restrictive for insert to authenticated with check (not public.yk_obs())', t);
    execute format('create policy obs_no_upd on public.%I as restrictive for update to authenticated using (not public.yk_obs())', t);
    execute format('create policy obs_no_del on public.%I as restrictive for delete to authenticated using (not public.yk_obs())', t);
  end loop;
end $$;

notify pgrst, 'reload schema';

-- Tekshiruv: kuzatuvchi va 2-darajali adminlar
select full_name as "Ism", phone as "Telefon",
       case when obs then '👁 Kuzatuvchi' when admin2 then '2-darajali admin' end as "Huquq"
  from public.profiles where role = 'teacher' and (obs or admin2) order by 1;
