-- Yangilanish 87: Boshlang'ich Ingliz tili / Matematika guruhlarini TO'LIQ nom bilan nomlash.
--   Masalan «2-A Matematika» → «2-A Ulug'beklar Matematika», «2-A Ingliz tili» → «2-A Ulug'beklar Ingliz tili».
--   Mavjud guruhlar qayta nomlanadi (yangi guruh yaratilmaydi), yangi o'quvchilar ham ko'chiriladi.
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing (loyiha: YUKSALISH-REYTING). Avval 85 ishga tushgan bo'lsin. Qayta ishga tushirish xavfsiz.

create or replace function public.yk_bosh_guruh() returns text
language plpgsql security definer set search_path = public as $$
declare m record; st record; subj text; cid bigint; gsid uuid; mlabel text; gname text;
        cls_auto boolean; stu_auto boolean; ngroups int := 0; nren int := 0; nstud int := 0; nlink int := 0; slotn int;
begin
  if public.yk_role() <> 'admin' then raise exception 'Faqat admin' using errcode = '42501'; end if;
  select column_default is not null or is_identity = 'YES' into cls_auto
    from information_schema.columns where table_schema='public' and table_name='classes' and column_name='id';
  select column_default is not null or is_identity = 'YES' into stu_auto
    from information_schema.columns where table_schema='public' and table_name='students' and column_name='id';

  for m in
    select c.id, c.name, coalesce(c.grade, nullif(substring(c.name from '^\s*(\d+)'), '')::int) as gr
      from public.classes c
     where c.kind is distinct from 'rep' and coalesce(c.grp, '') = '' and coalesce(c.subject, '') !~* '^(arab|koreys)'
       and coalesce(c.grade, nullif(substring(c.name from '^\s*(\d+)'), '')::int) between 1 and 4
  loop
    mlabel := replace((regexp_match(m.name, '^\s*(\d+\s*-\s*[A-Za-zА-Яа-я])'))[1], ' ', '');
    if mlabel is null then mlabel := split_part(btrim(m.name), ' ', 1); end if;

    foreach subj in array array['Ingliz tili', 'Matematika'] loop
      gname := regexp_replace(btrim(m.name), '\s+', ' ', 'g') || ' ' || subj;  -- TO'LIQ nom
      -- mavjud guruhni grp (= mlabel) + fan + daraja bo'yicha topamiz (eski «2-A Matematika» ham topiladi)
      select id into cid from public.classes
       where coalesce(grp, '') = mlabel and coalesce(subject, '') = subj
         and coalesce(grade, nullif(substring(name from '^\s*(\d+)'), '')::int) = m.gr
         and (kind = 'rep' is not true) limit 1;
      if cid is null then
        -- eski usulda (nom «mlabel subj») yaratilgan bo'lsa ham topamiz
        select id into cid from public.classes where name = mlabel || ' ' || subj and coalesce(subject, '') = subj limit 1;
      end if;
      if cid is null then
        if cls_auto then
          insert into public.classes (name, grade, grp, subject, renamed) values (gname, m.gr, mlabel, subj, true) returning id into cid;
        else
          insert into public.classes (id, name, grade, grp, subject, renamed)
          values ((select coalesce(max(id), 0) + 1 from public.classes), gname, m.gr, mlabel, subj, true) returning id into cid;
        end if;
        ngroups := ngroups + 1;
      else
        update public.classes set name = gname, grp = mlabel, subject = subj, renamed = true where id = cid and name is distinct from gname;
        if found then nren := nren + 1; end if;
      end if;

      slotn := coalesce((select max(slot) from public.students where class_id = cid), 0);
      for st in select id, slot, full_name from public.students
                 where class_id = m.id and coalesce(btrim(full_name), '') <> '' order by slot loop
        select id into gsid from public.students
          where class_id = cid and btrim(full_name) = btrim(st.full_name) limit 1;
        if gsid is null then
          slotn := slotn + 1;
          if stu_auto then
            insert into public.students (class_id, slot, full_name) values (cid, slotn, st.full_name) returning id into gsid;
          else
            execute 'insert into public.students (id, class_id, slot, full_name) select coalesce(max(id),0)+1, $1, $2, $3 from public.students returning id'
              into gsid using cid, slotn, st.full_name;
          end if;
          nstud := nstud + 1;
          insert into public.student_private (student_id, code)
          select gsid, upper(substr(md5(random()::text || gsid::text), 1, 6))
           where not exists (select 1 from public.student_private p where p.student_id = gsid);
        end if;
        insert into public.student_links (gid, kid, score, auto)
        values (gsid::text, st.id::text, 1, false)
        on conflict (gid) do update set kid = excluded.kid, auto = false;
        nlink := nlink + 1;
      end loop;
    end loop;
  end loop;
  return ngroups || ' ta yangi guruh, ' || nren || ' ta guruh qayta nomlandi, ' || nstud || ' ta o''quvchi ko''chirildi.';
end $$;
revoke all on function public.yk_bosh_guruh() from public, anon;
grant execute on function public.yk_bosh_guruh() to authenticated;

notify pgrst, 'reload schema';
select public.yk_bosh_guruh() as natija;
