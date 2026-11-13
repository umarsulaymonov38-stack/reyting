-- Yangilanish 68: Kunlik vazifalar bali — oddiy yig'indi, kuniga ko'pi bilan 31 ball (oyiga 620):
--   Davomat — ball bermaydi (faqat belgilanadi).
--   Kitob o'qish 0–10 + Odoblar 0–10 + Ota-onaga yaxshilik (ota-ona juma kungi so'rovnomasi):
--     😊 xursand qildi — 11, 😐 aralash — 6, 😞 ranjitdi — 0; javob berilmagan bo'lsa — 0.
--   Misol: kitob 8, odob 9, yaxshilik javobi yo'q → 17 ball. Hammasi to'liq: 10 + 10 + 11 = 31.
--   1-sinf (kitob o'qish yo'q): Odoblar ×2 (0–20) + Ota-onaga yaxshilik (0–11) = 31.
--   Eski yozuvlar (09.11.2026 dan oldingi, sport bor kunlar): 4 mezon ×0.75 (davomat balli olib tashlandi).
-- Supabase → SQL Editor ga to'liq nusxalab, "Run" bosing (loyiha: YUKSALISH-REYTING). Qayta ishga tushirish xavfsiz.

create or replace function public.yk_day_total(g1 boolean, att int, book int, sport int, behavior int, kindness int, activity int)
returns int language sql immutable as $$
  select case
           when g1 and sport is null then coalesce(behavior, 0) * 2 + coalesce(round(kindness * 1.1)::int, 0)
           when g1 then coalesce(sport, 0) + coalesce(behavior, 0) + coalesce(kindness, 0)
           when g1 is null and sport is null then coalesce(book, 0) + coalesce(behavior, 0) + coalesce(round(kindness * 1.1)::int, 0)
           else round((coalesce(book, 0) + coalesce(sport, 0) + coalesce(behavior, 0) + coalesce(kindness, 0)) * 0.75)::int
         end
$$;

notify pgrst, 'reload schema';

-- Tekshiruv: kitob 8 + odob 9 (javob yo'q) = 17; 10+10+xursand = 31; 1-sinf odob 10 + xursand = 31
select public.yk_day_total(null, 1, 8, null, 9, null, null) as "8+9 (javob yo'q)",
       public.yk_day_total(null, 1, 10, null, 10, 10, null) as "10+10+xursand",
       public.yk_day_total(null, 1, 10, null, 10, 5, null) as "10+10+aralash",
       public.yk_day_total(true, 1, null, null, 10, 10, null) as "1-sinf: 10×2+xursand";
