-- Tezlashtirish: 1000 foydalanuvchi bir vaqtda kirganda so'rovlar tez ishlashi uchun indekslar.
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing. Bir necha marta ishga tushirish xavfsiz
-- (IF NOT EXISTS: mavjud indeks qayta yaratilmaydi, hech qanday ma'lumot o'zgarmaydi yoki o'chmaydi).

-- Kunlik ballar: sana bo'yicha (kelmaganlar, sinflar reytingi) va o'quvchi+oy bo'yicha (ota-ona sahifasi)
create index if not exists daily_scores_day_idx         on public.daily_scores (day);
create index if not exists daily_scores_student_day_idx on public.daily_scores (student_id, day);

-- Repetitor jadvali
create index if not exists rep_daily_day_idx         on public.rep_daily (day);
create index if not exists rep_daily_student_day_idx on public.rep_daily (student_id, day);

-- O'quvchilar sinf bo'yicha tartibda
create index if not exists students_class_slot_idx on public.students (class_id, slot);

-- To'lovlar: oy bo'yicha hisob (to'lagan/to'lamagan)
create index if not exists payments_student_month_idx on public.payments (student_id, month);
create index if not exists payments_month_paid_idx    on public.payments (month, paid);

-- O'qituvchi ↔ sinf
create index if not exists teacher_classes_user_idx  on public.teacher_classes (user_id);
create index if not exists teacher_classes_class_idx on public.teacher_classes (class_id);

-- Ota-ona telefoni bo'yicha qidiruv (ro'yxatdan o'tish) va o'quvchi bo'yicha
create index if not exists student_private_student_idx on public.student_private (student_id);
create index if not exists student_private_phone_idx   on public.student_private (parent_phone);

-- Profil → farzand
create index if not exists profiles_student_idx on public.profiles (student_id);

-- Taomnoma, rasmlar, SMS jurnali
create index if not exists menu_day_idx                on public.menu (day);
create index if not exists class_images_class_time_idx on public.class_images (class_id, created_at desc);
create index if not exists sms_log_month_status_idx    on public.sms_log (month, status);

-- Statistikani yangilash (Postgres yangi indekslardan to'g'ri foydalanishi uchun)
analyze;
