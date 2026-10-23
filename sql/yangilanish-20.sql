-- Yangilanish 20: ko'p foydalanuvchi uchun qo'shimcha indekslar (yangi jadvallar va so'rovlar).
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing. Qayta ishga tushirish xavfsiz, ma'lumot o'zgarmaydi.

do $$
declare ix text[];
begin
  foreach ix slice 1 in array array[
    ['teacher_classes_class_role_idx', 'teacher_classes',  'class_id, role'],
    ['profiles_role_idx',              'profiles',         'role'],
    ['student_private_claimed_idx',    'student_private',  'claimed_by'],
    ['subject_scores_teacher_day_idx', 'subject_scores',   'teacher_id, day'],
    ['daily_scores_day_att_idx',       'daily_scores',     'day, att'],
    ['rep_daily_day_att_idx',          'rep_daily',        'day, att'],
    ['feedback_class_time_idx',        'feedback',         'class_id, created_at desc'],
    ['payments_month_idx',             'payments',         'month'],
    ['turnstile_events_student_idx',   'turnstile_events', 'student_id, ts desc']
  ] loop
    if to_regclass('public.' || ix[2]) is null then
      raise notice 'O''tkazib yuborildi: % jadvali yo''q', ix[2]; continue;
    end if;
    begin
      execute format('create index if not exists %I on public.%I (%s)', ix[1], ix[2], ix[3]);
    exception when undefined_column then
      raise notice 'O''tkazib yuborildi: % (%) ustuni yo''q', ix[2], ix[3];
    end;
  end loop;
end $$;

analyze;
