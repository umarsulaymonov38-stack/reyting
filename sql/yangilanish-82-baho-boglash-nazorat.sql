-- Yangilanish 82: Guruh/repetitor baholari ota-onaga yetib bormayotgan o'quvchilarni topish va tuzatish.
--   Guruhlarda (Matematika, Ingliz tili, Arab/Koreys tili, repetitor) o'quvchi alohida yozilgan; baho ota-onaga
--   faqat u asosiy sinfdagi farzand bilan bog'langanda boradi.
--   1) Avtomatik tuzatish:
--      * ism aynan bir xil, lekin guruhning sinf raqami mos kelmagani uchun bog'lanmay qolganlar —
--        maktabda shu ismli o'quvchi YAGONA bo'lsa, bog'lanadi;
--      * ism biroz boshqacha yozilganlar — o'xshashlik bo'yicha (yangilanish-75 dagi kabi).
--   2) Har kuni 06:30 da shu tuzatish o'zi ishlaydi (yangi qo'shilgan o'quvchilar ham bog'lanadi).
--   3) Oxirida — hali ham muammoli o'quvchilar ro'yxati (oxirgi 30 kunda baho olganlar).
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing (loyiha: YUKSALISH-REYTING). Avval 75 ishga tushgan bo'lsin.
-- Qayta ishga tushirish xavfsiz.

-- Guruhdagi har bir o'quvchi qaysi asosiy sinf farzandlariga bog'langan (ota-ona sahifasidagi qoida bilan aynan bir xil)
create or replace function public.yk_link_map()
returns table (gid text, kid text)
language sql stable security definer set search_path = public as $$
  with k as (
    select s.id, public.yk_norm3(s.full_name) as nk, public.yk_norm3(public.yk_first2(s.full_name)) as nk2,
           coalesce(c.grade, nullif(substring(c.name from '^\s*(\d+)'), '')::int) as cg
      from public.students s join public.classes c on c.id = s.class_id
     where c.kind is distinct from 'rep' and coalesce(c.grp, '') = '' and coalesce(c.subject, '') !~* '^(arab|koreys)'
       and coalesce(btrim(s.full_name), '') <> ''),
  g as (
    select g.id, gc.name as gn, gc.grade as gg, public.yk_norm3(g.full_name) as ng, public.yk_norm3(public.yk_first2(g.full_name)) as ng2
      from public.students g join public.classes gc on gc.id = g.class_id
     where coalesce(btrim(g.full_name), '') <> ''
       and (gc.kind = 'rep' or coalesce(gc.grp, '') <> '' or coalesce(gc.subject, '') ~* '^(arab|koreys)'))
  select g.id::text, k.id::text
    from g join k on (g.ng = k.nk or g.ng2 = k.nk2)
     and (g.gg is null or k.cg is null or g.gg = k.cg or g.gn ~ ('(^|[^0-9])' || k.cg || '([^0-9]|$)'))
  union
  select sl.gid, sl.kid from public.student_links sl
$$;
revoke all on function public.yk_link_map() from public, anon, authenticated;

-- Avtomatik tuzatish
create or replace function public.yk_link_fix() returns int
language plpgsql security definer set search_path = public, extensions as $$
declare n int := 0; m int := 0;
begin
  -- 1) ism aynan bir xil, maktabda yagona — sinf raqamidan qat'i nazar bog'lanadi
  with lm as (select distinct gid from public.yk_link_map()),
  mainst as (
    select s.id::text as sid, public.yk_norm3(s.full_name) as nk, public.yk_norm3(public.yk_first2(s.full_name)) as nk2
      from public.students s join public.classes c on c.id = s.class_id
     where c.kind is distinct from 'rep' and coalesce(c.grp, '') = '' and coalesce(c.subject, '') !~* '^(arab|koreys)'
       and coalesce(btrim(s.full_name), '') <> ''),
  un as (
    select g.id::text as gid, public.yk_norm3(g.full_name) as ng, public.yk_norm3(public.yk_first2(g.full_name)) as ng2
      from public.students g join public.classes gc on gc.id = g.class_id
     where coalesce(btrim(g.full_name), '') <> ''
       and (gc.kind = 'rep' or coalesce(gc.grp, '') <> '' or coalesce(gc.subject, '') ~* '^(arab|koreys)')
       and g.id::text not in (select gid from lm)),
  c as (
    select u.gid, min(m.sid) as sid, count(distinct m.sid) as cnt
      from un u join mainst m on (u.ng = m.nk or u.ng2 = m.nk2) group by u.gid)
  insert into public.student_links (gid, kid, score)
  select c.gid, c.sid, 1 from c where c.cnt = 1
  on conflict (gid) do nothing;
  get diagnostics n = row_count;
  -- 2) ism biroz boshqacha yozilganlar — o'xshashlik bo'yicha (faqat ishonchli va yagona moslik)
  select count(*) into m from public.yk_link_groups(0.6, 0.1) r where r.holat like '✅%';
  return n + m;
end $$;
revoke all on function public.yk_link_fix() from public, anon, authenticated;

-- Hali ham muammoli o'quvchilar (oxirgi 30 kunda guruhda baho olgan)
create or replace function public.yk_link_diag(p_days int default 30)
returns table (guruh text, guruhdagi_ism text, baho_kunlari int, boglangan text, holat text)
language sql stable security definer set search_path = public as $$
  with gr as (
    select g.id, g.full_name::text as nm, gc.name::text as gn,
           (select count(distinct d.day) from public.daily_scores d
             where d.student_id = g.id and d.day > (now() at time zone 'Asia/Tashkent')::date - p_days)
         + (select count(distinct r.day) from public.rep_daily r
             where r.student_id = g.id and r.day > (now() at time zone 'Asia/Tashkent')::date - p_days) as nd
      from public.students g join public.classes gc on gc.id = g.class_id
     where coalesce(btrim(g.full_name), '') <> ''
       and (gc.kind = 'rep' or coalesce(gc.grp, '') <> '' or coalesce(gc.subject, '') ~* '^(arab|koreys)')),
  lm as (
    select l.gid, string_agg(s.full_name || ' (' || c.name || ')', '; ' order by s.full_name) as kids, count(*) as cnt
      from public.yk_link_map() l join public.students s on s.id::text = l.kid join public.classes c on c.id = s.class_id
     group by l.gid)
  select gr.gn, gr.nm, gr.nd::int, lm.kids,
         case when lm.cnt is null then '❌ bog''lanmagan — baholari ota-onaga BORMAYDI'
              else '⚠️ ' || lm.cnt || ' ta farzandga ketyapti — bittasi noto''g''ri' end
    from gr left join lm on lm.gid = gr.id::text
   where gr.nd > 0 and (lm.cnt is null or lm.cnt > 1)
   order by 5, 1, 2
$$;
revoke all on function public.yk_link_diag(int) from public, anon, authenticated;

-- Har kuni 06:30 (Toshkent) = 01:30 UTC, dushanba–shanba
do $$ begin perform cron.unschedule('yk-baho-boglash'); exception when others then null; end $$;
do $$ begin
  perform cron.schedule('yk-baho-boglash', '30 1 * * 1-6', 'select public.yk_link_fix()');
exception when others then raise notice 'pg_cron topilmadi — jadval qo''yilmadi: %', sqlerrm;
end $$;

-- Hozir bir marta tuzatish
select public.yk_link_fix() as "hozir bog'landi";

notify pgrst, 'reload schema';

-- Qolgan muammolar (bo'sh chiqsa — hammasi joyida)
select * from public.yk_link_diag(30);
