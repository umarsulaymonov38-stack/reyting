-- MAXFIYLIK TEKSHIRUVI: kim qaysi ma'lumotni ko'ra oladi (faqat o'qiydi, bazada hech narsa o'zgarmaydi).
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing.
-- Uch xil foydalanuvchi nomidan sinaladi:
--   begona    — platformaga kirmagan odam (saytdagi ochiq kalit bilan)
--   ota-ona   — bazadagi tasodifiy ota-ona
--   o'qituvchi — bazadagi tasodifiy o'qituvchi
-- Natijada ❌ chiqsa — o'sha ma'lumot ortiqcha odamga ko'rinyapti.

drop table if exists pg_temp.yk_res, pg_temp.yk_tabs, pg_temp.yk_total, pg_temp.yk_who;
create temp table yk_res (rol text, jadval text, koradi bigint);
grant all on yk_res to anon, authenticated;

create temp table yk_tabs (t text);
insert into yk_tabs values ('students'),('student_private'),('profiles'),('payments'),('daily_scores'),('rep_daily'),
  ('subject_scores'),('feedback'),('teacher_classes'),('turnstile_events'),('tk_config'),('class_codes');
delete from yk_tabs where to_regclass('public.' || t) is null;
grant select on yk_tabs to anon, authenticated;

create temp table yk_total as select t as jadval, 0::bigint as jami from yk_tabs;
do $$ declare r record; n bigint; begin
  for r in select t from yk_tabs loop execute format('select count(*) from public.%I', r.t) into n; update yk_total set jami = n where jadval = r.t; end loop;
end $$;

create temp table yk_who as
select (select id from public.profiles where role = 'parent' order by random() limit 1) as parent,
       (select id from public.profiles where role = 'teacher' order by random() limit 1) as teacher;
grant select on yk_who to anon, authenticated;

-- 1. Begona (kirmagan)
select set_config('request.jwt.claims', '{"role":"anon"}', false), set_config('request.jwt.claim.sub', '', false);
set role anon;
do $$ declare r record; n bigint; begin
  for r in select t from yk_tabs loop
    begin execute format('select count(*) from public.%I', r.t) into n; exception when insufficient_privilege then n := -1; end;
    insert into yk_res values ('1 begona', r.t, n);
  end loop;
end $$;
reset role;

-- 2. Ota-ona
select set_config('request.jwt.claims', json_build_object('sub', parent, 'role', 'authenticated')::text, false),
       set_config('request.jwt.claim.sub', coalesce(parent::text, ''), false) from yk_who;
set role authenticated;
do $$ declare r record; n bigint; begin
  if (select parent from yk_who) is null then return; end if;
  for r in select t from yk_tabs loop
    begin execute format('select count(*) from public.%I', r.t) into n; exception when insufficient_privilege then n := -1; end;
    insert into yk_res values ('2 ota-ona', r.t, n);
  end loop;
end $$;
reset role;

-- 3. O'qituvchi
select set_config('request.jwt.claims', json_build_object('sub', teacher, 'role', 'authenticated')::text, false),
       set_config('request.jwt.claim.sub', coalesce(teacher::text, ''), false) from yk_who;
set role authenticated;
do $$ declare r record; n bigint; begin
  if (select teacher from yk_who) is null then return; end if;
  for r in select t from yk_tabs loop
    begin execute format('select count(*) from public.%I', r.t) into n; exception when insufficient_privilege then n := -1; end;
    insert into yk_res values ('3 o''qituvchi', r.t, n);
  end loop;
end $$;
reset role;

select set_config('request.jwt.claims', '', false), set_config('request.jwt.claim.sub', '', false);

select r.rol, r.jadval,
       case when r.koradi < 0 then 'ruxsat yo''q' else r.koradi || ' / ' || t.jami end as "ko'radi / jami",
       case
         when r.koradi <= 0 then '✅ yopiq'
         when r.rol = '1 begona' then '❌ KIRMAGAN ODAM KO''RA OLADI'
         when r.jadval in ('tk_config') then '❌ maxfiy kalit ochiq'
         when r.rol = '2 ota-ona' and r.jadval in ('students','student_private','payments','daily_scores','rep_daily','subject_scores','profiles','turnstile_events')
              and r.koradi > 10 and r.koradi >= t.jami * 0.5 then '❌ ota-ona boshqalarnikini ham ko''radi'
         when r.rol = '2 ota-ona' and r.jadval in ('teacher_classes','class_codes') and r.koradi > 0 then '⚠️ tekshirish kerak'
         when r.rol = '3 o''qituvchi' and r.jadval in ('student_private','profiles','payments') and r.koradi = t.jami and t.jami > 40 then '⚠️ o''qituvchi butun maktabnikini ko''radi'
         else '✅ cheklangan'
       end as xulosa
  from yk_res r join yk_total t on t.jadval = r.jadval
 order by r.rol, r.jadval;
