# Turniketni platformaga ulash (Hikvision)

O'quvchi turniketdan o'tganda platformada avtomatik **davomat ✅ keldi** qo'yiladi va **kelgan vaqti** yoziladi.
Maktab ichki tarmog'idagi bitta kompyuterda kichik "ko'prik" dastur ishlaydi: u 4 ta turniketdan
har 20 soniyada yangi o'tishlarni o'qiydi va platformaga yuboradi. Turniketlarni internetga ochish shart emas.

## 1. Platformani tayyorlash (bir marta)
1. Supabase → SQL Editor da `sql/yangilanish-5-turniket.sql` ni ishga tushiring.
2. Natijada uzun **turniket kaliti** chiqadi — uni nusxalab oling (3-qadamda kerak).

## 2. Turniketlar haqida ma'lumot
Har bir eshik qurilmasi uchun bilib oling (iVMS-4200 dasturida yoki qurilma menyusida):
- **IP manzili** (masalan `192.168.1.101`);
- **admin login va paroli** (qurilmaning veb-sahifasiga kiradigan).

Qurilmalarda tekshiring:
- **Vaqt va vaqt zonasi** to'g'ri: (UTC+05:00) Toshkent. Aks holda kelgan vaqt noto'g'ri yoziladi.
- O'quvchilar turniketga ism-familiyasi bilan, platformadagidek yozilgan bo'lsin (bog'lash shunga qarab bo'ladi).

## 3. Kompyuterni tayyorlash
Turniketlar bilan bir tarmoqda doim yoqilgan kompyuter kerak (Windows yoki Linux).
1. https://www.python.org/downloads/ dan Python 3 ni o'rnating (o'rnatishda **"Add Python to PATH"** ni belgilang).
2. Buyruqlar oynasida (cmd): `pip install requests`
3. `turniket` papkasini kompyuterga ko'chiring, `config.namuna.json` dan nusxa olib nomini `config.json` qiling va to'ldiring:
   - `"token"` — 1-qadamdagi turniket kaliti;
   - `"devices"` — 4 ta eshikning IP manzili, logini va paroli.

## 4. Tekshirish va bog'lash
`turniket` papkasida buyruqlar oynasini ochib:
```
python turniket_bridge.py --test
```
Har bir eshik va platforma yonida ✅ chiqishi kerak.

So'ng o'quvchilarni turniketdagi ID raqamlari bilan bog'lang (ism-familiya bo'yicha, avtomatik):
```
python turniket_bridge.py --sync-ids
```
Bog'lanmay qolganlar `boglanmaganlar.csv` fayliga yoziladi (ismi topilmagan yoki bir xil ismli o'quvchilar).
Ularning **Turniket ID** sini platformada: sinfni tanlang → **Sozlamalar** → "Ota-onalar telefonlari" jadvalidagi
**Turniket ID** ustuniga qo'lda yozing. Yangi o'quvchi qo'shilganda `--sync-ids` ni qayta ishga tushirish kifoya.

## 5. Doimiy ishga tushirish
```
python turniket_bridge.py
```
Kompyuter qayta yoqilganda o'zi ishga tushishi uchun (Windows): **Task Scheduler** → *Create Basic Task* →
"When the computer starts" → dastur: `python`, argument: `turniket_bridge.py`, "Start in": `turniket` papkasi manzili.

Ishlash jurnali: `turniket.log`. Platformada admin chap paneldagi **"Turniket: oxirgi o'tish …"** yozuvidan
ko'prik ishlayotganini ko'radi (kunduzi 2 soatdan ortiq ma'lumot kelmasa, ogohlantirish chiqadi).

## Qanday ishlaydi
- Tanilgan o'quvchi o'tsa — o'sha kuni asosiy sinfida **davomat ✅** va birinchi o'tgan vaqti yoziladi
  (soat 08:30 dan keyin kelganlar baholash jadvalida to'q sariq rangda ko'rinadi).
- O'qituvchi davomatni avvalgidek qo'lda ham o'zgartira oladi.
- Guruh darslari (Matematika, Ingliz tili, Arab/Koreys tili, repetitor) davomatini o'qituvchi o'zi qo'yadi.
- Internet uzilsa, ko'prik keyinroq qayta urinadi; o'tishlar yo'qolmaydi.
- Kalit faqat shu kompyuterda saqlanadi; kalitsiz hech kim davomat yubora olmaydi.
