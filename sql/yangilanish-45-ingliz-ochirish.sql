-- Yangilanish 45: «8-sinf IELTS · Ingliz tili» va «10-sinf B1 · Ingliz tili» guruhlarini o'chirish.
-- DIQQAT: shu ikki guruhdagi o'quvchi yozuvlari va SHU GURUHDAGI baholar ham o'chadi
-- (o'quvchining asosiy sinfidagi ma'lumotlari va boshqa guruhlari saqlanadi).
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing. Qayta ishga tushirish xavfsiz.

drop table if exists pg_temp.yk_del;
create temp table yk_del as
select c.id, c.name,
       (select count(*) from public.students s where s.class_id = c.id and coalesce(btrim(s.full_name), '') <> '') as oquvchi
  from public.classes c
 where c.subject = 'Ingliz tili' and c.kind is distinct from 'rep'
   and ((coalesce(c.grade, 0) = 8 and upper(btrim(coalesce(c.grp, ''))) = 'IELTS')
     or (coalesce(c.grade, 0) = 10 and upper(btrim(coalesce(c.grp, ''))) = 'B1'));

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

notify pgrst, 'reload schema';

select 'O''chirildi' as holat, d.name as guruh, d.oquvchi as "o'quvchi yozuvlari"
  from yk_del d where not exists (select 1 from public.classes c where c.id = d.id)
union all
select 'O''CHMADI (xabar bering)', d.name, d.oquvchi from yk_del d where exists (select 1 from public.classes c where c.id = d.id)
union all
select 'Qoldi', c.name, (select count(*) from public.students s where s.class_id = c.id and coalesce(btrim(s.full_name), '') <> '')
  from public.classes c where c.subject = 'Ingliz tili' and coalesce(c.grp, '') <> ''
order by 1, 2;
