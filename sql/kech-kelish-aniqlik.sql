-- KECH KELGANLAR RO'YXATI ANIQLIGI (faqat o'qiydi, hech narsa o'zgarmaydi).
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing. Turniket ma'lumoti bor eng oxirgi kun tekshiriladi.
-- Boshqa kunni tekshirish uchun pastdagi "kun" qatoridagi sanani o'zgartiring, masalan: select date '2026-10-27'

with kun as (
  select coalesce(max((ts at time zone 'Asia/Tashkent')::date), current_date) as d from public.turnstile_events
  -- select date '2026-10-27' as d
),
ev as (
  select e.*, (e.ts at time zone 'Asia/Tashkent') as lt from public.turnstile_events e, kun
   where (e.ts at time zone 'Asia/Tashkent')::date = kun.d
),
tk as (  -- turniket bo'yicha hisoblanadigan o'quvchilar (3–10-sinf, ismi yozilgan)
  select s.id, s.ext_id, d.att, d.arrived_at
    from public.students s
    join kun on true
    left join public.daily_scores d on d.student_id = s.id and d.day = kun.d
   where public.yk_tk_class(s.class_id) and coalesce(btrim(s.full_name), '') <> ''
),
rep as (
  select 1 n, 'Kun' tur, (select to_char(d, 'DD.MM.YYYY') from kun) qiymat, '' izoh
  union all
  -- 1. Qurilma soati: o'tish vaqti (qurilma soati) va serverga kelgan vaqt farqi. Eng kichik farq ~0–30 soniya bo'lishi kerak.
  select 2, 'Qurilma soati: ' || door,
         case when min(extract(epoch from created_at - ts)) < -60 then '❌ ' || round(-min(extract(epoch from created_at - ts)) / 60) || ' daqiqa OLDINDA'
              when min(extract(epoch from created_at - ts)) > 300 then '⚠️ ' || round(min(extract(epoch from created_at - ts)) / 60) || ' daqiqa orqada yoki ko''prik kechikkan'
              else '✅ to''g''ri (farq ' || round(min(extract(epoch from created_at - ts))) || ' soniya)' end,
         'qurilma soati noto''g''ri bo''lsa, kelish vaqti ham shuncha xato bo''ladi'
    from ev group by door
  union all
  select 3, 'Ertalabki o''tishlar (09:30 gacha)', count(*)::text, count(distinct emp_no) || ' ta shaxs' from ev where lt::time <= time '09:30'
  union all
  select 4, 'Bog''lanmagan shaxslar (09:30 gacha)',
         case when count(distinct emp_no) = 0 then '✅ 0' else '⚠️ ' || count(distinct emp_no) end,
         'o''qituvchilar, xodimlar yoki platformaga hali bog''lanmagan o''quvchilar — ro''yxatga kirmaydi'
    from ev where lt::time <= time '09:30' and student_id is null
  union all
  select 5, 'Turniket hisoblaydigan o''quvchilar (3–10-sinf)', count(*)::text, 'ismi yozilganlar' from tk
  union all
  select 6, '…shundan turniket bilan bog''langan', count(*) filter (where coalesce(ext_id, '') <> '')::text,
         round(100.0 * count(*) filter (where coalesce(ext_id, '') <> '') / greatest(count(*), 1)) || '% — bog''lanmaganlar kech kelsa ham ro''yxatga tushmaydi' from tk
  union all
  select 7, 'Kelgan (turniketdan o''tgan vaqti bor)', count(*) filter (where arrived_at is not null)::text, 'kech kelganligi aniq hisoblanadi' from tk
  union all
  select 8, 'Kelgan, lekin vaqti yo''q (qo''lda belgilangan)',
         case when count(*) filter (where att = 1 and arrived_at is null) = 0 then '✅ 0' else '⚠️ ' || count(*) filter (where att = 1 and arrived_at is null) end,
         'turniketdan o''tmagan yoki tanilmagan — kech kelgan-kelmagani noma''lum' from tk
  union all
  select 9, 'Kech kelganlar (08:30 dan keyin)',
         count(*) filter (where (arrived_at at time zone 'Asia/Tashkent')::time > time '08:30')::text, 'platformadagi ro''yxat' from tk
  union all
  select 10, 'ANIQLIK (qamrov)',
         round(100.0 * count(*) filter (where arrived_at is not null) / greatest(count(*) filter (where att = 1 or arrived_at is not null), 1)) || '%',
         'kelgan o''quvchilarning qanchasi turniket vaqti bilan qayd etilgan' from tk
)
select tur, qiymat, izoh from rep order by n, tur;
