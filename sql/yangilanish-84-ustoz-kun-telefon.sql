-- Yangilanish 84: 1) Har bir fan/guruh o'qituvchisi o'zi dars o'tadigan hafta kunlarini belgilaydi.
--                 2) Ingliz tili / Matematika (va boshqa guruh) o'qituvchilari o'z o'quvchisiga ota-ona
--                    telefon raqamini yozadi va bitta tugma bilan qo'ng'iroq qiladi.
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing (loyiha: YUKSALISH-REYTING). Qayta ishga tushirish xavfsiz.

-- Yordamchi: joriy foydalanuvchi shu sinf/guruhda o'qituvchimi?
create or replace function public.yk_teaches(p_class bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select public.yk_role() = 'admin'
      or exists (select 1 from public.teacher_classes t where t.user_id = auth.uid() and t.class_id = p_class)
$$;
grant execute on function public.yk_teaches(bigint) to authenticated;

-- 1) O'qituvchi o'z dars kunlarini o'zi belgilaydi (o'z biriktirilgan sinfi uchun)
create or replace function public.set_my_days(p_class bigint, p_days smallint[]) returns smallint[]
language plpgsql security definer set search_path = public as $$
declare d smallint[];
begin
  if not exists (select 1 from public.teacher_classes t where t.user_id = auth.uid() and t.class_id = p_class)
     and public.yk_role() <> 'admin' then
    raise exception 'Bu sinf sizga biriktirilmagan' using errcode = '42501';
  end if;
  select array(select distinct x from unnest(coalesce(p_days, '{}'::smallint[])) x where x between 1 and 6 order by 1) into d;
  update public.teacher_classes set days = nullif(d, '{}'::smallint[])
   where user_id = auth.uid() and class_id = p_class;
  return d;
end $$;
revoke all on function public.set_my_days(bigint, smallint[]) from public, anon;
grant execute on function public.set_my_days(bigint, smallint[]) to authenticated;

-- 2a) Guruh o'qituvchisi: o'z o'quvchilarining ota-ona telefonlarini ko'radi
create or replace function public.group_phones(p_class bigint)
returns table (student_id text, parent_phone text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.yk_teaches(p_class) then
    raise exception 'Bu sinf sizga biriktirilmagan' using errcode = '42501';
  end if;
  return query
  select s.id::text, sp.parent_phone::text
    from public.students s left join public.student_private sp on sp.student_id = s.id
   where s.class_id = p_class and coalesce(btrim(s.full_name), '') <> '';
end $$;
revoke all on function public.group_phones(bigint) from public, anon;
grant execute on function public.group_phones(bigint) to authenticated;

-- 2b) Guruh o'qituvchisi: o'quvchiga ota-ona telefon raqamini yozadi/yangilaydi
create or replace function public.set_group_phone(p_sid text, p_phone text) returns text
language plpgsql security definer set search_path = public as $$
declare cid bigint; ph text;
begin
  select s.class_id into cid from public.students s where s.id::text = p_sid;
  if cid is null then raise exception 'O''quvchi topilmadi'; end if;
  if not public.yk_teaches(cid) then
    raise exception 'Bu o''quvchi sizning guruhingizda emas' using errcode = '42501';
  end if;
  ph := nullif(regexp_replace(coalesce(p_phone, ''), '[^0-9+]', '', 'g'), '');
  if ph is not null and length(regexp_replace(ph, '\D', '', 'g')) < 9 then
    raise exception 'Telefon raqami to''liq emas';
  end if;
  update public.student_private set parent_phone = ph where student_id::text = p_sid;
  if not found then
    insert into public.student_private (student_id, parent_phone) values (p_sid::uuid, ph);
  end if;
  return ph;
end $$;
revoke all on function public.set_group_phone(text, text) from public, anon;
grant execute on function public.set_group_phone(text, text) to authenticated;

notify pgrst, 'reload schema';
select 'Tayyor — set_my_days, group_phones, set_group_phone yaratildi' as natija;
