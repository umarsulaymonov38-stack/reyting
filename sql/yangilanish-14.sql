-- Yangilanish 14: o'qituvchi sinfga qo'shilganda avtomatik "Fan o'qituvchisi" bo'lsin (sinf rahbari faqat admin tanlasa).
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing. Qayta ishga tushirish xavfsiz.

alter table public.teacher_classes alter column role set default 'fan';
update public.teacher_classes set role = 'fan' where role is null or role not in ('rahbar', 'fan');

-- Bir o'qituvchi bir sinfda faqat bir marta bo'lsin (vazifasini o'zgartirish uchun kerak)
do $$ begin
  if not exists (
    select 1 from pg_index i join pg_class t on t.oid = i.indrelid
     where t.relname = 'teacher_classes' and i.indisunique
       and (select array_agg(a.attname::text order by a.attname) from pg_attribute a
             where a.attrelid = t.oid and a.attnum = any(i.indkey)) = array['class_id', 'user_id']) then
    create unique index teacher_classes_user_class_uq on public.teacher_classes (user_id, class_id);
  end if;
end $$;

notify pgrst, 'reload schema';

-- Tekshirish: har bir sinfdagi o'qituvchilar va vazifasi (noto'g'ri bo'lsa, platformada Sozlamalar → O'qituvchi akkaunti bo'limida o'zgartiring)
select c.name as sinf, p.full_name as oqituvchi,
       case t.role when 'rahbar' then 'Sinf rahbari' else 'Fan o''qituvchisi' end as vazifasi
  from public.teacher_classes t
  join public.classes c on c.id = t.class_id
  left join public.profiles p on p.id = t.user_id
 order by c.name, t.role desc, p.full_name;
