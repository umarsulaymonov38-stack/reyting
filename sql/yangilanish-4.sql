-- Yangilanish 4: Alfa/Betta/Gamma nomlari, 3-guruh sig'imi 18 ta, 5-guruh (Arab tili va Koreys tili).
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing. Qayta ishga tushirish xavfsiz.
-- Ismi yozilgan yoki bahosi, to'lovi, ota-onasi bor o'quvchi hech qachon o'chirilmaydi.

-- Yordamchi: sinfda o'quvchi joylarini (slot) kerakli songacha to'ldirish
create or replace function pg_temp.yk_add_slots(cid bigint, cnt int) returns void language plpgsql as $$
declare k int; sid_auto boolean;
begin
  select column_default is not null or is_identity = 'YES' into sid_auto from information_schema.columns
   where table_schema = 'public' and table_name = 'students' and column_name = 'id';
  for k in 1..cnt loop
    if not exists (select 1 from public.students where class_id = cid and slot = k) then
      if sid_auto then
        insert into public.students (class_id, slot, full_name) values (cid, k, '');
      else
        insert into public.students (id, class_id, slot, full_name)
        values ((select coalesce(max(id), 0) + 1 from public.students), cid, k, '');
      end if;
    end if;
  end loop;
  begin
    insert into public.student_private (student_id, code)
    select s.id, upper(substr(md5(random()::text || s.id::text), 1, 6)) from public.students s
     where s.class_id = cid and not exists (select 1 from public.student_private p where p.student_id = s.id);
  exception when others then raise notice 'student_private: %', sqlerrm;
  end;
end $$;

-- Yordamchi: yangi sinf (guruh) qo'shish, id avtomatik bo'lmasa keyingi raqam bilan
create or replace function pg_temp.yk_add_class(p_name text, p_grade int, p_grp text, p_subject text) returns bigint language plpgsql as $$
declare cid bigint; cid_auto boolean;
begin
  select id into cid from public.classes where name = p_name limit 1;
  if cid is not null then return cid; end if;
  select column_default is not null or is_identity = 'YES' into cid_auto from information_schema.columns
   where table_schema = 'public' and table_name = 'classes' and column_name = 'id';
  if cid_auto then
    insert into public.classes (name, grade, grp, subject) values (p_name, p_grade, p_grp, p_subject) returning id into cid;
  else
    insert into public.classes (id, name, grade, grp, subject)
    values ((select coalesce(max(id), 0) + 1 from public.classes), p_name, p_grade, p_grp, p_subject) returning id into cid;
  end if;
  return cid;
end $$;

-- 1. Guruh nomlari bir xil yozilsin: Alfa, Betta, Gamma
update public.classes set grp = initcap(grp)
 where upper(grp) in ('ALFA', 'BETTA', 'GAMMA') and grp <> initcap(grp);

-- 2. 3-guruh (Matematika va Ingliz tili, Alfa/Betta/Gamma): har birida 18 ta o'quvchi joyi
do $$
declare c record; s record; n_kept int := 0;
begin
  for c in select id from public.classes where upper(grp) in ('ALFA', 'BETTA', 'GAMMA') and kind is distinct from 'rep' loop
    perform pg_temp.yk_add_slots(c.id, 18);
    for s in select st.id, st.slot, st.full_name from public.students st where st.class_id = c.id and st.slot > 18 loop
      if coalesce(btrim(s.full_name), '') = ''
         and not exists (select 1 from public.daily_scores d where d.student_id = s.id)
         and not exists (select 1 from public.rep_daily r where r.student_id = s.id)
         and not exists (select 1 from public.payments p where p.student_id = s.id)
         and not exists (select 1 from public.student_private sp where sp.student_id = s.id
                          and (sp.claimed_by is not null or coalesce(sp.parent_phone, '') <> '')) then
        begin
          delete from public.student_private where student_id = s.id;
          delete from public.students where id = s.id;
        exception when others then
          n_kept := n_kept + 1;
          raise notice 'O''chirilmadi (bog''liq ma''lumot bor): o''quvchi id=%', s.id;
        end;
      else
        n_kept := n_kept + 1;
        raise notice 'Saqlab qolindi (ismi yoki ma''lumoti bor): sinf id=%, joy=%, %', c.id, s.slot, s.full_name;
      end if;
    end loop;
  end loop;
  if n_kept > 0 then raise notice '18 dan ortiq, ma''lumoti bor % ta o''quvchi saqlab qolindi', n_kept; end if;
end $$;

-- 3. 5-guruh: Arab tili va Koreys tili (har biri 15 o'quvchilik)
do $$
declare cid bigint;
begin
  cid := pg_temp.yk_add_class('5-6-sinf Arab tili 1-guruh',   5, '1-guruh', 'Arab tili');   perform pg_temp.yk_add_slots(cid, 15);
  cid := pg_temp.yk_add_class('5-6-sinf Arab tili 2-guruh',   5, '2-guruh', 'Arab tili');   perform pg_temp.yk_add_slots(cid, 15);
  cid := pg_temp.yk_add_class('7-sinf Arab tili 1-guruh',     7, '1-guruh', 'Arab tili');   perform pg_temp.yk_add_slots(cid, 15);
  cid := pg_temp.yk_add_class('7-sinf Arab tili 2-guruh',     7, '2-guruh', 'Arab tili');   perform pg_temp.yk_add_slots(cid, 15);
  cid := pg_temp.yk_add_class('5-6-sinf Koreys tili 1-guruh', 5, '1-guruh', 'Koreys tili'); perform pg_temp.yk_add_slots(cid, 15);
  cid := pg_temp.yk_add_class('5-6-sinf Koreys tili 2-guruh', 5, '2-guruh', 'Koreys tili'); perform pg_temp.yk_add_slots(cid, 15);
end $$;

notify pgrst, 'reload schema';
