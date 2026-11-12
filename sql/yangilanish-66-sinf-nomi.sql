-- Yangilanish 66: Sinf (guruh) nomini o'zgartirish — faqat shu sinfga biriktirilgan SINF RAHBARI (va bosh admin).
--   Nom 2–60 belgi. O'zgartirilgan nom platformaning hamma joyida aynan shu ko'rinishda chiqadi.
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing (loyiha: YUKSALISH-REYTING). Qayta ishga tushirish xavfsiz.

alter table public.classes add column if not exists renamed boolean not null default false;

create or replace function public.set_class_name(p_class bigint, p_name text) returns text
language plpgsql security definer set search_path = public as $$
declare nm text := regexp_replace(btrim(coalesce(p_name, '')), '\s+', ' ', 'g');
begin
  if not (public.yk_role() = 'admin'
          or exists (select 1 from public.teacher_classes t
                      where t.user_id = auth.uid() and t.class_id = p_class and t.role = 'rahbar')) then
    raise exception 'Sinf nomini faqat shu sinfning rahbari o''zgartira oladi' using errcode = '42501';
  end if;
  if length(nm) < 2 or length(nm) > 60 then raise exception 'Nom 2 dan 60 belgigacha bo''lsin'; end if;
  update public.classes set name = nm, renamed = true where id = p_class;
  if not found then raise exception 'Sinf topilmadi'; end if;
  return nm;
end $$;
revoke all on function public.set_class_name(bigint, text) from public, anon;
grant execute on function public.set_class_name(bigint, text) to authenticated;

notify pgrst, 'reload schema';
