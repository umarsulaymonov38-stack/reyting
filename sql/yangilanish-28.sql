-- Yangilanish 28: 4-guruh (Ingliz tili) — 8–10-sinflar uchun o'qituvchilar bo'yicha guruhlar.
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing. Qayta ishga tushirish xavfsiz.
--  1) Yangi guruhlar (har biri 18 o'quvchilik, 8–10-sinf o'quvchilari aralash bo'lishi mumkin):
--     Firuz Ustoz (A2), Jonibek Ustoz (A1), Jonibek Ustoz (A2), Sevinch Ustoz (B1), Sevinch Ustoz (CEFR),
--     Mutabar Ustoz (CEFR), Timur Ustoz (IELTS 6.0), Firuz Ustoz (IELTS 7.0)
--  2) Eski 8–10-sinf Ingliz tili guruhlari (A1…C1, IELTS, Alfa/Betta/Gamma): BO'SH bo'lsa o'chiriladi,
--     ichida o'quvchi bo'lsa — saqlab qolinadi (natijada ko'rsatiladi).
--  3) O'qituvchilar AVTOMATIK BIRIKTIRILMAYDI — natijada mos keladigan akkauntlar ko'rsatiladi,
--     admin "O'qituvchilar" bo'limida o'zi biriktiradi (vazifasi: Sinf rahbari).

drop table if exists pg_temp.yk_eng;
create temp table yk_eng (name text, lvl text, ustoz text);
insert into yk_eng values
  ('Firuz Ustoz (A2)',        'A2',        'firuz'),
  ('Jonibek Ustoz (A1)',      'A1',        'jonibek'),
  ('Jonibek Ustoz (A2)',      'A2',        'jonibek'),
  ('Sevinch Ustoz (B1)',      'B1',        'sevinch'),
  ('Sevinch Ustoz (CEFR)',    'CEFR',      'sevinch'),
  ('Mutabar Ustoz (CEFR)',    'CEFR',      'mutabar'),
  ('Timur Ustoz (IELTS 6.0)', 'IELTS 6.0', 'timur'),
  ('Firuz Ustoz (IELTS 7.0)', 'IELTS 7.0', 'firuz');

do $$
declare r record; cid bigint; cid_auto boolean; used boolean;
begin
  select column_default is not null or is_identity = 'YES' into cid_auto from information_schema.columns
   where table_schema = 'public' and table_name = 'classes' and column_name = 'id';

  -- 1. Yangi guruhlar
  for r in select * from yk_eng loop
    select id into cid from public.classes where lower(name) = lower(r.name) limit 1;
    if cid is null then
      if cid_auto then
        insert into public.classes (name, grade, grp, subject) values (r.name, null, r.lvl, 'Ingliz tili') returning id into cid;
      else
        insert into public.classes (id, name, grade, grp, subject)
        values ((select coalesce(max(id), 0) + 1 from public.classes), r.name, null, r.lvl, 'Ingliz tili') returning id into cid;
      end if;
    end if;
    insert into public.students (class_id, slot, full_name)
    select cid, s, '' from generate_series(1, 18) s
     where not exists (select 1 from public.students x where x.class_id = cid and x.slot = s);
    insert into public.student_private (student_id, code)
    select x.id, upper(substr(md5(random()::text || x.id::text), 1, 6)) from public.students x
     where x.class_id = cid and not exists (select 1 from public.student_private p where p.student_id = x.id);
  end loop;

  -- 2. Eski 8–10-sinf Ingliz tili guruhlari
  for r in select c.id, c.name from public.classes c
            where c.subject = 'Ingliz tili' and coalesce(c.grade, 0) between 8 and 10 and coalesce(c.grp, '') <> ''
              and lower(c.name) not in (select lower(name) from yk_eng) loop
    used := exists (select 1 from public.students s where s.class_id = r.id and coalesce(btrim(s.full_name), '') <> '')
         or exists (select 1 from public.daily_scores d join public.students s on s.id = d.student_id where s.class_id = r.id)
         or exists (select 1 from public.student_private p join public.students s on s.id = p.student_id
                     where s.class_id = r.id and (p.claimed_by is not null or coalesce(p.parent_phone, '') <> ''));
    if used then
      raise notice 'SAQLANDI (ichida o''quvchilar bor): %', r.name;
    else
      begin
        delete from public.teacher_classes where class_id = r.id;
        delete from public.student_private where student_id in (select id from public.students where class_id = r.id);
        delete from public.students where class_id = r.id;
        delete from public.classes where id = r.id;
      exception when others then
        raise notice 'SAQLANDI (bog''liq ma''lumot bor): %', r.name;
      end;
    end if;
  end loop;
end $$;

notify pgrst, 'reload schema';

-- Natija: yangi guruhlar, saqlab qolingan eskilari va mos kelishi mumkin bo'lgan o'qituvchi akkauntlari
select c.name as guruh,
       case when e.name is not null then '✅ yangi' else '⚠️ eski (ichida o''quvchi bor)' end as holat,
       coalesce((select string_agg(p.full_name, ', ') from public.profiles p
                  where e.ustoz is not null and p.role = 'teacher'
                    and lower(p.full_name) ~ ('(^|\s)' || e.ustoz || '($|\s)')), '') as "mos o'qituvchi akkaunti",
       coalesce((select string_agg(p.full_name || case t.role when 'rahbar' then ' (sinf rahbari)' else ' (fan)' end, ', ')
                  from public.teacher_classes t join public.profiles p on p.id = t.user_id where t.class_id = c.id), '—') as "biriktirilgan"
  from public.classes c left join yk_eng e on lower(e.name) = lower(c.name)
 where c.subject = 'Ingliz tili' and (e.name is not null or coalesce(c.grade, 0) between 8 and 10)
 order by e.name is null, c.name;
