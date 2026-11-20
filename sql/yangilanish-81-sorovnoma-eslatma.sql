-- Yangilanish 81: «Ota-onaga yaxshilik» haftalik so'rovnomasi — ota-onalarga avtomatik eslatma (bildirishnoma).
--   * Juma 18:00 — so'rovnoma ochildi (hali javob bermagan barcha ota-onalarga).
--   * Yakshanba 18:00 — «bugun yopiladi» (faqat hali javob bermaganlarga).
--   Faqat ilovada bildirishnomani yoqqan ota-onalarga boradi; 1–10-sinflar (asosiy sinflar).
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing (loyiha: YUKSALISH-REYTING). Qayta ishga tushirish xavfsiz.

alter table public.push_queue drop constraint if exists push_queue_kind_check;
alter table public.push_queue add constraint push_queue_kind_check
  check (kind in ('keldi', 'ketdi', 'kelmadi', 'test', 'yomon', 'yaxshi', 'savol', 'javob', 'eslatma', 'tk', 'sorov'));

create or replace function public.yk_week_remind(p_last boolean) returns int
language plpgsql security definer set search_path = public as $$
declare d date := (now() at time zone 'Asia/Tashkent')::date; w date := date_trunc('week', d)::date; n int;
begin
  if extract(isodow from d) < 5 then return 0; end if;  -- so'rovnoma juma–yakshanba ochiq
  insert into public.push_queue (user_id, kind, student_id, title, body)
  select p.id, 'sorov', s.id::text,
         case when p_last then '⏰ So''rovnoma bugun yopiladi' else '📝 Haftalik so''rovnoma ochildi' end,
         case when p_last
              then s.full_name || ': «Ota-onaga yaxshilik» so''rovnomasiga hali javob bermadingiz. '
                   || 'Bugun javob bering — javob bo''lmasa, bu bo''limdan 0 ball qo''yiladi.'
              else s.full_name || ': shu hafta farzandingiz sizga qanday yaxshilik qildi? '
                   || 'Ilovani ochib, 1 daqiqada javob bering (yakshanbagacha ochiq).' end
    from public.profiles p
    join public.students s on s.id = p.student_id
   where p.role = 'parent'
     and public.yk_g2(s.class_id)
     and exists (select 1 from public.push_subs ps where ps.user_id = p.id)
     and not exists (select 1 from public.parent_week pw where pw.student_id = s.id and pw.week = w)
  on conflict do nothing;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.yk_week_remind(boolean) from public, anon, authenticated;

-- Jadval: juma 18:00 va yakshanba 18:00 (Toshkent) = 13:00 UTC
do $$ begin perform cron.unschedule('yk-sorov-juma'); exception when others then null; end $$;
do $$ begin perform cron.unschedule('yk-sorov-yakshanba'); exception when others then null; end $$;
do $$ begin
  perform cron.schedule('yk-sorov-juma', '0 13 * * 5', 'select public.yk_week_remind(false)');
  perform cron.schedule('yk-sorov-yakshanba', '0 13 * * 0', 'select public.yk_week_remind(true)');
exception when others then raise notice 'pg_cron topilmadi — jadval qo''yilmadi: %', sqlerrm;
end $$;

notify pgrst, 'reload schema';

-- Tekshiruv: eslatma boradigan ota-onalar soni (bildirishnoma yoqqan, bu hafta hali javob bermagan)
select count(*) as "eslatma boradi",
       (select count(*) from cron.job where jobname in ('yk-sorov-juma', 'yk-sorov-yakshanba')) as "jadval (2 bo'lishi kerak)"
  from public.profiles p join public.students s on s.id = p.student_id
 where p.role = 'parent' and public.yk_g2(s.class_id)
   and exists (select 1 from public.push_subs ps where ps.user_id = p.id)
   and not exists (select 1 from public.parent_week pw where pw.student_id = s.id
                    and pw.week = date_trunc('week', (now() at time zone 'Asia/Tashkent')::date)::date);
