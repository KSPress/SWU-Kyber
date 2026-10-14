class_name AiBot
extends RefCounted
## Heuristic bot (spec 10.1). Scores every legal action and every choice with
## cheap board heuristics — no search, so a decision costs well under a millisecond.
## Deterministic for a given match seed. Profiles tilt the weights.

const PROFILES := {
	"aggressive": {"face": 1.6, "trade": 0.9, "keep_units": 0.7, "initiative": 0.6},
	"defensive": {"face": 0.7, "trade": 1.3, "keep_units": 1.3, "initiative": 1.2},
	"tempo": {"face": 1.1, "trade": 1.1, "keep_units": 1.0, "initiative": 1.0},
}


static func weights(m: Match, p: int) -> Dictionary:
	return PROFILES.get(m.players[p].ai_profile, PROFILES["tempo"])


static func unit_value(u: CardInst) -> float:
	var v := u.power() * 1.0 + u.remaining_hp() * 0.7
	for k in u.keyword_list():
		match k["k"]:
			"sentinel", "overwhelm", "saboteur", "grit":
				v += 1.0
			"raid", "restore":
				v += 0.5 * k["v"]
			_:
				v += 0.4
	v += u.shield_count() * 1.5
	if u.is_leader():
		v += 3.0
	if u.flags.get("protected", false):
		v += 6.0
	return v


## Pick and perform the best action for the active AI player.
static func act(m: Match) -> Dictionary:
	var p := m.active
	var acts := m.legal_actions(p)
	if acts.is_empty():
		return {}
	# Claiming a token ends your round, so only do it once nothing worthwhile is left
	# (taking the initiative early hands the opponent free attacks).
	var best: Dictionary = {}
	var best_s := -INF
	for a in acts:
		if a["a"] in ["claim", "pass"]:
			continue
		var s := score_action(m, p, a)
		if s > best_s:
			best_s = s
			best = a
	if best_s < 0.6:
		best = {"a": "pass"}
		var claim_s := 0.0
		for a in acts:
			if a["a"] == "claim":
				var s2 := score_action(m, p, a)
				if s2 > claim_s:
					claim_s = s2
					best = a
	m.do_action(best)
	return best


static func score_action(m: Match, p: int, a: Dictionary) -> float:
	var w := weights(m, p)
	var me: PlayerState = m.players[p]
	var foe: PlayerState = m.players[m.opp(p)]
	match a["a"]:
		"pass":
			return 0.0
		"claim":
			if a["token"] == "initiative":
				return 1.0 * w["initiative"]
			# Custom tokens: worth it only if their effect has something to hit.
			for tk in m.tokens:
				if tk["id"] == a["token"]:
					for e in tk.get("effects", []):
						if e.has("t") and Effects.candidates(m, e["t"], {"ctl": p}).is_empty():
							return -1.0
			return 1.5
		"deploy":
			return 7.0
		"play", "smuggle":
			var c := m.card(a["uid"])
			var cost := m.play_cost(p, c, a["a"] == "smuggle")
			var s := 2.0 + cost * 0.9
			match c.card_type():
				"unit":
					s += c.printed_power() * 0.4 + c.printed_hp() * 0.3 + c.keyword_list().size() * 0.4
				"event":
					s += _event_value(m, p, c) - 1.0
				"upgrade":
					s += 0.5 if me.units.size() > 0 else -5.0
			return s
		"attack":
			var at := m.card(a["uid"])
			var t := m.card(a["target"])
			if t.zone == "base":
				var dmg := at.power(true)
				var s: float = dmg * 0.9 * w["face"]
				if dmg >= foe.base_remaining():
					s += 100.0
				return s + 0.2
			var ap := at.power(true)
			var dp := t.power()
			var kills := ap >= t.remaining_hp() and t.shield_count() == 0
			var dies := dp >= at.remaining_hp() and at.shield_count() == 0
			var s2 := 0.0
			s2 += (unit_value(t) * 1.3 if kills else ap * 0.35) * w["trade"]
			s2 -= (unit_value(at) if dies else dp * 0.2) * w["keep_units"]
			if t.flags.get("protected", false):
				s2 += 8.0
			return s2
		"ability":
			return 1.5
	return 0.0


static func _event_value(m: Match, p: int, c: CardInst) -> float:
	var v := 0.0
	for ab in c.abilities():
		for e in ab.get("effects", []):
			var op: String = e.get("op", "")
			if op in Effects.HOSTILE_OPS:
				var ctx := {"ctl": p, "src": c.uid}
				var cands := Effects.candidates(m, e.get("t", {}), ctx) if e.has("t") else []
				var best := 0.0
				for t in cands:
					if t.controller != p:
						best = maxf(best, unit_value(t))
				v += best * 0.6
			elif op in ["draw", "experience", "shield", "heal", "buff", "token"]:
				v += 1.5
	return v


## Resolve m.pending for an AI player.
static func choose(m: Match) -> Array:
	var pd := m.pending
	var p: int = pd["player"]
	var opts: Array = pd["options"]
	var mn: int = pd["min"]
	var mx: int = pd["max"]
	var sel: Array = []
	match pd["kind"]:
		"mulligan":
			var ps: PlayerState = m.players[p]
			var cheap := 0
			for c in ps.hand:
				if c.cost() <= 3:
					cheap += 1
			sel = [1 if cheap < 2 else 0]
		"yesno":
			sel = [1]
		"option":
			# prefer the option with the most immediately useful effects;
			# when an opponent forces the choice, pick the least harmful
			var opt_list: Array = pd.get("effect", {}).get("options", [])
			var best_i := 0
			var best_v := -INF
			var src := m.card(pd.get("src", 0))
			var mine: bool = src == null or src.controller == p
			for i in opt_list.size():
				var v := 0.0
				for ef in opt_list[i].get("effects", []):
					var op: String = ef.get("op", "")
					v += {"damage": 2.0, "defeat": 3.0, "token": 2.0, "draw": 1.5, "experience": 1.5, "shield": 1.5,
						"ready_resource": 1.0, "exhaust": 1.0, "buff": 1.0, "heal": 1.0}.get(op, 0.5) * int(ef.get("n", 1))
				if not mine:
					v = -v
				if v > best_v:
					best_v = v
					best_i = i
			sel = [best_i]
		"resource":
			var ranked := opts.duplicate()
			ranked.sort_custom(func(a, b): return _resource_rank(m, p, m.card(a)) > _resource_rank(m, p, m.card(b)))
			var ps2: PlayerState = m.players[p]
			var want := mn
			if mx > mn and (ps2.resources.size() < 7 or ps2.hand.size() > 3):
				want = mx
			sel = ranked.slice(0, want)
		"scry":
			var res: int = m.players[p].resources.size()
			for uid in opts:
				if m.card(uid).cost() > res + 2:
					sel.append(uid)
		"search":
			var ranked2 := opts.duplicate()
			ranked2.sort_custom(func(a, b): return m.card(a).cost() > m.card(b).cost())
			sel = ranked2.slice(0, mx)
		"hand" when pd.get("op", "") == "play_from_hand":
			var best := opts.duplicate()
			best.sort_custom(func(a, b): return m.card(a).cost() > m.card(b).cost())
			sel = best.slice(0, 1)
		"hand":
			var ranked3 := opts.duplicate()
			ranked3.sort_custom(func(a, b): return m.card(a).cost() < m.card(b).cost())
			if pd.get("player", p) != p:
				ranked3.reverse()
			sel = ranked3.slice(0, mn)
		_:
			sel = _choose_targets(m, pd)
	sel = sel.slice(0, mx)
	while sel.size() < mn:
		for o in opts:
			if not (o in sel):
				sel.append(o)
				break
	m.submit_choice(sel)
	return sel


static func _resource_rank(m: Match, p: int, c: CardInst) -> float:
	# Resource cards we can't cast soon; keep cheap units.
	var res: int = m.players[p].resources.size()
	var r := float(c.cost())
	if c.cost() > res + 3:
		r += 3.0
	if c.card_type() == "event":
		r += 0.5
	return r


static func _choose_targets(m: Match, pd: Dictionary) -> Array:
	var p: int = pd["player"]
	var hostile: bool = pd.get("hostile", false)
	var e: Dictionary = pd.get("effect", {})
	var scored: Array = []
	for uid in pd["options"]:
		var c := m.card(uid)
		var s := 0.0
		var mine := c.controller == p
		if c.zone == "base":
			s = (3.0 if not mine else -3.0) if hostile else (2.0 if mine else -2.0)
		else:
			var v := unit_value(c)
			if hostile:
				s = v if not mine else -v
				if e.get("op", "") == "damage":
					var n := int(e.get("n", 1))
					if n >= c.remaining_hp() and c.shield_count() == 0:
						s *= 1.6
					elif c.shield_count() > 0:
						s *= 0.3
			else:
				s = v if mine else -v
				# helping only counts if it does something: heal the hurt, ready the exhausted
				var hop: String = e.get("op", "")
				if mine and hop == "heal" and c.damage <= 0:
					s = 0.05
				if mine and hop == "ready" and not c.exhausted:
					s = 0.05
		scored.append([s, uid])
	scored.sort_custom(func(a, b): return a[0] > b[0])
	var out: Array = []
	for pair in scored:
		if out.size() >= int(pd["max"]):
			break
		if pair[0] <= 0.0 and out.size() >= int(pd["min"]):
			break
		out.append(pair[1])
	return out
