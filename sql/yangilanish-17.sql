-- Yangilanish 17: admin o'qituvchining ism-familiyasini "O'qituvchilar" bo'limida tahrirlaydi.
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing. Qayta ishga tushirish xavfsiz.

create or replace function public.set_teacher_name(p_id uuid, p_name text) returns void
language plpgsql security definer set search_path = public as $$
declare old text; n text := left(btrim(coalesce(p_name, '')), 80);
begin
  if public.yk_role() <> 'admin' then raise exception 'Faqat admin o''zgartiradi' using errcode = '42501'; end if;
  if n = '' then raise exception 'Ism-familiya bo''sh bo''lmasin'; end if;
  select full_name into old from public.profiles where id = p_id and role = 'teacher';
  if not found then raise exception 'O''qituvchi topilmadi'; end if;
  update public.profiles set full_name = n where id = p_id;
  -- Sinf kartochkasidagi o'qituvchi nomi ham yangilanadi (eski nom bilan yozilgan bo'lsa)
  if coalesce(old, '') <> '' then
    update public.classes set teacher_name = n where teacher_name = old;
  end if;
end $$;
revoke all on function public.set_teacher_name(uuid, text) from public, anon;
grant execute on function public.set_teacher_name(uuid, text) to authenticated;

notify pgrst, 'reload schema';
