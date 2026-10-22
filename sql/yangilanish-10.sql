-- Yangilanish 10: "Avitsena" sinfi (2-guruh: Yuqori sinflar) va o'qituvchilar o'z sinfiga o'quvchi qo'shishi / ismini yozishi.
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing. Qayta ishga tushirish xavfsiz.

-- 1. Avitsena sinfi: joylar soni boshqa yuqori sinflardagidek (topilmasa 30 ta)
do $$
declare cid bigint; n int; cid_auto boolean;
begin
  select id into cid from public.classes where lower(name) = 'avitsena' limit 1;
  if cid is null then
    select column_default is not null or is_identity = 'YES' into cid_auto from information_schema.columns
     where table_schema = 'public' and table_name = 'classes' and column_name = 'id';
    if cid_auto then
      insert into public.classes (name) values ('Avitsena') returning id into cid;
    else
      insert into public.classes (id, name) values ((select coalesce(max(id), 0) + 1 from public.classes), 'Avitsena') returning id into cid;
    end if;
  end if;
  select coalesce(max(s.slot), 30) into n from public.students s join public.classes c on c.id = s.class_id
   where coalesce(c.grade, 0) between 5 and 10 and coalesce(c.grp, '') = '' and c.kind is distinct from 'rep';
  insert into public.students (class_id, slot, full_name)
  select cid, g, '' from generate_series(1, n) g
   where not exists (select 1 from public.students s where s.class_id = cid and s.slot = g);
  insert into public.student_private (student_id, code)
  select s.id, upper(substr(md5(random()::text || s.id::text), 1, 6)) from public.students s
   where s.class_id = cid and not exists (select 1 from public.student_private p where p.student_id = s.id);
end $$;

-- 2. Foydalanuvchi shu sinfni boshqara oladimi (admin yoki sinfga biriktirilgan o'qituvchi)
create or replace function public.yk_can_class(p_class bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select public.yk_role() = 'admin'
      or exists (select 1 from public.teacher_classes t where t.user_id = auth.uid() and t.class_id = p_class)
      or exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'teacher' and p.class_id = p_class)
$$;

-- 3. O'quvchi ism-familiyasini yozish / tuzatish
create or replace function public.set_student_name(p_id text, p_name text) returns void
language plpgsql security definer set search_path = public as $$
declare v public.students.id%type := p_id; cid bigint;
begin
  select class_id into cid from public.students where id = v;
  if cid is null then raise exception 'O''quvchi topilmadi'; end if;
  if not public.yk_can_class(cid) then raise exception 'Bu sinfga ruxsatingiz yo''q' using errcode = '42501'; end if;
  update public.students set full_name = left(btrim(coalesce(p_name, '')), 120) where id = v;
end $$;

-- 4. Sinfga yangi o'quvchi joyi qo'shish (bitta sinfda ko'pi bilan 60 ta)
create or replace function public.add_student(p_class bigint) returns text
language plpgsql security definer set search_path = public as $$
declare n int; sid public.students.id%type; sid_auto boolean;
begin
  if not public.yk_can_class(p_class) then raise exception 'Bu sinfga ruxsatingiz yo''q' using errcode = '42501'; end if;
  select coalesce(max(slot), 0) into n from public.students where class_id = p_class;
  if n >= 60 then raise exception 'Sinfda 60 tadan ortiq o''quvchi bo''lmaydi'; end if;
  select column_default is not null or is_identity = 'YES' into sid_auto from information_schema.columns
   where table_schema = 'public' and table_name = 'students' and column_name = 'id';
  if sid_auto then
    insert into public.students (class_id, slot, full_name) values (p_class, n + 1, '') returning id into sid;
  else
    execute 'insert into public.students (id, class_id, slot, full_name) select coalesce(max(id), 0) + 1, $1, $2, '''' from public.students returning id'
      into sid using p_class, n + 1;
  end if;
  insert into public.student_private (student_id, code) values (sid, upper(substr(md5(random()::text || sid::text), 1, 6)));
  return sid::text;
end $$;

revoke all on function public.yk_can_class(bigint) from public, anon;
revoke all on function public.set_student_name(text, text) from public, anon;
revoke all on function public.add_student(bigint) from public, anon;
grant execute on function public.yk_can_class(bigint) to authenticated;
grant execute on function public.set_student_name(text, text) to authenticated;
grant execute on function public.add_student(bigint) to authenticated;

notify pgrst, 'reload schema';
