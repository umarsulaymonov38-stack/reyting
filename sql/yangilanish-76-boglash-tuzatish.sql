-- Yangilanish 76: yangilanish-75 natijasini ko'rib chiqish bo'yicha tuzatishlar.
--   1) Noto'g'ri bog'langan 2 ta o'quvchi bekor qilinadi (Timur Ustoz (IELTS 6.0): «Nurullayev Muhammad Ali», «Sirojiddinova Sangina»).
--   2) «Shubhali» bo'lib, aslida bir xil bola ekani ko'rinib turgan 26 ta moslik tasdiqlanadi.
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing (loyiha: YUKSALISH-REYTING). Avval 75 ishga tushgan bo'lsin.
-- Qayta ishga tushirish xavfsiz.

-- 1. Noto'g'ri bog'lanishlarni bekor qilish
delete from public.student_links sl
 using public.students g, public.classes c
 where sl.gid = g.id::text and c.id = g.class_id
   and c.name = 'Timur Ustoz (IELTS 6.0)'
   and regexp_replace(btrim(g.full_name), '\s+', ' ', 'g') in ('Nurullayev Muhammad Ali', 'Sirojiddinova Sangina');

-- 2. Tasdiqlangan mosliklar
select x.guruh, x.guruhdagi_ism, x.asosiy_sinfdagi_ism, public.yk_link_one(x.guruh, x.guruhdagi_ism, x.asosiy_sinfdagi_ism) as natija
  from (
  select '3-sinf Arab tili 1-guruh', 'Joraqulov Muhammad Ali', 'Jòraqulov Muhammadali' union all
  select '3-sinf Arab tili 3-guruh', 'Xayrullayev Nodir', 'Xayrulloyev Nodirjon' union all
  select '3-sinf Koreys tili', 'Nurillayeva Sojida', 'Nurulloyeva Sojidaxon' union all
  select '3-sinf Koreys tili', 'Rahimjonova Soliha', 'Raximjonova Solehabonu' union all
  select '4-sinf Arab tili 2-guruh', 'ASLAMDIJANOV ISMOIL', 'Aslamdjonov Ismoiljon' union all
  select '4-sinf Arab tili 3-guruh', 'Nurullayev Fozilbek', 'Nurilloyev Fozil' union all
  select '4-sinf Koreys tili', 'Farhodjonov Faridun', 'Farxodov Faridun' union all
  select '4-sinf Koreys tili', 'Toshmatov Murodjon', 'Tashmanov Murodjon' union all
  select '5-6-sinflar Koreys tili', 'Abdurashidova Shaxnura', 'Abdurashitova Shahura' union all
  select '5-6-sinflar Koreys tili', 'Sapoyeva Shaxinabonu', 'Sabboyeva Shaxina' union all
  select '5-sinf Matematika Betta', 'Sapoyeva Shaxinabonu', 'Sabboyeva Shaxina' union all
  select '5-Sinf Ingliz tili Betta', 'Umida', 'Fayzullayeva Umida' union all
  select '6-Sinf Ingliz tili Gamma', 'Mamadnazarov Shaxzodjon', 'Mamatnazarov Shaxzod' union all
  select '6-sinf Matematika Alfa', 'Musoyev Jasur', 'Musayev Jasurbek' union all
  select '7-sinf A2 guruh', 'Chingizov Aslam', 'Chengizov Aslambek' union all
  select '7-sinf Arab tili 2-guruh', 'Chingizov Aslam', 'Chengizov Aslambek' union all
  select '8-sinf Matematika Alfa', 'Obidova Latifa', 'Abidova Latifaxon' union all
  select 'Repetitor: BIOLOGIYA', 'Obidova Latifa', 'Abidova Latifaxon' union all
  select '8-sinf Matematika Betta', 'Abdulloyev Diyorbek', 'Abdullayev Diyorjon' union all
  select 'Feruz Ustoz (8-9-10-sinflar)', 'Abdulloyev Diyor', 'Abdullayev Diyorjon' union all
  select 'Repetitor: ONA TILI', 'Abdullah Diyor', 'Abdullayev Diyorjon' union all
  select 'Repetitor: KIMYO', 'Rabimkulov Feruz', 'Rabbimqulov Firuz' union all
  select 'Repetitor: KIMYO', 'Xudoyberdiyev Yusufjon', 'Xudayberdiyev Yusuf' union all
  select 'Repetitor: MATEMATIKA', 'Ilibayova Dilafruz', 'Eliboyeva Dilafruz' union all
  select 'Repetitor: ONA TILI', 'Batıyorov Diyorbek', 'Baxtiyorov Diyorjon' union all
  select 'Repetitor: ONA TILI', 'Nematillayev Sohib', 'Nematullay Sohibxon'
  ) as x(guruh, guruhdagi_ism, asosiy_sinfdagi_ism);
