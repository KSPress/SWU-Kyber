#!/usr/bin/env python3
"""SWU Kyber card importer.

Reads the raw SWU-DB dump (swu_data/cards_all.json), keeps one entry per unique
printed card (VariantType == "Normal"), normalises it to the game schema
(build spec section 7.1) and compiles card text into the effect DSL that the
Godot rules engine (game/engine/effects.gd) executes.

Outputs (all IP-bearing, git-ignored):
  game/ip/data/cards.json        normalised card database
  docs/coverage_report.md        what the DSL can / cannot express yet

Usage:  python -I tools/import_cards.py [--src swu_data/cards_all.json]
Stdlib only, so it runs anywhere Python 3.9+ exists.
"""
from __future__ import annotations

import argparse
import collections
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_SRC = ROOT / "swu_data" / "cards_all.json"
OUT = ROOT / "game" / "ip" / "data" / "cards.json"
REPORT = ROOT / "docs" / "coverage_report.md"

TYPE_MAP = {
    "Unit": "unit", "Event": "event", "Upgrade": "upgrade", "Leader": "leader", "Base": "base",
    "Token Unit": "token_unit", "Token Upgrade": "token_upgrade",
    "Force Token": "force_token", "Credit Token": "credit_token",
}
# Keywords the engine implements natively (no DSL needed).
NATIVE_KEYWORDS = {"sentinel", "shielded", "grit", "saboteur", "ambush", "overwhelm", "raid",
                   "restore", "hidden", "smuggle", "exploit", "coordinate", "piloting",
                   "bounty", "support", "plot", "fortify"}
VALUE_KEYWORDS = {"raid", "restore", "exploit"}
NUM_WORDS = {"a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6}

# ---------------------------------------------------------------------------
# helpers


def card_id(set_code: str, number: str) -> str:
    """SET_NNN, tokens SET_T01. Matches art filenames (tokens: SET_001T.png)."""
    number = number.strip()
    if number.upper().startswith("T"):
        return f"{set_code}_T{int(number[1:]):02d}"
    if number.isdigit():
        return f"{set_code}_{int(number):03d}"
    return f"{set_code}_{number}"


def art_name(cid: str) -> str:
    s, n = cid.split("_", 1)
    if n.startswith("T"):
        return f"{s}_{int(n[1:]):03d}T"
    return cid


def to_int(v, default=None):
    try:
        return int(str(v).strip())
    except (TypeError, ValueError):
        return default


def num(word: str) -> int:
    word = word.lower().strip()
    if word.isdigit():
        return int(word)
    return NUM_WORDS.get(word, 1)


def strip_reminders(text: str) -> str:
    return re.sub(r"\s*\([^()]*\)", "", text)


def norm_text(text: str) -> str:
    text = text.replace("–", "-").replace("—", "-").replace("’", "'")
    text = text.replace("“", '"').replace("”", '"').replace("{", "").replace("}", "")
    return text


# ---------------------------------------------------------------------------
# target phrase -> target selector

STOPWORDS = {"a", "an", "the", "that", "with", "shares", "aspect", "of", "to", "and", "or", "for", "each",
              "this", "it", "its", "you", "your", "their", "in", "on", "from", "is", "was", "who", "which",
              "attacking", "defending", "played", "control", "controls", "named", "card", "cards", "token"}


def parse_target(phrase: str) -> dict | None:
    """Turn 'an enemy non-leader ground unit with 3 or less remaining HP' into a selector."""
    p = phrase.strip().rstrip(".").lower()
    p = re.sub(r"^(?:to|from|on) ", "", p)
    simple = {
        "this unit": {"s": "self"}, "it": {"s": "it"}, "him": {"s": "self"}, "her": {"s": "self"},
        "your base": {"s": "own_base"}, "the defender": {"s": "defender"},
        "the defending unit": {"s": "defender"}, "attached unit": {"s": "attached"},
        "an enemy base": {"s": "enemy_base"}, "each enemy base": {"s": "enemy_base"},
        "the defending player's base": {"s": "enemy_base"}, "a base": {"s": "choose", "kind": "base", "side": "any"},
        "each base": {"s": "each", "kind": "base", "side": "any"},
        "this leader": {"s": "self"},
    }
    if p in simple:
        return dict(simple[p])
    t: dict = {"s": "choose", "kind": "unit", "side": "any"}
    m = re.match(r"^(each|a|an|another|up to (\w+)|(\w+)) ", p)
    if not m:
        return None
    lead = m.group(1)
    rest = p[m.end():]
    if lead == "each":
        t["s"] = "each"
    elif lead == "another":
        t["other"] = True
    elif lead.startswith("up to"):
        t["count"] = num(m.group(2)); t["upto"] = True
    elif lead not in ("a", "an"):
        if m.group(3) and m.group(3) in NUM_WORDS:
            t["count"] = num(m.group(3))
        else:
            return None
    # words before "unit"
    m2 = re.match(r"^((?:other |enemy |friendly |non-leader |damaged |exhausted |ready |non-unique |unique |"
                  r"ground |space |non-vehicle |vehicle |[a-z]+ )*)(units?|bases?|units? or bases?)(.*)$", rest)
    if not m2:
        return None
    adjs, noun, tail = m2.group(1).split(), m2.group(2), m2.group(3).strip()
    # "creature or spectre unit" -> any of these traits
    if "or" in adjs and adjs.index("or") > 0 and adjs.index("or") < len(adjs) - 1:
        i = adjs.index("or")
        t["traits_any"] = [adjs[i - 1], adjs[i + 1]]
        adjs = adjs[:i - 1] + adjs[i + 2:]
    if "token" in adjs:
        t["token"] = True
        adjs = [a for a in adjs if a != "token"]
    if "different" in adjs:
        t["different"] = True
        adjs = [a for a in adjs if a != "different"]
    if any(a in STOPWORDS for a in adjs):
        return None
    if noun.startswith("base"):
        t["kind"] = "base"
    elif "or base" in noun:
        t["kind"] = "unit_or_base"
    for a in adjs:
        if a == "other": t["other"] = True
        elif a == "enemy": t["side"] = "enemy"
        elif a == "friendly": t["side"] = "friendly"
        elif a == "non-leader": t["nonleader"] = True
        elif a == "damaged": t["damaged"] = True
        elif a == "exhausted": t["exhausted"] = True
        elif a == "ready": t["ready"] = True
        elif a in ("ground", "space"): t["arena"] = a
        elif a == "unique": t["unique"] = True
        elif a == "non-unique": t["unique"] = False
        elif a == "non-vehicle": t["not_trait"] = "vehicle"
        elif a == "random": t["random"] = True
        elif a == "upgraded": t["upgraded"] = True
        elif a in ("vehicle",): t["trait"] = "vehicle"
        elif a in ("heroism", "villainy", "vigilance", "command", "aggression", "cunning"): t["aspect"] = a
        else: t["trait"] = a  # e.g. "rebel", "trooper", "tusken", "force"
    if True:
        mmin = re.match(r"^with (\d+) or more (remaining hp|hp|power)$", tail)
        mwo = re.match(r"^without an? (experience|shield) token on it$", tail)
        if mmin:
            t["min_hp" if "hp" in mmin.group(2) else "min_power"] = int(mmin.group(1))
            tail = ""
        elif mwo:
            t["without_token"] = mwo.group(1)
            tail = ""
        m3 = re.match(r"^with (\d+) or less (remaining hp|hp|power|cost)$", tail) or \
             re.match(r"^that costs (\d+) or less()$", tail)
        m4 = re.match(r"^in (?:this|the) (ground|space) arena$", tail)
        if m3:
            key = {"remaining hp": "max_hp", "hp": "max_hp", "power": "max_power", "cost": "max_cost", "": "max_cost"}[m3.group(2)]
            t[key] = int(m3.group(1))
        elif m4:
            t["arena"] = m4.group(1)
        elif tail in ("in this arena", "in the same arena"):
            t["same_arena"] = True
        elif tail == "you control":
            t["side"] = "friendly"
        elif tail == "an opponent controls":
            t["side"] = "enemy"
        elif tail == "":
            pass
        else:
            return None
    return t


TOKEN_NAMES = {"battle droid": "battle_droid", "clone trooper": "clone_trooper", "tie fighter": "tie_fighter",
               "x-wing": "x_wing", "spy": "spy", "mandalorian": "mandalorian", "credit": "credit",
               "beast": "beast"}

# ---------------------------------------------------------------------------
# sentence -> effect


def compile_sentence(s: str) -> list | None:
    s = s.strip().rstrip(".").strip()
    if not s:
        return []
    low = s.lower()
    opt = False
    if low.startswith("you may "):
        opt = True
        s = s[8:]
        low = low[8:]

    def wrap(eff):
        if opt:
            eff["optional"] = True
            if "t" in eff and eff["t"].get("s") == "choose":
                eff["t"]["opt"] = True
        return [eff]

    m = re.match(r"^deal (\d+) damage to (.+)$", low)
    if m and parse_target(m.group(2)):
        return wrap({"op": "damage", "n": int(m.group(1)), "t": parse_target(m.group(2))})
    m = re.match(r"^deal (\d+) damage to (.+) and (\d+) damage to (.+)$", low)
    if m:
        t1, t2 = parse_target(m.group(2)), parse_target(m.group(4))
        if t1 and t2:
            return [{"op": "damage", "n": int(m.group(1)), "t": t1}, {"op": "damage", "n": int(m.group(3)), "t": t2}]
    m = re.match(r"^heal (\d+) damage from (.+)$", low)
    if m:
        t = parse_target(m.group(2))
        return wrap({"op": "heal", "n": int(m.group(1)), "t": t}) if t else None
    m = re.match(r"^heal all damage from (.+)$", low)
    if m:
        t = parse_target(m.group(1))
        return wrap({"op": "heal", "n": 999, "t": t}) if t else None
    m = re.match(r"^draw (a|an|one|two|three|\d+) cards?$", low)
    if m:
        return wrap({"op": "draw", "n": num(m.group(1))})
    m = re.match(r"^discard (a|one|two|\d+) cards? from your hand$", low)
    if m:
        return wrap({"op": "discard", "n": num(m.group(1)), "who": "self"})
    m = re.match(r"^each opponent discards (a|one|two|\d+) cards? from their hand$", low) or \
        re.match(r"^an opponent discards (a|one|two|\d+) cards? from their hand$", low)
    if m:
        return wrap({"op": "discard", "n": num(m.group(1)), "who": "opponent"})
    m = re.match(r"^give (a|an|one|two|three|\d+) (shield|experience) tokens? to (.+)$", low)
    if m:
        t = parse_target(m.group(3))
        return wrap({"op": m.group(2), "n": num(m.group(1)), "t": t}) if t else None
    m = re.match(r"^give (.+?) (a|an|one|two|three|\d+) (shield|experience) tokens?$", low)
    if m:
        t = parse_target(m.group(1))
        return wrap({"op": m.group(3), "n": num(m.group(2)), "t": t}) if t else None
    m = re.match(r"^(exhaust|ready|defeat) (.+)$", low)
    if m and not m.group(2).startswith(("a resource", "this leader", "your")):
        t = parse_target(m.group(2))
        return wrap({"op": m.group(1), "t": t}) if t else None
    m = re.match(r"^ready (a|one|two|\d+) resources?$", low)
    if m:
        return wrap({"op": "ready_resource", "n": num(m.group(1))})
    m = re.match(r"^return (.+?) to (?:its|their) owner's hand$", low)
    if m:
        t = parse_target(m.group(1))
        return wrap({"op": "bounce", "t": t}) if t else None
    m = re.match(r"^(.+?) gets? ([+-]\d+)/([+-]\d+) for this (phase|attack)$", low) or \
        re.match(r"^give (.+?) ([+-]\d+)/([+-]\d+) for this (phase|attack)$", low)
    if m:
        t = parse_target(m.group(1))
        return wrap({"op": "buff", "p": int(m.group(2)), "h": int(m.group(3)), "dur": m.group(4), "t": t}) if t else None
    m = re.match(r"^(.+?) gains (sentinel|saboteur|overwhelm|grit|ambush|hidden|raid \d+|restore \d+) for this (phase|attack)$", low) or \
        re.match(r"^give (.+?) (sentinel|saboteur|overwhelm|grit|hidden|raid \d+|restore \d+) for this (phase|attack)$", low)
    if m:
        t = parse_target(m.group(1))
        kw = m.group(2).split()
        eff = {"op": "gain_kw", "kw": kw[0], "dur": m.group(3), "t": t}
        if len(kw) > 1:
            eff["v"] = int(kw[1])
        return wrap(eff) if t else None
    m = re.match(r"^(.+?) loses (sentinel) for this phase$", low)
    if m:
        t = parse_target(m.group(1))
        return wrap({"op": "lose_kw", "kw": m.group(2), "dur": "phase", "t": t}) if t else None
    m = re.match(r"^create (a|an|one|two|three|\d+) (battle droid|clone trooper|tie fighter|x-wing|spy|mandalorian|credit|beast) tokens?$", low)
    if m:
        return wrap({"op": "token", "name": TOKEN_NAMES[m.group(2)], "n": num(m.group(1))})
    # "Deal 1 damage to a unit and 1 damage to a different unit"
    m = re.match(r"^deal (\d+) damage to (.+?) and (\d+) damage to (.+)$", low)
    if m:
        t1, t2 = parse_target(m.group(2)), parse_target(m.group(4))
        if t1 and t2:
            return [{"op": "damage", "n": int(m.group(1)), "t": t1}, {"op": "damage", "n": int(m.group(3)), "t": t2}]
    # "Play a [Trait] unit|event|card from your hand [(paying its cost)]"
    m = re.match(r"^play (a|an|2) ((?:[a-z-]+ )*?)(unit|event|card|upgrade|non-unit card)( that costs (\d+) or less)?( with (\d+) or less power)? from your hand(.*)$", low)
    if m:
        words = m.group(2).replace("capital ship", "capital_ship").replace("bounty hunter", "bounty_hunter").replace("first order", "first_order").replace("new republic", "new_republic").split()
        words = [w.replace("_", " ") for w in words]
        eff = {"op": "play_from_hand", "kind": m.group(3), "count": 2 if m.group(1) == "2" else 1}
        aspects = {"heroism", "villainy", "vigilance", "command", "aggression", "cunning"}
        for w in words:
            if w in aspects:
                eff["aspect"] = w
            elif w == "non-unit":
                eff["kind"] = "non-unit"
            else:
                eff.setdefault("traits_any", []).append(w.rstrip(","))
        if "or" in eff.get("traits_any", []):
            eff["traits_any"] = [w for w in eff["traits_any"] if w != "or"]
        if m.group(5):
            eff["max_cost"] = int(m.group(5))
        if m.group(7):
            eff["max_power"] = int(m.group(7))
        rest = m.group(8)
        if "ignoring its aspect penalties" in rest or "ignoring its" in rest:
            eff["ignore_aspects"] = True
        mm = re.search(r"it costs (\d+) less", rest)
        if mm:
            eff["discount"] = int(mm.group(1))
        if "enters play ready" in rest:
            eff["ready"] = True
        if "give it ambush" in rest:
            eff["gain_kw"] = "ambush"
        leftover = re.sub(r"\(paying (?:its|their) costs?\)|, ignoring its aspect penalties|ignoring its aspect penalties|"
                          r"\. it costs \d+ less|it costs \d+ less|\. it enters play ready|and give it ambush for this phase|"
                          r"(?:one at a time, )|[ .,]", "", rest)
        if leftover:
            return None
        return wrap(eff)
    m = re.match(r"^it costs (\d+) less$", low)
    if m:
        return [{"op": "_mod_last_play", "discount": int(m.group(1))}]
    m = re.match(r"^it enters play ready$", low)
    if m:
        return [{"op": "_mod_last_play", "ready": True}]
    m = re.match(r"^attack with an? ((?:[a-z-]+ )*)unit( that costs (\d+) or less)?$", low)
    if m and m.group(1).strip() not in ("", "another", "friendly"):
        t = {"s": "choose", "kind": "unit", "side": "friendly", "ready": True}
        for w in m.group(1).split():
            if w in ("ground", "space"):
                t["arena"] = w
            elif w == "damaged":
                t["damaged"] = True
            elif w == "non-leader":
                t["nonleader"] = True
            elif w == "token":
                t["token"] = True
            elif w == "upgraded":
                t["upgraded"] = True
            elif w == "unique":
                t["unique"] = True
            elif w != "friendly":
                t["trait"] = w
        if m.group(3):
            t["max_cost"] = int(m.group(3))
        return wrap({"op": "attack_with", "t": t})
    m = re.match(r"^attack with (a|another) (friendly )?unit$", low) or re.match(r"^attack with a unit$", low)
    if m:
        return wrap({"op": "attack_with", "t": {"s": "choose", "kind": "unit", "side": "friendly",
                                                "ready": True, "other": "another" in low}})
    m = re.match(r"^either (.+?),? or (.+)$", low)
    if m:
        opts = []
        for part in (m.group(1), m.group(2)):
            c = compile_sentence(part[0].upper() + part[1:])
            if c is None:
                return None
            opts.append({"label": part[0].upper() + part[1:], "effects": c})
        return [{"op": "choose_one", "options": opts, "who": "self", "optional": opt}]
    m = re.match(r"^use the force$", low)
    if m:
        return wrap({"op": "use_force"})
    m = re.match(r"^the force is with you$", low)
    if m:
        return wrap({"op": "force_token"})
    return None


SPLIT_SENT = re.compile(r"(?<=[.!])\s+(?=[A-Z])")


def compile_condition(phrase: str) -> dict | None:
    p = phrase.lower().strip()
    m = re.match(r"^you attacked with an? ((?:[a-z-]+ )*?)unit this phase$", p)
    if m:
        return {"attacked_trait": m.group(1).strip().replace("non-token ", "")}
    m = re.match(r"^you played an? ((?:[a-z-]+ )*?)card this phase$", p)
    if m:
        return {"played_trait": m.group(1).strip()}
    m = re.match(r"^an? friendly ((?:[a-z-]+ )*?)unit was defeated this phase$", p)
    if m:
        return {"friendly_defeated_trait": m.group(1).strip()}
    m = re.match(r"^(\d+|two) or more friendly units were defeated this phase$", p)
    if m:
        return {"friendly_defeated_min": 2 if m.group(1) == "two" else int(m.group(1))}
    m = re.match(r"^you control (.+)$", p)
    if m:
        t = parse_target(m.group(1))
        if t and t.get("kind") == "unit":
            t["side"] = "friendly"
            t["s"] = "count"
            return {"control": t, "min": t.pop("count", 1)}
    m = re.match(r"^you control (\d+|two|three|four) or more (.+)$", p)
    if m:
        t = parse_target("a " + m.group(2).rstrip("s"))
        if t:
            t["side"] = "friendly"; t["s"] = "count"
            return {"control": t, "min": num(m.group(1))}
    m = re.match(r"^an enemy unit was defeated this phase$", p)
    if m:
        return {"enemy_defeated_this_phase": True}
    m = re.match(r"^(?:you have|you control) the initiative$", p)
    if m:
        return {"has_initiative": True}
    m = re.match(r"^it's damaged$|^this unit is damaged$", p)
    if m:
        return {"self_damaged": True}
    return None


def compile_special(sent: str) -> list | None:
    low = sent.lower().rstrip(".")
    m = re.match(r"^look at the top card of your deck$", low)
    if m:
        return [{"op": "scry", "n": 1}]
    m = re.match(r"^you may put it on the bottom of your deck$", low)
    if m:
        return []  # folded into scry
    m = re.match(r"^search the top (\d+|\w+) cards of your deck for (a|an|up to \w+) (.+?), reveal (?:it|them),? and draw (?:it|them)$", low)
    if m:
        what = m.group(3)
        if what.endswith(("card", "cards")):
            tw = what.replace(" cards", "").replace(" card", "").split()
            if len(tw) > 1 or (tw and tw[0] in STOPWORDS):
                return None
            filt = {"kind": "card", "trait": tw[0]} if tw else {"kind": "card"}
        else:
            filt = parse_target("a " + re.sub(r"s$", "", what))
            if not filt:
                return None
            filt.pop("s", None)
        return [{"op": "search", "n": num(m.group(1)), "filter": filt,
                 "count": num(m.group(2).split()[-1]) if m.group(2).startswith("up to") else 1}]
    return None


def inert(effects: list, ok: bool) -> bool:
    if ok or not effects:
        return False
    first = effects[0]
    return bool(first.get("if_did") or first.get("t", {}).get("s") == "it" or first.get("op", "").startswith("_"))


def compile_body(body: str) -> tuple[list, bool]:
    if re.search(r"chooses? one:", body, re.I):
        c = compile_choose_one(body.strip())
        return (c, True) if c else ([], False)
    effects, ok = [], True
    for sent in SPLIT_SENT.split(body.strip()):
        sent = sent.strip()
        if not sent:
            continue
        low = sent.lower()
        cond, if_did = None, False
        m = re.match(r"^if (.+?), (.+)$", sent, re.I)
        if m and m.group(1).lower() == "you do":
            if_did, sent = True, m.group(2)
        elif m:
            cond = compile_condition(m.group(1))
            if cond is None:
                ok = False
                continue
            sent = m.group(2)
        elif re.match(r"^then,? ", low):
            sent = re.sub(r"^then,? ", "", sent, flags=re.I)
        sp = compile_special(sent)
        if sp is not None:
            effects += sp
            continue
        if re.match(r"^(otherwise|while|choose|an opponent chooses|search|look|reveal|for each)", sent.lower()):
            ok = False
            continue
        c = compile_sentence(sent[0].upper() + sent[1:])
        if c is None and " and " in sent:
            a_part, b_part = sent.split(" and ", 1)
            ca = compile_sentence(a_part[0].upper() + a_part[1:])
            cb = compile_sentence(b_part[0].upper() + b_part[1:])
            if ca is not None and cb is not None:
                c = ca + cb
        if c is None:
            ok = False
            continue
        for e in c:
            if cond:
                e["if"] = cond
            if if_did:
                e["if_did"] = True
        effects += c
    # "Attack with a unit. It gets +3/+0 for this attack." -> buff applied before combat
    merged = []
    for e in effects:
        if merged and merged[-1]["op"] == "play_from_hand" and e["op"] == "_mod_last_play":
            merged[-1].update({k: v for k, v in e.items() if k != "op"})
            continue
        if merged and merged[-1]["op"] == "attack_with" and e["op"] in ("buff", "gain_kw")                 and e.get("t", {}).get("s") == "it" and e.get("dur") == "attack":
            merged[-1].setdefault("pre", []).append(e)
        else:
            merged.append(e)
    return merged, ok


TRIGGERS = [
    (r"^when played/on attack", ["when_played", "on_attack"]),
    (r"^on attack/when defeated", ["on_attack", "when_defeated"]),
    (r"^when played/when defeated", ["when_played", "when_defeated"]),
    (r"^when played as an upgrade", ["when_played_upgrade"]),
    (r"^when played", ["when_played"]),
    (r"^on attack", ["on_attack"]),
    (r"^when defeated", ["when_defeated"]),
    (r"^when deployed", ["when_deployed"]),
    (r"^when attack ends", ["attack_end"]),
    (r"^when this unit completes an attack", ["attack_end"]),
    (r"^when the regroup phase starts", ["regroup_start"]),
    (r"^when the action phase starts", ["action_start"]),
    (r"^when this unit deals combat damage to a base", ["base_damage"]),
]


def parse_action_cost(inner: str) -> dict:
    cost = {"exhaust": False, "resources": 0}
    for part in [p.strip().lower() for p in inner.split(",")]:
        if part == "exhaust":
            cost["exhaust"] = True
        elif part.startswith("c="):
            cost["resources"] = to_int(part[2:], 0)
        elif part:
            cost["other"] = part
    return cost


CHOICE_SEP = " \u2016 "   # joins option lines into one logical line


def merge_choose_one(text: str) -> str:
    """Fold 'Choose one:' + following option lines into a single line so the
    per-line compiler sees the whole modal ability."""
    lines = text.split("\n")
    out = []
    i = 0
    while i < len(lines):
        line = lines[i].rstrip()
        if re.search(r"(choose|chooses) one:\s*$", strip_reminders(line).strip(), re.I):
            opts = []
            j = i + 1
            while j < len(lines):
                nxt = strip_reminders(lines[j]).strip()
                if not nxt:
                    j += 1
                    continue
                if re.match(r"^(when |on attack|action \[|epic action|attached unit|smuggle|bounty|coordinate|piloting)", nxt, re.I):
                    break
                opts.append(nxt.lstrip("\u2022- ").strip())
                j += 1
            out.append(line.strip() + " " + CHOICE_SEP.join(opts))
            i = j
            continue
        out.append(lines[i])
        i += 1
    return "\n".join(out)


def compile_choose_one(body: str):
    """'Choose one: A || B' -> choose_one effect (or None if an option can't compile)."""
    who = "self"
    m = re.match(r"^(an opponent|each opponent) chooses? one:\s*(.+)$", body, re.I)
    if m:
        who = "opponent"
        rest = m.group(2)
    else:
        m = re.match(r"^(?:for each opponent, )?choose one:\s*(.+)$", body, re.I)
        if not m:
            return None
        rest = m.group(1)
    parts = [p.strip() for p in rest.split(CHOICE_SEP.strip()) if p.strip()]
    if len(parts) == 1 and re.match(r"^either ", parts[0], re.I):
        e = compile_sentence(parts[0])
        if e:
            e[0]["who"] = who
        return e
    opts = []
    for part in parts:
        effs, ok = compile_body(part)
        if not ok or not effs:
            return None
        opts.append({"label": part.rstrip("."), "effects": effs})
    if len(opts) < 2:
        return None
    return [{"op": "choose_one", "options": opts, "who": who}]


def compile_text(text: str, keywords: list) -> tuple[list, list, str]:
    """Return (abilities, gains, status) where status is full|partial|manual|vanilla."""
    if not text:
        return [], [], "full"
    text = norm_text(text)
    abilities, unparsed, parsed = [], [], 0
    text = merge_choose_one(text)
    for raw_line in text.split("\n"):
        line = strip_reminders(raw_line).strip()
        if not line:
            continue
        low = line.lower()
        # keyword lines are handled natively
        first = re.split(r"[\s\[\-]", low, maxsplit=1)[0]
        if first in NATIVE_KEYWORDS and (len(line.split()) <= 3 or first in ("smuggle", "piloting", "bounty", "coordinate", "exploit")):
            if first in ("bounty", "coordinate"):
                unparsed.append(line)  # their sub-abilities are not compiled yet
            else:
                parsed += 1
            continue
        if low.startswith("attach to"):
            parsed += 1
            continue
        m = re.match(r"^action \[([^\]]*)\]:\s*(.+)$", line, re.I)
        if m:
            eff, ok = compile_body(m.group(2))
            if eff and not inert(eff, ok):
                abilities.append({"trigger": "action", "cost": parse_action_cost(m.group(1)), "effects": eff, "text": line})
            else:
                eff = [] if inert(eff, ok) else eff
            (parsed := parsed + 1) if ok and eff else unparsed.append(line)
            continue
        m = re.match(r"^attached unit gains:?\s*\"?(.+?)\"?$", line, re.I)
        if m:
            inner = m.group(1).strip().strip('"')
            sub, _, sub_status = compile_text(inner, [])
            kw = re.match(r"^(sentinel|saboteur|overwhelm|grit|ambush|hidden|raid \d+|restore \d+)$", inner.lower())
            if kw:
                parts = inner.lower().split()
                abilities.append({"trigger": "attached_kw", "kw": parts[0], "v": to_int(parts[1], 0) if len(parts) > 1 else 0, "text": line})
                parsed += 1
            elif sub and sub_status == "full":
                for a in sub:
                    a["granted"] = True
                abilities += sub
                parsed += 1
            else:
                unparsed.append(line)
            continue
        mf = re.match(r"^when a friendly ([a-z ]+?) unit attacks\s*:\s*(.+)$", line, re.I)
        if mf:
            eff, ok = compile_body(mf.group(2))
            if eff and ok:
                abilities.append({"trigger": "friendly_attack", "trait": mf.group(1).lower(), "effects": eff, "text": line})
                parsed += 1
            else:
                unparsed.append(line)
            continue
        matched = False
        for pat, trig in TRIGGERS:
            mm = re.match(pat + r"\s*:\s*(.+)$", line, re.I)
            if mm:
                matched = True
                eff, ok = compile_body(mm.group(1))
                if inert(eff, ok):
                    eff = []
                if eff:
                    for tg in trig:
                        abilities.append({"trigger": tg, "effects": eff, "text": line})
                (parsed := parsed + 1) if ok and eff else unparsed.append(line)
                break
        if matched:
            continue
        # constant abilities we understand
        mm = re.match(r"^(?:this unit|he|she) can't attack bases$", low)
        if mm:
            abilities.append({"trigger": "constant", "flag": "no_base_attack", "text": line}); parsed += 1; continue
        # bare event body ("Deal 3 damage to a unit.")
        eff, ok = compile_body(line)
        if eff and ok:
            abilities.append({"trigger": "event", "effects": eff, "text": line}); parsed += 1
        else:
            unparsed.append(line)
    if not unparsed:
        status = "full"
    elif parsed or abilities:
        status = "partial"
    else:
        status = "manual"
    return abilities, unparsed, status


def parse_keywords(card: dict, text: str) -> list:
    out, seen = [], set()
    text = norm_text(text or "")
    listed = [k.lower() for k in card.get("Keywords") or []]
    # The DB sometimes omits keywords from its list; bare keyword lines in the text count too.
    for line in text.split("\n"):
        m = re.match(r"^\s*([A-Za-z]+)(?:\s+\d+)?\s*(?:\(|$|\[|-)", strip_reminders(line) + "\n" if False else line)
        if m and m.group(1).lower() in NATIVE_KEYWORDS and m.group(1).lower() not in listed:
            listed.append(m.group(1).lower())
    for kw in listed:
        k = kw.lower()
        if k in ("keyword", "keywords") or k in seen:
            continue
        seen.add(k)
        entry = {"k": k}
        if k in VALUE_KEYWORDS:
            m = re.search(rf"\b{k}\s+(\d+)", text, re.I)
            entry["v"] = int(m.group(1)) if m else 1
        if k in ("smuggle", "piloting"):
            m = re.search(rf"\b{k}\s*\[\s*C=(\d+)([^\]]*)\]", text, re.I)
            if m:
                entry["v"] = int(m.group(1))
                entry["aspects"] = [a.lower() for a in m.group(2).split()]
        out.append(entry)
    return out


SABER_HINTS = [("vader", "red"), ("sidious", "red"), ("palpatine", "red"), ("maul", "red"), ("dooku", "red"),
               ("kylo", "red"), ("ventress", "red"), ("inquisitor", "red"), ("windu", "purple"),
               ("yoda", "green"), ("qui-gon", "green"), ("ahsoka", "white"), ("rey", "yellow"),
               ("luke", "green"), ("obi-wan", "blue"), ("ben kenobi", "blue"), ("anakin", "blue")]


def saber_color(card: dict) -> str | None:
    traits = [t.lower() for t in card.get("Traits") or []]
    if "force" not in traits and "jedi" not in traits and "sith" not in traits:
        return None
    name = card["Name"].lower()
    for key, col in SABER_HINTS:
        if key in name:
            return col
    return "red" if "Villainy" in (card.get("Aspects") or []) or "sith" in traits else "blue"


def normalise(c: dict) -> dict:
    cid = card_id(c["Set"], c["Number"])
    typ = TYPE_MAP.get(c["Type"], c["Type"].lower())
    text = c.get("FrontText") or ""
    out = {
        "id": cid, "set": c["Set"], "number": c["Number"], "name": c["Name"].replace("C-3P0", "C-3PO"),
        "subtitle": c.get("Subtitle") or "", "type": typ,
        "arena": (c.get("Arenas") or [None])[0].lower() if c.get("Arenas") else None,
        "cost": to_int(c.get("Cost"), 0), "power": to_int(c.get("Power"), 0), "hp": to_int(c.get("HP"), 0),
        "aspects": [a.lower() for a in c.get("Aspects") or []],
        "traits": [t.lower() for t in c.get("Traits") or [] if t],
        "unique": bool(c.get("Unique")), "rarity": c.get("Rarity", ""),
        "text": norm_text(text), "art": art_name(cid),
    }
    out["keywords"] = parse_keywords(c, text)
    abilities, unparsed, status = compile_text(text, out["keywords"])
    if typ == "leader":
        out["epic_cost"] = out["cost"]
        out["leader_unit"] = {"arena": out["arena"] or "ground", "power": out["power"], "hp": out["hp"],
                              "text": norm_text(c.get("BackText") or "")}
        back_kw = parse_keywords({"Keywords": c.get("Keywords")}, c.get("BackText") or "")
        out["leader_unit"]["keywords"] = [k for k in back_kw if re.search(rf"\b{k['k']}\b", c.get("BackText") or "", re.I)]
        out["keywords"] = [k for k in out["keywords"] if re.search(rf"\b{k['k']}\b", text, re.I)]
        b_ab, b_un, b_status = compile_text(c.get("BackText") or "", out["leader_unit"]["keywords"])
        out["leader_unit"]["abilities"] = b_ab
        out["art_back"] = cid
        unparsed += b_un
        if status == "full" and b_status != "full":
            status = "partial"
    out["abilities"] = abilities
    out["unparsed"] = unparsed
    out["implemented"] = status
    sc = saber_color(c)
    if sc:
        out["saber"] = sc
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=str(DEFAULT_SRC))
    args = ap.parse_args()
    raw = json.loads(Path(args.src).read_text(encoding="utf-8"))
    cards, seen = {}, set()
    for c in raw:
        if c.get("VariantType") != "Normal":
            continue
        n = normalise(c)
        if n["id"] in seen:
            continue
        seen.add(n["id"])
        cards[n["id"]] = n
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps({"version": 1, "count": len(cards), "cards": cards}, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")

    # coverage report
    by_status = collections.Counter(c["implemented"] for c in cards.values())
    by_set = collections.defaultdict(collections.Counter)
    for c in cards.values():
        by_set[c["set"]][c["implemented"]] += 1
    unparsed = collections.Counter()
    for c in cards.values():
        for u in c["unparsed"]:
            unparsed[re.sub(r"\d+", "N", u.split(":")[0])[:60]] += 1
    lines = ["# Card coverage report", "",
             f"Generated by `tools/import_cards.py` from `{Path(args.src).name}`. {len(cards)} unique cards.", "",
             "| Status | Cards | Meaning |", "|---|---|---|",
             f"| full | {by_status['full']} | Every line of text is compiled to the effect DSL or is a natively implemented keyword |",
             f"| partial | {by_status['partial']} | Some lines compiled; the rest are shown to the player but not enforced |",
             f"| manual | {by_status['manual']} | Needs a hand-written script in `game/engine/cards/custom/` |", "",
             "## By set", "", "| Set | full | partial | manual |", "|---|---|---|---|"]
    for s in sorted(by_set):
        b = by_set[s]
        lines.append(f"| {s} | {b['full']} | {b['partial']} | {b['manual']} |")
    lines += ["", "## Most common uncompiled ability openers", "", "| Opener | Count |", "|---|---|"]
    for k, v in unparsed.most_common(40):
        lines.append(f"| {k.replace('|', '/')} | {v} |")
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"wrote {len(cards)} cards -> {OUT}")
    print(dict(by_status))
    return 0


if __name__ == "__main__":
    sys.exit(main())
