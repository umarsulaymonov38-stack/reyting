-- Yangilanish 15: "Avitsena" guruhi 4-guruhga (Repetitor guruhlar) o'tkaziladi, guruh o'qituvchisi — Jalilova Mastura.
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing. Qayta ishga tushirish xavfsiz.

do $$
declare cid bigint; uid uuid; n int;
begin
  select id into cid from public.classes where lower(btrim(name)) = 'avitsena' limit 1;
  if cid is null then raise exception 'Avitsena guruhi topilmadi (avval yangilanish-10.sql ni ishga tushiring)'; end if;

  update public.classes set kind = 'rep', grp = null, subject = null, teacher_name = 'Jalilova Mastura' where id = cid;

  -- Platformada Jalilova Mastura nomli o'qituvchi akkaunti bo'lsa — guruhga "Guruh rahbari" sifatida biriktiriladi
  select count(*), (array_agg(p.id))[1] into n, uid from public.profiles p
   where p.role in ('teacher', 'admin')
     and lower(p.full_name) ~ 'jalilova' and lower(p.full_name) ~ 'mastura';
  if n = 1 then
    update public.teacher_classes set role = 'rahbar' where user_id = uid and class_id = cid;
    if not found then
      insert into public.teacher_classes (user_id, class_id, role) values (uid, cid, 'rahbar');
    end if;
    raise notice 'Jalilova Mastura akkaunti Avitsena guruhiga biriktirildi';
  elsif n = 0 then
    raise notice 'Jalilova Mastura akkaunti hali yo''q — platformada Avitsena → O''qituvchi bo''limida akkaunt yarating (vazifasi: Guruh rahbari)';
  else
    raise notice 'Jalilova Mastura nomli % ta akkaunt bor — platformada Avitsena → O''qituvchi bo''limida qo''lda biriktiring', n;
  end if;
end $$;

notify pgrst, 'reload schema';

select c.name as guruh, c.kind as turi, c.teacher_name as oqituvchi,
       (select string_agg(p.full_name || ' (' || case t.role when 'rahbar' then 'guruh rahbari' else 'yordamchi' end || ')', ', ')
          from public.teacher_classes t left join public.profiles p on p.id = t.user_id where t.class_id = c.id) as akkauntlar
  from public.classes c where lower(btrim(c.name)) = 'avitsena';
