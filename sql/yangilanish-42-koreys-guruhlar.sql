-- Yangilanish 42: 6-guruh — Koreys tili guruhlari qayta tuziladi.
-- HOZIRGI barcha Koreys tili guruhlari (masalan «5-6-sinf Koreys tili 1-guruh / 2-guruh») O'CHIRILADI, o'rniga 4 ta guruh ochiladi:
--   «3-sinf Koreys tili», «4-sinf Koreys tili», «5-6-sinflar Koreys tili», «7-sinf Koreys tili» (har biri 20 o'quvchilik).
-- Arab tili guruhlari va boshqa hamma narsa QOLADI.
-- DIQQAT: o'chiriladigan guruhlardagi o'quvchi ro'yxatlari va SHU GURUHDAGI baholar ham o'chadi
-- (o'quvchining asosiy sinfidagi ma'lumotlari saqlanadi). Kerak bo'lsa, avval «Zaxira nusxa»ni yuklab oling.
-- O'qituvchilarni yangi guruhlarga admin «O'qituvchilar» bo'limida biriktiradi.
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing. Qayta ishga tushirish xavfsiz (yangi guruhlar qayta o'chirilmaydi).

drop table if exists pg_temp.yk_new;
create temp table yk_new (name text, grade int);
insert into yk_new values ('3-sinf Koreys tili', 3), ('4-sinf Koreys tili', 4), ('5-6-sinflar Koreys tili', 5), ('7-sinf Koreys tili', 7);

drop table if exists pg_temp.yk_del;
create temp table yk_del as
select c.id, c.name,
       (select count(*) from public.students s where s.class_id = c.id and coalesce(btrim(s.full_name), '') <> '') as oquvchi
  from public.classes c
 where coalesce(c.subject, '') ~* '^koreys' and c.kind is distinct from 'rep'
   and lower(c.name) not in (select lower(name) from yk_new);

do $$
declare r record;
begin
  for r in select * from yk_del loop
    begin
      update public.profiles p
         set student_id = (select sp2.student_id from public.student_private sp2 join public.students s2 on s2.id = sp2.student_id
                            where sp2.claimed_by = p.id and s2.class_id <> r.id limit 1)
       where p.student_id in (select id from public.students where class_id = r.id);
      if to_regclass('public.daily_scores') is not null then
        delete from public.daily_scores where student_id in (select id from public.students where class_id = r.id);
      end if;
      if to_regclass('public.subject_scores') is not null then
        delete from public.subject_scores where student_id in (select id from public.students where class_id = r.id);
      end if;
      if to_regclass('public.payments') is not null then
        delete from public.payments where student_id in (select id from public.students where class_id = r.id);
      end if;
      if to_regclass('public.push_queue') is not null then
        delete from public.push_queue where split_part(student_id, '#', 1) in (select id::text from public.students where class_id = r.id);
      end if;
      delete from public.teacher_classes where class_id = r.id;
      delete from public.student_private where student_id in (select id from public.students where class_id = r.id);
      delete from public.students where class_id = r.id;
      delete from public.classes where id = r.id;
    exception when others then
      raise notice 'O''chirilmadi: % — %', r.name, sqlerrm;
    end;
  end loop;
end $$;

do $$
declare r record; cid bigint; cid_auto boolean;
begin
  select column_default is not null or is_identity = 'YES' into cid_auto from information_schema.columns
   where table_schema = 'public' and table_name = 'classes' and column_name = 'id';
  for r in select * from yk_new loop
    select id into cid from public.classes where lower(name) = lower(r.name) limit 1;
    if cid is null then
      if cid_auto then
        insert into public.classes (name, grade, grp, subject) values (r.name, r.grade, 'Koreys', 'Koreys tili') returning id into cid;
      else
        insert into public.classes (id, name, grade, grp, subject)
        values ((select coalesce(max(id), 0) + 1 from public.classes), r.name, r.grade, 'Koreys', 'Koreys tili') returning id into cid;
      end if;
    end if;
    insert into public.students (class_id, slot, full_name)
    select cid, s, '' from generate_series(1, 20) s where not exists (select 1 from public.students x where x.class_id = cid and x.slot = s);
    insert into public.student_private (student_id, code)
    select x.id, upper(substr(md5(random()::text || x.id::text), 1, 6)) from public.students x
     where x.class_id = cid and not exists (select 1 from public.student_private p where p.student_id = x.id);
    cid := null;
  end loop;
end $$;

notify pgrst, 'reload schema';

select 'O''chirildi' as holat, d.name as guruh, d.oquvchi as "o'quvchi yozuvlari"
  from yk_del d where not exists (select 1 from public.classes c where c.id = d.id)
union all
select 'O''CHMADI (xabar bering)', d.name, d.oquvchi from yk_del d where exists (select 1 from public.classes c where c.id = d.id)
union all
select 'Hozir bor', c.name, (select count(*) from public.students s where s.class_id = c.id and coalesce(btrim(s.full_name), '') <> '')
  from public.classes c where coalesce(c.subject, '') ~* '^(koreys|arab)'
order by 1, 2;
