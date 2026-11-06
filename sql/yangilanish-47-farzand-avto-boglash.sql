-- Yangilanish 47: ota-ona allaqachon ro'yxatdan o'tgan bo'lsa, keyinroq boshqa farzandiga ham shu telefon yozilganda
-- o'sha farzand avtomatik uning ilovasiga qo'shiladi (masalan, aka-uka / opa-singillar).
-- Avval: farzand faqat ota-ona birinchi marta kirgan paytda bog'lanardi, keyin yozilgan telefonlar bog'lanmay qolardi.
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing. Qayta ishga tushirish xavfsiz.

-- 1. Hozir bog'lanmay qolganlarni bog'lash
update public.student_private sp
   set claimed_by = u.id
  from auth.users u join public.profiles p on p.id = u.id and p.role = 'parent'
 where sp.claimed_by is null
   and length(right(regexp_replace(coalesce(sp.parent_phone, ''), '\D', '', 'g'), 9)) = 9
   and u.email = 'p' || right(regexp_replace(coalesce(sp.parent_phone, ''), '\D', '', 'g'), 9) || '@ota.yuksalish.app';

-- 2. Bundan keyin: telefon yozilganda yoki o'zgartirilganda — o'sha raqamli ota-ona akkaunti bo'lsa, darhol bog'lanadi
create or replace function public.yk_autolink_parent() returns trigger
language plpgsql security definer set search_path = public, auth as $$
declare ph text := right(regexp_replace(coalesce(new.parent_phone, ''), '\D', '', 'g'), 9); uid uuid;
begin
  if new.claimed_by is null and length(ph) = 9 then
    select u.id into uid from auth.users u join public.profiles p on p.id = u.id and p.role = 'parent'
     where u.email = 'p' || ph || '@ota.yuksalish.app';
    if uid is not null then new.claimed_by := uid; end if;
  end if;
  return new;
end $$;
-- nomi «zz_» bilan: mavjud triggerlardan keyin ishlaydi (telefon almashsa eski bog'lanish avval uziladi)
drop trigger if exists zz_yk_autolink_parent on public.student_private;
create trigger zz_yk_autolink_parent before insert or update of parent_phone, claimed_by on public.student_private
  for each row execute function public.yk_autolink_parent();

notify pgrst, 'reload schema';

-- Natija: bir telefon raqamiga bog'langan farzandlar (2 va undan ko'p bo'lganlari)
select right(regexp_replace(coalesce(sp.parent_phone, ''), '\D', '', 'g'), 9) as telefon,
       string_agg(s.full_name || ' (' || c.name || ')', ', ' order by c.name) as farzandlar,
       count(*) filter (where sp.claimed_by is not null) as "ilovaga bog'langan", count(*) as jami
  from public.student_private sp join public.students s on s.id = sp.student_id join public.classes c on c.id = s.class_id
 where coalesce(btrim(s.full_name), '') <> '' and length(right(regexp_replace(coalesce(sp.parent_phone, ''), '\D', '', 'g'), 9)) = 9
 group by 1 having count(*) > 1
 order by count(*) filter (where sp.claimed_by is null) desc, 1
 limit 100;
