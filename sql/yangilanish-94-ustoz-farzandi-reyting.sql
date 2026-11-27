-- Yangilanish 94: Farzandi shu maktabda o'qiydigan ustoz — farzandlarining REYTINGI va dars jadvalini ham ko'radi;
--   farzandlarni admin QO'LDA bog'lashi mumkin (telefon raqami mos kelmasa ham).
--   Ustoz o'z sinfini boshqaradi (baho qo'yadi) va shu bilan birga «Farzandlarim» orqali farzandlarini kuzatadi.
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing (loyiha: YUKSALISH-REYTING). Avval 73 va 83 ishga tushgan bo'lsin. Qayta ishga tushirish xavfsiz.

create table if not exists public.teacher_kid_links (
  teacher_id uuid not null, student_id uuid not null, created_at timestamptz not null default now(),
  primary key (teacher_id, student_id)
);
alter table public.teacher_kid_links enable row level security;
revoke all on public.teacher_kid_links from anon, authenticated;

-- Ustozning farzandlari: ota-ona telefoni ustoz raqamiga mos YOKI admin qo'lda bog'lagan
create or replace function public.teacher_kids()
returns table (id text, full_name text, class_id bigint, class_name text)
language sql stable security definer set search_path = public, auth as $$
  with me as (
    select right(regexp_replace(coalesce(p.phone, ''), '\D', '', 'g'), 9) as ph1,
           substring(u.email from '^o(\d{9})@') as ph2
      from public.profiles p join auth.users u on u.id = p.id
     where p.id = auth.uid() and p.role = 'teacher')
  select s.id::text, s.full_name::text, s.class_id::bigint, c.name::text
    from public.students s join public.classes c on c.id = s.class_id
   where c.kind is distinct from 'rep' and coalesce(c.grp, '') = '' and coalesce(c.subject, '') !~* '^(arab|koreys)'
     and coalesce(btrim(s.full_name), '') <> ''
     and (exists (select 1 from public.teacher_kid_links l where l.teacher_id = auth.uid() and l.student_id = s.id)
          or exists (select 1 from public.student_private sp, me
                      where sp.student_id = s.id
                        and length(right(regexp_replace(coalesce(sp.parent_phone, ''), '\D', '', 'g'), 9)) = 9
                        and right(regexp_replace(coalesce(sp.parent_phone, ''), '\D', '', 'g'), 9) in (me.ph1, me.ph2)))
   order by s.full_name
$$;
revoke all on function public.teacher_kids() from public, anon;
grant execute on function public.teacher_kids() to authenticated;

-- Reyting (sinfdagi/maktabdagi o'rin, fanlar bo'yicha) ustozga ham farzandi uchun ko'rinsin
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
  or exists (select 1 from public.teacher_kids() k where k.id = p_sid)
$$;
revoke all on function public.yk_is_my_kid(text) from public, anon;
grant execute on function public.yk_is_my_kid(text) to authenticated;

-- Admin: ustozning farzandlari ro'yxati (qo'lda bog'langan va telefon bo'yicha topilgan)
create or replace function public.teacher_kids_of(p_teacher uuid)
returns table (student_id text, full_name text, class_name text, via text)
language plpgsql stable security definer set search_path = public, auth as $$
declare ph text;
begin
  if public.yk_role() is distinct from 'admin' then raise exception 'Faqat bosh admin' using errcode = '42501'; end if;
  select right(regexp_replace(coalesce(p.phone, ''), '\D', '', 'g'), 9) into ph from public.profiles p where p.id = p_teacher;
  return query
  select s.id::text, s.full_name::text, c.name::text,
         case when exists (select 1 from public.teacher_kid_links l where l.teacher_id = p_teacher and l.student_id = s.id) then 'qo''lda' else 'telefon' end
    from public.students s join public.classes c on c.id = s.class_id
   where c.kind is distinct from 'rep' and coalesce(c.grp, '') = '' and coalesce(btrim(s.full_name), '') <> ''
     and (exists (select 1 from public.teacher_kid_links l where l.teacher_id = p_teacher and l.student_id = s.id)
          or (length(coalesce(ph, '')) = 9 and exists (select 1 from public.student_private sp where sp.student_id = s.id
               and right(regexp_replace(coalesce(sp.parent_phone, ''), '\D', '', 'g'), 9) = ph)))
   order by s.full_name;
end $$;
revoke all on function public.teacher_kids_of(uuid) from public, anon;
grant execute on function public.teacher_kids_of(uuid) to authenticated;

create or replace function public.link_teacher_kid(p_teacher uuid, p_student uuid, p_on boolean default true) returns void
language plpgsql security definer set search_path = public as $$
begin
  if public.yk_role() is distinct from 'admin' then raise exception 'Faqat bosh admin' using errcode = '42501'; end if;
  if p_on then
    insert into public.teacher_kid_links (teacher_id, student_id) values (p_teacher, p_student) on conflict do nothing;
  else
    delete from public.teacher_kid_links where teacher_id = p_teacher and student_id = p_student;
  end if;
end $$;
revoke all on function public.link_teacher_kid(uuid, uuid, boolean) from public, anon;
grant execute on function public.link_teacher_kid(uuid, uuid, boolean) to authenticated;

notify pgrst, 'reload schema';

-- Tekshiruv: Zebo Sherqulova va uning farzandlari (telefon bo'yicha topilganlar)
select p.full_name as ustoz, p.phone as ustoz_telefoni,
       (select string_agg(s.full_name || ' (' || c.name || ')', ', ')
          from public.student_private sp join public.students s on s.id = sp.student_id join public.classes c on c.id = s.class_id
         where right(regexp_replace(coalesce(sp.parent_phone, ''), '\D', '', 'g'), 9) = right(regexp_replace(coalesce(p.phone, ''), '\D', '', 'g'), 9)) as farzandlari
  from public.profiles p where p.role = 'teacher' and p.full_name ilike '%Sherqulova%';
