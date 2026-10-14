#!/usr/bin/env python3
"""Card-assignment helper (spec 10.2): comb the imported DB for cards that fit a
film / chapter so they can be tagged into campaign pools.

Examples:
  python -I tools/assign_cards.py --names "Luke,R2-D2,C-3PO,Obi-Wan,Ben Kenobi" --side heroism
  python -I tools/assign_cards.py --traits tusken,creature --types unit --max-cost 5
  python -I tools/assign_cards.py --text "Death Star" --out docs/ep4_candidates.md

Output is a Markdown table (stdout or --out) with id, name, cost, stats, aspects,
arena, engine support and the first line of text, sorted by implementation
status so fully playable cards float to the top.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DB = ROOT / "game" / "ip" / "data" / "cards.json"
ORDER = {"full": 0, "partial": 1, "manual": 2}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--names", default="", help="comma list; substring match on name/subtitle")
    ap.add_argument("--traits", default="", help="comma list; any trait matches")
    ap.add_argument("--text", default="", help="substring in card text")
    ap.add_argument("--types", default="unit,event,upgrade,leader,base")
    ap.add_argument("--side", choices=["heroism", "villainy", "any"], default="any",
                    help="campaign gate: heroism excludes villainy cards and vice versa")
    ap.add_argument("--arena", choices=["ground", "space", "any"], default="any")
    ap.add_argument("--max-cost", type=int, default=99)
    ap.add_argument("--only-full", action="store_true")
    ap.add_argument("--out", default="")
    a = ap.parse_args()
    if not DB.exists():
        print("Run tools/import_cards.py first.", file=sys.stderr)
        return 1
    cards = json.loads(DB.read_text(encoding="utf-8"))["cards"]
    names = [n.strip().lower() for n in a.names.split(",") if n.strip()]
    traits = [t.strip().lower() for t in a.traits.split(",") if t.strip()]
    types = [t.strip() for t in a.types.split(",") if t.strip()]
    rows = []
    for c in cards.values():
        if c["type"] not in types or c["cost"] > a.max_cost:
            continue
        if a.side == "heroism" and "villainy" in c["aspects"]:
            continue
        if a.side == "villainy" and "heroism" in c["aspects"]:
            continue
        if a.arena != "any" and c.get("arena") not in (a.arena, None):
            continue
        if a.only_full and c["implemented"] != "full":
            continue
        hay = (c["name"] + " " + c["subtitle"]).lower()
        hit = False
        if names and any(n in hay for n in names):
            hit = True
        if traits and any(t in c["traits"] for t in traits):
            hit = True
        if a.text and a.text.lower() in c["text"].lower():
            hit = True
        if not (names or traits or a.text):
            hit = True
        if hit:
            rows.append(c)
    rows.sort(key=lambda c: (ORDER.get(c["implemented"], 3), c["cost"], c["name"]))
    out = ["| id | name | cost | P/HP | aspects | arena | support | text |", "|---|---|---|---|---|---|---|---|"]
    for c in rows:
        name = c["name"] + (f", {c['subtitle']}" if c["subtitle"] else "")
        stats = f"{c['power']}/{c['hp']}" if c["type"] in ("unit", "leader") else ("-" if c["type"] != "base" else f"{c['hp']} HP")
        first = c["text"].split("\n")[0][:70].replace("|", "/")
        out.append(f"| {c['id']} | {name} | {c['cost']} | {stats} | {'/'.join(c['aspects'])} | {c.get('arena') or ''} | {c['implemented']} | {first} |")
    text = "\n".join(out) + f"\n\n{len(rows)} cards\n"
    if a.out:
        Path(a.out).write_text(text, encoding="utf-8")
        print(f"wrote {len(rows)} rows to {a.out}")
    else:
        sys.stdout.reconfigure(encoding="utf-8")
        print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
