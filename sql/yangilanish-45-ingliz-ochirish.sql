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

alter table yk_del add column if not exists xato text;

-- Guruhga yoki uning o'quvchilariga bog'langan barcha jadvallar (kodlar, rasmlar, baholar, navbatlar...) avtomatik topiladi
do $$
declare r record; f record; sids uuid[];
begin
  for r in select * from yk_del loop
    begin
      select array_agg(id) into sids from public.students where class_id = r.id;
      update public.profiles p
         set student_id = (select sp2.student_id from public.student_private sp2 join public.students s2 on s2.id = sp2.student_id
                            where sp2.claimed_by = p.id and s2.class_id <> r.id limit 1)
       where p.student_id = any(coalesce(sids, '{}'));
      if to_regclass('public.push_queue') is not null then
        delete from public.push_queue where split_part(student_id, '#', 1) = any(coalesce(sids, '{}')::text[]);
      end if;
      for f in select cl.relname as tbl, a.attname as col, ref.relname as reft
                 from pg_constraint c
                 join pg_class cl on cl.oid = c.conrelid join pg_namespace n on n.oid = cl.relnamespace
                 join pg_class ref on ref.oid = c.confrelid
                 join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
                where c.contype = 'f' and n.nspname = 'public' and ref.relname in ('students', 'classes')
                  and cl.relname not in ('students', 'classes') loop
        if f.tbl = 'profiles' then
          execute format('update public.profiles set %I = null where %I::text = any($1)', f.col, f.col)
            using case when f.reft = 'students' then sids::text[] else array[r.id::text] end;
        elsif f.reft = 'students' then
          execute format('delete from public.%I where %I::text = any($1)', f.tbl, f.col) using coalesce(sids, '{}')::text[];
        else
          execute format('delete from public.%I where %I::text = $1', f.tbl, f.col) using r.id::text;
        end if;
      end loop;
      -- bog'lanishi (FK) yozilmagan, lekin o'quvchiga tegishli jadvallar
      if to_regclass('public.daily_scores') is not null then delete from public.daily_scores where student_id = any(coalesce(sids, '{}')); end if;
      if to_regclass('public.subject_scores') is not null then delete from public.subject_scores where student_id = any(coalesce(sids, '{}')); end if;
      if to_regclass('public.payments') is not null then delete from public.payments where student_id = any(coalesce(sids, '{}')); end if;
      delete from public.teacher_classes where class_id = r.id;
      delete from public.student_private where student_id = any(coalesce(sids, '{}'));
      delete from public.students where class_id = r.id;
      delete from public.classes where id = r.id;
    exception when others then
      update yk_del set xato = sqlerrm where id = r.id;
    end;
  end loop;
end $$;

notify pgrst, 'reload schema';

select 'O''chirildi' as holat, d.name as guruh, d.oquvchi as "o'quvchi yozuvlari"
  from yk_del d where not exists (select 1 from public.classes c where c.id = d.id)
union all
select 'O''CHMADI: ' || coalesce(d.xato, '?'), d.name, d.oquvchi from yk_del d where exists (select 1 from public.classes c where c.id = d.id)
union all
select 'Qoldi', c.name, (select count(*) from public.students s where s.class_id = c.id and coalesce(btrim(s.full_name), '') <> '')
  from public.classes c where c.subject = 'Ingliz tili' and coalesce(c.grp, '') <> ''
order by 1, 2;
