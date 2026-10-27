-- Yangilanish 23:
--  1) 4-guruh (Ingliz tili): 8-sinf Alfa/Betta/Gamma o'rniga A1, A2, B1, B2, C1 va IELTS guruhlari;
--     9- va 10-sinf uchun A1, A2, B1, B2, C1 guruhlari (har biri 18 o'quvchilik).
--     Eski 8-sinf Ingliz tili Alfa/Betta/Gamma guruhi BO'SH bo'lsa (o'quvchi ismi, bahosi yo'q) — o'chiriladi;
--     ichida o'quvchi bo'lsa — saqlab qolinadi (natijada ko'rsatiladi), o'quvchilarni yangi guruhga o'zingiz o'tkazasiz.
--  2) Repetitor: "Avitsena" ikkiga bo'linadi — "Avitsena (Biologiya)" (eski guruh, o'quvchilari va o'qituvchisi bilan)
--     va "Avitsena (Kimyo)" (yangi; o'quvchilar ro'yxati va ota-ona telefonlari nusxalanadi).
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing. Qayta ishga tushirish xavfsiz.

create or replace function pg_temp.yk_class(p_name text, p_grade int, p_grp text, p_subject text, p_kind text, p_slots int) returns bigint
language plpgsql as $$
declare cid bigint; cid_auto boolean;
begin
  select id into cid from public.classes where lower(name) = lower(p_name) limit 1;
  if cid is null then
    select column_default is not null or is_identity = 'YES' into cid_auto from information_schema.columns
     where table_schema = 'public' and table_name = 'classes' and column_name = 'id';
    if cid_auto then
      insert into public.classes (name, grade, grp, subject, kind) values (p_name, p_grade, p_grp, p_subject, coalesce(p_kind, 'sinf')) returning id into cid;
    else
      insert into public.classes (id, name, grade, grp, subject, kind)
      values ((select coalesce(max(id), 0) + 1 from public.classes), p_name, p_grade, p_grp, p_subject, coalesce(p_kind, 'sinf')) returning id into cid;
    end if;
  end if;
  insert into public.students (class_id, slot, full_name)
  select cid, s, '' from generate_series(1, p_slots) s
   where not exists (select 1 from public.students x where x.class_id = cid and x.slot = s);
  insert into public.student_private (student_id, code)
  select x.id, upper(substr(md5(random()::text || x.id::text), 1, 6)) from public.students x
   where x.class_id = cid and not exists (select 1 from public.student_private p where p.student_id = x.id);
  return cid;
end $$;

-- 1. Ingliz tili guruhlari
do $$
declare g int; lv text; c record; used boolean;
begin
  foreach g in array array[8, 9, 10] loop
    foreach lv in array case when g = 8 then array['A1','A2','B1','B2','C1','IELTS'] else array['A1','A2','B1','B2','C1'] end loop
      perform pg_temp.yk_class(g || '-sinf Ingliz tili ' || lv, g, lv, 'Ingliz tili', 'sinf', 18);
    end loop;
  end loop;

  for c in select id, name from public.classes
            where coalesce(grade, 0) = 8 and subject = 'Ingliz tili' and upper(coalesce(grp, '')) in ('ALFA', 'BETTA', 'GAMMA') loop
    used := exists (select 1 from public.students s where s.class_id = c.id and coalesce(btrim(s.full_name), '') <> '')
         or exists (select 1 from public.daily_scores d join public.students s on s.id = d.student_id where s.class_id = c.id)
         or exists (select 1 from public.student_private p join public.students s on s.id = p.student_id
                     where s.class_id = c.id and (p.claimed_by is not null or coalesce(p.parent_phone, '') <> ''));
    if used then
      raise notice 'SAQLANDI (ichida o''quvchilar bor): % — o''quvchilarni yangi guruhga o''tkazib, keyin admin o''chirsin', c.name;
    else
      begin
        delete from public.teacher_classes where class_id = c.id;
        delete from public.student_private where student_id in (select id from public.students where class_id = c.id);
        delete from public.students where class_id = c.id;
        delete from public.classes where id = c.id;
        raise notice 'O''chirildi (bo''sh edi): %', c.name;
      exception when others then
        raise notice 'SAQLANDI (bog''liq ma''lumot bor): %', c.name;
      end;
    end if;
  end loop;
end $$;

-- 2. Avitsena: Biologiya va Kimyo
do $$
declare old bigint; kim bigint; n int;
begin
  select id into old from public.classes where lower(btrim(name)) in ('avitsena', 'avitsena (biologiya)') order by (lower(btrim(name)) = 'avitsena (biologiya)') desc limit 1;
  if old is null then raise notice 'Avitsena guruhi topilmadi'; return; end if;
  update public.classes set name = 'Avitsena (Biologiya)', kind = 'rep', grp = null, subject = null where id = old;

  select count(*) into n from public.students where class_id = old;
  kim := pg_temp.yk_class('Avitsena (Kimyo)', null, null, null, 'rep', greatest(n, 15));
  update public.classes set kind = 'rep', grp = null, subject = null where id = kim;

  -- Kimyo guruhiga o'quvchilar ismi va ota-ona telefoni nusxalanadi (bo'sh joylarga, faqat bir marta)
  update public.students k set full_name = o.full_name
    from public.students o
   where o.class_id = old and k.class_id = kim and k.slot = o.slot
     and coalesce(btrim(k.full_name), '') = '' and coalesce(btrim(o.full_name), '') <> '';
  update public.student_private kp set parent_phone = op.parent_phone
    from public.students k join public.students o on o.class_id = old and o.slot = k.slot
         join public.student_private op on op.student_id = o.id
   where k.class_id = kim and kp.student_id = k.id
     and coalesce(kp.parent_phone, '') = '' and coalesce(op.parent_phone, '') <> '';
  raise notice 'Avitsena (Biologiya) va Avitsena (Kimyo) tayyor; Kimyo guruhiga o''qituvchini "O''qituvchilar" bo''limida biriktiring';
end $$;

notify pgrst, 'reload schema';

select name as guruh, grade as sinf, grp as daraja,
       (select count(*) from public.students s where s.class_id = c.id and coalesce(btrim(s.full_name), '') <> '') as oquvchi
  from public.classes c
 where (subject = 'Ingliz tili' and coalesce(grade, 0) between 8 and 10) or name ilike 'avitsena%'
 order by name;
