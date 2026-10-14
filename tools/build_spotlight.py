#!/usr/bin/env python3
"""Builds the Quick Play deck pool -> game/data/spotlight_decks.json.

Leaders are the real Expansion Spotlight Deck leaders (FFG):
  LOF  Darth Maul / Qui-Gon Jinn       SEC  Chancellor Palpatine / Padme Amidala
  LAW  Jabba the Hutt / Leia Organa    JTL  Boba Fett / Han Solo (pilot leaders)
  ASH  Luke Skywalker / Emperor Palpatine
The official 50-card lists are only published as images, so the card lists here
are PROVISIONAL: balanced 50-card decks built from the leader's own expansion
(then older sets) within the leader+base aspects. Paste official lists into the
"cards" maps to replace them (set "provisional": false).

Variants per mode:
  traditional / one_lane : the Spotlight list itself
  ground                 : same leader, ground units only (+ fitting events/upgrades)
  space                  : pilot leaders only (Jump to Lightspeed), space units only
Run after tools/import_cards.py:  python -I tools/build_spotlight.py
"""
from __future__ import annotations

import json
import random
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DB = ROOT / "game" / "ip" / "data" / "cards.json"
OUT = ROOT / "game" / "data" / "spotlight_decks.json"

SPOTLIGHT = [
    # (deck id, set, leader id, base id or None, label)
    ("lof_maul", "LOF", "LOF_009", None, "Legends of the Force — Darth Maul"),
    ("lof_quigon", "LOF", "LOF_016", None, "Legends of the Force — Qui-Gon Jinn"),
    ("sec_palpatine", "SEC", "SEC_001", "SEC_022", "Secrets of Power — Chancellor Palpatine"),
    ("sec_padme", "SEC", "SEC_016", None, "Secrets of Power — Padmé Amidala"),
    ("law_jabba", "LAW", "LAW_015", None, "A Lawless Time — Jabba the Hutt"),
    ("law_leia", "LAW", "LAW_010", None, "A Lawless Time — Leia Organa"),
    ("jtl_boba", "JTL", "JTL_009", None, "Jump to Lightspeed — Boba Fett"),
    ("jtl_han", "JTL", "JTL_017", None, "Jump to Lightspeed — Han Solo"),
    ("ash_luke", "ASH", "ASH_005", None, "Ashes of the Empire — Luke Skywalker"),
    ("ash_palpatine", "ASH", "ASH_015", None, "Ashes of the Empire — Emperor Palpatine"),
]
SET_ORDER = ["SOR", "SHD", "TWI", "JTL", "LOF", "SEC", "LAW", "HMW", "ASH", "IBH", "TS26"]
CURVE = {1: 6, 2: 10, 3: 10, 4: 9, 5: 7, 6: 5, 7: 3}   # target counts per cost (sums 50)
SPACE_TOKENS = ("tie fighter token", "x-wing token")
GROUND_TOKENS = ("battle droid token", "clone trooper token", "spy token")


def is_pilot_leader(c: dict) -> bool:
    return c["type"] == "leader" and "pilot" in c["traits"]


def fits_arena(c: dict, arena: str | None) -> bool:
    if arena is None:
        return True
    other = "space" if arena == "ground" else "ground"
    if c["type"] == "unit":
        return c.get("arena") == arena
    txt = c["text"].lower()
    if other in txt and arena not in txt:
        return False
    for t in (SPACE_TOKENS if arena == "ground" else GROUND_TOKENS):
        if t in txt:
            return False
    if arena == "ground" and "vehicle" in txt and "attach to a vehicle" in txt:
        return False
    return True


def build(cards: dict, leader: str, base: str, home_set: str, arena: str | None, seed: str) -> dict:
    L, B = cards[leader], cards[base]
    pool_aspects = L["aspects"] + B["aspects"]
    hero, vill = "heroism" in pool_aspects, "villainy" in pool_aspects
    rng = random.Random(seed)
    cands = []
    for c in cards.values():
        if c["type"] not in ("unit", "event", "upgrade") or c.get("custom"):
            continue
        if c["implemented"] == "manual":
            continue
        if any(a not in pool_aspects for a in c["aspects"]):
            continue
        if ("heroism" in c["aspects"] and vill) or ("villainy" in c["aspects"] and hero):
            continue
        if not fits_arena(c, arena):
            continue
        if arena is None and c["type"] == "unit" and c.get("arena") not in ("ground", "space"):
            continue
        # weight: own expansion first, fully supported cards first
        w = 4.0 if c["set"] == home_set else (1.5 if c["set"] in SET_ORDER[-4:] else 1.0)
        w *= 2.0 if c["implemented"] == "full" else 1.0
        cands.append((c, w))
    deck: dict[str, int] = {}

    def add_from(pool, n):
        pool = list(pool)
        for _ in range(n * 6):
            if n <= 0 or not pool:
                break
            tot = sum(w for _, w in pool)
            r = rng.uniform(0, tot)
            acc = 0.0
            for i, (c, w) in enumerate(pool):
                acc += w
                if acc >= r:
                    break
            c = pool[i][0]
            cap = 2 if c.get("unique") else 3
            if deck.get(c["id"], 0) >= cap:
                pool.pop(i)
                continue
            deck[c["id"]] = deck.get(c["id"], 0) + 1
            n -= 1
        return n

    # units by curve (~32), then events (~12) and upgrades (~6); space share ~1/3 in two-arena decks
    for cost, n in CURVE.items():
        units = [(c, w) for c, w in cands if c["type"] == "unit" and (c["cost"] == cost or (cost == 7 and c["cost"] >= 7))]
        if arena is None:
            sp = [(c, w) for c, w in units if c["arena"] == "space"]
            gr = [(c, w) for c, w in units if c["arena"] == "ground"]
            left = add_from(sp, round(n * 0.65 * 0.33))
            add_from(gr, round(n * 0.65) - round(n * 0.65 * 0.33) + left)
        else:
            add_from(units, round(n * 0.65))
    add_from([(c, w) for c, w in cands if c["type"] == "event"], 12)
    add_from([(c, w) for c, w in cands if c["type"] == "upgrade" and c["cost"] <= 4], 6)
    total = sum(deck.values())
    if total < 50:
        add_from([(c, w) for c, w in cands if c["type"] == "unit" and c["cost"] <= 4], 50 - total)
    while sum(deck.values()) > 50:
        k = rng.choice(list(deck))
        deck[k] -= 1
        if deck[k] == 0:
            del deck[k]
    return dict(sorted(deck.items()))


def pick_base(cards: dict, leader: dict, home_set: str) -> str:
    bases = sorted((c for c in cards.values() if c["type"] == "base" and c["set"] == home_set and not c.get("custom")), key=lambda c: c["id"])
    for b in bases:
        if b["aspects"] and b["aspects"][0] == leader["aspects"][0]:
            return b["id"]
    return bases[0]["id"]


def main() -> int:
    cards = json.loads(DB.read_text(encoding="utf-8"))["cards"]
    decks = []
    for did, st, leader, base, label in SPOTLIGHT:
        L = cards[leader]
        base = base or pick_base(cards, L, st)
        pilot = is_pilot_leader(L)
        entry = {
            "id": did, "name": label, "set": st, "leader": leader, "base": base,
            "pilot_leader": pilot, "provisional": True,
            "modes": ["space"] if pilot else ["traditional", "one_lane", "ground"],
            "cards": build(cards, leader, base, st, None, did),
        }
        if not pilot:
            entry["variants"] = {"ground": build(cards, leader, base, st, "ground", did + "_g")}
        else:
            entry["variants"] = {"space": build(cards, leader, base, st, "space", did + "_s")}
        decks.append(entry)
    # Space Only also gets every other pilot leader from Jump to Lightspeed
    have = {d["leader"] for d in decks}
    for c in sorted(cards.values(), key=lambda c: c["id"]):
        if is_pilot_leader(c) and c["id"] not in have:
            base = pick_base(cards, c, "JTL")
            decks.append({
                "id": "space_" + c["id"].lower(), "name": f"Squadron — {c['name']}", "set": c["set"],
                "leader": c["id"], "base": base, "pilot_leader": True, "provisional": True,
                "modes": ["space"], "cards": {},
                "variants": {"space": build(cards, c["id"], base, "JTL", "space", c["id"])},
            })
    out = {
        "_comment": "Quick Play decks. Spotlight leaders are official; card lists are provisional "
                    "(auto-balanced from the leader's expansion). Replace 'cards' with the official list "
                    "and set provisional=false. Generated by tools/build_spotlight.py.",
        "decks": decks,
    }
    OUT.write_text(json.dumps(out, indent=1, ensure_ascii=False), encoding="utf-8")
    for d in decks:
        sizes = {k: sum(v.values()) for k, v in [("main", d["cards"])] + list(d["variants"].items())}
        print(f"{d['id']:<24} {cards[d['leader']]['name']:<22} base={cards[d['base']]['name']:<28} {sizes}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
