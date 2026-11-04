-- Yangilanish 44: 4-guruh (Ingliz tili)
--  1) «Jonibek Ustoz (A1)» va «Jonibek Ustoz (A2)» — bitta guruh: «Jonibek Ustoz (8-9-10) A1».
--     A2 guruhidagi o'quvchilar (baholari bilan birga) A1 guruhi oxiriga ko'chiriladi, A2 guruhi o'chiriladi.
--  2) «Firuz Ustoz (IELTS 7.0)» → «Mirjohon Ustoz (IELTS 7.0)» (o'quvchilar va baholar o'zgarmaydi).
--     O'qituvchini almashtirish: admin «O'qituvchilar» bo'limida Mirjohon ustozga shu guruhni biriktiradi.
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing. Qayta ishga tushirish xavfsiz.

do $$
declare a1 bigint; a2 bigint;
begin
  select id into a1 from public.classes where lower(name) in ('jonibek ustoz (a1)', 'jonibek ustoz (8-9-10) a1') order by lower(name) = 'jonibek ustoz (8-9-10) a1' desc limit 1;
  select id into a2 from public.classes where lower(name) = 'jonibek ustoz (a2)' limit 1;
  if a1 is null and a2 is not null then a1 := a2; a2 := null; end if;
  if a1 is null then raise notice 'Jonibek Ustoz guruhlari topilmadi'; return; end if;

  if a2 is not null and a2 <> a1 then
    -- A2 o'quvchilari (ismi, bahosi yoki ota-ona telefoni bor) A1 ga ko'chadi
    update public.students s set class_id = a1, slot = 1000 + s.slot
     where s.class_id = a2 and (coalesce(btrim(s.full_name), '') <> ''
           or exists (select 1 from public.daily_scores d where d.student_id = s.id)
           or exists (select 1 from public.student_private p where p.student_id = s.id and (p.claimed_by is not null or coalesce(p.parent_phone, '') <> '')));
    -- tartib raqamlari: avval A1 ning o'zi, keyin A2 dan kelganlar, oxirida bo'sh joylar
    with o as (
      select s.id, row_number() over (order by (coalesce(btrim(s.full_name), '') = '') , (s.slot >= 1000), s.slot) as n
        from public.students s where s.class_id = a1)
    update public.students s set slot = o.n + 100000 from o where s.id = o.id;
    update public.students set slot = slot - 100000 where class_id = a1 and slot > 100000;
    -- o'qituvchilar: A2 ga biriktirilganlar A1 ga o'tadi (takrorlanmasdan)
    insert into public.teacher_classes (user_id, class_id, role)
    select t.user_id, a1, t.role from public.teacher_classes t
     where t.class_id = a2 and not exists (select 1 from public.teacher_classes x where x.user_id = t.user_id and x.class_id = a1);
    delete from public.teacher_classes where class_id = a2;
    -- A2 da qolgan bo'sh joylar va guruhning o'zi
    delete from public.student_private where student_id in (select id from public.students where class_id = a2);
    delete from public.students where class_id = a2;
    delete from public.classes where id = a2;
  end if;
  update public.classes set name = 'Jonibek Ustoz (8-9-10) A1', grp = 'A1' where id = a1;
end $$;

update public.classes set name = 'Mirjohon Ustoz (IELTS 7.0)' where lower(name) = 'firuz ustoz (ielts 7.0)';

notify pgrst, 'reload schema';

select c.name as guruh,
       (select count(*) from public.students s where s.class_id = c.id and coalesce(btrim(s.full_name), '') <> '') as "o'quvchi",
       (select count(*) from public.students s where s.class_id = c.id) as "jami joy",
       coalesce((select string_agg(p.full_name || case t.role when 'rahbar' then ' (sinf rahbari)' else ' (fan)' end, ', ')
                   from public.teacher_classes t join public.profiles p on p.id = t.user_id where t.class_id = c.id), '—') as "biriktirilgan o'qituvchi"
  from public.classes c where c.subject = 'Ingliz tili' and coalesce(c.grp, '') <> '' order by c.name;
