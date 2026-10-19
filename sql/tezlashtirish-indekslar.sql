-- Tezlashtirish: 1000 foydalanuvchi bir vaqtda kirganda so'rovlar tez ishlashi uchun indekslar.
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing. Bir necha marta ishga tushirish xavfsiz
-- (mavjud indeks qayta yaratilmaydi, bazada yo'q jadval (masalan sms_log) o'tkazib yuboriladi,
-- hech qanday ma'lumot o'zgarmaydi yoki o'chmaydi).

do $$
declare
  ix text[];
begin
  foreach ix slice 1 in array array[
    -- [indeks nomi, jadval, ustunlar]
    -- Kunlik ballar: sana bo'yicha (kelmaganlar, sinflar reytingi) va o'quvchi+oy bo'yicha (ota-ona sahifasi)
    ['daily_scores_day_idx',          'daily_scores',    'day'],
    ['daily_scores_student_day_idx',  'daily_scores',    'student_id, day'],
    -- Repetitor jadvali
    ['rep_daily_day_idx',             'rep_daily',       'day'],
    ['rep_daily_student_day_idx',     'rep_daily',       'student_id, day'],
    -- O'quvchilar sinf bo'yicha tartibda
    ['students_class_slot_idx',       'students',        'class_id, slot'],
    -- To'lovlar: oy bo'yicha hisob (to'lagan/to'lamagan)
    ['payments_student_month_idx',    'payments',        'student_id, month'],
    ['payments_month_paid_idx',       'payments',        'month, paid'],
    -- O'qituvchi ↔ sinf
    ['teacher_classes_user_idx',      'teacher_classes', 'user_id'],
    ['teacher_classes_class_idx',     'teacher_classes', 'class_id'],
    -- Ota-ona telefoni bo'yicha qidiruv (ro'yxatdan o'tish) va o'quvchi bo'yicha
    ['student_private_student_idx',   'student_private', 'student_id'],
    ['student_private_phone_idx',     'student_private', 'parent_phone'],
    -- Profil → farzand
    ['profiles_student_idx',          'profiles',        'student_id'],
    -- Taomnoma, rasmlar, SMS jurnali
    ['menu_day_idx',                  'menu',            'day'],
    ['class_images_class_time_idx',   'class_images',    'class_id, created_at desc'],
    ['sms_log_month_status_idx',      'sms_log',         'month, status']
  ] loop
    if to_regclass('public.' || ix[2]) is null then
      raise notice 'O''tkazib yuborildi: % jadvali yo''q', ix[2];
      continue;
    end if;
    begin
      execute format('create index if not exists %I on public.%I (%s)', ix[1], ix[2], ix[3]);
    exception when undefined_column then
      raise notice 'O''tkazib yuborildi: % (%) ustuni yo''q', ix[2], ix[3];
    end;
  end loop;
end $$;

-- Statistikani yangilash (Postgres yangi indekslardan to'g'ri foydalanishi uchun)
analyze;
