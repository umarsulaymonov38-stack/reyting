-- Yangilanish 50: 4-guruh (Ingliz tili) — yangi guruh «Feruz Ustoz (8-9-10-sinflar)» (20 o'quvchilik).
-- O'qituvchini admin «O'qituvchilar» bo'limida biriktiradi (o'quvchilarni kirituvchi bo'lsa — «Sinf rahbari»).
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing. Qayta ishga tushirish xavfsiz (ikkinchi marta guruh qo'shilmaydi).

do $$
declare cid bigint; cid_auto boolean;
begin
  select column_default is not null or is_identity = 'YES' into cid_auto from information_schema.columns
   where table_schema = 'public' and table_name = 'classes' and column_name = 'id';
  select id into cid from public.classes where lower(name) = lower('Feruz Ustoz (8-9-10-sinflar)') limit 1;
  if cid is null then
    if cid_auto then
      insert into public.classes (name, grade, grp, subject) values ('Feruz Ustoz (8-9-10-sinflar)', null, 'Feruz', 'Ingliz tili') returning id into cid;
    else
      insert into public.classes (id, name, grade, grp, subject)
      values ((select coalesce(max(id), 0) + 1 from public.classes), 'Feruz Ustoz (8-9-10-sinflar)', null, 'Feruz', 'Ingliz tili') returning id into cid;
    end if;
  end if;
  insert into public.students (class_id, slot, full_name)
  select cid, s, '' from generate_series(1, 20) s where not exists (select 1 from public.students x where x.class_id = cid and x.slot = s);
  insert into public.student_private (student_id, code)
  select x.id, upper(substr(md5(random()::text || x.id::text), 1, 6)) from public.students x
   where x.class_id = cid and not exists (select 1 from public.student_private p where p.student_id = x.id);
end $$;

notify pgrst, 'reload schema';

select c.name as "Ingliz tili guruhlari", (select count(*) from public.students s where s.class_id = c.id) as "joylar"
  from public.classes c where c.subject = 'Ingliz tili' and coalesce(c.grp, '') <> '' order by c.name;
