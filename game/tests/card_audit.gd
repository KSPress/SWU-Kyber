extends SceneTree
## Card-by-card engine audit. Every leader, base, unit, event and upgrade is put
## through the real rules engine on a staged board:
##   unit/event/upgrade : played from hand (cost paid), every choice answered by
##                        the bot, then (units) readied + attacks, uses its
##                        action abilities, and is defeated (When Defeated)
##   leader             : every action ability used, Epic Action deploy, attack
##   base               : a short bot-vs-bot game on that base
## For each card it records: script errors (attributed via "AUDIT <id>" markers
## in the log), stalls (choices that never resolve), illegal states, and for
## automated abilities whether the game state actually changed ("no-op").
##   godot --headless --path game --script res://tests/card_audit.gd -- <out.json> [id-filter]

var lib := CardLibrary.new()
var results: Dictionary = {}
var filler := "SOR_095"   # Battlefield Marine


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://card_audit.json"
	var only: String = args[1] if args.size() > 1 else ""
	lib.load_file("res://ip/data/cards.json")
	var ids: Array = lib.cards.keys()
	ids.sort()
	var n := 0
	for id in ids:
		if only != "" and not str(id).begins_with(only):
			continue
		var c: Dictionary = lib.cards[id]
		var t: String = c.get("type", "")
		if t.begins_with("token") or t.ends_with("_token"):
			continue
		print("AUDIT ", id)
		var r: Dictionary
		match t:
			"leader":
				r = audit_leader(id)
			"base":
				r = audit_base(id)
			_:
				r = audit_card(id)
		r["type"] = t
		r["implemented"] = c.get("implemented", "")
		results[id] = r
		n += 1
	print("AUDIT_END ", n)
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify(results))
	quit()


func new_match(leader := "SEC_015", base := "HMW_019", seed_v := 1) -> Match:
	var m := Match.new()
	var deck: Array = []
	for i in 30:
		deck.append(filler)
	var rules := RuleSet.premier()
	rules.aspect_penalties = false
	m.setup(lib, {"seed": seed_v, "rules": rules, "first": 0, "players": [
		{"leader": leader, "base": base, "deck": deck, "ai": true},
		{"leader": "SOR_017", "base": "HMW_028", "deck": deck.duplicate(), "ai": true}]})
	resolve(m)
	return m


## Answer every pending choice with the bot. Returns false if it never settles.
func resolve(m: Match, cap := 60) -> bool:
	for i in cap:
		if m.pending.is_empty():
			return true
		AiBot.choose(m)
	return m.pending.is_empty()


func stage(m: Match) -> void:
	# a board with something to hit and something to help, plenty of resources
	for p in 2:
		var ps: PlayerState = m.players[p]
		while ps.resources.size() < 16 and not ps.deck.is_empty():
			m.move_to_resources(p, ps.deck.pop_front())
		for r in ps.resources:
			r.exhausted = false
		# trooper, fighter, creature, droid, 3 officials, underworld transport,
		# force unit, 1-HP fighter, a 7-power beast
		for id in ["SOR_095", "SOR_237", "ASH_121", "ASH_252", "ASH_076", "ASH_076", "ASH_076", "ASH_173", "HMW_128", "ASH_141", "ASH_131"]:
			var u := m._new_inst(id, p)
			m._put_in_play(u, u.arena(), false)
		var hurt := m._new_inst("SOR_046", p)   # damaged + shielded + exhausted
		m._put_in_play(hurt, hurt.arena(), true)
		hurt.damage = 2
		m.attach_token(hurt, "shield")
		var tok := m.create_unit_token(p, "battle_droid")
		if tok:
			tok.exhausted = false
		for u in ps.units:
			if u.id in ["SOR_237", "HMW_128"]:
				u.exhausted = true      # something to ready
			if u.id == "ASH_121":
				u.damage = 1            # a damaged unit that can still attack
		ps.base.damage = 5
		ps.credits = 2
	# a varied hand for "play a ___ from your hand" effects
	for id in ["SOR_172", "HMW_128", "HMW_140", "HMW_106", "ASH_069", "ASH_121", "SOR_073", "LOF_215", "SOR_095", "SOR_237"]:
		var hc := m._new_inst(id, 0)
		hc.zone = "hand"
		m.players[0].hand.append(hc)
	m.players[0].force_token = true
	m.defeated_cards_this_phase[0].append(m._new_inst("SOR_095", 0))
	m.take_events()


func snapshot(m: Match) -> String:
	var parts: Array = []
	for ps in m.players:
		var ready := 0
		for r in ps.resources:
			if not r.exhausted:
				ready += 1
		parts.append("B%d H%d D%d X%d R%d/%d F%s C%d" % [ps.base.damage, ps.hand.size(), ps.deck.size(), ps.discard.size(), ready, ps.resources.size(), ps.force_token, ps.credits])
		var us: Array = []
		for u in ps.units:
			us.append("%s:%d:%s:%d:%d:%d:%s" % [u.id, u.damage, u.exhausted, u.upgrades.size(), u.power(), u.max_hp(), u.mods.size()])
		us.sort()
		parts.append(",".join(us))
	return "|".join(parts)


func sane(m: Match) -> String:
	for ps in m.players:
		for u in ps.units:
			if not u.in_play():
				return "unit listed in play but zone=%s" % u.zone
			if u.damage < 0:
				return "negative damage"
		for c in ps.hand:
			if c.zone != "hand":
				return "hand card zone=%s" % c.zone
	if not m.frames.is_empty() and m.pending.is_empty() and not m.is_over():
		return "frames left unresolved"
	return ""


func has_trigger(c: Dictionary, trig: Array) -> bool:
	for a in c.get("abilities", []):
		if a.get("trigger", "") in trig and not a.get("effects", []).is_empty():
			return true
	return false


func audit_card(id: String) -> Dictionary:
	var r := {"steps": [], "issues": []}
	var m := new_match()
	stage(m)
	var ps: PlayerState = m.players[0]
	var c := m._new_inst(id, 0)
	c.zone = "hand"
	ps.hand.append(c)
	var data: Dictionary = c.data
	var t := c.card_type()
	# --- play it
	if t == "unit" and not (m.arena_for(c) in m.rules.arenas):
		r["issues"].append("unit arena not in rules")
		return r
	var legal := false
	for a in m.legal_actions(0):
		if a["a"] == "play" and a["uid"] == c.uid:
			legal = true
	if not legal:
		r["issues"].append("not playable with 10 resources")
		return r
	# give the Force token unless the card is what grants it (so either use is observable)
	m.players[0].force_token = str(data.get("text", "")).to_lower().find("the force is with you") < 0
	var before := snapshot(m)
	m.do_action({"a": "play", "uid": c.uid})
	if not resolve(m):
		r["issues"].append("stuck after play (pending %s)" % m.pending.get("kind", ""))
		return r
	var after := snapshot(m)
	r["steps"].append("played")
	if has_trigger(data, ["when_played", "event"]):
		# the play itself always changes hand/resources; compare everything except them
		var changed := _strip(before) != _strip(after)
		if not changed:
			r["issues"].append("no-op: when-played/event effect changed nothing")
	var s := sane(m)
	if s != "":
		r["issues"].append(s)
	if t != "unit" or not c.in_play():
		return r
	# --- attack
	c.exhausted = false
	m.active = 0
	var tgts := m.attack_targets(c)
	if tgts.is_empty():
		r["issues"].append("no attack targets")
	else:
		var b2 := snapshot(m)
		m.do_action({"a": "attack", "uid": c.uid, "target": tgts[0]})
		if not resolve(m):
			r["issues"].append("stuck after attack (pending %s)" % m.pending.get("kind", ""))
			return r
		r["steps"].append("attacked")
		if snapshot(m) == b2:
			r["issues"].append("attack changed nothing")
	# --- action abilities
	if c.in_play():
		var acts := c.abilities_with("action")
		for i in acts.size():
			c.exhausted = false
			for rr in ps.resources:
				rr.exhausted = false
			m.active = 0
			if not m.can_act(0):
				break
			var ok := false
			for a in m.legal_actions(0):
				if a["a"] == "ability" and a["uid"] == c.uid and int(a["idx"]) == i:
					ok = true
			if not ok:
				r["issues"].append("action %d not usable" % i)
				continue
			var b3 := snapshot(m)
			m.do_action({"a": "ability", "uid": c.uid, "idx": i})
			if not resolve(m):
				r["issues"].append("stuck after action ability")
				return r
			r["steps"].append("action")
			if snapshot(m) == b3:
				r["issues"].append("no-op: action ability changed nothing")
	# --- defeat
	if c.in_play():
		m.defeat(c)
		m.pump()
		if not resolve(m):
			r["issues"].append("stuck after defeat")
			return r
		r["steps"].append("defeated")
	s = sane(m)
	if s != "":
		r["issues"].append(s)
	return r


## Remove the acting player's hand/resource/discard counters (paying for and
## playing the card changes those by definition).
func _strip(snap: String) -> String:
	var p := snap.split("|")
	var a := p[0].split(" ")
	return "B" + a[0].substr(1) + " " + a[2] + " " + a[5] + " " + a[6] + "|" + "|".join(p.slice(1))


func audit_leader(id: String) -> Dictionary:
	var r := {"steps": [], "issues": []}
	var m := new_match(id)
	stage(m)
	var ps: PlayerState = m.players[0]
	var l: CardInst = ps.leader
	ps.force_token = str(l.data.get("text", "")).to_lower().find("the force is with you") < 0
	var acts := l.abilities_with("action")
	for i in acts.size():
		l.exhausted = false
		for rr in ps.resources:
			rr.exhausted = false
		m.active = 0
		# give the leader something to work with for "play from hand" style actions
		var helper := m._new_inst(filler, 0)
		helper.zone = "hand"
		ps.hand.append(helper)
		var ok := false
		for a in m.legal_actions(0):
			if a["a"] == "ability" and a["uid"] == l.uid and int(a["idx"]) == i:
				ok = true
		if not ok:
			r["issues"].append("leader action %d not usable" % i)
			continue
		var b := snapshot(m)
		m.do_action({"a": "ability", "uid": l.uid, "idx": i})
		if not resolve(m):
			r["issues"].append("stuck after leader action")
			return r
		r["steps"].append("action")
		if snapshot(m) == b:
			# conditional actions ("If you attacked with...") legitimately do nothing here
			var cond := false
			for e in acts[i].get("effects", []):
				if e.has("if"):
					cond = true
			if not cond:
				r["issues"].append("no-op: leader action changed nothing")
	l.exhausted = false
	m.active = 0
	var dep := false
	for a in m.legal_actions(0):
		if a["a"] == "deploy":
			dep = true
	if not dep:
		if int(l.data.get("leader_unit", {}).get("hp", 0)) == 0:
			r["steps"].append("no unit side (flips between leader sides)")
			return r
		r["issues"].append("cannot deploy with 16 resources")
		return r
	m.do_action({"a": "deploy"})
	if not resolve(m):
		r["issues"].append("stuck after deploy")
		return r
	r["steps"].append("deployed")
	if not l.in_play():
		r["issues"].append("deployed leader not in play")
		return r
	l.exhausted = false
	m.active = 0
	var tg := m.attack_targets(l)
	if not tg.is_empty():
		var b2 := snapshot(m)
		m.do_action({"a": "attack", "uid": l.uid, "target": tg[0]})
		if not resolve(m):
			r["issues"].append("stuck after leader attack")
			return r
		r["steps"].append("attacked")
		if snapshot(m) == b2:
			r["issues"].append("leader attack changed nothing")
	m.defeat(l)
	m.pump()
	resolve(m)
	if l.zone != "leader":
		r["issues"].append("defeated leader did not return to leader zone")
	var s := sane(m)
	if s != "":
		r["issues"].append(s)
	return r


func audit_base(id: String) -> Dictionary:
	var r := {"steps": [], "issues": []}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	var m := Match.new()
	var deck := DeckBuilder.auto_deck(lib, "SEC_015", id, 30, rng)
	m.setup(lib, {"seed": hash(id), "rules": RuleSet.quick_mode("traditional"), "players": [
		{"leader": "SEC_015", "base": id, "deck": deck, "ai": true},
		{"leader": "SOR_017", "base": "HMW_028", "deck": deck.duplicate(), "ai": true}]})
	var steps := 0
	while not m.is_over() and steps < 3000:
		steps += 1
		if not m.pending.is_empty():
			AiBot.choose(m)
		elif m.phase == "action":
			AiBot.act(m)
		else:
			break
	if not m.is_over():
		r["issues"].append("bot game did not finish")
	r["steps"].append("game %d rounds" % m.round_num)
	return r
