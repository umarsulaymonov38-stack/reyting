-- Yangilanish 13: 8-sinf Ingliz tili va Matematika Alfa/Betta/Gamma guruhlari (3-guruh);
-- o'quvchi ismi va ota-ona telefonini faqat sinf rahbari (va admin) kiritadi, fan o'qituvchilari faqat ko'radi.
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing. Qayta ishga tushirish xavfsiz.

-- 1. 8-sinf guruhlari (har biri 18 o'quvchilik)
do $$
declare s text; n text; cid bigint; cid_auto boolean;
begin
  select column_default is not null or is_identity = 'YES' into cid_auto from information_schema.columns
   where table_schema = 'public' and table_name = 'classes' and column_name = 'id';
  foreach s in array array['Ingliz tili', 'Matematika'] loop
    foreach n in array array['Alfa', 'Betta', 'Gamma'] loop
      select id into cid from public.classes
       where grade = 8 and upper(grp) = upper(n) and subject = s and kind is distinct from 'rep' limit 1;
      if cid is null then
        if cid_auto then
          insert into public.classes (name, grade, grp, subject) values ('8-sinf ' || s || ' ' || n, 8, n, s) returning id into cid;
        else
          insert into public.classes (id, name, grade, grp, subject)
          values ((select coalesce(max(id), 0) + 1 from public.classes), '8-sinf ' || s || ' ' || n, 8, n, s) returning id into cid;
        end if;
      end if;
      insert into public.students (class_id, slot, full_name)
      select cid, g, '' from generate_series(1, 18) g
       where not exists (select 1 from public.students x where x.class_id = cid and x.slot = g);
      insert into public.student_private (student_id, code)
      select x.id, upper(substr(md5(random()::text || x.id::text), 1, 6)) from public.students x
       where x.class_id = cid and not exists (select 1 from public.student_private p where p.student_id = x.id);
    end loop;
  end loop;
end $$;

-- 2. O'quvchi qo'shish / ismini yozish / ota-ona telefoni: faqat admin yoki shu sinfning sinf rahbari
create or replace function public.yk_can_class(p_class bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select public.yk_role() = 'admin'
      or exists (select 1 from public.teacher_classes t where t.user_id = auth.uid() and t.class_id = p_class and t.role = 'rahbar')
      or (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'teacher' and p.class_id = p_class)
          and not exists (select 1 from public.teacher_classes t where t.user_id = auth.uid() and t.class_id = p_class))
$$;

create or replace function public.set_parent_phone(p_id text, p_phone text) returns void
language plpgsql security definer set search_path = public as $$
declare v public.students.id%type := p_id; cid bigint; ph text := btrim(coalesce(p_phone, '')); n int;
begin
  select class_id into cid from public.students where id = v;
  if cid is null then raise exception 'O''quvchi topilmadi'; end if;
  if not public.yk_can_class(cid) then
    raise exception 'Telefon raqamni faqat sinf rahbari yoki admin kiritadi' using errcode = '42501';
  end if;
  n := length(regexp_replace(ph, '\D', '', 'g'));
  if ph <> '' and n not in (9, 12) then
    raise exception 'Telefon raqam noto''g''ri: +998 90 123 45 67 ko''rinishida yozing';
  end if;
  update public.student_private set parent_phone = ph where student_id = v;
  if not found then
    insert into public.student_private (student_id, code, parent_phone)
    values (v, upper(substr(md5(random()::text || p_id), 1, 6)), ph);
  end if;
end $$;
revoke all on function public.set_parent_phone(text, text) from public, anon;
grant execute on function public.set_parent_phone(text, text) to authenticated;

notify pgrst, 'reload schema';
