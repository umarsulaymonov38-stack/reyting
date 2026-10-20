-- Yangilanish 2: matematika guruhlari, o'qituvchilar reytingi, sinf rahbari / fan o'qituvchisi, fan darsliklari.
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing. Qayta ishga tushirish xavfsiz (bor narsalar qayta yaratilmaydi).
-- Hech qanday mavjud ma'lumot o'chirilmaydi.

-- 0. Yordamchi: joriy foydalanuvchi roli (admin / teacher / parent)
create or replace function public.yk_role() returns text
language sql stable security definer set search_path = public as $$
  select role from public.profiles where id = auth.uid()
$$;
grant execute on function public.yk_role() to authenticated;

-- 1. 3-guruh: 5, 6, 7-sinf Matematika ALFA / BETTA / GAMMA guruhlari (har biri 15 o'quvchilik)
--    Avvaldan bor guruhlar (fani yozilmagan) — Ingliz tili guruhlari deb belgilanadi.
update public.classes set subject = 'Ingliz tili'
 where coalesce(grp, '') <> '' and kind is distinct from 'rep' and coalesce(subject, '') = '';

do $$
declare g int; n text; cid bigint; k int; sid_auto boolean; cid_auto boolean;
begin
  -- id ustuni avtomatik to'ldirilmasa (default yo'q bo'lsa), keyingi raqamni o'zimiz beramiz
  select column_default is not null or is_identity = 'YES' into cid_auto from information_schema.columns
   where table_schema = 'public' and table_name = 'classes' and column_name = 'id';
  select column_default is not null or is_identity = 'YES' into sid_auto from information_schema.columns
   where table_schema = 'public' and table_name = 'students' and column_name = 'id';
  foreach g in array array[5, 6, 7] loop
    foreach n in array array['ALFA', 'BETTA', 'GAMMA'] loop
      select id into cid from public.classes
       where grade = g and upper(grp) = n and subject = 'Matematika' limit 1;
      if cid is null then
        if cid_auto then
          insert into public.classes (name, grade, grp, subject)
          values (g || '-sinf Matematika ' || initcap(n), g, n, 'Matematika')
          returning id into cid;
        else
          insert into public.classes (id, name, grade, grp, subject)
          values ((select coalesce(max(id), 0) + 1 from public.classes), g || '-sinf Matematika ' || initcap(n), g, n, 'Matematika')
          returning id into cid;
        end if;
      end if;
      for k in 1..15 loop
        if not exists (select 1 from public.students where class_id = cid and slot = k) then
          if sid_auto then
            insert into public.students (class_id, slot, full_name) values (cid, k, '');
          else
            insert into public.students (id, class_id, slot, full_name)
            values ((select coalesce(max(id), 0) + 1 from public.students), cid, k, '');
          end if;
        end if;
      end loop;
      -- ota-ona telefoni yoziladigan qator (agar bazada buni trigger o'zi yaratmasa)
      begin
        insert into public.student_private (student_id, code)
        select s.id, upper(substr(md5(random()::text || s.id::text), 1, 6))
          from public.students s
         where s.class_id = cid
           and not exists (select 1 from public.student_private p where p.student_id = s.id);
      exception when others then
        raise notice 'student_private qatorlari yaratilmadi: %', sqlerrm;
      end;
      cid := null;
    end loop;
  end loop;
end $$;

-- 2. O'qituvchining sinfdagi vazifasi: 'rahbar' (sinf rahbari) yoki 'fan' (fan o'qituvchisi)
alter table public.teacher_classes add column if not exists role text not null default 'fan';

-- 3. Baholar qachon to'liq qo'yilganini yozib borish (o'qituvchilar reytingi uchun)
alter table public.daily_scores add column if not exists done_at timestamptz;
alter table public.daily_scores add column if not exists updated_at timestamptz;
alter table public.rep_daily    add column if not exists done_at timestamptz;
alter table public.rep_daily    add column if not exists updated_at timestamptz;

create or replace function public.yk_mark_done() returns trigger
language plpgsql security definer set search_path = public as $$
declare g text; done boolean;
begin
  new.updated_at := now();
  if tg_table_name = 'rep_daily' then
    done := new.att is not null and (new.att = 0 or (new.hw is not null and new.test is not null and new.grade is not null));
  else
    select c.grp into g from public.students s join public.classes c on c.id = s.class_id where s.id = new.student_id;
    if coalesce(g, '') <> '' then
      -- 3-guruh: davomat, uyga vazifa, sinfdagi faollik, tartib-intizom
      done := new.att is not null and (new.att = 0 or (new.hw is not null and new.activity is not null and new.behavior is not null));
    else
      done := new.att is not null and (new.att = 0 or (new.book is not null and new.sport is not null and new.behavior is not null
              and new.kindness is not null and new.activity is not null));
    end if;
  end if;
  if not done then new.done_at := null;
  elsif new.done_at is null then new.done_at := now();
  end if;
  return new;
end $$;

drop trigger if exists yk_done on public.daily_scores;
create trigger yk_done before insert or update on public.daily_scores for each row execute function public.yk_mark_done();
drop trigger if exists yk_done on public.rep_daily;
create trigger yk_done before insert or update on public.rep_daily for each row execute function public.yk_mark_done();

-- Eski to'liq yozuvlar: o'z kunida o'z vaqtida qo'yilgan deb hisoblanadi
update public.daily_scores set done_at = ((day + time '18:00') at time zone 'Asia/Tashkent') where done_at is null and att is not null;
update public.rep_daily    set done_at = ((day + time '18:00') at time zone 'Asia/Tashkent') where done_at is null and att is not null;

create index if not exists daily_scores_day_done_idx on public.daily_scores (day, student_id, done_at);
create index if not exists rep_daily_day_done_idx    on public.rep_daily (day, student_id, done_at);

-- 4. O'qituvchilar reytingi.
--    Har bir "sinf-kun": sinfdagi barcha o'quvchilarga baho shu kuni soat 21:00 gacha to'liq qo'yilgan bo'lsa — o'z vaqtida,
--    keyin qo'yilgan bo'lsa — kechikkan, to'liq qo'yilmagan bo'lsa — bajarilmagan.
--    Oylik ball: 100 − 2 × kechikkan − 5 × bajarilmagan (0 dan kam emas).
--    Asosiy sinflar uchun maktab ishlagan har bir kun hisoblanadi; 3-guruh va repetitor guruhlarida esa dars bo'lgan (baho kiritilgan) kunlar.
--    Admin hamma o'qituvchini, o'qituvchi faqat o'zini ko'radi.
create or replace function public.teacher_rating(p_from date, p_to date)
returns table (user_id uuid, full_name text, phone text, classes text, class_days int, on_time int, late int, missed int, score int)
language sql stable security definer set search_path = public as $$
with nowt as (select (now() at time zone 'Asia/Tashkent') t),
cut as (  -- bugungi kun faqat 21:00 dan keyin hisoblanadi
  select case when (select t from nowt)::time >= time '21:00' then (select t from nowt)::date
              else (select t from nowt)::date - 1 end as last_day
),
cls as (
  select c.id, c.name, (c.kind is distinct from 'rep' and coalesce(c.grp, '') = '') as is_main from public.classes c
),
st as (select s.id, s.class_id from public.students s where coalesce(btrim(s.full_name), '') <> ''),
sd as (  -- maktab ish kunlari: asosiy sinflarning birortasida baho bor kunlar
  select distinct ds.day from public.daily_scores ds
    join public.students s on s.id = ds.student_id join cls c on c.id = s.class_id and c.is_main
   where ds.day between p_from and least(p_to, (select last_day from cut))
),
cday as (
  select c.id as class_id, sd.day from cls c join sd on c.is_main
  union
  select s.class_id, ds.day from public.daily_scores ds join public.students s on s.id = ds.student_id
    join cls c on c.id = s.class_id and not c.is_main
   where ds.day between p_from and least(p_to, (select last_day from cut))
  union
  select s.class_id, r.day from public.rep_daily r join public.students s on s.id = r.student_id
   where r.day between p_from and least(p_to, (select last_day from cut))
),
rws as (
  select student_id, day, done_at from public.daily_scores where day between p_from and p_to
  union all
  select student_id, day, done_at from public.rep_daily where day between p_from and p_to
),
cstat as (
  select cd.class_id, cd.day, count(st.id) as n,
         count(r.student_id) filter (where r.done_at is not null) as done,
         count(r.student_id) filter (where r.done_at <= ((cd.day + time '21:00') at time zone 'Asia/Tashkent')) as ok
    from cday cd join st on st.class_id = cd.class_id
    left join rws r on r.student_id = st.id and r.day = cd.day
   group by cd.class_id, cd.day
),
tc as (
  select t.user_id, t.class_id from public.teacher_classes t
   where public.yk_role() = 'admin' or t.user_id = auth.uid()
)
select p.id, p.full_name, p.phone,
       (select string_agg(c.name, ', ' order by c.name) from tc t2 join public.classes c on c.id = t2.class_id where t2.user_id = p.id),
       count(cs.class_id)::int,
       (count(cs.class_id) filter (where cs.ok = cs.n))::int,
       (count(cs.class_id) filter (where cs.done = cs.n and cs.ok < cs.n))::int,
       (count(cs.class_id) filter (where cs.done < cs.n))::int,
       greatest(0, 100 - 2 * (count(cs.class_id) filter (where cs.done = cs.n and cs.ok < cs.n))
                       - 5 * (count(cs.class_id) filter (where cs.done < cs.n)))::int
  from public.profiles p
  join (select distinct user_id from tc) u on u.user_id = p.id
  left join tc on tc.user_id = p.id
  left join cstat cs on cs.class_id = tc.class_id
 group by p.id, p.full_name, p.phone
 order by 9 desc, 6 desc, 2
$$;
grant execute on function public.teacher_rating(date, date) to authenticated;

-- 5. Fan darsliklari (PDF / Word)
create table if not exists public.books (
  id bigint generated by default as identity primary key,
  grp smallint not null check (grp between 1 and 4),
  class_id bigint references public.classes(id) on delete cascade,
  title text not null,
  path text not null,
  size bigint,
  mime text,
  uploaded_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);
create index if not exists books_grp_idx on public.books (grp, class_id);
alter table public.books enable row level security;
drop policy if exists books_read on public.books;
create policy books_read on public.books for select to authenticated using (true);
drop policy if exists books_add on public.books;
create policy books_add on public.books for insert to authenticated with check (public.yk_role() in ('admin', 'teacher'));
drop policy if exists books_del on public.books;
create policy books_del on public.books for delete to authenticated using (public.yk_role() = 'admin' or uploaded_by = auth.uid());

-- Fayllar uchun ombor (har bir fayl 50 MB gacha)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('darsliklar', 'darsliklar', true, 52428800,
        array['application/pdf', 'application/msword', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'])
on conflict (id) do update set public = true, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists darsliklar_read on storage.objects;
create policy darsliklar_read on storage.objects for select to authenticated using (bucket_id = 'darsliklar');
drop policy if exists darsliklar_add on storage.objects;
create policy darsliklar_add on storage.objects for insert to authenticated
  with check (bucket_id = 'darsliklar' and public.yk_role() in ('admin', 'teacher'));
drop policy if exists darsliklar_del on storage.objects;
create policy darsliklar_del on storage.objects for delete to authenticated
  using (bucket_id = 'darsliklar' and (public.yk_role() = 'admin' or owner = auth.uid()));
