#!/usr/bin/env python3
"""Builds game/data/art_urls.json: card art key -> official card image URL.

  python -I tools/web/build_art_map.py

The public web build doesn't host any card art. Players' browsers load each
image straight from the official Star Wars: Unlimited image server
(cdn.starwarsunlimited.com, which allows cross-site requests), the same
source the official card database uses. This file is only the index of URLs
(IP-free), so it can live in the public repo. Re-run it when a new set comes out.

Source: https://admin.starwarsunlimited.com/api/cards (31 pages, ~180 MB; the
API can't trim its responses, so expect a few minutes).
"""
import json
import sys
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CARDS = ROOT / "game" / "ip" / "data" / "cards.json"
OUT = ROOT / "game" / "data" / "art_urls.json"
API = ("https://admin.starwarsunlimited.com/api/cards?pagination%5Bpage%5D={page}"
       "&pagination%5BpageSize%5D=100&filters%5BvariantOf%5D%5Bid%5D%5B%24null%5D=true")
CDN = "https://cdn.starwarsunlimited.com/"


def get(page: int) -> dict:
    for attempt in range(5):
        try:
            req = urllib.request.Request(API.format(page=page), headers={"User-Agent": "swu-kyber-art-map"})
            with urllib.request.urlopen(req, timeout=120) as r:
                return json.load(r)
        except Exception as e:  # noqa: BLE001 - retry anything network-ish
            print(f"  page {page}: {e} (retry {attempt + 1})")
            time.sleep(3 * (attempt + 1))
    sys.exit(f"could not fetch page {page}")


def url_of(rel: dict) -> str:
    data = (rel or {}).get("data") or {}
    return (data.get("attributes") or {}).get("url", "") or ""


official: dict = {}   # (SET, number) -> (front, back)
page, pages = 1, 1
while page <= pages:
    d = get(page)
    pages = d["meta"]["pagination"]["pageCount"]
    for c in d["data"]:
        a = c["attributes"]
        exp = ((a.get("expansion") or {}).get("data") or {}).get("attributes", {}).get("code", "")
        if not exp or a.get("cardNumber") is None:
            continue
        typ = (((a.get("type") or {}).get("data") or {}).get("attributes") or {}).get("value", "")
        # tokens are numbered 1, 2, 3... inside each set, alongside the real cards
        key = (exp.upper(), "T" if "token" in typ.lower() else "", int(a["cardNumber"]))
        if key not in official:
            official[key] = (url_of(a.get("artFront")), url_of(a.get("artBack")))
    print(f"page {page}/{pages}: {len(official)} cards")
    page += 1

db = json.loads(CARDS.read_text(encoding="utf-8"))["cards"]
out, missing = {}, []
for cid, c in db.items():
    if c.get("custom"):
        continue
    try:
        digits = "".join(ch for ch in str(c.get("number", "")) if ch.isdigit())
        key = (str(c.get("set", "")).upper(), "T" if "token" in str(c.get("type", "")) else "", int(digits or "0"))
    except ValueError:
        missing.append(cid)
        continue
    front, back = official.get(key, ("", ""))
    art = c.get("art", cid)
    if front:
        out[art] = front.replace(CDN, "")
    else:
        missing.append(cid)
    if c.get("art_back") is not None or c.get("type") == "leader":
        if back:
            out[art + "_b"] = back.replace(CDN, "")
OUT.write_text(json.dumps({"base": CDN, "art": dict(sorted(out.items()))}, separators=(",", ":")), encoding="utf-8")
print(f"{OUT}: {len(out)} images; {len(missing)} cards without official art: {' '.join(sorted(missing)[:40])}")
