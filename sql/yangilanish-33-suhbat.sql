-- Yangilanish 33: ota-onalar uchun kunlik savolnoma — "Bugun farzandingiz bilan suhbatlashdingizmi?"
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing. Qayta ishga tushirish xavfsiz.
-- Ota-ona kuniga bir marta 4 ta savolga Ha/Yo'q javob beradi; admin umumiy natijani ko'radi (kim nima deb javob bergani emas).

create table if not exists public.parent_checkin (
  user_id uuid not null default auth.uid(),
  day date not null default (now() at time zone 'Asia/Tashkent')::date,
  q_talk boolean,      -- farzandingiz bilan suhbatlashdingizmi
  q_day boolean,       -- kuni va darslari qanday o'tganini so'radingizmi
  q_interest boolean,  -- qiziqishlari haqida gaplashdingizmi
  q_dream boolean,     -- kelajakdagi orzulari haqida gaplashdingizmi
  created_at timestamptz not null default now(),
  primary key (user_id, day)
);
alter table public.parent_checkin enable row level security;
grant select, insert, update on public.parent_checkin to authenticated;
drop policy if exists parent_checkin_own on public.parent_checkin;
create policy parent_checkin_own on public.parent_checkin for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid() and day = (now() at time zone 'Asia/Tashkent')::date);

-- Admin uchun: kunlar kesimida nechta ota-ona javob berdi va har bir savolga "Ha" foizi
create or replace function public.checkin_stats(p_days int default 14)
returns table (day date, javob int, talk int, kun int, qiziqish int, orzu int)
language plpgsql stable security definer set search_path = public as $$
begin
  if public.yk_role() <> 'admin' then raise exception 'Faqat admin' using errcode = '42501'; end if;
  return query
  select c.day, count(*)::int,
         round(100.0 * count(*) filter (where c.q_talk) / count(*))::int,
         round(100.0 * count(*) filter (where c.q_day) / count(*))::int,
         round(100.0 * count(*) filter (where c.q_interest) / count(*))::int,
         round(100.0 * count(*) filter (where c.q_dream) / count(*))::int
    from public.parent_checkin c
   where c.day > (now() at time zone 'Asia/Tashkent')::date - greatest(p_days, 1)
   group by c.day order by c.day desc;
end $$;
revoke all on function public.checkin_stats(int) from public, anon;
grant execute on function public.checkin_stats(int) to authenticated;

notify pgrst, 'reload schema';
