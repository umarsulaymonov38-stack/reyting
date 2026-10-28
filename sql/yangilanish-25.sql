-- Yangilanish 25: 3-guruh (Matematika) — 9- va 10-sinf Matematika Alfa va Betta guruhlari (har biri 18 o'quvchilik).
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing. Qayta ishga tushirish xavfsiz (bor guruh qayta yaratilmaydi).

do $$
declare g int; lv text; nm text; cid bigint; cid_auto boolean;
begin
  select column_default is not null or is_identity = 'YES' into cid_auto from information_schema.columns
   where table_schema = 'public' and table_name = 'classes' and column_name = 'id';
  foreach g in array array[9, 10] loop
    foreach lv in array array['Alfa', 'Betta'] loop
      nm := g || '-sinf Matematika ' || lv;
      select id into cid from public.classes
       where (lower(name) = lower(nm) or (grade = g and lower(grp) = lower(lv) and subject = 'Matematika'))
         and kind is distinct from 'rep' limit 1;
      if cid is null then
        if cid_auto then
          insert into public.classes (name, grade, grp, subject) values (nm, g, lv, 'Matematika') returning id into cid;
        else
          insert into public.classes (id, name, grade, grp, subject)
          values ((select coalesce(max(id), 0) + 1 from public.classes), nm, g, lv, 'Matematika') returning id into cid;
        end if;
      end if;
      insert into public.students (class_id, slot, full_name)
      select cid, s, '' from generate_series(1, 18) s
       where not exists (select 1 from public.students x where x.class_id = cid and x.slot = s);
      insert into public.student_private (student_id, code)
      select x.id, upper(substr(md5(random()::text || x.id::text), 1, 6)) from public.students x
       where x.class_id = cid and not exists (select 1 from public.student_private p where p.student_id = x.id);
    end loop;
  end loop;
end $$;

notify pgrst, 'reload schema';

select name as guruh, grade as sinf, grp, (select count(*) from public.students s where s.class_id = c.id) as joylar
  from public.classes c where subject = 'Matematika' and grade in (9, 10) order by grade, grp;
