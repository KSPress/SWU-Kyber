#!/usr/bin/env python3
"""Turns the engine card audit (game/tests/card_audit.gd output) into docs/card_audit.md.
  godot --headless --path game --script res://tests/card_audit.gd -- audit.json
  python -I tools/audit_report.py audit.json
"""
import collections
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
audit = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
cards = json.loads((ROOT / "game/ip/data/cards.json").read_text(encoding="utf-8"))["cards"]
by_type = collections.defaultdict(lambda: collections.Counter())
flagged = []
for cid, r in sorted(audit.items()):
    t = r["type"]
    by_type[t]["cards"] += 1
    by_type[t]["clean"] += 0 if r["issues"] else 1
    by_type[t][r.get("implemented", "")] += 1
    if r["issues"]:
        flagged.append((cid, r))
lines = ["# Engine card audit", "",
         "Every card is run through the real rules engine on a staged board (play it, answer every choice, "
         "attack, use action abilities, be defeated; leaders also deploy and attack; bases play a full bot game). "
         "A card is *clean* when nothing errored, stalled or broke a game invariant, and every automated ability "
         "visibly changed the game.", "",
         "| Type | Cards | Clean | Text fully automated | Partly automated | Text not automated |", "|---|---|---|---|---|---|"]
for t in ("leader", "base", "unit", "event", "upgrade"):
    c = by_type[t]
    lines.append(f"| {t} | {c['cards']} | {c['clean']} | {c['full']} | {c['partial']} | {c['manual']} |")
total = sum(by_type[t]["cards"] for t in by_type)
clean = sum(by_type[t]["clean"] for t in by_type)
lines += ["", f"**{clean} / {total} cards clean.** *Clean* means the engine handles the card safely; abilities whose "
          "text isn't automated yet are shown to the player as \"not automated\" and simply don't fire.", "",
          "## Flagged", "", "| Card | Issue | Why |", "|---|---|---|"]
why = {"no-op": "nothing on the audit board met its condition (expected)", "not usable": "its extra cost can't be met on the audit board (expected)"}
for cid, r in flagged:
    issue = "; ".join(r["issues"])
    reason = next((v for k, v in why.items() if k in issue), "")
    lines.append(f"| {cid} {cards[cid]['name']} | {issue} | {reason} |")
(ROOT / "docs/card_audit.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
print(f"wrote docs/card_audit.md ({clean}/{total} clean)")
