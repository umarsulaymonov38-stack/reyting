-- Yangilanish 86: Haftalik so'rovnoma — ota-ona akkaunti guruh nusxasiga ulangan bo'lsa ham,
--   so'rovnoma ASOSIY SINF farzaniga yo'naltiriladi (shunda so'rovnoma to'g'ri ko'rinadi va javob asosiy farzandga yoziladi).
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing (loyiha: YUKSALISH-REYTING). Qayta ishga tushirish xavfsiz.

create or replace function public.parent_week_status() returns jsonb
language sql stable security definer set search_path = public as $$
  with raw as (
    select s.id, s.full_name, s.class_id,
           (c.kind = 'rep' or coalesce(c.grp, '') <> '' or coalesce(c.subject, '') ~* '^(arab|koreys)') as is_grp
      from public.profiles p join public.students s on s.id = p.student_id
      join public.classes c on c.id = s.class_id
     where p.id = auth.uid() and public.yk_role() = 'parent'),
  k as (
    select coalesce(mm.id, raw.id) as id,
           coalesce(mm.full_name, raw.full_name) as full_name,
           coalesce(mm.class_id, raw.class_id) as class_id
      from raw
      left join lateral (
        select m.id, m.full_name, m.class_id
          from public.students m join public.classes mc on mc.id = m.class_id
         where raw.is_grp
           and mc.kind is distinct from 'rep' and coalesce(mc.grp, '') = '' and coalesce(mc.subject, '') !~* '^(arab|koreys)'
           and (public.yk_norm3(m.full_name) = public.yk_norm3(raw.full_name)
                or exists (select 1 from public.student_links l where l.gid = raw.id::text and l.kid = m.id::text))
         limit 1
      ) mm on true),
  t as (select (now() at time zone 'Asia/Tashkent')::date d)
  select jsonb_build_object(
           'ok', public.yk_g2(k.class_id),
           'open', extract(isodow from t.d) >= 5,
           'week', date_trunc('week', t.d)::date,
           'sid', k.id::text, 'name', k.full_name,
           'ans', (select jsonb_build_object('mood', pw.mood, 'note', pw.note, 'at', pw.created_at)
                     from public.parent_week pw where pw.student_id = k.id and pw.week = date_trunc('week', t.d)::date))
    from k, t
$$;
revoke all on function public.parent_week_status() from public, anon;
grant execute on function public.parent_week_status() to authenticated;

notify pgrst, 'reload schema';
select 'Tayyor — so''rovnoma asosiy farzandga yo''naltiriladi' as natija;
