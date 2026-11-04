-- Yangilanish 41: yangilanish-40 ni BEKOR QILISH — Ingliz tili guruhlarini oldingi holatiga qaytarish.
-- FAQAT yangilanish-40 ni ishga tushirgan bo'lsangiz kerak. Ishga tushirmagan bo'lsangiz — bu faylni ham ishga tushirmang.
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing. Qayta ishga tushirish xavfsiz.
--  1) O'qituvchilar bo'yicha 8 ta guruh qayta ochiladi (har biri 18 o'quvchilik, bo'sh).
--  2) «7-sinf A1» va «8-9-10-sinf A2» guruhlari — ichida o'quvchi yoki baho bo'lmasa — o'chiriladi.
-- ESLATMA: o'chirilgan guruhlardagi o'quvchi ro'yxatlari va baholarni bu fayl qaytara olmaydi
-- (ular «Zaxira nusxa» faylidan yoki Supabase zaxirasidan tiklanadi).

drop table if exists pg_temp.yk_eng;
create temp table yk_eng (name text, lvl text);
insert into yk_eng values
  ('Firuz Ustoz (A2)', 'A2'), ('Jonibek Ustoz (A1)', 'A1'), ('Jonibek Ustoz (A2)', 'A2'), ('Sevinch Ustoz (B1)', 'B1'),
  ('Sevinch Ustoz (CEFR)', 'CEFR'), ('Mutabar Ustoz (CEFR)', 'CEFR'), ('Timur Ustoz (IELTS 6.0)', 'IELTS 6.0'), ('Firuz Ustoz (IELTS 7.0)', 'IELTS 7.0');

do $$
declare r record; cid bigint; cid_auto boolean; used boolean;
begin
  select column_default is not null or is_identity = 'YES' into cid_auto from information_schema.columns
   where table_schema = 'public' and table_name = 'classes' and column_name = 'id';
  for r in select * from yk_eng loop
    select id into cid from public.classes where lower(name) = lower(r.name) limit 1;
    if cid is null then
      if cid_auto then
        insert into public.classes (name, grade, grp, subject) values (r.name, null, r.lvl, 'Ingliz tili') returning id into cid;
      else
        insert into public.classes (id, name, grade, grp, subject)
        values ((select coalesce(max(id), 0) + 1 from public.classes), r.name, null, r.lvl, 'Ingliz tili') returning id into cid;
      end if;
    end if;
    insert into public.students (class_id, slot, full_name)
    select cid, s, '' from generate_series(1, 18) s where not exists (select 1 from public.students x where x.class_id = cid and x.slot = s);
    insert into public.student_private (student_id, code)
    select x.id, upper(substr(md5(random()::text || x.id::text), 1, 6)) from public.students x
     where x.class_id = cid and not exists (select 1 from public.student_private p where p.student_id = x.id);
    cid := null;
  end loop;

  for r in select c.id, c.name from public.classes c where lower(c.name) in ('7-sinf a1', '8-9-10-sinf a2') loop
    used := exists (select 1 from public.students s where s.class_id = r.id and coalesce(btrim(s.full_name), '') <> '')
         or exists (select 1 from public.daily_scores d join public.students s on s.id = d.student_id where s.class_id = r.id);
    if used then raise notice 'SAQLANDI (ichida o''quvchi bor): %', r.name;
    else
      delete from public.teacher_classes where class_id = r.id;
      delete from public.student_private where student_id in (select id from public.students where class_id = r.id);
      delete from public.students where class_id = r.id;
      delete from public.classes where id = r.id;
    end if;
  end loop;
end $$;

notify pgrst, 'reload schema';

select c.name as "Ingliz tili guruhlari (hozir)", c.grade as sinf,
       (select count(*) from public.students s where s.class_id = c.id and coalesce(btrim(s.full_name), '') <> '') as "o'quvchi"
  from public.classes c where c.subject = 'Ingliz tili' and coalesce(c.grp, '') <> '' order by c.grade nulls last, c.name;
