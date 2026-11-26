-- Yangilanish 89: To'lov qilmaganlarga JIDDIY OGOHLANTIRISH (ilovada bildirishnoma, bepul).
--   Admin to'lov bo'limidagi «Jiddiy ogohlantirish» tugmasini bosadi → joriy oy uchun to'lamagan
--   o'quvchilarning ota-onalariga (ilovada bildirishnomani yoqqanlarga) qat'iy ogohlantirish boradi.
--   Bitta o'quvchiga kuniga bir marta. Iyun–avgust (ta'til) va to'lov muddati (5-sana) o'tmaguncha yuborilmaydi.
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing (loyiha: YUKSALISH-REYTING). Qayta ishga tushirish xavfsiz.

alter table public.push_queue drop constraint if exists push_queue_kind_check;
alter table public.push_queue add constraint push_queue_kind_check
  check (kind in ('keldi', 'ketdi', 'kelmadi', 'test', 'yomon', 'yaxshi', 'savol', 'javob', 'eslatma', 'tk', 'sorov', 'ogoh'));

create or replace function public.pay_warn_now(p_class bigint default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare t date := (now() at time zone 'Asia/Tashkent')::date; m date := date_trunc('month', t)::date;
        due int := coalesce((select tolov_due from public.sms_config where id = 1), 5);
        late int; q int; unp int; nopush int; nm date := t + (8 - extract(isodow from t)::int);
        oy text[] := array['yanvar','fevral','mart','aprel','may','iyun','iyul','avgust','sentabr','oktabr','noyabr','dekabr'];
begin
  if public.yk_role() <> 'admin' then raise exception 'Faqat admin' using errcode = '42501'; end if;
  late := extract(day from t)::int - due;
  if extract(month from t) in (6, 7, 8) then raise exception 'Yozgi ta''til — to''lov ogohlantirishi yuborilmaydi'; end if;
  if late < 1 then raise exception 'To''lov muddati (har oyning %-sanasi) hali o''tmagan', due; end if;

  create temp table _unp on commit drop as
  select s.id, s.full_name from public.students s join public.classes cl on cl.id = s.class_id
   where cl.kind is distinct from 'rep' and coalesce(cl.grp, '') = '' and coalesce(cl.subject, '') !~* '^(arab|koreys)'
     and coalesce(btrim(s.full_name), '') <> '' and (p_class is null or s.class_id = p_class)
     and not exists (select 1 from public.payments p where p.student_id = s.id and p.month = m and p.paid);
  select count(*) into unp from _unp;

  insert into public.push_queue (user_id, kind, student_id, title, body)
  select p.id, 'ogoh', u.id::text,
         '⚠️ DIQQAT: to''lov kechikmoqda',
         u.full_name || ' uchun ' || oy[extract(month from t)::int] || ' oyi maktab to''lovi ' || late
         || ' kundan beri to''lanmagan. Shartnomaning 5.2-bandiga ko''ra, to''lov oyning ' || due || '-sanasigacha amalga oshirilmasa, maktab shartnomani bir tomonlama bekor qilish huquqiga ega. '
         || 'DIQQAT: agar to''lov ' || extract(day from nm)::int || '-' || oy[extract(month from nm)::int] || ', dushanba kunigacha amalga oshirilmasa, turniket to''lov qilmagan o''quvchini tanib o''tkazmaydi va farzandingiz dars mashg''ulotlarida qatnasha olmaydi. '
         || 'Shuningdek, ilovada farzandingiz ma''lumotlarini ko''rish cheklanishi mumkin. Iltimos, to''lovni zudlik bilan amalga oshiring yoki maktab ma''muriyati bilan bog''laning.'
  from _unp u join public.profiles p on p.student_id = u.id and p.role = 'parent'
   where exists (select 1 from public.push_subs ps where ps.user_id = p.id)
  on conflict do nothing;
  get diagnostics q = row_count;

  select count(*) into nopush from _unp u
   where not exists (select 1 from public.profiles p join public.push_subs ps on ps.user_id = p.id
                      where p.student_id = u.id and p.role = 'parent');
  return jsonb_build_object('unpaid', unp, 'queued', q, 'no_push', nopush);
end $$;
revoke all on function public.pay_warn_now(bigint) from public, anon;
grant execute on function public.pay_warn_now(bigint) to authenticated;

notify pgrst, 'reload schema';
select 'Tayyor — pay_warn_now yaratildi' as natija;
