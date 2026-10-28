-- Yangilanish 26: sinf kartochkasidagi o'qituvchi ismi (classes.teacher_name) o'qituvchi akkauntidagi ism bilan doim bir xil bo'ladi.
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing. Qayta ishga tushirish xavfsiz.
--  1) Hozirgi farqlar to'g'rilanadi: har bir sinfda kartochkadagi ism — shu sinf rahbarining akkauntidagi ism.
--  2) Bundan keyin: admin o'qituvchi ismini o'zgartirsa yoki o'qituvchini sinf rahbari qilsa — kartochka o'zi yangilanadi.

-- 1. Bir martalik to'g'rilash (oldin–keyin ro'yxati natijada ko'rinadi)
drop table if exists pg_temp.yk_tn;
create temp table yk_tn as
select c.id, c.name as sinf, c.teacher_name as eski, p.full_name as yangi
  from public.classes c
  join lateral (select t.user_id from public.teacher_classes t where t.class_id = c.id and t.role = 'rahbar' limit 1) r on true
  join public.profiles p on p.id = r.user_id
 where coalesce(btrim(p.full_name), '') <> '' and c.teacher_name is distinct from p.full_name;
update public.classes c set teacher_name = x.yangi from yk_tn x where x.id = c.id;

-- 2. Ism o'zgarsa — u sinf rahbari bo'lgan sinflar kartochkasi ham o'zgaradi
create or replace function public.yk_sync_tname() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.full_name is distinct from old.full_name and coalesce(btrim(new.full_name), '') <> '' then
    update public.classes c set teacher_name = new.full_name
     where c.id in (select t.class_id from public.teacher_classes t where t.user_id = new.id and t.role = 'rahbar')
        or (coalesce(old.full_name, '') <> '' and c.teacher_name = old.full_name);
  end if;
  return new;
end $$;
drop trigger if exists profiles_sync_tname on public.profiles;
create trigger profiles_sync_tname after update of full_name on public.profiles
  for each row execute function public.yk_sync_tname();

-- 3. O'qituvchi sinf rahbari qilinsa — kartochkada uning ismi chiqadi
create or replace function public.yk_sync_tname_tc() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.role = 'rahbar' then
    update public.classes set teacher_name = p.full_name
      from public.profiles p where p.id = new.user_id and coalesce(btrim(p.full_name), '') <> '' and classes.id = new.class_id;
  end if;
  return new;
end $$;
drop trigger if exists teacher_classes_sync_tname on public.teacher_classes;
create trigger teacher_classes_sync_tname after insert or update of role on public.teacher_classes
  for each row execute function public.yk_sync_tname_tc();

notify pgrst, 'reload schema';

-- Natija: qaysi sinflarda ism to'g'rilandi
select sinf, eski as "edi", yangi as "bo'ldi" from yk_tn order by sinf;
