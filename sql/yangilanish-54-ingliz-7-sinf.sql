-- Yangilanish 54: 4-guruh (Ingliz tili)
--  1) «5-sinf Ingliz tili Gamma» → «7-sinf A2 guruh» (o'quvchilari, baholari va o'qituvchisi o'zgarmaydi).
--  2) Yangi guruh: «7-sinf Pre Intermediate» (18 o'quvchilik).
--  3) Yangi, bo'sh «5-sinf Ingliz tili Gamma» guruhi (18 o'quvchilik).
-- Yangi guruhlarga o'qituvchini admin «O'qituvchilar» bo'limida biriktiradi.
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing. Qayta ishga tushirish xavfsiz.

do $$
declare cid bigint; cid_auto boolean; g record;
begin
  select column_default is not null or is_identity = 'YES' into cid_auto from information_schema.columns
   where table_schema = 'public' and table_name = 'classes' and column_name = 'id';

  -- 1. Eski Gamma → 7-sinf A2 guruh (faqat birinchi marta: «7-sinf A2 guruh» hali bo'lmasa)
  if not exists (select 1 from public.classes where lower(name) = lower('7-sinf A2 guruh')) then
    update public.classes set name = '7-sinf A2 guruh', grade = 7, grp = 'A2'
     where id = (select id from public.classes
                  where subject = 'Ingliz tili' and coalesce(grade, 0) = 5 and upper(coalesce(grp, '')) = 'GAMMA'
                  order by id limit 1);
  end if;

  -- 2–3. Yangi guruhlar
  for g in select * from (values ('7-sinf Pre Intermediate', 7, 'Pre Intermediate'),
                                 ('5-sinf Ingliz tili Gamma', 5, 'Gamma')) v(nm, gr, gp) loop
    select id into cid from public.classes
     where subject = 'Ingliz tili' and coalesce(grade, 0) = g.gr and upper(coalesce(grp, '')) = upper(g.gp) limit 1;
    if cid is null then
      if cid_auto then
        insert into public.classes (name, grade, grp, subject) values (g.nm, g.gr, g.gp, 'Ingliz tili') returning id into cid;
      else
        insert into public.classes (id, name, grade, grp, subject)
        values ((select coalesce(max(id), 0) + 1 from public.classes), g.nm, g.gr, g.gp, 'Ingliz tili') returning id into cid;
      end if;
    end if;
    insert into public.students (class_id, slot, full_name)
    select cid, s, '' from generate_series(1, 18) s where not exists (select 1 from public.students x where x.class_id = cid and x.slot = s);
    insert into public.student_private (student_id, code)
    select x.id, upper(substr(md5(random()::text || x.id::text), 1, 6)) from public.students x
     where x.class_id = cid and not exists (select 1 from public.student_private p where p.student_id = x.id);
  end loop;
end $$;

notify pgrst, 'reload schema';

select c.name as "Ingliz tili guruhlari",
       (select count(*) from public.students s where s.class_id = c.id and coalesce(btrim(s.full_name), '') <> '') as "o'quvchi",
       (select count(*) from public.students s where s.class_id = c.id) as "joylar"
  from public.classes c where c.subject = 'Ingliz tili' and coalesce(c.grp, '') <> '' order by c.grade nulls last, c.name;
