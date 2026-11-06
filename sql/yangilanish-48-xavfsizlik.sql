-- Yangilanish 48: xavfsizlikni kuchaytirish.
--  1) Ro'yxatdan o'tgan-u, hali farzandga/sinfga bog'lanmagan («pending») yoki profili yo'q akkaunt
--     HECH QAYSI jadvalni ko'ra olmaydi va o'zgartira olmaydi (faqat o'z profilini ko'radi).
--     Begona odam API orqali o'zi akkaunt ochsa ham, maktab ma'lumotlariga yo'l yo'q.
--  2) «phone_status» (telefon maktab ro'yxatida bormi) — begonalar uchun yopiladi (endi kerak emas).
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing. Qayta ishga tushirish xavfsiz.
-- Oxirida tekshiruv: «pending» akkaunt nomidan har bir jadval sinaladi — hammasida 0 chiqishi kerak.

-- 1. Barcha jadvallarga «cheklovchi» (restrictive) qoida: rol pending yoki yo'q bo'lsa — hech narsa
do $$
declare t text;
begin
  for t in select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'public' and c.relkind = 'r' and c.relrowsecurity loop
    execute format('drop policy if exists yk_no_pending on public.%I', t);
    if t = 'profiles' then
      execute 'create policy yk_no_pending on public.profiles as restrictive for all to authenticated
               using (id = auth.uid() or (select coalesce(public.yk_role(), ''pending'')) <> ''pending'')
               with check (id = auth.uid() or (select coalesce(public.yk_role(), ''pending'')) <> ''pending'')';
    else
      execute format('create policy yk_no_pending on public.%I as restrictive for all to authenticated
                      using ((select coalesce(public.yk_role(), ''pending'')) <> ''pending'')
                      with check ((select coalesce(public.yk_role(), ''pending'')) <> ''pending'')', t);
    end if;
  end loop;
end $$;

-- 2. Telefon raqam ro'yxatda bormi — begonalarga aytilmaydi
do $$ begin
  revoke all on function public.phone_status(text) from public, anon;
exception when undefined_function then null;
end $$;

notify pgrst, 'reload schema';

-- 3. Tekshiruv: «pending» foydalanuvchi nomidan har bir jadvaldan nechta qator ko'rinadi (hammasi 0 bo'lishi kerak)
drop table if exists pg_temp.yk_res;
create temp table yk_res (jadval text, koradi bigint);
grant all on yk_res to authenticated;
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-0000-0000-00000000dead"}', false),
       set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000dead', false);
set role authenticated;
do $$ declare r record; n bigint; begin
  for r in select c.relname from pg_class c join pg_namespace s on s.oid = c.relnamespace
            where s.nspname = 'public' and c.relkind = 'r' order by 1 loop
    begin execute format('select count(*) from public.%I', r.relname) into n; exception when insufficient_privilege then n := -1; end;
    insert into yk_res values (r.relname, n);
  end loop;
end $$;
reset role;
select jadval, case when koradi > 0 then '❌ ' || koradi || ' qator ko''rinadi' else '✅ yopiq' end as "begona (pending) akkaunt"
  from yk_res order by koradi desc, jadval;
