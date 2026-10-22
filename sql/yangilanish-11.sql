-- Yangilanish 11: 1-guruh (1–4-sinflar) va 2-guruh (5–10-sinflar, Avitsena) sinf rahbarlari o'z sinfi
-- o'quvchilarining ota-ona telefon raqamlarini kiritadi. Admin hamma sinfga kiritadi.
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing. Qayta ishga tushirish xavfsiz.

create or replace function public.set_parent_phone(p_id text, p_phone text) returns void
language plpgsql security definer set search_path = public as $$
declare v public.students.id%type := p_id; c record; ph text := btrim(coalesce(p_phone, '')); n int;
begin
  select cl.id, cl.kind, cl.grp, cl.subject into c
    from public.students s join public.classes cl on cl.id = s.class_id where s.id = v;
  if c.id is null then raise exception 'O''quvchi topilmadi'; end if;
  if not (public.yk_role() = 'admin'
          or (c.kind is distinct from 'rep' and coalesce(c.grp, '') = '' and coalesce(c.subject, '') !~* '^(arab|koreys)'
              and (exists (select 1 from public.teacher_classes t where t.user_id = auth.uid() and t.class_id = c.id and t.role = 'rahbar')
                   or exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'teacher' and p.class_id = c.id)))) then
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
