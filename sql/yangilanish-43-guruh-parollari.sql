-- Yangilanish 43: fan guruhlarida (3-, 4-, 6-guruh: Matematika, Ingliz tili, Arab tili, Koreys tili) ota-ona paroli bo'lmaydi.
-- O'quvchi asosiy sinfiga (1–2-guruh) bog'langan — ota-ona o'sha sinfdagi parol bilan kiradi va guruh baholarini ham o'sha yerda ko'radi.
-- Repetitor guruhlari (5-guruh) parollari avvalgidek ishlaydi.
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing. Qayta ishga tushirish xavfsiz.

create or replace function public.parent_code_login(p_phone text, p_code text, p_dev text default null) returns jsonb
language plpgsql security definer set search_path = public, extensions, auth as $$
declare ph text := right(regexp_replace(coalesce(p_phone, ''), '\D', '', 'g'), 9);
        c text := upper(btrim(coalesce(p_code, '')));
        nm text; uid uuid; f public.parent_code_fail;
begin
  if length(ph) <> 9 or length(c) < 6 then return '{"st":"bad"}'; end if;
  if p_dev is not null and exists (select 1 from public.staff_devices where dev = p_dev) then return '{"st":"staff"}'; end if;
  select * into f from public.parent_code_fail where phone = ph;
  if f.phone is not null and f.since > now() - interval '1 hour' and f.cnt >= 10 then return '{"st":"lock"}'; end if;
  select s.full_name into nm
    from public.student_private sp join public.students s on s.id = sp.student_id join public.classes cl on cl.id = s.class_id
   where right(regexp_replace(coalesce(sp.parent_phone, ''), '\D', '', 'g'), 9) = ph and upper(btrim(sp.code)) = c
     -- fan guruhlari (3-, 4-, 6-guruh: Matematika, Ingliz tili, Arab va Koreys tili) kodlari parol emas — o'quvchi asosiy sinfidan kiradi
     and (cl.kind = 'rep' or coalesce(cl.grp, '') = '')
   limit 1;
  if nm is null then
    insert into public.parent_code_fail (phone, cnt, since) values (ph, 1, now())
    on conflict (phone) do update set
      cnt = case when public.parent_code_fail.since < now() - interval '1 hour' then 1 else public.parent_code_fail.cnt + 1 end,
      since = case when public.parent_code_fail.since < now() - interval '1 hour' then now() else public.parent_code_fail.since end;
    return '{"st":"bad"}';
  end if;
  delete from public.parent_code_fail where phone = ph;
  select au.id into uid from auth.users au where au.email = 'p' || ph || '@ota.yuksalish.app';
  if uid is null then return jsonb_build_object('st', 'new', 'name', nm); end if;
  if exists (select 1 from public.parent_pw_set where user_id = uid) then return '{"st":"own"}'; end if;
  update auth.users set encrypted_password = extensions.crypt(c, extensions.gen_salt('bf')), updated_at = now()
   where id = uid and case when coalesce(encrypted_password, '') ~ '^\$2' then encrypted_password <> extensions.crypt(c, encrypted_password) else true end;
  return '{"st":"ok"}';
end $$;
revoke all on function public.parent_code_login(text, text, text) from public;
grant execute on function public.parent_code_login(text, text, text) to anon, authenticated;

notify pgrst, 'reload schema';
