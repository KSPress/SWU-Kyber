class_name Match
extends RefCounted
## The SWU rules engine for one game. Pure logic (no Nodes): the board UI, the
## headless simulator and the tests all drive it through the same API:
##
##   setup(cfg)                 build players, shuffle, queue setup steps
##   pending                    non-empty => someone must answer a choice
##   submit_choice(selection)   answer it (Array of uids / indices)
##   legal_actions(p)           what player p may do now (action phase)
##   do_action(action)          perform one action
##   take_events()              drain animation events for the view
##
## Everything that happens (setup, regroup, abilities, attacks) is an op in a
## stack of frames (see Effects). A frame that needs input suspends and sets
## `pending`, which keeps the whole flow resumable and replayable.

const SIDES := ["player", "enemy"]

var lib: CardLibrary
var rules: RuleSet
var players: Array = []
var rng := RandomNumberGenerator.new()
var seed_value := 0
var round_num := 1
var phase := "setup"            # setup | action | regroup | over
var phase_serial := 0           # bumps every phase, for "this phase" durations
var active := 0
var initiative := 0
var consecutive_passes := 0
var winner := -1                # 0/1, 2 = draw
var events: Array = []
var log_lines: Array = []
var pending: Dictionary = {}
var frames: Array = []
var by_uid: Dictionary = {}
var tokens: Array = []          # claimable token definitions in this match
var tokens_claimed: Dictionary = {}
var objective: Objective
var attack: Dictionary = {}
var defeated_this_phase := [0, 0]
var attacked_with := [[], []]
var played_this_phase := [[], []]         # CardInst played this phase, per player
var defeated_cards_this_phase := [[], []]  # CardInst (controller's side) defeated this phase
var history: Array = []         # [{"a":..}, {"choice":[..]}] for deterministic replays
var _next_uid := 1
var _need_advance := false
var _last_actor := 0


# ---------------------------------------------------------------- setup

## cfg = {
##   seed, rules: RuleSet,
##   players: [{name, leader, base, deck:[ids], ai, profile, base_hp_bonus, preplaced:[{id, arena, flags}]}],
##   tokens: [token defs], objective: {type, params}
## }
func setup(p_lib: CardLibrary, cfg: Dictionary) -> void:
	lib = p_lib
	rules = cfg.get("rules", RuleSet.premier())
	seed_value = int(cfg.get("seed", randi()))
	rng.seed = seed_value
	players.clear()
	for i in 2:
		var pc: Dictionary = cfg["players"][i]
		var ps := PlayerState.new()
		ps.index = i
		ps.display_name = pc.get("name", "Player %d" % (i + 1))
		ps.is_ai = pc.get("ai", i == 1)
		ps.ai_profile = pc.get("profile", "tempo")
		ps.hero_skin = pc.get("hero_skin", "")
		players.append(ps)
		if pc.get("leader", "") != "":
			ps.leader = _new_inst(pc["leader"], i)
			ps.leader.zone = "leader"
		ps.base = _new_inst(pc.get("base", ""), i)
		ps.base.zone = "base"
		var hp_target := rules.base_hp_override if rules.base_hp_override > 0 else ps.base.printed_hp()
		if int(pc.get("base_hp", 0)) > 0:
			hp_target = int(pc["base_hp"])
		hp_target += int(pc.get("base_hp_bonus", 0))
		if hp_target != ps.base.printed_hp():
			ps.base.mods.append({"h": hp_target - ps.base.printed_hp(), "dur": "permanent"})
		for cid in pc.get("deck", []):
			if not lib.has(cid):
				push_warning("Match: unknown card id %s skipped" % cid)
				continue
			var c := _new_inst(cid, i)
			c.zone = "deck"
			ps.deck.append(c)
		_shuffle(ps.deck)
		ps.base.damage = int(pc.get("base_damage", 0))
		ps.first_unit_experience = int(pc.get("first_unit_experience", 0))
		ps.first_unit_shield = int(pc.get("first_unit_shield", 0))
		ps.card_upgrades = pc.get("card_upgrades", {})
		ps.force_token = int(pc.get("start_force", 0)) > 0
		for pre in pc.get("preplaced", []):
			if not lib.has(pre["id"]):
				continue
			var u := _new_inst(pre["id"], i)
			_put_in_play(u, pre.get("arena", u.arena()), not pre.get("ready", true))
			u.flags.merge(pre.get("flags", {}), true)
		for cid in pc.get("bonus_hand", []):
			if lib.has(cid):
				var hc := _new_inst(cid, i)
				hc.zone = "hand"
				ps.hand.append(hc)
	tokens = Tokens.resolve(cfg.get("tokens", ["initiative"]))
	objective = Objective.create(cfg.get("objective", {"type": "standard"}))
	objective.setup(self)
	initiative = int(cfg.get("first", rng.randi_range(0, 1)))
	_log("%s has the initiative." % players[initiative].display_name)
	var seq: Array = []
	var pcs: Array = cfg["players"]
	for p in [initiative, 1 - initiative]:
		seq.append({"op": "_draw", "p": p, "n": rules.starting_hand + int(pcs[p].get("extra_hand", 0))})
	if rules.allow_mulligan:
		for p in [initiative, 1 - initiative]:
			seq.append({"op": "_mulligan", "p": p})
	for p in [initiative, 1 - initiative]:
		seq.append({"op": "_setup_resources", "p": p, "n": rules.starting_resources})
		if int(pcs[p].get("extra_resources", 0)) > 0:
			seq.append({"op": "_deck_to_resources", "p": p, "n": int(pcs[p]["extra_resources"])})
	seq.append({"op": "_start_action"})
	push_frame(seq, {"ctl": initiative})
	pump()


func _new_inst(cid: String, owner_idx: int) -> CardInst:
	var data := lib.get_card(cid)
	if data.is_empty():
		data = {"id": cid, "name": cid, "type": "unit", "power": 1, "hp": 1, "cost": 1, "text": "MISSING CARD DATA", "implemented": "manual"}
	var c := CardInst.new(_next_uid, cid, data, owner_idx)
	_next_uid += 1
	by_uid[c.uid] = c
	return c


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t


# ---------------------------------------------------------------- queries

func opp(p: int) -> int:
	return 1 - p


func card(uid: int) -> CardInst:
	return by_uid.get(uid)


func all_units() -> Array:
	return players[0].units + players[1].units


func is_over() -> bool:
	return winner >= 0


func can_act(p: int) -> bool:
	return phase == "action" and winner < 0 and pending.is_empty() and frames.is_empty() and active == p


## Cost to play `c` for player p, including aspect penalties (+2 per missing icon).
func play_cost(p: int, c: CardInst, smuggle := false, opts := {}) -> int:
	var cost := c.cost()
	var needed: Array = c.aspects()
	if smuggle:
		var sm := _kw_entry(c, "smuggle")
		cost = int(sm.get("v", cost))
		needed = sm.get("aspects", needed)
	if rules.aspect_penalties and not opts.get("ignore_aspects", false):
		var pool: Array = players[p].aspect_pool().duplicate()
		for a in needed:
			var i := pool.find(a)
			if i >= 0:
				pool.remove_at(i)
			else:
				cost += 2
	return maxi(0, cost - int(opts.get("discount", 0)))


## Exploit X: defeat up to X friendly units, each lowers the cost by 2.
func exploit_discount(p: int, c: CardInst) -> int:
	var x := c.kw("exploit")
	if x <= 0:
		return 0
	var n := 0
	for u in players[p].units:
		if not u.is_leader():
			n += 1
	return 2 * mini(x, n)


func _kw_entry(c: CardInst, k: String) -> Dictionary:
	for e in c.data.get("keywords", []):
		if e.get("k", "") == k:
			return e
	return {}


func attack_targets(u: CardInst) -> Array:
	var out: Array = []
	if not u.in_play() or u.exhausted or u.flags.get("cannot_attack", false):
		return out
	var p := u.controller
	var enemies: Array = players[opp(p)].units_in(u.zone)
	var sab := u.has_kw("saboteur")
	var sentinels: Array = []
	if not sab:
		for e in enemies:
			if e.has_kw("sentinel"):
				sentinels.append(e)
	var pool := sentinels if sentinels.size() > 0 else enemies
	for e in pool:
		if e.has_kw("hidden") and e.entered_phase == phase_serial:
			continue
		if e.flags.get("untargetable", false):
			continue
		out.append(e.uid)
	var no_base := false
	for a in u.abilities_with("constant"):
		if a.get("flag", "") == "no_base_attack":
			no_base = true
	if sentinels.is_empty() and not no_base:
		out.append(players[opp(p)].base.uid)
	return out


func _has_upgrade_target(p: int, c: CardInst) -> bool:
	return Effects.upgrade_targets(self, p, c).size() > 0


func legal_actions(p: int) -> Array:
	var out: Array = []
	if not can_act(p):
		return out
	var ps: PlayerState = players[p]
	var res := ps.available()
	for c in ps.hand:
		var t: String = c.card_type()
		if t == "unit" and not (arena_for(c) in rules.arenas):
			continue
		if t == "upgrade" and not _has_upgrade_target(p, c):
			continue
		if play_cost(p, c) - exploit_discount(p, c) <= res:
			out.append({"a": "play", "uid": c.uid})
	for r in ps.resources:
		if r.has_kw("smuggle") and play_cost(p, r, true) <= res - (0 if r.exhausted else 1):
			if r.card_type() == "upgrade" and not _has_upgrade_target(p, r):
				continue
			out.append({"a": "smuggle", "uid": r.uid})
	for u in ps.units:
		for t in attack_targets(u):
			out.append({"a": "attack", "uid": u.uid, "target": t})
		var acts: Array = u.abilities_with("action")
		for i in acts.size():
			if _can_pay_action(p, u, acts[i]):
				out.append({"a": "ability", "uid": u.uid, "idx": i})
	if ps.leader and not ps.leader.deployed:
		var acts := ps.leader.abilities_with("action")
		for i in acts.size():
			if _can_pay_action(p, ps.leader, acts[i]):
				out.append({"a": "ability", "uid": ps.leader.uid, "idx": i})
		# double-sided leaders with no unit side (e.g. Chancellor Palpatine // Darth Sidious) never deploy
		var has_unit_side := int(ps.leader.data.get("leader_unit", {}).get("hp", 0)) > 0
		if has_unit_side and not ps.leader.epic_used and ps.resources.size() >= int(ps.leader.data.get("epic_cost", 99)):
			out.append({"a": "deploy"})
	for tk in tokens:
		if _token_claimable(p, tk):
			out.append({"a": "claim", "token": tk["id"]})
	out.append({"a": "pass"})
	return out


func _can_pay_action(p: int, c: CardInst, ab: Dictionary) -> bool:
	var cost: Dictionary = ab.get("cost", {})
	if cost.get("exhaust", false) and c.exhausted:
		return false
	if cost.has("other"):
		# Only costs the engine can actually pay are offered; others would make the action free.
		var extra := Effects.extra_cost(self, p, c, str(cost["other"]))
		if not extra.get("ok", false):
			return false
	return players[p].available() >= int(cost.get("resources", 0))


func _token_claimable(p: int, tk: Dictionary) -> bool:
	if players[p].out_of_round or tokens_claimed.has(tk["id"]):
		return false
	var side: String = tk.get("side_claimable", "both")
	return side == "both" or side == SIDES[p]


# ---------------------------------------------------------------- actions

func do_action(a: Dictionary) -> bool:
	var p := active
	if not can_act(p):
		return false
	var legal := false
	for l in legal_actions(p):
		if _same_action(l, a):
			legal = true
			break
	if not legal:
		push_warning("illegal action %s" % [a])
		return false
	history.append({"p": p, "a": a})
	_last_actor = p
	var ps: PlayerState = players[p]
	match a["a"]:
		"pass":
			consecutive_passes += 1
			_log("%s passes." % ps.display_name)
			events.append({"t": "pass", "p": p})
			if rules.turn_mode == RuleSet.TurnMode.BURST:
				ps.turn_done = true
		"play":
			consecutive_passes = 0
			var pc := card(a["uid"])
			if exploit_discount(p, pc) > 0:
				push_frame([{"op": "_exploit", "uid": pc.uid}], {"ctl": p, "src": pc.uid, "name": pc.name(), "text": "Exploit"})
			else:
				_play_card(p, pc, false)
		"smuggle":
			consecutive_passes = 0
			_play_card(p, card(a["uid"]), true)
		"attack":
			consecutive_passes = 0
			begin_attack(card(a["uid"]), card(a["target"]))
		"ability":
			consecutive_passes = 0
			_use_action_ability(p, card(a["uid"]), int(a["idx"]))
		"deploy":
			consecutive_passes = 0
			_deploy_leader(p)
		"claim":
			consecutive_passes = 0
			_claim_token(p, a["token"])
	_need_advance = true
	pump()
	return true


func _same_action(l: Dictionary, a: Dictionary) -> bool:
	for k in l:
		if not a.has(k) or str(a[k]) != str(l[k]):
			return false
	return true


func submit_choice(sel: Array) -> bool:
	if pending.is_empty():
		return false
	var opts: Array = pending.get("options", [])
	if sel.size() < int(pending.get("min", 0)) or sel.size() > int(pending.get("max", 1)):
		return false
	for s in sel:
		if not (s in opts):
			return false
	history.append({"choice": sel.duplicate()})
	var frame: Dictionary = frames.back()
	frame["ctx"]["_choice"] = sel.duplicate()
	pending = {}
	pump()
	return true


func take_events() -> Array:
	var e := events
	events = []
	return e


# ---------------------------------------------------------------- frames

func push_frame(effects: Array, ctx: Dictionary) -> void:
	frames.append({"effects": effects, "i": 0, "ctx": ctx})


func push_ability(src: CardInst, ab: Dictionary, extra := {}) -> void:
	if ab.get("effects", []).is_empty():
		return
	var ctx := {"src": src.uid, "ctl": src.controller, "text": ab.get("text", ""), "name": src.name()}
	ctx.merge(extra, true)
	push_frame(ab["effects"], ctx)


## Runs queued work until a choice is needed or nothing is left.
func pump() -> void:
	var guard := 0
	while winner < 0 and pending.is_empty():
		guard += 1
		if guard > 5000:
			push_error("Match.pump: runaway loop")
			return
		if not frames.is_empty():
			var fr: Dictionary = frames.back()
			if fr["i"] >= fr["effects"].size():
				frames.pop_back()
				continue
			var eff: Dictionary = fr["effects"][fr["i"]]
			var r := Effects.exec(self, eff, fr["ctx"])
			if r == Effects.SUSPEND:
				return
			fr["i"] += 1
			continue
		if _state_based():
			continue
		if _need_advance:
			_need_advance = false
			_advance()
			continue
		return


# ---------------------------------------------------------------- flow

func _advance() -> void:
	if phase != "action":
		return
	if rules.turn_mode == RuleSet.TurnMode.BURST:
		var p := _last_actor
		if players[p].out_of_round:
			players[p].turn_done = true
		if players[0].turn_done and players[1].turn_done:
			_end_action_phase()
		elif players[p].turn_done:
			active = opp(p)
		return
	var nxt := opp(_last_actor)
	for _i in 4:
		if consecutive_passes >= 2:
			_end_action_phase()
			return
		if players[nxt].out_of_round:
			consecutive_passes += 1
			events.append({"t": "pass", "p": nxt, "auto": true})
			nxt = opp(nxt)
			continue
		active = nxt
		events.append({"t": "turn", "p": active})
		return
	_end_action_phase()


func start_action_phase() -> void:
	phase = "action"
	phase_serial += 1
	active = initiative
	consecutive_passes = 0
	defeated_this_phase = [0, 0]
	attacked_with = [[], []]
	played_this_phase = [[], []]
	defeated_cards_this_phase = [[], []]
	for ps in players:
		ps.out_of_round = false
		ps.turn_done = false
	tokens_claimed.clear()
	events.append({"t": "phase", "phase": "action", "round": round_num})
	_log("— Round %d: action phase —" % round_num)
	objective.on_action_start(self)
	for u in all_units():
		for ab in u.abilities_with("action_start"):
			push_ability(u, ab)
	events.append({"t": "turn", "p": active})


func _end_action_phase() -> void:
	_expire("phase")
	phase = "regroup"
	phase_serial += 1
	events.append({"t": "phase", "phase": "regroup", "round": round_num})
	_log("— Regroup phase —")
	var seq: Array = []
	seq.append({"op": "_regroup_triggers"})
	for p in [initiative, opp(initiative)]:
		seq.append({"op": "_draw", "p": p, "n": rules.regroup_draw})
	for p in [initiative, opp(initiative)]:
		for _i in rules.regroup_resource:
			seq.append({"op": "_regroup_resource", "p": p})
	seq.append({"op": "_ready_all"})
	seq.append({"op": "_new_round"})
	push_frame(seq, {"ctl": initiative})


func end_round() -> void:
	_expire("phase")
	_expire("round")
	objective.on_round_end(self)
	if winner >= 0:
		return
	round_num += 1
	start_action_phase()


func _expire(dur: String) -> void:
	for u in all_units() + [players[0].base, players[1].base]:
		var keep: Array = []
		for m in u.mods:
			if m.get("dur", "") != dur:
				keep.append(m)
		u.mods = keep


func _state_based() -> bool:
	var acted := false
	for u in all_units():
		if u.in_play() and u.damage >= u.max_hp():
			defeat(u)
			acted = true
	var dead := [players[0].base_remaining() <= 0, players[1].base_remaining() <= 0]
	if dead[0] or dead[1]:
		set_winner(2 if dead[0] and dead[1] else (1 if dead[0] else 0), "base destroyed")
		return true
	var w := objective.check(self)
	if w >= 0:
		set_winner(w, objective.describe())
		return true
	return acted


func set_winner(w: int, why := "") -> void:
	if winner >= 0:
		return
	winner = w
	phase = "over"
	pending = {}
	frames.clear()
	events.append({"t": "win", "p": w, "why": why})
	_log("Game over: %s (%s)" % ["draw" if w == 2 else (players[w].display_name + (" win" if players[w].display_name == "You" else " wins")), why])


# ---------------------------------------------------------------- zones

func draw(p: int, n: int) -> void:
	var ps: PlayerState = players[p]
	for _i in n:
		if ps.deck.is_empty():
			if rules.deck_out_damage > 0:
				_log("%s cannot draw and takes %d damage." % [ps.display_name, rules.deck_out_damage])
				deal_damage(ps.base, rules.deck_out_damage, null)
			continue
		var c: CardInst = ps.deck.pop_front()
		c.zone = "hand"
		ps.hand.append(c)
		events.append({"t": "draw", "p": p, "uid": c.uid})


func move_to_resources(p: int, c: CardInst, exhausted := false) -> void:
	_remove_from_zones(c)
	c.zone = "resource"
	c.exhausted = exhausted
	c.controller = p
	players[p].resources.append(c)
	events.append({"t": "resource", "p": p, "uid": c.uid})


func _remove_from_zones(c: CardInst) -> void:
	for ps in players:
		for arr in [ps.hand, ps.deck, ps.discard, ps.resources, ps.units]:
			arr.erase(c)


func pay(p: int, amount: int) -> void:
	var left := amount
	# Spend smuggle-able resources last so they stay available.
	var order: Array = players[p].resources.duplicate()
	order.sort_custom(func(a, b): return int(a.has_kw("smuggle")) < int(b.has_kw("smuggle")))
	for r in order:
		if left <= 0:
			break
		if not r.exhausted:
			r.exhausted = true
			left -= 1
	if left > 0 and players[p].credits > 0:
		var spent := mini(left, players[p].credits)
		players[p].credits -= spent
		left -= spent
		events.append({"t": "credits", "p": p, "n": -spent})
	if amount > 0:
		events.append({"t": "pay", "p": p, "n": amount})


## Where a card's unit enters play under this ruleset. In One Lane every unit
## (ground or space) fights in the single shared lane.
func arena_for(c: CardInst, printed := "") -> String:
	var a := printed if printed != "" or c == null else c.arena()
	if rules.single_lane:
		return str(rules.arenas[0])
	return a


func _put_in_play(u: CardInst, arena: String, exhausted := true) -> void:
	arena = arena_for(u, arena)
	_remove_from_zones(u)
	u.zone = arena
	u.exhausted = exhausted
	u.entered_phase = phase_serial
	u.damage = 0 if not u.deployed else u.damage
	players[u.controller].units.append(u)
	events.append({"t": "enter", "uid": u.uid, "p": u.controller})


## opts (from abilities like "Play a unit from your hand. It costs 1 less."):
##   discount, ignore_aspects, ready, gain_kw
func _play_card(p: int, c: CardInst, smuggle: bool, opts := {}) -> void:
	var cost := play_cost(p, c, smuggle, opts)
	played_this_phase[p].append(c)
	if smuggle:
		c.exhausted = true  # can't pay with itself
	pay(p, cost)
	var ps: PlayerState = players[p]
	if smuggle:
		ps.resources.erase(c)
		if not ps.deck.is_empty():
			move_to_resources(p, ps.deck.pop_front(), true)
	else:
		ps.hand.erase(c)
	events.append({"t": "play", "p": p, "uid": c.uid})
	_log("%s plays %s." % [ps.display_name, c.title()])
	match c.card_type():
		"unit":
			_enforce_unique(p, c)
			_put_in_play(c, c.arena(), not opts.get("ready", false))
			if opts.has("gain_kw"):
				c.mods.append({"kw": opts["gain_kw"], "v": 1, "dur": "phase"})
			_on_unit_enters(c, "when_played")
		"event":
			c.zone = "discard"
			ps.discard.append(c)
			for ab in c.abilities():
				if ab.get("trigger", "") in ["event", "when_played"]:
					push_ability(c, ab)
		"upgrade":
			c.zone = "limbo"
			push_frame([{"op": "_attach", "uid": c.uid}], {"src": c.uid, "ctl": p})
		_:
			c.zone = "discard"
			ps.discard.append(c)


func _enforce_unique(p: int, c: CardInst) -> void:
	if not c.unique():
		return
	for u in players[p].units.duplicate():
		if u.flags.get("protected", false):
			continue  # scenario units (e.g. unconscious Luke) are outside the unique rule
		if u.id == c.id or (u.unique() and u.title() == c.title()):
			_log("Unique rule: %s is defeated." % u.title())
			defeat(u)


func _on_unit_enters(u: CardInst, trigger: String) -> void:
	if u.has_kw("shielded"):
		attach_token(u, "shield")
	var ps: PlayerState = players[u.controller]
	if ps.first_unit_experience > 0 and trigger == "when_played":
		ps.first_unit_experience -= 1
		attach_token(u, "experience")
	if ps.first_unit_shield > 0 and trigger == "when_played":
		ps.first_unit_shield -= 1
		attach_token(u, "shield")
	for kind in ps.card_upgrades.get(u.id, []):
		attach_token(u, kind)
	# Ambush is pushed first so When Played resolves before the ambush attack.
	if u.has_kw("ambush") and trigger == "when_played":
		push_frame([{"op": "_ambush", "uid": u.uid}], {"src": u.uid, "ctl": u.controller})
	for ab in u.abilities_with(trigger):
		push_ability(u, ab)
	for other in players[u.controller].units:
		if other != u:
			for ab in other.abilities_with("friendly_unit_played"):
				push_ability(other, ab, {"it": u.uid})


func attach_upgrade(up: CardInst, target: CardInst) -> void:
	_remove_from_zones(up)
	up.zone = "upgrade"
	up.attached_to = target
	up.controller = target.controller
	target.upgrades.append(up)
	events.append({"t": "upgrade", "uid": up.uid, "on": target.uid})
	for ab in up.data.get("abilities", []):
		if not ab.get("granted", false) and ab.get("trigger", "") == "when_played":
			push_ability(up, ab)


func attach_token(target: CardInst, key: String) -> void:
	if not target.in_play():
		return
	var tid := lib.token_id(key)
	var t := _new_inst(tid, target.controller) if tid != "" else _new_inst("TOKEN_" + key, target.controller)
	if tid == "":
		t.data = {"name": key.capitalize(), "type": "token_upgrade", "power": 1 if key == "experience" else 0, "hp": 1 if key == "experience" else 0}
	t.is_token = true
	t.zone = "upgrade"
	t.attached_to = target
	target.upgrades.append(t)
	events.append({"t": "token", "kind": key, "on": target.uid})


func create_unit_token(p: int, key: String) -> CardInst:
	var tid := lib.token_id(key)
	if tid == "":
		return null
	var tok_arena = lib.get_card(tid).get("arena")
	var arena: String = tok_arena if tok_arena else "ground"
	if not (arena_for(null, arena) in rules.arenas):
		return null  # e.g. a TIE Fighter token in a ground-only Quick game
	var t := _new_inst(tid, p)
	t.is_token = true
	_put_in_play(t, arena, true)
	return t


func summon(p: int, cid: String, ready := false) -> CardInst:
	var u := _new_inst(cid, p)
	_put_in_play(u, u.arena(), not ready)
	_on_unit_enters(u, "when_played")
	return u


func deal_damage(target: CardInst, n: int, source: CardInst) -> int:
	if n <= 0 or target == null:
		return 0
	if target.in_play():
		for up in target.upgrades:
			if up.data.get("name", "") == "Shield":
				target.upgrades.erase(up)
				by_uid.erase(up.uid)
				events.append({"t": "shield_break", "uid": target.uid})
				return 0
	elif target.zone != "base":
		return 0
	target.damage += n
	events.append({"t": "damage", "uid": target.uid, "n": n, "src": source.uid if source else 0})
	return n


func heal(target: CardInst, n: int) -> int:
	var h := mini(n, target.damage)
	if h > 0:
		target.damage -= h
		events.append({"t": "heal", "uid": target.uid, "n": h})
	return h


func defeat(u: CardInst) -> void:
	if not u.in_play():
		return
	var p := u.controller
	var ps: PlayerState = players[p]
	ps.units.erase(u)
	defeated_this_phase[p] += 1
	defeated_cards_this_phase[p].append(u)
	events.append({"t": "defeat", "uid": u.uid, "p": p})
	_log("%s is defeated." % u.title())
	for up in u.upgrades:
		up.attached_to = null
		if up.is_token:
			by_uid.erase(up.uid)
		else:
			up.zone = "discard"
			players[up.owner].discard.append(up)
	u.upgrades.clear()
	u.mods.clear()
	var abil := u.abilities_with("when_defeated")
	if u.is_leader():
		u.deployed = false
		u.zone = "leader"
		u.exhausted = true
		u.damage = 0
	elif u.is_token:
		u.zone = "removed"
	else:
		u.zone = "discard"
		u.damage = 0
		players[u.owner].discard.append(u)
	if u.flags.get("protected", false):
		objective.on_protected_lost(self, u)
	for ab in abil:
		push_ability(u, ab, {"lki_arena": u.arena()})


func return_to_hand(u: CardInst) -> void:
	if u.is_leader() or u.is_token:
		defeat(u)
		return
	var ps: PlayerState = players[u.controller]
	ps.units.erase(u)
	for up in u.upgrades:
		if up.is_token:
			by_uid.erase(up.uid)
		else:
			up.zone = "discard"
			players[up.owner].discard.append(up)
	u.upgrades.clear()
	u.mods.clear()
	u.damage = 0
	u.exhausted = false
	u.zone = "hand"
	u.controller = u.owner
	players[u.owner].hand.append(u)
	events.append({"t": "bounce", "uid": u.uid})


func exhaust(u: CardInst, v := true) -> void:
	if u.exhausted != v:
		u.exhausted = v
		events.append({"t": "exhaust" if v else "ready", "uid": u.uid})


# ---------------------------------------------------------------- combat

func begin_attack(a: CardInst, t: CardInst) -> void:
	var p := a.controller
	exhaust(a)
	attack = {"a": a.uid, "t": t.uid}
	attacked_with[p].append(a.uid)
	events.append({"t": "attack", "a": a.uid, "target": t.uid})
	_log("%s attacks %s." % [a.title(), t.title() if t.zone != "base" else "the enemy base"])
	push_frame([{"op": "_combat"}, {"op": "_attack_end"}], {"src": a.uid, "ctl": p})
	# "When a friendly <Trait> unit attacks" on the attacker's base and other units
	for src in [players[p].base] + players[p].units:
		for ab in src.abilities_with("friendly_attack"):
			if a.has_trait(str(ab.get("trait", ""))):
				push_ability(src, ab, {"it": a.uid})
	var restore := a.kw("restore")
	if restore > 0:
		heal(players[p].base, restore)
	for ab in a.abilities_with("on_attack"):
		push_ability(a, ab, {"attack": true})


func resolve_combat() -> void:
	if attack.is_empty():
		return
	var a := card(attack["a"])
	var t := card(attack["t"])
	if a == null or not a.in_play() or t == null:
		return
	if t.zone == "base":
		var n := deal_damage(t, a.power(true), a)
		if n > 0:
			for ab in a.abilities_with("base_damage"):
				push_ability(a, ab)
		return
	if not t.in_play():
		return
	if a.has_kw("saboteur"):
		var kept: Array = []
		for up in t.upgrades:
			if up.data.get("name", "") == "Shield":
				events.append({"t": "shield_break", "uid": t.uid})
				by_uid.erase(up.uid)
			else:
				kept.append(up)
		t.upgrades = kept
	var ap := a.power(true)
	var dp := t.power(false)
	var t_rem := t.remaining_hp()
	var t_shielded := t.shield_count() > 0
	deal_damage(t, ap, a)
	deal_damage(a, dp, t)
	if a.has_kw("overwhelm") and not t_shielded and ap > t_rem:
		deal_damage(players[opp(a.controller)].base, ap - t_rem, a)


func end_attack() -> void:
	if attack.is_empty():
		return
	var a := card(attack["a"])
	attack = {}
	_expire("attack")
	if a and a.in_play():
		for ab in a.abilities_with("attack_end"):
			push_ability(a, ab)


# ---------------------------------------------------------------- leaders, abilities, tokens

func _use_action_ability(p: int, c: CardInst, idx: int) -> void:
	var ab: Dictionary = c.abilities_with("action")[idx]
	var cost: Dictionary = ab.get("cost", {})
	if cost.get("exhaust", false):
		exhaust(c)
	pay(p, int(cost.get("resources", 0)))
	var other := str(cost.get("other", ""))
	events.append({"t": "ability", "uid": c.uid})
	_log("%s uses %s's action." % [players[p].display_name, c.name()])
	if other != "":
		var extra := Effects.extra_cost(self, p, c, other)
		var seq: Array = extra.get("ops", []).duplicate()
		seq.append({"op": "_reset_ctx"})
		seq.append_array(ab.get("effects", []))
		push_frame(seq, {"src": c.uid, "ctl": p, "text": ab.get("text", ""), "name": c.name()})
		return
	push_ability(c, ab)


func _deploy_leader(p: int) -> void:
	var l: CardInst = players[p].leader
	l.deployed = true
	l.epic_used = true
	var was_exhausted := l.exhausted
	# Scenario stand-in until Piloting is automated: a leader whose printed arena
	# isn't used by this node (e.g. Luke, Hero of Yavin in the all-space trench run)
	# deploys into the node's first arena.
	var arena := l.arena() if l.arena() in rules.arenas else str(rules.arenas[0])
	_put_in_play(l, arena, was_exhausted)
	events.append({"t": "deploy", "uid": l.uid, "p": p})
	_log("%s deploys %s!" % [players[p].display_name, l.title()])
	_on_unit_enters(l, "when_deployed")


func _claim_token(p: int, token_id: String) -> void:
	var tk: Dictionary = {}
	for t in tokens:
		if t["id"] == token_id:
			tk = t
	tokens_claimed[token_id] = p
	players[p].out_of_round = true
	if token_id == "initiative":
		initiative = p
	events.append({"t": "claim", "p": p, "token": token_id})
	_log("%s claims %s." % [players[p].display_name, tk.get("name", token_id)])
	if not tk.get("effects", []).is_empty():
		push_frame(tk["effects"], {"ctl": p, "text": tk.get("name", ""), "src": players[p].base.uid})


func _log(s: String) -> void:
	log_lines.append(s)
	events.append({"t": "log", "text": s})
