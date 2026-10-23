-- TEKSHIRUV: platforma bazasining to'liq holati (faqat o'qiydi, hech narsani o'zgartirmaydi).
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing. Natijada ❌ va ⚠️ qatorlarga e'tibor bering.
-- Istalgancha ishga tushirish mumkin (masalan, har hafta).

with
need_tables(t) as (values
  ('classes'),('students'),('student_private'),('profiles'),('teacher_classes'),('daily_scores'),('rep_daily'),
  ('payments'),('feedback'),('menu'),('class_codes'),('class_images'),('subject_scores'),('tk_config'),('turnstile_events')),
need_funcs(f, fayl) as (values
  ('my_kids','asosiy'),('phone_status','asosiy'),('register_parent','asosiy'),('switch_kid','asosiy'),
  ('class_ranking','asosiy'),('my_task_rank','asosiy'),('rep_group_ranking','asosiy'),('rep_my_rank','asosiy'),
  ('yk_role','yangilanish-2'),('teacher_rating','yangilanish-2'),('tk_push','yangilanish-7'),('tk_map','yangilanish-9'),
  ('parent_overview','yangilanish-8'),('add_student','yangilanish-10'),('set_student_name','yangilanish-10'),
  ('yk_can_class','yangilanish-13'),('set_parent_phone','yangilanish-13'),('my_month_stats','yangilanish-12'),
  ('parent_subjects','yangilanish-16'),('set_teacher_name','yangilanish-17'),('admin_set_password','yangilanish-18'),
  ('class_month_totals','yangilanish-19'),('my_month_totals','yangilanish-19')),
need_cols(t, c, fayl) as (values
  ('daily_scores','excused','yangilanish-6'),('rep_daily','excused','yangilanish-6'),('daily_scores','arrived_at','yangilanish-5'),
  ('students','ext_id','yangilanish-5'),('teacher_classes','role','yangilanish-2'),('teacher_classes','subject','yangilanish-16'),
  ('feedback','student_id','yangilanish-3')),
rep as (
  -- 1. Jadvallar
  select 1 as n, 'Jadval' as tur, t as nomi,
         case when to_regclass('public.' || t) is null then '❌ YO''Q' else '✅' end as holat,
         case when to_regclass('public.' || t) is null then 'tegishli yangilanish SQL ishga tushirilmagan' else '' end as izoh
    from need_tables
  union all
  -- 2. Funksiyalar
  select 2, 'Funksiya', f,
         case when exists (select 1 from pg_proc p join pg_namespace s on s.oid = p.pronamespace where s.nspname = 'public' and p.proname = f) then '✅' else '❌ YO''Q' end,
         case when exists (select 1 from pg_proc p join pg_namespace s on s.oid = p.pronamespace where s.nspname = 'public' and p.proname = f) then '' when fayl = 'asosiy' then 'platformaning asosiy funksiyasi yo''q — menga xabar bering' else fayl || '.sql ni ishga tushiring' end
    from need_funcs
  union all
  -- 3. Ustunlar
  select 3, 'Ustun', t || '.' || c,
         case when exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = t and column_name = c) then '✅' else '❌ YO''Q' end,
         case when exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = t and column_name = c) then '' else fayl || '.sql ni ishga tushiring' end
    from need_cols
  union all
  -- 4. Xavfsizlik: himoyasiz (RLS o'chiq) jadvallar
  select 4, 'Xavfsizlik', c.relname,
         case when c.relrowsecurity then '✅ himoyalangan' else '❌ RLS O''CHIQ' end,
         case when c.relrowsecurity then '' else 'jadvalni API orqali hamma o''qiy oladi — bu haqda xabar bering' end
    from pg_class c join pg_namespace s on s.oid = c.relnamespace
   where s.nspname = 'public' and c.relkind = 'r'
  union all
  -- 5. Hajm (bepul tarifda 500 MB)
  select 5, 'Hajm', 'Butun baza', 
         case when pg_database_size(current_database()) > 400 * 1024 * 1024 then '⚠️ ' else '✅ ' end || pg_size_pretty(pg_database_size(current_database())),
         'bepul tarifda chegara 500 MB'
  union all
  select * from (
    select 6, 'Hajm', c.relname, pg_size_pretty(pg_total_relation_size(c.oid)),
           coalesce((select n_live_tup::text from pg_stat_user_tables st where st.relid = c.oid), '?') || ' qator'
      from pg_class c join pg_namespace s on s.oid = c.relnamespace
     where s.nspname = 'public' and c.relkind = 'r'
     order by pg_total_relation_size(c.oid) desc limit 8) x
  union all
  -- 6. Foydalanuvchilar
  select 7, 'Foydalanuvchilar', coalesce(role, '?'), count(*)::text || ' ta', ''
    from public.profiles group by role
  union all
  select 8, 'Foydalanuvchilar', 'Profilsiz akkauntlar',
         case when count(*) = 0 then '✅ 0' else '⚠️ ' || count(*) end,
         case when count(*) = 0 then '' else 'kirganda xato beradi: akkaunt bor, lekin profil yo''q' end
    from auth.users u where not exists (select 1 from public.profiles p where p.id = u.id)
  union all
  -- 7. Tartib: sinf rahbari yo'q sinflar, sinfsiz o'qituvchilar
  select 9, 'Tartib', 'Sinf rahbari yo''q sinflar',
         case when count(*) = 0 then '✅ 0' else '⚠️ ' || count(*) end,
         coalesce(left(string_agg(c.name, ', ' order by c.name), 300), '')
    from public.classes c
   where not exists (select 1 from public.teacher_classes t where t.class_id = c.id and t.role = 'rahbar')
  union all
  select 10, 'Tartib', 'Sinf biriktirilmagan o''qituvchilar',
         case when count(*) = 0 then '✅ 0' else '⚠️ ' || count(*) end,
         coalesce(left(string_agg(p.full_name, ', ' order by p.full_name), 300), '')
    from public.profiles p
   where p.role = 'teacher' and not exists (select 1 from public.teacher_classes t where t.user_id = p.id)
  union all
  select 11, 'Tartib', 'Ota-ona telefoni kiritilgan o''quvchilar',
         count(*) filter (where coalesce(sp.parent_phone, '') <> '')::text || ' / ' || count(*)::text,
         'ota-onasi ulangan: ' || count(*) filter (where sp.claimed_by is not null)
    from public.students s left join public.student_private sp on sp.student_id = s.id
   where coalesce(btrim(s.full_name), '') <> ''
)
select tur, nomi, holat, izoh from rep order by n, holat desc, nomi;
