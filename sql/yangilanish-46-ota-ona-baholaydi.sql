-- Yangilanish 46: 1–2-guruh sinflarida kunlik mezonlar taqsimoti:
--   ota-ona belgilaydi:      Kitob o'qish, Sport, Ota-onaga yaxshilik (0–10, faqat bugungi kun uchun, o'z farzandiga);
--   sinf rahbari belgilaydi:  Davomat va «Maktabdagi odoblar» (avvalgi «Kunlik odoblar»).
-- Kunlik maksimal 51, oylik 1020 ball o'zgarmaydi. O'qituvchilar reytingida sinf rahbari faqat o'z ustunlari uchun javob beradi.
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing. Qayta ishga tushirish xavfsiz.

-- 1. «Baho to'liq qo'yildi» belgisi (o'qituvchilar reytingi): faqat o'qituvchi to'ldiradigan ustunlar bo'yicha
create or replace function public.yk_mark_done() returns trigger
language plpgsql security definer set search_path = public as $$
declare g text; done boolean; j jsonb := to_jsonb(new);
begin
  new.updated_at := now();
  if tg_table_name = 'rep_daily' then
    done := new.att is not null and (new.att = 0 or j ->> 'task' is not null);
  else
    select c.grp into g from public.students s join public.classes c on c.id = s.class_id where s.id = new.student_id;
    if coalesce(g, '') <> '' then
      done := new.att is not null and (new.att = 0 or (new.hw is not null and new.activity is not null and new.behavior is not null));
    else
      done := new.att is not null and (new.att = 0 or new.behavior is not null);
    end if;
  end if;
  if not done then new.done_at := null;
  elsif new.done_at is null then new.done_at := now();
  end if;
  return new;
end $$;

-- 2. Ota-ona o'z farzandining bugungi bahosini qo'yadi
create or replace function public.yk_is_my_kid(p_sid text) returns boolean
language sql stable security definer set search_path = public, auth as $$
  select exists (
    select 1 from public.student_private sp
     where sp.student_id::text = p_sid
       and (sp.claimed_by = auth.uid()
            or right(regexp_replace(coalesce(sp.parent_phone, ''), '\D', '', 'g'), 9)
               = (select substring(u.email from '^p(\d{9})@') from auth.users u where u.id = auth.uid())))
  or exists (select 1 from public.profiles p where p.id = auth.uid() and p.student_id::text = p_sid)
$$;
revoke all on function public.yk_is_my_kid(text) from public, anon;

create or replace function public.parent_set_score(p_sid text, p_field text, p_val int) returns void
language plpgsql security definer set search_path = public as $$
declare t date := (now() at time zone 'Asia/Tashkent')::date; sid uuid; g text;
begin
  if public.yk_role() is distinct from 'parent' then raise exception 'Faqat ota-ona' using errcode = '42501'; end if;
  if p_field not in ('book', 'sport', 'kindness') then raise exception 'Bu ustunni ota-ona belgilamaydi'; end if;
  if p_val is not null and (p_val < 0 or p_val > 10) then raise exception 'Ball 0 dan 10 gacha'; end if;
  if not public.yk_is_my_kid(p_sid) then raise exception 'Bu sizning farzandingiz emas' using errcode = '42501'; end if;
  select s.id, c.grp into sid, g from public.students s join public.classes c on c.id = s.class_id
   where s.id::text = p_sid and c.kind is distinct from 'rep';
  if sid is null or coalesce(g, '') <> '' then raise exception 'Faqat asosiy sinf (1–2-guruh) uchun'; end if;
  execute format('insert into public.daily_scores (student_id, day, %1$I) values ($1, $2, $3)
                  on conflict (student_id, day) do update set %1$I = excluded.%1$I', p_field) using sid, t, p_val;
end $$;
revoke all on function public.parent_set_score(text, text, int) from public, anon;
grant execute on function public.parent_set_score(text, text, int) to authenticated;

-- Ota-ona uchun: farzandlarining bugungi ballari (asosiy sinflar)
create or replace function public.parent_today() returns table (student_id text, book int, sport int, kindness int, behavior int, att int)
language sql stable security definer set search_path = public as $$
  select s.id::text, d.book::int, d.sport::int, d.kindness::int, d.behavior::int, d.att::int
    from public.students s join public.classes c on c.id = s.class_id
    left join public.daily_scores d on d.student_id = s.id and d.day = (now() at time zone 'Asia/Tashkent')::date
   where c.kind is distinct from 'rep' and coalesce(c.grp, '') = '' and coalesce(btrim(s.full_name), '') <> ''
     and public.yk_role() = 'parent' and public.yk_is_my_kid(s.id::text)
$$;
revoke all on function public.parent_today() from public, anon;
grant execute on function public.parent_today() to authenticated;

-- 3. Baho bildirishnomalari: ota-ona qo'ygan ballar uchun xabar yuborilmaydi (faqat sinf rahbari/guruh o'qituvchisi baholari)
create or replace function public.yk_push_daily() returns trigger
language plpgsql security definer set search_path = public as $$
declare g boolean; sid text := new.student_id::text; c record;
begin
  if new.day <> (now() at time zone 'Asia/Tashkent')::date then return new; end if;
  select coalesce(cl.grp, '') <> '' into g from public.students s join public.classes cl on cl.id = s.class_id where s.id = new.student_id;
  g := coalesce(g, false);
  -- 1–2-guruh: kitob o'qish, sport, ota-onaga yaxshilik — ota-onaning o'zi belgilaydi, xabar yuborilmaydi
  for c in select * from (values ('behavior', case when g then 'Tartib-intizom' else 'Maktabdagi odoblar' end, case when g then 5 else 10 end),
                                 ('hw', 'Uyga vazifa', 5), ('activity', 'Sinfdagi faollik', 5)) v(k, t, m) loop
    continue when (case when g then c.k not in ('hw', 'activity', 'behavior') else c.k <> 'behavior' end);
    if tg_op = 'INSERT' or (to_jsonb(new) ->> c.k) is distinct from (to_jsonb(old) ->> c.k) then
      perform public.yk_grade_mark(sid, 'd:' || c.k, (to_jsonb(new) ->> c.k)::numeric,
                                   case when c.m = 5 then 2 else 4 end, case when c.m = 5 then 5 else 9 end,
                                   c.t || ' ' || (to_jsonb(new) ->> c.k) || '/' || c.m);
    end if;
  end loop;
  if g and (tg_op = 'INSERT' or (to_jsonb(new) ->> 'beh_band') is distinct from (to_jsonb(old) ->> 'beh_band')) then
    perform public.yk_grade_note(sid, 'yomon', 'd:band', case (to_jsonb(new) ->> 'beh_band')
      when '1' then 'tartib qoidaga amal qilmadi' when '2' then 'atrofdagilar va ustozlarni hurmat qilmadi'
      when '3' then 'o''z joyini toza saqlamadi' end);
  end if;
  return new;
exception when others then
  raise warning 'push baho: %', sqlerrm;  -- bildirishnomadagi xato baho saqlanishiga to'sqinlik qilmasin
  return new;
end $$;
drop trigger if exists yk_push_daily on public.daily_scores;

notify pgrst, 'reload schema';
