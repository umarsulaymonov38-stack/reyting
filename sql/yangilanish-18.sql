-- Yangilanish 18: admin "O'qituvchilar" bo'limida o'qituvchiga yangi parol qo'yadi.
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing. Qayta ishga tushirish xavfsiz.
-- Eslatma: Supabase parollarni shifrlab (bcrypt) saqlaydi — eski parolni ko'rib bo'lmaydi, faqat yangisini qo'yish mumkin.

create extension if not exists pgcrypto with schema extensions;

create or replace function public.admin_set_password(p_id uuid, p_pw text) returns void
language plpgsql security definer set search_path = public, extensions, auth as $$
begin
  if public.yk_role() <> 'admin' then raise exception 'Faqat admin o''zgartiradi' using errcode = '42501'; end if;
  if length(coalesce(p_pw, '')) < 6 then raise exception 'Parol kamida 6 belgidan iborat bo''lsin'; end if;
  if not exists (select 1 from public.profiles where id = p_id and role = 'teacher') then
    raise exception 'O''qituvchi topilmadi';
  end if;
  update auth.users set encrypted_password = extensions.crypt(p_pw, extensions.gen_salt('bf')), updated_at = now()
   where id = p_id;
  if not found then raise exception 'Akkaunt topilmadi'; end if;
end $$;
revoke all on function public.admin_set_password(uuid, text) from public, anon;
grant execute on function public.admin_set_password(uuid, text) to authenticated;

notify pgrst, 'reload schema';
