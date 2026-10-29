-- Yangilanish 32: push-bildirishnoma server funksiyasining nomi bazada saqlanadi
-- (Supabase funksiyaga avtomatik nom qo'ygan bo'lsa ham ishlaydi).
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing. Qayta ishga tushirish xavfsiz.
-- Funksiya nomini keyin o'zgartirish kerak bo'lsa — pastdagi 'smooth-task' ni yangi nomga almashtirib, qayta ishga tushiring.

alter table public.push_config add column if not exists fn_name text not null default 'push-yubor';
update public.push_config set fn_name = 'smooth-task' where id = 1;

-- Ilova ochiq kalitni olish uchun funksiya manzilini shu yerdan oladi
create or replace function public.push_fn_url() returns text language sql stable security definer set search_path = public as $$
  select 'https://yzaxyjypswpjcebmjsnj.supabase.co/functions/v1/' || fn_name from public.push_config where id = 1
$$;
grant execute on function public.push_fn_url() to anon, authenticated;

create or replace function public.yk_push_kick() returns void
language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from public.push_queue where status = 'navbat') then
    perform net.http_post(url := public.push_fn_url(),
      body := '{}'::jsonb, headers := '{"Content-Type": "application/json"}'::jsonb, timeout_milliseconds := 60000);
  end if;
end $$;
revoke all on function public.yk_push_kick() from public, anon, authenticated;

notify pgrst, 'reload schema';

select fn_name as "funksiya nomi", public.push_fn_url() as manzil, public.push_public_key() is not null as kalit_bor from public.push_config;
