-- Yangilanish 95: «Ota-onaga yaxshilik» haftalik so'rovnomasi — farzandi shu maktabda o'qiydigan USTOZ uchun ham chiqadi
--   (juma–yakshanba kunlari, ustozning «Farzandlarim» bo'limida). Javob farzandning asosiy sinf yozuviga saqlanadi.
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing (loyiha: YUKSALISH-REYTING). Avval 86 va 94 ishga tushgan bo'lsin. Qayta ishga tushirish xavfsiz.

create or replace function public.parent_week_all() returns jsonb
language sql stable security definer set search_path = public as $$
  with t as (select (now() at time zone 'Asia/Tashkent')::date d),
  kk as (
    select k.id::text as id, k.full_name::text as full_name, k.class_id::bigint as class_id from public.my_kids() k
    union
    select k.id, k.full_name, k.class_id from public.teacher_kids() k),
  raw as (
    select kk.id::uuid as sid, kk.full_name, kk.class_id,
           (c.kind = 'rep' or coalesce(c.grp, '') <> '' or coalesce(c.subject, '') ~* '^(arab|koreys)') as is_grp
      from kk join public.classes c on c.id = kk.class_id),
  res as (
    select coalesce(mm.id, raw.sid) as sid, coalesce(mm.full_name, raw.full_name) as name,
           coalesce(mm.class_id, raw.class_id) as class_id
      from raw left join lateral (
        select m.id, m.full_name, m.class_id from public.students m join public.classes mc on mc.id = m.class_id
         where raw.is_grp and mc.kind is distinct from 'rep' and coalesce(mc.grp, '') = '' and coalesce(mc.subject, '') !~* '^(arab|koreys)'
           and (public.yk_norm3(m.full_name) = public.yk_norm3(raw.full_name)
                or exists (select 1 from public.student_links l where l.gid = raw.sid::text and l.kid = m.id::text))
         limit 1) mm on true),
  uniq as (select distinct sid, name, class_id from res where public.yk_g2(class_id))
  select jsonb_build_object(
    'open', (select extract(isodow from d) >= 5 from t),
    'week', (select date_trunc('week', d)::date from t),
    'kids', coalesce((select jsonb_agg(jsonb_build_object(
        'sid', u.sid::text, 'name', u.name,
        'answered', (select jsonb_build_object('mood', pw.mood, 'note', pw.note)
                       from public.parent_week pw where pw.student_id = u.sid
                        and pw.week = (select date_trunc('week', d)::date from t))
      ) order by u.name) from uniq u), '[]'::jsonb));
$$;
revoke all on function public.parent_week_all() from public, anon;
grant execute on function public.parent_week_all() to authenticated;

-- Javob berish: ota-ona yoki (farzandi bor) ustoz. Kuzatuvchi javob bera olmaydi.
create or replace function public.parent_week_submit(p_sid text, p_mood int, p_note text, p_honest boolean) returns void
language plpgsql security definer set search_path = public as $$
declare d date := (now() at time zone 'Asia/Tashkent')::date; w date := date_trunc('week', d)::date; sid public.students.id%type; cid bigint;
begin
  if public.yk_role() not in ('parent', 'teacher') or public.yk_obs() then raise exception 'Faqat ota-ona' using errcode = '42501'; end if;
  if not public.yk_is_my_kid(p_sid) then raise exception 'Bu sizning farzandingiz emas' using errcode = '42501'; end if;
  if extract(isodow from d) < 5 then raise exception 'So''rovnoma juma kuni ochiladi'; end if;
  if p_mood not between 0 and 2 then raise exception 'Javobni tanlang'; end if;
  if p_honest is not true then raise exception 'Vijdonan belgilaganingizni tasdiqlang'; end if;
  select s.id, s.class_id into sid, cid from public.students s where s.id::text = p_sid;
  if sid is null or not public.yk_g2(cid) then raise exception 'So''rovnoma faqat asosiy sinflar (1–10) uchun'; end if;
  insert into public.parent_week (student_id, week, mood, score, note, honest)
  values (sid, w, p_mood, case p_mood when 2 then 10 when 1 then 5 else 0 end, nullif(btrim(left(p_note, 500)), ''), true)
  on conflict do nothing;
  if not found then raise exception 'Bu hafta uchun javob allaqachon berilgan'; end if;
  update public.daily_scores set updated_at = now() where student_id = sid and day between w and w + 6;
end $$;
revoke all on function public.parent_week_submit(text, int, text, boolean) from public, anon;
grant execute on function public.parent_week_submit(text, int, text, boolean) to authenticated;

notify pgrst, 'reload schema';
select 'Tayyor — ustoz-ota uchun so''rovnoma yoqildi' as natija;
