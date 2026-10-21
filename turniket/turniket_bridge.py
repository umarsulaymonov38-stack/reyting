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
    from requests.auth import HTTPDigestAuth
except ImportError:
    sys.exit("'requests' kutubxonasi yo'q. O'rnatish: pip install requests")

HERE = os.path.dirname(os.path.abspath(__file__))
TZ = dt.timezone(dt.timedelta(hours=5))  # Toshkent vaqti
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


class Device:
    def __init__(self, cfg):
        self.name = cfg.get("name") or cfg["host"]
        self.base = ("https://" if cfg.get("https") else "http://") + cfg["host"]
        self.s = requests.Session()
        self.s.auth = HTTPDigestAuth(cfg["user"], cfg["password"])
        self.s.verify = False

    def post(self, path, body):
        r = self.s.post(self.base + path, json=body, timeout=15)
        r.raise_for_status()
        return r.json()

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
        """Turniketga kiritilgan barcha shaxslar: [(employeeNo, ism)]."""
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
        last = st.get("last")
        start = dt.datetime.fromisoformat(last) - dt.timedelta(minutes=2) if last else now.replace(hour=0, minute=0, second=0)
        seen = set(st.get("seen", []))
        try:
            items = d.events(start, now + dt.timedelta(minutes=1))
        except Exception as e:  # noqa: BLE001 — bitta turniket ishlamasa, qolganlari davom etadi
            if not st.get("err"):  # bir xil xatoni har 20 soniyada qayta yozmaslik uchun
                log.warning("%s: turniketdan o'qib bo'lmadi: %s", d.name, e)
            st["err"] = True
            continue
        if st.pop("err", None):
            log.info("%s: aloqa tiklandi", d.name)
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
    import getpass
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
    print("\n3) Turniket paroli (4 ta eshikda bir xil deb olinadi).")
    print("   Diqqat: yozayotganingiz ekranda KO'RINMAYDI — bu normal. Yozib, Enter bosing.")
    pw = getpass.getpass("   Parol: ")
    while not pw:
        pw = getpass.getpass("   Parol bo'sh bo'lmasin: ")
    base["token"] = token
    for d in base["devices"]:
        d["user"], d["password"] = user, pw
    save_json(cfg_name, base)
    print("\n✅ config.json saqlandi. Endi tekshiruv boshlanadi...\n")


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
                log.info("✅ %s: ulandi, bugun %d ta voqea", d.name, n)
            except Exception as e:  # noqa: BLE001
                ok = False
                log.error("❌ %s: %s", d.name, e)
        try:
            platform.push([])
            log.info("✅ Platforma: ulandi, kalit to'g'ri")
        except Exception as e:  # noqa: BLE001
            ok = False
            log.error("❌ Platforma: %s", e)
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
        res = platform.map_ids([{"emp": k, "name": v} for k, v in people.items()])
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
