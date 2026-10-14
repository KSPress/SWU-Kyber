class_name Effects
extends RefCounted
## Interpreter for the effect DSL produced by tools/import_cards.py.
##
## An effect is a Dictionary: {"op": "damage", "n": 3, "t": <selector>, "optional": bool,
## "if": <condition>, "if_did": bool}. Ops prefixed "_" are engine-internal steps
## (setup, regroup, combat...). exec() returns DONE or SUSPEND; on SUSPEND,
## Match.pending describes the choice and the same effect re-runs once
## Match.submit_choice() stores the answer in ctx["_choice"].

const DONE := 0
const SUSPEND := 1
const HOSTILE_OPS := ["damage", "defeat", "exhaust", "bounce", "lose_kw"]


static func exec(m: Match, e: Dictionary, ctx: Dictionary) -> int:
	var op: String = e.get("op", "")
	if e.get("if_did", false) and not ctx.get("did", false):
		return DONE
	if e.has("if") and not ctx.has("_choice") and not condition(m, e["if"], ctx):
		ctx["did"] = false
		return DONE
	if op.begins_with("_"):
		return _system(m, e, ctx)
	if op == "choose_one":
		return _choose_one(m, e, ctx)
	if op == "play_from_hand":
		return _play_from_hand(m, e, ctx)
	if op == "use_force" and not m.players[ctx.get("ctl", 0)].force_token:
		ctx["did"] = false
		return DONE
	# Optional effect with no target to pick => ask yes/no first.
	if e.get("optional", false) and not e.has("t") and not ctx.get("_yes", false):
		if not ctx.has("_choice"):
			_ask(m, ctx, "yesno", "Use: %s?" % _label(ctx, e), [1, 0], 1, 1, e)
			return SUSPEND
		var yes: bool = ctx["_choice"][0] == 1
		ctx.erase("_choice")
		if not yes:
			ctx["did"] = false
			return DONE
	var targets: Array = []
	if e.has("t") and not ctx.has("_attacker"):
		var r = _targets(m, e, ctx)
		if r == null:
			return SUSPEND
		targets = r
		if targets.is_empty() and op not in ["token", "draw"]:
			ctx["did"] = false
			return DONE
	var ctl: int = ctx.get("ctl", 0)
	var src: CardInst = m.card(ctx.get("src", 0))
	var n: int = int(e.get("n", 1))
	match op:
		"damage":
			for t in targets:
				m.deal_damage(t, n, src)
		"heal":
			for t in targets:
				m.heal(t, n)
		"draw":
			m.draw(ctl, n)
		"discard":
			return _discard(m, e, ctx)
		"shield", "experience":
			for t in targets:
				for _i in n:
					m.attach_token(t, op)
		"exhaust":
			for t in targets:
				m.exhaust(t, true)
		"ready":
			for t in targets:
				m.exhaust(t, false)
		"defeat":
			for t in targets:
				m.defeat(t)
		"bounce":
			for t in targets:
				m.return_to_hand(t)
		"buff":
			for t in targets:
				t.mods.append({"p": int(e.get("p", 0)), "h": int(e.get("h", 0)), "dur": e.get("dur", "phase")})
				m.events.append({"t": "buff", "uid": t.uid, "p": int(e.get("p", 0)), "h": int(e.get("h", 0))})
		"gain_kw":
			for t in targets:
				t.mods.append({"kw": e["kw"], "v": int(e.get("v", 1)), "dur": e.get("dur", "phase")})
				m.events.append({"t": "buff", "uid": t.uid, "kw": e["kw"]})
		"lose_kw":
			for t in targets:
				t.mods.append({"lose_kw": e["kw"], "dur": e.get("dur", "phase")})
		"token":
			if e.get("name", "") == "credit":
				m.players[ctl].credits += n
				m.events.append({"t": "credits", "p": ctl, "n": n})
			else:
				for _i in n:
					m.create_unit_token(ctl, e.get("name", "battle_droid"))
		"summon":
			for _i in n:
				m.summon(ctl, e["id"], e.get("ready", false))
		"force_token":
			if not m.players[ctl].force_token:
				m.players[ctl].force_token = true
				m.events.append({"t": "force", "p": ctl})
		"use_force":
			if not m.players[ctl].force_token:
				ctx["did"] = false
				return DONE
			m.players[ctl].force_token = false
			m.events.append({"t": "force_used", "p": ctl})
		"ready_resource":
			var left := n
			for r in m.players[ctl].resources:
				if left > 0 and r.exhausted:
					r.exhausted = false
					left -= 1
		"scry":
			return _scry(m, e, ctx)
		"search":
			return _search(m, e, ctx)
		"attack_with":
			return _attack_with(m, e, ctx, targets)
		"base_damage":
			m.deal_damage(m.players[m.opp(ctl)].base, n, src)
		_:
			push_warning("Effects: unknown op %s" % op)
	ctx["did"] = true
	if not targets.is_empty():
		ctx["it"] = targets[0].uid
	return DONE


# ---------------------------------------------------------------- targeting

## Returns Array[CardInst], or null when the controller must choose (pending set).
static func _targets(m: Match, e: Dictionary, ctx: Dictionary):
	var t: Dictionary = e["t"]
	var s: String = t.get("s", "choose")
	var ctl: int = ctx.get("ctl", 0)
	var src: CardInst = m.card(ctx.get("src", 0))
	match s:
		"self":
			return [src] if src and src.in_play() else []
		"it":
			var it := m.card(ctx.get("it", 0))
			return [it] if it and (it.in_play() or it.zone == "base") else []
		"own_base":
			return [m.players[ctl].base]
		"enemy_base":
			return [m.players[m.opp(ctl)].base]
		"defender":
			var d := m.card(m.attack.get("t", 0))
			return [d] if d and d.in_play() else []
		"attacker":
			var a := m.card(m.attack.get("a", 0))
			return [a] if a and a.in_play() else []
		"attached":
			if src and src.zone == "upgrade" and src.attached_to:
				return [src.attached_to]
			return [src] if src and src.in_play() else []
		"each":
			return candidates(m, t, ctx)
	# choose
	if ctx.has("_choice"):
		var picked: Array = []
		for uid in ctx["_choice"]:
			var c := m.card(uid)
			if c:
				picked.append(c)
		ctx.erase("_choice")
		return picked
	var cands := candidates(m, t, ctx)
	if cands.is_empty():
		return []
	var count := int(t.get("count", 1))
	if t.get("random", false):
		var pick: Array = []
		for _i in mini(count, cands.size()):
			var c: CardInst = cands[m.rng.randi_range(0, cands.size() - 1)]
			cands.erase(c)
			pick.append(c)
		return pick
	var optional: bool = t.get("opt", false) or t.get("upto", false)
	var mx := mini(count, cands.size())
	var mn := 0 if optional else mx
	var uids: Array = []
	for c in cands:
		uids.append(c.uid)
	if not optional and cands.size() == mx and m.players[ctl].is_ai:
		return cands
	_ask(m, ctx, "target", _label(ctx, e), uids, mn, mx, e)
	return null


static func candidates(m: Match, t: Dictionary, ctx: Dictionary) -> Array:
	var out: Array = []
	var pool: Array = []
	var kind: String = t.get("kind", "unit")
	if kind == "unit" or kind == "unit_or_base":
		pool.append_array(m.all_units())
	if kind == "base" or kind == "unit_or_base":
		pool.append(m.players[0].base)
		pool.append(m.players[1].base)
	for c in pool:
		if matches(m, c, t, ctx):
			out.append(c)
	return out


static func matches(m: Match, c: CardInst, t: Dictionary, ctx: Dictionary) -> bool:
	var ctl: int = ctx.get("ctl", 0)
	var src: CardInst = m.card(ctx.get("src", 0))
	var side: String = t.get("side", "any")
	if side == "enemy" and c.controller == ctl:
		return false
	if side == "friendly" and c.controller != ctl:
		return false
	if c.zone == "base":
		return true
	if c.flags.get("untargetable", false) and side != "friendly":
		return false
	if t.get("other", false) and src and c.uid == src.uid:
		return false
	if t.has("arena") and c.zone != t["arena"]:
		return false
	if t.get("same_arena", false) and src and c.zone != src.zone:
		return false
	if t.get("nonleader", false) and c.is_leader():
		return false
	if t.get("damaged", false) and c.damage <= 0:
		return false
	if t.get("exhausted", false) and not c.exhausted:
		return false
	if t.get("ready", false) and c.exhausted:
		return false
	if t.has("max_hp") and c.remaining_hp() > int(t["max_hp"]):
		return false
	if t.has("max_power") and c.power() > int(t["max_power"]):
		return false
	if t.has("max_cost") and c.cost() > int(t["max_cost"]):
		return false
	if t.has("trait") and not c.has_trait(t["trait"]):
		return false
	if t.has("traits_any"):
		var any_ok := false
		for tr in t["traits_any"]:
			if c.has_trait(tr):
				any_ok = true
		if not any_ok:
			return false
	if t.get("token", false) and not c.is_token:
		return false
	if t.get("upgraded", false) and c.upgrades.is_empty():
		return false
	if t.get("different", false) and ctx.has("it") and c.uid == int(ctx["it"]):
		return false
	if t.has("min_hp") and c.remaining_hp() < int(t["min_hp"]):
		return false
	if t.has("min_power") and c.power() < int(t["min_power"]):
		return false
	if t.has("without_token"):
		for up in c.upgrades:
			if str(up.data.get("name", "")).to_lower() == t["without_token"]:
				return false
	if t.has("not_trait") and c.has_trait(t["not_trait"]):
		return false
	if t.has("aspect") and not (t["aspect"] in c.aspects()):
		return false
	if t.has("unique") and c.unique() != t["unique"]:
		return false
	return true


static func condition(m: Match, cond: Dictionary, ctx: Dictionary) -> bool:
	var ctl: int = ctx.get("ctl", 0)
	if cond.has("control"):
		return candidates(m, cond["control"], ctx).size() >= int(cond.get("min", 1))
	if cond.get("enemy_defeated_this_phase", false):
		return m.defeated_this_phase[m.opp(ctl)] > 0
	if cond.get("has_initiative", false):
		return m.initiative == ctl
	if cond.has("attacked_trait"):
		var tr: String = cond["attacked_trait"]
		for uid in m.attacked_with[ctl]:
			var a := m.card(uid)
			if a and (tr == "" or a.has_trait(tr)):
				return true
		return false
	if cond.has("played_trait"):
		var tr2: String = cond["played_trait"]
		for c in m.played_this_phase[ctl]:
			if tr2 == "" or c.has_trait(tr2) or tr2 in c.aspects() or (tr2 == "non-unit force" and c.card_type() != "unit" and c.has_trait("force")):
				return true
		return false
	if cond.has("friendly_defeated_trait"):
		var tr3: String = cond["friendly_defeated_trait"]
		for c in m.defeated_cards_this_phase[ctl]:
			if tr3 == "" or c.has_trait(tr3) or tr3 in c.aspects():
				return true
		return false
	if cond.has("friendly_defeated_min"):
		return m.defeated_cards_this_phase[ctl].size() >= int(cond["friendly_defeated_min"])
	if cond.get("self_damaged", false):
		var src := m.card(ctx.get("src", 0))
		return src != null and src.damage > 0
	return true


static func upgrade_targets(m: Match, p: int, up: CardInst) -> Array:
	var out: Array = []
	var txt: String = up.data.get("text", "").to_lower()
	for u in m.all_units():
		if txt.find("attach to a non-vehicle unit") >= 0 and u.has_trait("vehicle"):
			continue
		if txt.find("attach to a vehicle unit") >= 0 and not u.has_trait("vehicle"):
			continue
		if txt.find("attach to a friendly unit") >= 0 and u.controller != p:
			continue
		if txt.find("attach to a non-leader unit") >= 0 and u.is_leader():
			continue
		if u.flags.get("untargetable", false) and u.controller != p:
			continue
		out.append(u)
	return out


static func _ask(m: Match, ctx: Dictionary, kind: String, prompt: String, options: Array, mn: int, mx: int, e := {}, who := -1) -> void:
	var op: String = e.get("op", "")
	var hostile := op in HOSTILE_OPS or (op == "buff" and (int(e.get("p", 0)) < 0 or int(e.get("h", 0)) < 0))
	m.pending = {
		"player": ctx.get("ctl", 0) if who < 0 else who, "kind": kind, "prompt": prompt,
		"options": options, "min": mn, "max": mx, "src": ctx.get("src", 0),
		"op": op, "hostile": hostile, "effect": e,
	}


static func _label(ctx: Dictionary, e: Dictionary) -> String:
	var txt: String = ctx.get("text", "")
	if txt != "":
		return ("%s — %s" % [ctx.get("name", ""), txt]) if ctx.has("name") else txt
	return str(e.get("op", "choose")).capitalize()


# ---------------------------------------------------------------- composite ops

static func _discard(m: Match, e: Dictionary, ctx: Dictionary) -> int:
	var ctl: int = ctx.get("ctl", 0)
	var who: int = ctl if e.get("who", "self") == "self" else m.opp(ctl)
	var ps: PlayerState = m.players[who]
	if ctx.has("_choice"):
		for uid in ctx["_choice"]:
			var c := m.card(uid)
			ps.hand.erase(c)
			c.zone = "discard"
			ps.discard.append(c)
			m.events.append({"t": "discard", "uid": uid, "p": who})
		ctx.erase("_choice")
		ctx["did"] = true
		return DONE
	if ps.hand.is_empty():
		ctx["did"] = false
		return DONE
	var uids: Array = []
	for c in ps.hand:
		if c.cost() >= int(e.get("min_cost", 0)):
			uids.append(c.uid)
	if uids.is_empty():
		ctx["did"] = false
		return DONE
	var n := mini(int(e.get("n", 1)), uids.size())
	_ask(m, ctx, "hand", "Discard %d card(s)" % n, uids, n, n, e, who)
	return SUSPEND


static func _scry(m: Match, e: Dictionary, ctx: Dictionary) -> int:
	var ps: PlayerState = m.players[ctx.get("ctl", 0)]
	if ctx.has("_choice"):
		for uid in ctx["_choice"]:
			var c := m.card(uid)
			ps.deck.erase(c)
			ps.deck.append(c)
		ctx.erase("_choice")
		ctx["did"] = true
		return DONE
	if ps.deck.is_empty():
		return DONE
	var top: Array = []
	for i in mini(int(e.get("n", 1)), ps.deck.size()):
		top.append(ps.deck[i].uid)
	_ask(m, ctx, "scry", "Choose cards to put on the bottom of your deck", top, 0, top.size(), e)
	m.pending["reveal"] = top
	return SUSPEND


static func _search(m: Match, e: Dictionary, ctx: Dictionary) -> int:
	var ps: PlayerState = m.players[ctx.get("ctl", 0)]
	var n := mini(int(e.get("n", 5)), ps.deck.size())
	var top: Array = ps.deck.slice(0, n)
	if ctx.has("_choice"):
		for uid in ctx["_choice"]:
			var c := m.card(uid)
			ps.deck.erase(c)
			c.zone = "hand"
			ps.hand.append(c)
			m.events.append({"t": "draw", "p": ps.index, "uid": uid, "reveal": true})
		for c in top:
			if c.zone == "deck":
				ps.deck.erase(c)
				ps.deck.append(c)
		ctx.erase("_choice")
		ctx["did"] = true
		return DONE
	var f: Dictionary = e.get("filter", {})
	var ok: Array = []
	for c in top:
		var kind: String = f.get("kind", "card")
		if kind == "unit" and c.card_type() != "unit":
			continue
		if f.has("trait") and not c.has_trait(f["trait"]):
			continue
		if f.has("aspect") and not (f["aspect"] in c.aspects()):
			continue
		if f.has("max_cost") and c.cost() > int(f["max_cost"]):
			continue
		ok.append(c.uid)
	var reveal: Array = []
	for c in top:
		reveal.append(c.uid)
	_ask(m, ctx, "search", "Search: choose up to %d" % int(e.get("count", 1)), ok, 0, mini(int(e.get("count", 1)), ok.size()), e)
	m.pending["reveal"] = reveal
	return SUSPEND


static func _attack_with(m: Match, e: Dictionary, ctx: Dictionary, attackers: Array) -> int:
	# Step 2: pick the target for the chosen attacker.
	if ctx.has("_attacker"):
		var a := m.card(ctx["_attacker"])
		if ctx.has("_choice"):
			var tgt := m.card(ctx["_choice"][0])
			ctx.erase("_choice")
			ctx.erase("_attacker")
			ctx["it"] = a.uid
			for pre in e.get("pre", []):
				if pre.get("op") == "buff":
					a.mods.append({"p": int(pre.get("p", 0)), "h": int(pre.get("h", 0)), "dur": "attack"})
				elif pre.get("op") == "gain_kw":
					a.mods.append({"kw": pre["kw"], "v": int(pre.get("v", 1)), "dur": "attack"})
			m.begin_attack(a, tgt)
			ctx["did"] = true
			return DONE
	if attackers.is_empty():
		return DONE
	var a: CardInst = attackers[0]
	var tg := m.attack_targets(a)
	if tg.is_empty():
		return DONE
	ctx["_attacker"] = a.uid
	_ask(m, ctx, "attack_target", "Choose a target for %s" % a.name(), tg, 1, 1, {"op": "damage"})
	return SUSPEND


# ---------------------------------------------------------------- system ops

static func _system(m: Match, e: Dictionary, ctx: Dictionary) -> int:
	var op: String = e["op"]
	match op:
		"_draw":
			m.draw(int(e["p"]), int(e["n"]))
		"_mulligan":
			var p := int(e["p"])
			if ctx.has("_choice"):
				var yes: bool = ctx["_choice"][0] == 1
				ctx.erase("_choice")
				if yes:
					var ps: PlayerState = m.players[p]
					var n := ps.hand.size()
					for c in ps.hand:
						c.zone = "deck"
						ps.deck.append(c)
					ps.hand.clear()
					m._shuffle(ps.deck)
					m.draw(p, n)
					m._log("%s mulligans." % ps.display_name)
				return DONE
			_ask(m, {"ctl": p}, "mulligan", "Mulligan your opening hand?", [1, 0], 1, 1)
			return SUSPEND
		"_setup_resources", "_regroup_resource":
			var p := int(e["p"])
			var ps: PlayerState = m.players[p]
			if ctx.has("_choice"):
				for uid in ctx["_choice"]:
					m.move_to_resources(p, m.card(uid), false)
				ctx.erase("_choice")
				return DONE
			if ps.hand.is_empty():
				return DONE
			var uids: Array = []
			for c in ps.hand:
				uids.append(c.uid)
			if op == "_setup_resources":
				var n := mini(int(e.get("n", 2)), uids.size())
				_ask(m, {"ctl": p}, "resource", "Choose %d card(s) to put into your resources" % n, uids, n, n)
			else:
				_ask(m, {"ctl": p}, "resource", "Resource up to 1 card", uids, 0, 1)
			return SUSPEND
		"_reset_ctx":
			ctx.erase("it")
			ctx.erase("did")
		"_mill":
			var mp := int(e.get("p", ctx.get("ctl", 0)))
			for _i in int(e.get("n", 1)):
				if not m.players[mp].deck.is_empty():
					var top: CardInst = m.players[mp].deck.pop_front()
					top.zone = "discard"
					m.players[mp].discard.append(top)
		"_defeat_resource":
			var rp: int = ctx.get("ctl", 0)
			var rs: Array = m.players[rp].resources
			if not rs.is_empty():
				var pick: CardInst = rs[0]
				for r in rs:
					if r.exhausted:
						pick = r
				rs.erase(pick)
				pick.zone = "discard"
				m.players[pick.owner].discard.append(pick)
				m.events.append({"t": "resource", "p": rp, "uid": pick.uid})
		"_defeat_upgrade":
			var up_p: int = ctx.get("ctl", 0)
			if ctx.has("_choice"):
				var host := m.card(ctx["_choice"][0])
				ctx.erase("_choice")
				for up in host.upgrades:
					if up.controller == up_p or host.controller == up_p:
						host.upgrades.erase(up)
						if not up.is_token:
							up.zone = "discard"
							m.players[up.owner].discard.append(up)
						m.events.append({"t": "token", "kind": "upgrade", "on": host.uid})
						break
				return DONE
			var hosts: Array = []
			for u in m.all_units():
				if u.controller == up_p and not u.upgrades.is_empty():
					hosts.append(u.uid)
			if hosts.is_empty():
				return DONE
			_ask(m, ctx, "target", "Cost: defeat a friendly upgrade (choose the unit)", hosts, 1, 1, {"op": "defeat"})
			return SUSPEND
		"_exploit":
			var c := m.card(int(e["uid"]))
			var xp: int = ctx.get("ctl", 0)
			var units: Array = []
			for u in m.players[xp].units:
				if not u.is_leader():
					units.append(u.uid)
			var full := m.play_cost(xp, c)
			var need := maxi(0, ceili((full - m.players[xp].available()) / 2.0))
			var mx := mini(c.kw("exploit"), units.size())
			if ctx.has("_choice"):
				var sel: Array = ctx["_choice"]
				ctx.erase("_choice")
				for uid in sel:
					m.defeat(m.card(uid))
				m._play_card(xp, c, false, {"discount": 2 * sel.size()})
				return DONE
			if mx <= 0:
				m._play_card(xp, c, false)
				return DONE
			_ask(m, ctx, "target", "Exploit %d: defeat friendly units to reduce the cost by 2 each (need %d)" % [c.kw("exploit"), need], units, need, mx, {"op": "defeat"})
			m.pending["hostile"] = false
			return SUSPEND
		"_deck_to_resources":
			var p := int(e["p"])
			for _i in int(e.get("n", 1)):
				if not m.players[p].deck.is_empty():
					m.move_to_resources(p, m.players[p].deck.pop_front(), false)
		"_start_action":
			m.phase = "action"
			m.start_action_phase()
		"_regroup_triggers":
			for u in m.all_units():
				for ab in u.abilities_with("regroup_start"):
					m.push_ability(u, ab)
		"_ready_all":
			for ps in m.players:
				for u in ps.units:
					u.exhausted = false
				for r in ps.resources:
					r.exhausted = false
				if ps.leader:
					ps.leader.exhausted = false
			m.events.append({"t": "ready_all"})
		"_new_round":
			m.end_round()
		"_combat":
			m.resolve_combat()
		"_attack_end":
			m.end_attack()
		"_attach":
			var up := m.card(int(e["uid"]))
			var p: int = ctx.get("ctl", 0)
			if ctx.has("_choice"):
				var tgt := m.card(ctx["_choice"][0])
				ctx.erase("_choice")
				m.attach_upgrade(up, tgt)
				return DONE
			var opts: Array = []
			for u in upgrade_targets(m, p, up):
				opts.append(u.uid)
			if opts.is_empty():
				up.zone = "discard"
				m.players[up.owner].discard.append(up)
				return DONE
			_ask(m, {"ctl": p, "src": up.uid}, "target", "Attach %s to a unit" % up.name(), opts, 1, 1, {"op": "attach"})
			m.pending["hostile"] = int(up.data.get("power", 0)) < 0
			return SUSPEND
		"_ambush":
			var u := m.card(int(e["uid"]))
			if u == null or not u.in_play():
				return DONE
			if ctx.has("_choice"):
				var sel: Array = ctx["_choice"]
				ctx.erase("_choice")
				if sel.is_empty():
					return DONE
				m.exhaust(u, false)
				m.begin_attack(u, m.card(sel[0]))
				return DONE
			var opts: Array = []
			var was := u.exhausted
			u.exhausted = false
			for t in m.attack_targets(u):
				if m.card(t).zone != "base":
					opts.append(t)
			u.exhausted = was
			if opts.is_empty():
				return DONE
			_ask(m, {"ctl": u.controller, "src": u.uid}, "target", "Ambush: %s may attack an enemy unit" % u.name(), opts, 0, 1, {"op": "damage"})
			return SUSPEND
		"_bottom_from_hand":
			var p: int = ctx.get("ctl", 0)
			var ps: PlayerState = m.players[p]
			if ctx.has("_choice"):
				for uid in ctx["_choice"]:
					var c := m.card(uid)
					ps.hand.erase(c)
					c.zone = "deck"
					ps.deck.append(c)
				ctx.erase("_choice")
				return DONE
			if ps.hand.is_empty():
				return DONE
			var uids: Array = []
			for c in ps.hand:
				uids.append(c.uid)
			_ask(m, {"ctl": p}, "hand", "Put a card from your hand on the bottom of your deck", uids, 1, 1)
			return SUSPEND
		_:
			push_warning("Effects: unknown system op %s" % op)
	return DONE


## "Choose one:" / "Either A or B" / "An opponent chooses one:" — the right
## player picks an option; its effects then resolve for the card's controller.
static func _choose_one(m: Match, e: Dictionary, ctx: Dictionary) -> int:
	var opts: Array = e.get("options", [])
	if opts.is_empty():
		return DONE
	if ctx.has("_choice"):
		var sel: Array = ctx["_choice"]
		ctx.erase("_choice")
		if sel.is_empty():
			ctx["did"] = false
			return DONE
		var pick: Dictionary = opts[int(sel[0])]
		m.events.append({"t": "log", "text": "Chose: %s" % pick.get("label", "")})
		m.log_lines.append("Chose: %s" % pick.get("label", ""))
		var sub := ctx.duplicate()
		sub.erase("_choice")
		m.push_frame(pick.get("effects", []), sub)
		ctx["did"] = true
		return DONE
	var idx: Array = []
	var labels: Array = []
	for i in opts.size():
		idx.append(i)
		labels.append(opts[i].get("label", "Option %d" % (i + 1)))
	var ctl: int = ctx.get("ctl", 0)
	var who := m.opp(ctl) if e.get("who", "self") == "opponent" else ctl
	var mn := 0 if e.get("optional", false) else 1
	_ask(m, ctx, "option", _label(ctx, e), idx, mn, 1, e, who)
	m.pending["labels"] = labels
	return SUSPEND


## "Play a [trait] unit/event/card from your hand [It costs N less / enters ready /
## ignoring aspect penalties / give it Ambush]". The player picks an affordable
## card (or skips); it is played immediately as part of this ability.
static func _play_from_hand(m: Match, e: Dictionary, ctx: Dictionary) -> int:
	var p: int = ctx.get("ctl", 0)
	var ps: PlayerState = m.players[p]
	var opts := {"discount": int(e.get("discount", 0)), "ignore_aspects": e.get("ignore_aspects", false),
		"ready": e.get("ready", false)}
	if e.has("gain_kw"):
		opts["gain_kw"] = e["gain_kw"]
	if ctx.has("_choice"):
		var sel: Array = ctx["_choice"]
		ctx.erase("_choice")
		if sel.is_empty():
			ctx["did"] = false
			return DONE
		var c := m.card(sel[0])
		if c and c.zone == "hand":
			m._play_card(p, c, false, opts)
			ctx["did"] = true
			ctx["it"] = c.uid
			var left := int(ctx.get("_play_left", int(e.get("count", 1)))) - 1
			if left > 0:
				ctx["_play_left"] = left
				return _play_from_hand(m, e, ctx)
		ctx.erase("_play_left")
		return DONE
	var cands: Array = []
	for c in ps.hand:
		var t: String = c.card_type()
		var kind: String = e.get("kind", "card")
		if kind == "unit" and t != "unit":
			continue
		if kind == "event" and t != "event":
			continue
		if kind == "upgrade" and t != "upgrade":
			continue
		if kind == "non-unit" and t == "unit":
			continue
		if t == "unit" and not (m.arena_for(c) in m.rules.arenas):
			continue
		if t == "upgrade" and upgrade_targets(m, p, c).is_empty():
			continue
		if e.has("aspect") and not (e["aspect"] in c.aspects()):
			continue
		if e.has("traits_any"):
			var ok := false
			for tr in e["traits_any"]:
				if c.has_trait(tr):
					ok = true
			if not ok:
				continue
		if e.has("max_cost") and c.cost() > int(e["max_cost"]):
			continue
		if e.has("max_power") and c.printed_power() > int(e["max_power"]):
			continue
		if m.play_cost(p, c, false, opts) > ps.available():
			continue
		cands.append(c.uid)
	if cands.is_empty():
		ctx["did"] = false
		ctx.erase("_play_left")
		return DONE
	_ask(m, ctx, "hand", _label(ctx, e) + "\nChoose a card to play", cands, 0, 1, e)
	return SUSPEND



## Extra Action costs ("Action [Exhaust, defeat a friendly unit]: ..."):
## returns {"ok": can it be paid now, "ops": effects that pay it}.
static func extra_cost(m: Match, p: int, src: CardInst, other: String) -> Dictionary:
	var o := other.to_lower().strip_edges()
	var ps: PlayerState = m.players[p]
	var friendly := {"s": "choose", "kind": "unit", "side": "friendly"}
	var ctx := {"ctl": p, "src": src.uid}
	if o.begins_with("use the force"):
		return {"ok": ps.force_token, "ops": [{"op": "use_force"}]}
	if o == "exhaust a friendly unit":
		var t := friendly.duplicate()
		t["ready"] = true
		t["other"] = true
		return {"ok": not candidates(m, t, ctx).is_empty(), "ops": [{"op": "exhaust", "t": t}]}
	if o == "defeat a friendly unit":
		var t2 := friendly.duplicate()
		t2["nonleader"] = true
		return {"ok": not candidates(m, t2, ctx).is_empty(), "ops": [{"op": "defeat", "t": t2}]}
	if o == "defeat a friendly token":
		var t3 := friendly.duplicate()
		t3["token"] = true
		return {"ok": not candidates(m, t3, ctx).is_empty(), "ops": [{"op": "defeat", "t": t3}]}
	if o == "defeat a friendly upgrade":
		for u in m.all_units():
			if u.controller == p and not u.upgrades.is_empty():
				return {"ok": true, "ops": [{"op": "_defeat_upgrade"}]}
		return {"ok": false}
	if o == "defeat a friendly resource":
		return {"ok": ps.resources.size() > 1, "ops": [{"op": "_defeat_resource"}]}
	if o == "discard a card from your hand":
		return {"ok": not ps.hand.is_empty(), "ops": [{"op": "discard", "n": 1, "who": "self"}]}
	var mc := RegEx.create_from_string("^discard a card that costs (\\d+) or more from your hand$").search(o)
	if mc:
		var need := int(mc.get_string(1))
		for c in ps.hand:
			if c.cost() >= need:
				return {"ok": true, "ops": [{"op": "discard", "n": 1, "who": "self", "min_cost": need}]}
		return {"ok": false}
	if o == "discard a card from your deck":
		return {"ok": not ps.deck.is_empty(), "ops": [{"op": "_mill", "n": 1, "p": p}]}
	var md := RegEx.create_from_string("^deal (\\d+) damage to a friendly unit$").search(o)
	if md:
		return {"ok": not candidates(m, friendly, ctx).is_empty(), "ops": [{"op": "damage", "n": int(md.get_string(1)), "t": friendly.duplicate()}]}
	var mb := RegEx.create_from_string("^deal (\\d+) damage to your base$").search(o)
	if mb:
		return {"ok": true, "ops": [{"op": "damage", "n": int(mb.get_string(1)), "t": {"s": "own_base"}}]}
	var mr := RegEx.create_from_string("^return a friendly (\\w+) unit to its owner's hand$").search(o)
	if mr:
		var t4 := friendly.duplicate()
		t4["trait"] = mr.get_string(1)
		t4["nonleader"] = true
		return {"ok": not candidates(m, t4, ctx).is_empty(), "ops": [{"op": "bounce", "t": t4}]}
	return {"ok": false}
