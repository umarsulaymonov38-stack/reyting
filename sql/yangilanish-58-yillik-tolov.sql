-- Yangilanish 58: Yillik (10 oylik) to'lov.
--  Admin yoki buxgalter o'quvchiga «Yillik to'lov» belgisini qo'yadi — o'quv yilining 10 oyi (sentyabr–iyun)
--  birdaniga «to'langan» bo'ladi (to'langan sana — bugun). Ota-ona profilida «to'lov qiling» eslatmasi va
--  to'lov SMS'i chiqmaydi. Belgi olib tashlansa — shu yillik to'lov bilan belgilangan oylar bekor qilinadi.
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing (loyiha: YUKSALISH-REYTING). Qayta ishga tushirish xavfsiz.

alter table public.payments add column if not exists yearly boolean not null default false;

create or replace function public.set_yearly(p_sid text, p_on boolean) returns int
language plpgsql security definer set search_path = public as $$
declare t date := (now() at time zone 'Asia/Tashkent')::date;
        sy int := case when extract(month from t) >= 9 then extract(year from t)::int else extract(year from t)::int - 1 end;
        sid public.students.id%type; n int;
begin
  if not (public.yk_role() = 'admin' or coalesce(public.yk_bux(), false)) then
    raise exception 'Faqat admin yoki buxgalter' using errcode = '42501';
  end if;
  select id into sid from public.students where id::text = p_sid;
  if sid is null then raise exception 'O''quvchi topilmadi'; end if;
  if p_on then
    insert into public.payments (student_id, month, paid, paid_on, yearly)
    select sid, make_date(case when m >= 9 then sy else sy + 1 end, m, 1), true, t, true
      from unnest(array[9, 10, 11, 12, 1, 2, 3, 4, 5, 6]) m
    on conflict (student_id, month) do update
      -- oldin alohida to'langan oy o'zgarmaydi (belgi olib tashlansa ham to'langanligicha qoladi)
      set yearly = public.payments.yearly or not public.payments.paid, paid = true,
          paid_on = case when public.payments.paid then public.payments.paid_on else excluded.paid_on end;
  else
    update public.payments set paid = false, paid_on = null, yearly = false
     where student_id = sid and yearly and month between make_date(sy, 9, 1) and make_date(sy + 1, 6, 1);
  end if;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.set_yearly(text, boolean) from public, anon;
grant execute on function public.set_yearly(text, boolean) to authenticated;

notify pgrst, 'reload schema';
