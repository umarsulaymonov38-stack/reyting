-- Yangilanish 71: «function public.yk_is_my_kid(text) does not exist» xatosini tuzatish.
--   Ota-ona so'rovnomasi (Ota-onaga yaxshilik) va «Nega baholanmadi?» savoli shu funksiyadan foydalanadi:
--   o'quvchi shu ota-onaning farzandimi (telefon raqami, ulangan akkaunt yoki profil bo'yicha).
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing (loyiha: YUKSALISH-REYTING). Qayta ishga tushirish xavfsiz.

create or replace function public.yk_is_my_kid(p_sid text) returns boolean
language sql stable security definer set search_path = public, auth as $$
  select exists (
    select 1 from public.student_private sp
     where sp.student_id::text = p_sid
       and (sp.claimed_by = auth.uid()
            or right(regexp_replace(coalesce(sp.parent_phone, ''), '\D', '', 'g'), 9)
               = (select substring(u.email from '^p(\d{9})@') from auth.users u where u.id = auth.uid())))
  or exists (select 1 from public.profiles p where p.id = auth.uid() and p.student_id::text = p_sid)
  or exists (select 1 from public.my_kids() k where k.id::text = p_sid)
$$;
revoke all on function public.yk_is_my_kid(text) from public, anon;
grant execute on function public.yk_is_my_kid(text) to authenticated;

notify pgrst, 'reload schema';

-- Tekshiruv: funksiya mavjud bo'lsa «bor» chiqadi
select case when to_regprocedure('public.yk_is_my_kid(text)') is not null then '✅ yk_is_my_kid bor' else '❌ yo''q' end as natija;
