#!/usr/bin/env python3
"""Hikvision turniketlari → Yuksalish reyting platformasi (avtomatik davomat).

Maktab ichki tarmog'idagi kompyuterda ishlaydi: har bir turniketdan (ISAPI orqali)
yangi o'tishlarni o'qiydi va platformaga yuboradi. Turniketlarni internetga ochish shart emas.

Ishga tushirish:
  python turniket_bridge.py --setup     sozlash: kalit va parolni so'raydi, config.json ni o'zi yaratadi
  python turniket_bridge.py --test      ulanishni tekshirish (turniketlar va platforma)
  python turniket_bridge.py --sync-ids  turniketdagi ro'yxatni o'quvchilar bilan ism bo'yicha bog'lash
  python turniket_bridge.py             doimiy ishlash (har N soniyada yangi o'tishlarni yuborish)
"""
import argparse
import datetime as dt
import json
import logging
import os
import sys
import time

try:
    import requests
    from requests.auth import HTTPBasicAuth, HTTPDigestAuth
except ImportError:
    sys.exit("'requests' kutubxonasi yo'q. O'rnatish: pip install requests")

HERE = os.path.dirname(os.path.abspath(__file__))
TZ = dt.timezone(dt.timedelta(hours=5))  # Toshkent vaqti
USER_DAYS = 14  # shaxslar ro'yxati yopiq bo'lsa, necha kunlik o'tishlardan yig'iladi
log = logging.getLogger("turniket")


def load_json(name, default=None):
    path = os.path.join(HERE, name)
    if not os.path.exists(path):
        return default
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def save_json(name, data):
    path = os.path.join(HERE, name)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
    os.replace(tmp, path)


class LoginError(RuntimeError):
    """Login yoki parol noto'g'ri — qayta urinish qurilmani qulflab qo'yadi."""


class Device:
    def __init__(self, cfg):
        self.name = cfg.get("name") or cfg["host"]
        self.host = cfg["host"]
        # Avval HTTP (ISAPI odatda shu orqali ishlaydi); qurilma HTTPS ga yo'naltirsa yoki HTTP yopiq bo'lsa — HTTPS
        self.base = ("https://" if cfg.get("https") else "http://") + self.host
        self.user, self.pw = cfg["user"], cfg["password"]
        self.locked_out = False
        self.new_session()

    def new_session(self):
        self.s = requests.Session()
        self.s.auth = HTTPDigestAuth(self.user, self.pw)
        self.s.verify = False

    def post(self, path, body):
        try:
            r = self.s.post(self.base + path, json=body, timeout=15, allow_redirects=False)
        except requests.exceptions.ConnectionError:
            if self.base.startswith("https://"):
                raise
            self.base = "https://" + self.host  # HTTP yopiq — HTTPS orqali
            r = self.s.post(self.base + path, json=body, timeout=15, allow_redirects=False)
        if r.status_code in (301, 302, 303, 307, 308) and self.base.startswith("http://"):
            self.base = "https://" + self.host  # qurilma HTTPS ga yo'naltiryapti
            r = self.s.post(self.base + path, json=body, timeout=15, allow_redirects=False)
        # Ba'zi qurilmalarda veb-kirish "Basic" usulida sozlangan bo'ladi
        if r.status_code == 401 and "basic" in r.headers.get("WWW-Authenticate", "").lower() \
                and "digest" not in r.headers.get("WWW-Authenticate", "").lower():
            self.s.auth = HTTPBasicAuth(self.user, self.pw)
            r = self.s.post(self.base + path, json=body, timeout=15, allow_redirects=False)
        if r.status_code == 401 and not r.headers.get("WWW-Authenticate"):
            # Qurilma eski kirish kalitini (nonce) rad etdi — ulanishni yangidan ochib, bir marta qayta urinamiz
            self.new_session()
            r = self.s.post(self.base + path, json=body, timeout=15, allow_redirects=False)
        if r.status_code == 401 and not r.headers.get("WWW-Authenticate"):
            # Parol to'g'ri, lekin qurilma bu so'rovga ruxsat bermadi (ba'zi proshivkalarda shaxslar ro'yxati yopiq)
            raise RuntimeError("qurilma bu ma'lumotni bermadi [%s]" % self.why(r))
        if r.status_code == 401:
            raise LoginError("kirish rad etildi (401) [%s]. Brauzerda kirish ishlasa — qurilma vaqtincha qulflangan bo'lishi mumkin, "
                               "30 daqiqa kuting" % self.why(r))
        if r.status_code == 403:
            raise RuntimeError("ruxsat yo'q (403): foydalanuvchida huquq yetarli emas yoki ISAPI o'chirilgan")
        r.raise_for_status()
        return r.json()

    @staticmethod
    def why(r):
        """401 javobidan sababni ajratib olish (tashxis uchun)."""
        import re
        txt, out = r.text or "", []
        for k in ("subStatusCode", "statusString", "lockStatus", "unlockTime", "retryLoginTime", "isActivated"):
            m = re.search(r'"?%s"?\s*[:>]\s*"?([^"<,}]+)' % k, txt)
            if m:
                out.append("%s=%s" % (k, m.group(1).strip()))
        auth = r.headers.get("WWW-Authenticate", "")
        out.append("usul=" + (auth.split(" ", 1)[0] or "-"))
        out.append(r.url.split(":", 1)[0].upper())
        return ", ".join(out)

    def events(self, start, end):
        """Berilgan oraliqdagi barcha kirish-nazorat voqealari (sahifalab)."""
        out, pos = [], 0
        while True:
            body = {"AcsEventCond": {
                "searchID": "yuksalish", "searchResultPosition": pos, "maxResults": 30,
                "major": 5, "minor": 0,
                "startTime": start.isoformat(timespec="seconds"),
                "endTime": end.isoformat(timespec="seconds")}}
            res = self.post("/ISAPI/AccessControl/AcsEvent?format=json", body).get("AcsEvent", {})
            items = res.get("InfoList") or []
            out += items
            pos += len(items)
            if res.get("responseStatusStrg") != "MORE" or not items:
                return out

    def users(self):
        """Turniketga kiritilgan barcha shaxslar: [(employeeNo, ism)].
        Qurilma ro'yxatni bermasa — so'nggi kunlardagi o'tishlardan (ism-familiya bilan) yig'iladi."""
        try:
            return self._users()
        except LoginError:
            raise
        except Exception as e:  # noqa: BLE001
            log.info("%s: shaxslar ro'yxati yopiq (%s) — so'nggi %d kundagi o'tishlardan olinadi...", self.name, e, USER_DAYS)
            now = dt.datetime.now(TZ).replace(microsecond=0)
            people = {}
            for it in self.events(now - dt.timedelta(days=USER_DAYS), now):
                emp, name = event_person(it)
                if emp and name:
                    people[emp] = name
            return list(people.items())

    def _users(self):
        out, pos = [], 0
        while True:
            body = {"UserInfoSearchCond": {"searchID": "yuksalish", "searchResultPosition": pos, "maxResults": 30}}
            res = self.post("/ISAPI/AccessControl/UserInfo/Search?format=json", body).get("UserInfoSearch", {})
            items = res.get("UserInfo") or []
            out += [(str(u.get("employeeNo", "")), u.get("name", "")) for u in items]
            pos += len(items)
            if res.get("responseStatusStrg") != "MORE" or not items:
                return out


class Platform:
    def __init__(self, cfg):
        self.url = cfg["supabase_url"].rstrip("/")
        self.token = cfg["token"]
        self.h = {"apikey": cfg["anon_key"], "Authorization": "Bearer " + cfg["anon_key"], "Content-Type": "application/json"}

    def rpc(self, fn, body):
        r = requests.post(f"{self.url}/rest/v1/rpc/{fn}", headers=self.h, json=body, timeout=30)
        if r.status_code >= 400:
            raise RuntimeError(f"{fn}: {r.status_code} {r.text[:300]}")
        return r.json()

    def push(self, events):
        return self.rpc("tk_push", {"p_token": self.token, "p_events": events})

    def map_ids(self, people):
        return self.rpc("tk_map", {"p_token": self.token, "p_people": people})


def event_person(item):
    """O'tish voqeasidagi shaxs: (employeeNo, ism)."""
    return str(item.get("employeeNoString") or item.get("employeeNo") or "").strip(), str(item.get("name") or "").strip()


def to_event(item, dev_name):
    emp = str(item.get("employeeNoString") or item.get("employeeNo") or "").strip()
    t = item.get("time")
    if not emp or not t:
        return None  # tanilmagan yuz/karta yoki tizim voqeasi
    return {"emp": emp, "ts": t, "door": dev_name}


def run_once(devices, platform, state):
    now = dt.datetime.now(TZ).replace(microsecond=0)
    sent = 0
    for d in devices:
        st = state.setdefault(d.name, {})
        if d.locked_out:
            continue  # parol noto'g'ri: qayta urinish qurilmani qulflab qo'yadi
        last = st.get("last")
        start = dt.datetime.fromisoformat(last) - dt.timedelta(minutes=2) if last else now.replace(hour=0, minute=0, second=0)
        seen = set(st.get("seen", []))
        try:
            items = d.events(start, now + dt.timedelta(minutes=1))
        except Exception as e:  # noqa: BLE001 — bitta turniket ishlamasa, qolganlari davom etadi
            if isinstance(e, LoginError):
                d.locked_out = True
                log.error("%s: login yoki parol noto'g'ri — qurilma qulflanmasligi uchun bu eshikka boshqa urinilmaydi. "
                          "Parolni to'g'rilab (1-SOZLASH.bat), dasturni qayta ishga tushiring.", d.name)
                continue
            if not st.get("err"):  # bir xil xatoni har 20 soniyada qayta yozmaslik uchun
                log.warning("%s: turniketdan o'qib bo'lmadi: %s", d.name, e)
            st["err"] = True
            continue
        if st.pop("err", None):
            log.info("%s: aloqa tiklandi", d.name)
        # Yangi ko'rilgan shaxslarni ism-familiya bo'yicha o'quvchilar bilan avtomatik bog'lash (davomatdan oldin)
        known = state.setdefault("_known", {})
        new = {}
        for it in items:
            emp, name = event_person(it)
            if emp and name and known.get(emp) != name:
                new[emp] = name
        if new:
            try:
                res = platform.map_ids([{"emp": k, "name": v} for k, v in new.items()])
                known.update(new)
                if res.get("boglandi"):
                    log.info("%s: %s ta yangi o'quvchi turniket bilan bog'landi", d.name, res["boglandi"])
            except Exception as e:  # noqa: BLE001
                log.warning("%s: o'quvchilarni bog'lab bo'lmadi: %s", d.name, e)
        batch = []
        for it in items:
            ev = to_event(it, d.name)
            key = f"{it.get('serialNo')}|{it.get('time')}|{ev and ev['emp']}"
            if ev and key not in seen:
                batch.append(ev)
                seen.add(key)
        if batch:
            try:
                n = platform.push(batch)
                sent += len(batch)
                log.info("%s: %d ta o'tish yuborildi, %d ta o'quvchiga davomat qo'yildi", d.name, len(batch), n)
            except Exception as e:  # noqa: BLE001
                log.warning("%s: platformaga yuborib bo'lmadi (keyingi safar qayta urinadi): %s", d.name, e)
                continue
        st["last"] = now.isoformat()
        st["seen"] = list(seen)[-2000:]
    return sent


def setup(cfg_name):
    """config.json ni savol-javob orqali yaratish (faylni qo'lda tahrirlash shart emas)."""
    base = load_json(cfg_name) or load_json("config.namuna.json")
    if not base:
        sys.exit("config.namuna.json topilmadi: turniket papkasidagi barcha fayllar joyidami?")
    print("\n=== Turniket ko'prigini sozlash ===\n")
    print("1) Supabase'dagi TURNIKET KALITI (SQL natijasida chiqqan uzun yozuv).")
    print("   Nusxalab, shu yerga sichqonchaning o'ng tugmasi bilan joylang va Enter bosing:")
    token = input("   Kalit: ").strip().strip('"')
    while len(token) < 20:
        token = input("   Kalit juda qisqa, qaytadan joylang: ").strip().strip('"')
    user = input("\n2) Turniket logini [admin]: ").strip() or "admin"
    print("\n3) Har bir eshik (turniket) paroli.")
    print("   Parol ekranda ko'rinadi — xato yozmaganingizni tekshirib, Enter bosing.")
    print("   (Bu oynani rasmga olmang.) Oldingi eshik bilan bir xil bo'lsa — hech narsa yozmay Enter bosing.")
    base["token"] = token
    pw = ""
    for d in base["devices"]:
        new = input(f"   {d.get('name')} ({d['host']}) paroli: ").strip()
        while not new and not pw:
            new = input("   Parol bo'sh bo'lmasin: ").strip()
        pw = new or pw
        d["user"], d["password"] = user, pw
    save_json(cfg_name, base)
    print("\n[OK] config.json saqlandi. Endi tekshiruv boshlanadi...\n")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--setup", action="store_true", help="kalit va parolni kiritib, config.json yaratish")
    ap.add_argument("--test", action="store_true", help="ulanishni tekshirish")
    ap.add_argument("--sync-ids", action="store_true", help="turniket ro'yxatini o'quvchilar bilan bog'lash")
    ap.add_argument("--config", default="config.json")
    a = ap.parse_args()

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s", datefmt="%Y-%m-%d %H:%M:%S",
                        handlers=[logging.StreamHandler(), logging.FileHandler(os.path.join(HERE, "turniket.log"), encoding="utf-8")])
    requests.packages.urllib3.disable_warnings()
    if a.setup or not load_json(a.config):
        setup(a.config)
        a.test = True
    cfg = load_json(a.config)
    if not cfg:
        sys.exit(f"{a.config} topilmadi. config.namuna.json dan nusxa olib, to'ldiring.")
    devices = [Device(x) for x in cfg["devices"]]
    platform = Platform(cfg)

    if a.test:
        ok = True
        for d in devices:
            try:
                n = len(d.events(dt.datetime.now(TZ).replace(hour=0, minute=0, second=0, microsecond=0), dt.datetime.now(TZ)))
                log.info("[OK]   %s: ulandi (%s), bugun %d ta voqea", d.name, d.base.split(":")[0].upper(), n)
            except Exception as e:  # noqa: BLE001
                ok = False
                log.error("[XATO] %s: %s", d.name, e)
        try:
            platform.push([])
            log.info("[OK]   Platforma: ulandi, kalit to'g'ri")
        except Exception as e:  # noqa: BLE001
            ok = False
            log.error("[XATO] Platforma: %s", e)
        sys.exit(0 if ok else 1)

    if a.sync_ids:
        people = {}
        for d in devices:
            try:
                for emp, name in d.users():
                    if emp:
                        people[emp] = name
                log.info("%s: ro'yxat olindi", d.name)
            except Exception as e:  # noqa: BLE001
                log.error("%s: ro'yxatni olib bo'lmadi: %s", d.name, e)
        log.info("Turniketlarda jami %d ta shaxs", len(people))
        res, items = {"boglandi": 0, "oldin_boglangan": 0, "boglanmadi": []}, [{"emp": k, "name": v} for k, v in people.items()]
        for i in range(0, len(items), 100):  # platforma vaqt chegarasiga sig'ishi uchun qismlarga bo'lib yuboriladi
            r = platform.map_ids(items[i:i + 100])
            res["boglandi"] += r["boglandi"]
            res["oldin_boglangan"] += r["oldin_boglangan"]
            res["boglanmadi"] += r["boglanmadi"]
        log.info("Bog'landi: %s, avval bog'langan: %s, bog'lanmadi: %d", res["boglandi"], res["oldin_boglangan"], len(res["boglanmadi"]))
        path = os.path.join(HERE, "boglanmaganlar.csv")
        with open(path, "w", encoding="utf-8-sig") as f:
            f.write("Turniket ID;Ism;Sabab\n")
            for m in res["boglanmadi"]:
                f.write(f"{m['emp']};{m['name']};{m['sabab']}\n")
        log.info("Bog'lanmaganlar ro'yxati: %s (ularni platformada Sozlamalar bo'limida qo'lda yozing)", path)
        return

    every = int(cfg.get("poll_seconds", 20))
    state = load_json("holat.json", {})
    log.info("Ko'prik ishga tushdi: %d ta turniket, har %d soniyada tekshiriladi", len(devices), every)
    while True:
        try:
            run_once(devices, platform, state)
            save_json("holat.json", state)
        except Exception as e:  # noqa: BLE001
            log.exception("Kutilmagan xato: %s", e)
        time.sleep(every)


if __name__ == "__main__":
    main()
