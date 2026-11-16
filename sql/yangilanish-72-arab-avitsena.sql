-- Yangilanish 72:
--  1) 6-guruh (Arab tili va Koreys tili): yangi guruh «5-6-sinf Arab tili boshlang'ich daraja» (15 o'quvchilik).
--  2) 2-guruh (Yuqori sinflar): «Avitsena» sinfi — yo'q bo'lsa ochiladi, bor bo'lsa asosiy sinf sifatida tiklanadi
--     (guruh/repetitor belgisi olib tashlanadi); joylar soni boshqa yuqori sinflardagidek.
--     Darajasi (sinf raqami) ko'rsatilmagan asosiy sinf — yuqori sinflar qoidasida hisoblanadi:
--     kitob + odoblar + ota-onaga yaxshilik = kuniga 31 ball.
-- O'qituvchilarni admin «O'qituvchilar» bo'limida biriktiradi (Avitsena uchun — «Sinf rahbari»).
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing (loyiha: YUKSALISH-REYTING). Qayta ishga tushirish xavfsiz.

do $$
declare cid bigint; cid_auto boolean; n int;
begin
  select column_default is not null or is_identity = 'YES' into cid_auto from information_schema.columns
   where table_schema = 'public' and table_name = 'classes' and column_name = 'id';

  -- 1. Arab tili boshlang'ich daraja (5-6-sinflar)
  select id into cid from public.classes where lower(name) = lower('5-6-sinf Arab tili boshlang''ich daraja') limit 1;
  if cid is null then
    if cid_auto then
      insert into public.classes (name, grade, grp, subject) values ('5-6-sinf Arab tili boshlang''ich daraja', null, 'Boshlang''ich', 'Arab tili') returning id into cid;
    else
      insert into public.classes (id, name, grade, grp, subject)
      values ((select coalesce(max(id), 0) + 1 from public.classes), '5-6-sinf Arab tili boshlang''ich daraja', null, 'Boshlang''ich', 'Arab tili') returning id into cid;
    end if;
  end if;
  insert into public.students (class_id, slot, full_name)
  select cid, g, '' from generate_series(1, 15) g where not exists (select 1 from public.students s where s.class_id = cid and s.slot = g);
  insert into public.student_private (student_id, code)
  select s.id, upper(substr(md5(random()::text || s.id::text), 1, 6)) from public.students s
   where s.class_id = cid and not exists (select 1 from public.student_private p where p.student_id = s.id);

  -- 2. Avitsena (asosiy sinf, 2-guruh)
  cid := null;
  select id into cid from public.classes where lower(btrim(name)) = 'avitsena' order by id limit 1;
  if cid is null then
    if cid_auto then
      insert into public.classes (name) values ('Avitsena') returning id into cid;
    else
      insert into public.classes (id, name) values ((select coalesce(max(id), 0) + 1 from public.classes), 'Avitsena') returning id into cid;
    end if;
  else
    update public.classes set kind = null, grp = null, subject = null where id = cid;
  end if;
  select coalesce(max(s.slot), 30) into n from public.students s join public.classes c on c.id = s.class_id
   where coalesce(c.grade, 0) between 5 and 10 and coalesce(c.grp, '') = '' and c.kind is distinct from 'rep';
  insert into public.students (class_id, slot, full_name)
  select cid, g, '' from generate_series(1, n) g where not exists (select 1 from public.students s where s.class_id = cid and s.slot = g);
  insert into public.student_private (student_id, code)
  select s.id, upper(substr(md5(random()::text || s.id::text), 1, 6)) from public.students s
   where s.class_id = cid and not exists (select 1 from public.student_private p where p.student_id = s.id);
end $$;

-- Darajasi ko'rsatilmagan asosiy sinf (masalan, Avitsena) — yuqori sinflar qoidasi
create or replace function public.yk_g2(p_class bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select c.kind is distinct from 'rep' and coalesce(c.grp, '') = ''
                          and coalesce(c.subject, '') !~* '^(arab|koreys)'
                          and coalesce(c.grade, nullif(substring(c.name from '^\s*(\d+)'), '')::int, 5) between 1 and 10
                     from public.classes c where c.id = p_class), false)
$$;

notify pgrst, 'reload schema';

select c.name as "Yangi / tiklangan sinflar", coalesce(c.subject, '2-guruh: Yuqori sinflar') as guruh,
       (select count(*) from public.students s where s.class_id = c.id) as joylar
  from public.classes c
 where lower(c.name) in (lower('5-6-sinf Arab tili boshlang''ich daraja'), 'avitsena');
