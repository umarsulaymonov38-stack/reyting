-- Yangilanish 92: XODIMLAR — Buxgalter, Kuzatuvchi va Yordamchi (2-darajali) adminlar profilini ko'rish/o'zgartirish
--   va ularga QO'SHIMCHA RUXSATLAR berish (Yurt School'dagi kabi). Ruxsatlar baza darajasida tekshiriladi.
--     parol   — ota-onalar parolini tiklash (kod berish)
--     telefon — o'quvchilar ismi va ota-ona telefonlari
--     baho    — baholar va davomatni tahrirlash
--     tolov   — to'lov qabul qilish va xarajatlar
--     taom    — taomnoma kiritish
--     fikr    — fikr-mulohazalarni ko'rish
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing (loyiha: YUKSALISH-REYTING). Avval 79 va 57 ishga tushgan bo'lsin. Qayta ishga tushirish xavfsiz.

alter table public.profiles add column if not exists perms text[] not null default '{}';

-- Hech kim o'z ruxsatlarini o'zi o'zgartira olmasin
create or replace function public.yk_perms_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if current_user in ('postgres', 'supabase_admin', 'service_role') or public.yk_role() = 'admin' then return new; end if;
  new.perms := old.perms;
  return new;
end $$;
drop trigger if exists yk_perms_guard on public.profiles;
create trigger yk_perms_guard before update on public.profiles for each row execute function public.yk_perms_guard();

-- Ruxsat bormi? Bosh admin — hammasiga; kuzatuvchi / yordamchi admin — berilganlariga
create or replace function public.yk_perm(p text) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select pr.role = 'admin' or (pr.role = 'teacher' and (pr.obs or pr.admin2) and p = any(pr.perms))
                     from public.profiles pr where pr.id = auth.uid()), false)
$$;
revoke all on function public.yk_perm(text) from public, anon;
grant execute on function public.yk_perm(text) to authenticated;

-- «To'lov» ruxsati berilgan xodim buxgalter kabi to'lovlarni yuritadi
create or replace function public.yk_bux() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select p.bux or ((p.obs or p.admin2) and 'tolov' = any(p.perms))
                     from public.profiles p where p.id = auth.uid() and p.role = 'teacher'), false)
$$;
grant execute on function public.yk_bux() to authenticated;

-- Jadval darajasidagi ruxsatlar (mavjud qoidalarga QO'SHIMCHA)
do $$
declare r record;
begin
  for r in select * from (values
      ('menu', 'taom', 'all'), ('feedback', 'fikr', 'select'),
      ('students', 'telefon', 'update'), ('student_private', 'telefon', 'select'), ('student_private', 'telefon', 'update'),
      ('daily_scores', 'baho', 'all'), ('rep_daily', 'baho', 'all'), ('subject_scores', 'baho', 'all'), ('score_changes', 'baho', 'insert')
    ) v(t, p, op)
  loop
    if to_regclass('public.' || r.t) is null then continue; end if;
    execute format('drop policy if exists %I on public.%I', 'perm_' || r.p || '_' || r.op, r.t);
    if r.op = 'select' then
      execute format('create policy %I on public.%I for select to authenticated using (public.yk_perm(%L))', 'perm_' || r.p || '_' || r.op, r.t, r.p);
    elsif r.op = 'insert' then
      execute format('create policy %I on public.%I for insert to authenticated with check (public.yk_perm(%L))', 'perm_' || r.p || '_' || r.op, r.t, r.p);
    elsif r.op = 'update' then
      execute format('create policy %I on public.%I for update to authenticated using (public.yk_perm(%L)) with check (public.yk_perm(%L))', 'perm_' || r.p || '_' || r.op, r.t, r.p, r.p);
    else
      execute format('create policy %I on public.%I for all to authenticated using (public.yk_perm(%L)) with check (public.yk_perm(%L))', 'perm_' || r.p || '_' || r.op, r.t, r.p, r.p);
    end if;
  end loop;
end $$;

-- Kuzatuvchi: hech narsani o'zgartira olmaydi — faqat bosh admin bergan ruxsat doirasida
create or replace function public.yk_obs_ok(t text) returns boolean
language sql stable security definer set search_path = public as $$
  select case
    when t = 'menu' then public.yk_perm('taom')
    when t = 'feedback' then public.yk_perm('fikr')
    when t in ('students', 'student_private') then public.yk_perm('telefon')
    when t in ('daily_scores', 'subject_scores', 'rep_daily', 'score_changes') then public.yk_perm('baho')
    when t ~ '^(payments|expenses|pay_)' then public.yk_perm('tolov')
    else false end
$$;
grant execute on function public.yk_obs_ok(text) to authenticated;

do $$
declare t text;
begin
  for t in select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'public' and c.relkind = 'r' and c.relrowsecurity and c.relname <> 'push_subs' loop
    execute format('drop policy if exists obs_no_ins on public.%I', t);
    execute format('drop policy if exists obs_no_upd on public.%I', t);
    execute format('drop policy if exists obs_no_del on public.%I', t);
    execute format('create policy obs_no_ins on public.%I as restrictive for insert to authenticated with check (not public.yk_obs() or public.yk_obs_ok(%L))', t, t);
    execute format('create policy obs_no_upd on public.%I as restrictive for update to authenticated using (not public.yk_obs() or public.yk_obs_ok(%L))', t, t);
    execute format('create policy obs_no_del on public.%I as restrictive for delete to authenticated using (not public.yk_obs() or public.yk_obs_ok(%L))', t, t);
  end loop;
end $$;

-- Bosh admin: xodimlar ro'yxati (turi, ruxsatlari, oxirgi kirishi)
create or replace function public.staff_list()
returns table (id uuid, full_name text, phone text, kind text, perms text[], last_sign_in timestamptz,
               created_at timestamptz, classes int)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if public.yk_role() is distinct from 'admin' then raise exception 'Faqat bosh admin' using errcode = '42501'; end if;
  return query
  select p.id, p.full_name::text, p.phone::text,
         case when p.bux then 'bux' when p.obs then 'obs' when p.admin2 then 'admin2' else '' end,
         coalesce(p.perms, '{}'), u.last_sign_in_at, u.created_at,
         (select count(*) from public.teacher_classes t where t.user_id = p.id)::int
    from public.profiles p left join auth.users u on u.id = p.id
   where p.role = 'teacher'
   order by (p.bux or p.admin2 or p.obs) desc, p.full_name;
end $$;
revoke all on function public.staff_list() from public, anon;
grant execute on function public.staff_list() to authenticated;

-- Turini va ruxsatlarini belgilash. p_kind: '' (oddiy o'qituvchi), 'bux', 'obs', 'admin2'
create or replace function public.set_staff(p_id uuid, p_kind text, p_perms text[]) returns void
language plpgsql security definer set search_path = public as $$
declare k text := coalesce(p_kind, ''); ps text[];
begin
  if public.yk_role() is distinct from 'admin' then raise exception 'Faqat bosh admin' using errcode = '42501'; end if;
  if k not in ('', 'bux', 'obs', 'admin2') then raise exception 'Noma''lum xodim turi: %', k; end if;
  select coalesce(array_agg(distinct x order by x), '{}') into ps from unnest(coalesce(p_perms, '{}')) x
   where x in ('parol', 'telefon', 'baho', 'tolov', 'taom', 'fikr');
  if k in ('', 'bux') then ps := '{}'; end if;
  update public.profiles set bux = (k = 'bux'), obs = (k = 'obs'), admin2 = (k = 'admin2'), perms = ps
   where id = p_id and role = 'teacher';
  if not found then raise exception 'Akkaunt topilmadi'; end if;
  -- Kuzatuvchi faqat ko'radi: sinf biriktirishlari olib tashlanadi (yordamchi admin o'z sinflarida ishlayveradi)
  if k = 'obs' then delete from public.teacher_classes where user_id = p_id; end if;
end $$;
revoke all on function public.set_staff(uuid, text, text[]) from public, anon;
grant execute on function public.set_staff(uuid, text, text[]) to authenticated;

notify pgrst, 'reload schema';
select (select count(*) from public.profiles where role = 'teacher' and (bux or obs or admin2)) as xodimlar,
       to_regprocedure('public.set_staff(uuid,text,text[])') is not null as ruxsatlar_tayyor;
