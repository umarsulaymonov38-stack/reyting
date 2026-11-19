-- Yangilanish 80: Kuzatuvchi o'z telefoniga bildirishnoma yoqa oladi va turniket ogohlantirishlarini oladi.
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing (loyiha: YUKSALISH-REYTING). Avval 79 ishga tushgan bo'lsin.

drop policy if exists obs_no_ins on public.push_subs;
drop policy if exists obs_no_upd on public.push_subs;
drop policy if exists obs_no_del on public.push_subs;

create or replace function public.yk_admin_push(p_key text, p_title text, p_body text) returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  insert into public.push_queue (user_id, kind, student_id, title, body)
  select p.id, 'tk', p_key, p_title, p_body
    from public.profiles p
   where (p.role = 'admin' or coalesce(p.admin2, false) or coalesce(p.obs, false))
     and exists (select 1 from public.push_subs s where s.user_id = p.id)
  on conflict do nothing;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.yk_admin_push(text, text, text) from public, anon, authenticated;

notify pgrst, 'reload schema';
select 'Tayyor' as natija;
