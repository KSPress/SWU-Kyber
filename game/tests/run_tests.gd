extends SceneTree
## Headless test runner + bot-vs-bot simulator (spec 10.2).
##   godot --headless --path game --script res://tests/run_tests.gd -- [sims=200]
## Exit code 0 = all assertions passed and no simulation crashed.

var lib := CardLibrary.new()
var failures := 0
var passes := 0


func _init() -> void:
	var n_sims := 200
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		n_sims = int(args[0])
	var loaded := lib.load_file("res://ip/data/cards.json")
	lib.load_file("res://data/custom_cards.json", true)
	print("cards loaded: ", loaded)
	if loaded == 0:
		print("FAIL: no card data. Run tools/import_cards.py first.")
		quit(1)
		return
	test_aspect_penalty()
	test_combat_and_shield()
	test_sentinel_and_saboteur()
	test_overwhelm_raid_grit()
	test_alternating_and_initiative()
	test_leader_deploy_and_defeat()
	test_effect_dsl()
	test_campaign_content()
	test_formats()
	test_choose_one()
	test_one_lane()
	test_spotlight()
	test_leader_actions_and_force()
	test_spotlight_runs()
	simulate_quick_modes(maxi(20, n_sims / 4))
	simulate(n_sims)
	simulate(maxi(20, n_sims / 4), "ground")
	simulate(maxi(20, n_sims / 4), "space")
	print("\n%d passed, %d failed" % [passes, failures])
	quit(1 if failures > 0 else 0)


func check(cond: bool, what: String) -> void:
	if cond:
		passes += 1
	else:
		failures += 1
		print("  FAIL: ", what)


## A started match in the action phase with empty hands; p0 acts first.
func blank_match(rules := RuleSet.premier()) -> Match:
	var m := Match.new()
	var deck: Array = []
	for i in 20:
		deck.append("SOR_095")  # Battlefield Marine
	m.setup(lib, {"seed": 1, "rules": rules, "first": 0, "players": [
		{"name": "A", "leader": "SEC_015", "base": "HMW_019", "deck": deck, "ai": false},
		{"name": "B", "leader": "SOR_017", "base": "HMW_028", "deck": deck.duplicate(), "ai": false}]})
	# answer setup: no mulligans, resource first 2 cards
	while not m.pending.is_empty():
		var pd := m.pending
		if pd["kind"] == "mulligan":
			m.submit_choice([0])
		else:
			m.submit_choice(pd["options"].slice(0, pd["min"]))
	return m


func add_unit(m: Match, p: int, id: String, ready := true) -> CardInst:
	var u := m._new_inst(id, p)
	m._put_in_play(u, u.arena(), not ready)
	return u


func test_aspect_penalty() -> void:
	print("aspect penalty")
	var m := blank_match()
	# C-3PO (cunning/heroism) + Dune Sea (vigilance) playing Battlefield Marine (command/heroism, cost 2) => +2
	var bm := m._new_inst("SOR_095", 0)
	check(m.play_cost(0, bm) == 4, "Battlefield Marine costs 4 with one missing aspect (got %d)" % m.play_cost(0, bm))
	var cm := blank_match(RuleSet.campaign())
	check(cm.play_cost(0, bm) == 2, "campaign ignores aspect penalties")


func test_combat_and_shield() -> void:
	print("combat & shields")
	var m := blank_match()
	var a := add_unit(m, 0, "SOR_095")       # 3/3
	var d := add_unit(m, 1, "SOR_095")
	m.attach_token(d, "shield")
	m.do_action({"a": "attack", "uid": a.uid, "target": d.uid})
	check(d.in_play() and d.damage == 0 and d.shield_count() == 0, "shield absorbs the attack")
	check(a.damage == 3 or not a.in_play(), "defender deals damage back")
	check(not a.in_play(), "3 damage defeats a 3-HP attacker")


func test_sentinel_and_saboteur() -> void:
	print("sentinel / saboteur")
	var m := blank_match()
	var a := add_unit(m, 0, "SOR_095")
	var s := add_unit(m, 1, "SOR_098")       # Echo Base Defender, Sentinel
	add_unit(m, 1, "SOR_095")
	var tg := m.attack_targets(a)
	check(tg.size() == 1 and tg[0] == s.uid, "sentinel must be attacked")
	var sab := add_unit(m, 0, "SOR_239")     # Rebel Pathfinder, Saboteur
	check(m.attack_targets(sab).size() == 3, "saboteur ignores sentinel (2 units + base)")


func test_overwhelm_raid_grit() -> void:
	print("overwhelm / raid / grit")
	var m := blank_match()
	var raider := add_unit(m, 0, "HMW_224")  # Tusken Raider 0/4 Raid 3
	check(raider.power(true) == 3 and raider.power() == 0, "raid applies only while attacking")
	var grit := add_unit(m, 0, "LOF_232")    # Sandtrooper Cavalry 2/6 grit
	grit.damage = 2
	check(grit.power() == 4, "grit adds damage to power")
	var ow := add_unit(m, 0, "SHD_172")      # Krayt Dragon 10/10 overwhelm
	var small := add_unit(m, 1, "SOR_095")
	var before: int = m.players[1].base_remaining()
	m.do_action({"a": "attack", "uid": ow.uid, "target": small.uid})
	check(m.players[1].base_remaining() == before - 7, "overwhelm sends 7 excess damage to base")


func test_alternating_and_initiative() -> void:
	print("turn flow")
	var m := blank_match()
	check(m.phase == "action" and m.active == 0, "p0 acts first")
	m.do_action({"a": "pass"})
	check(m.active == 1, "alternates after pass")
	m.do_action({"a": "claim", "token": "initiative"})
	check(m.initiative == 1 and m.active == 0, "claiming initiative passes turn")
	var r := m.round_num
	m.do_action({"a": "pass"})
	# p1 is out of the round, so p0 passing ends the phase (p1 auto-passes).
	while not m.pending.is_empty():
		m.submit_choice(m.pending["options"].slice(0, m.pending["min"]))
	check(m.round_num == r + 1 and m.phase == "action", "regroup -> next round")
	check(m.active == 1, "initiative holder acts first next round")
	check(m.players[0].hand.size() >= 2, "regroup draws")


func test_leader_deploy_and_defeat() -> void:
	print("leader deploy")
	var m := blank_match()
	var ps: PlayerState = m.players[0]
	while ps.resources.size() < 4:
		m.move_to_resources(0, ps.deck.pop_front())
	var has_deploy := false
	for a in m.legal_actions(0):
		if a["a"] == "deploy":
			has_deploy = true
	check(has_deploy, "C-3PO can deploy at 4 resources")
	m.do_action({"a": "deploy"})
	check(ps.leader.in_play() and ps.leader.power() == 1 and ps.leader.max_hp() == 6, "leader unit side stats 1/6")
	m.defeat(ps.leader)
	check(ps.leader.zone == "leader" and ps.leader.epic_used, "defeated leader returns, can't redeploy")


func test_effect_dsl() -> void:
	print("effect DSL")
	var m := blank_match()
	var enemy := add_unit(m, 1, "SOR_095")
	var e := {"op": "damage", "n": 2, "t": {"s": "choose", "kind": "unit", "side": "enemy"}}
	m.push_frame([e], {"ctl": 0, "src": m.players[0].base.uid})
	m.pump()
	check(m.pending.get("kind", "") == "target", "damage asks for a target")
	m.submit_choice([enemy.uid])
	check(enemy.damage == 2, "damage applied")
	m.push_frame([{"op": "experience", "n": 1, "t": {"s": "it"}}], {"ctl": 0, "it": enemy.uid})
	m.pump()
	check(enemy.power() == 4 and enemy.max_hp() == 4, "experience token +1/+1")
	var c3po: Dictionary = lib.get_card("SEC_015")
	check(c3po.get("implemented", "") == "full", "C-3PO leader compiled fully")


func test_campaign_content() -> void:
	print("campaign data")
	var f := FileAccess.get_file_as_string("res://data/campaign/ep4.json")
	var ep = JSON.parse_string(f)
	check(typeof(ep) == TYPE_DICTIONARY, "ep4.json parses")
	if typeof(ep) != TYPE_DICTIONARY:
		return
	for ch in ep.get("chapters", []):
		for id in ch.get("starting_deck", []) + ch.get("leader_options", []) + ch.get("base_sequence", []):
			check(lib.has(id), "%s: card %s exists" % [ch.get("id", "?"), id])
		# Heroism campaign: nothing the player can own may be Villainy (spec 3.7).
		for id in ch.get("starting_deck", []) + ch.get("reward_pool", []) + ch.get("leader_options", []):
			check(not ("villainy" in lib.get_card(id).get("aspects", [])), "%s: %s breaks the Heroism gate" % [ch["id"], id])
		for node in ch.get("nodes", []):
			for id in node.get("enemy", {}).get("deck", []):
				check(lib.has(id), "%s/%s: enemy card %s exists" % [ch["id"], node["id"], id])
			for id in [node.get("pickup", "")] + node.get("player_bonus_hand", []):
				if id != "":
					check(not ("villainy" in lib.get_card(id).get("aspects", [])), "%s/%s: pickup %s is Villainy" % [ch["id"], node["id"], id])
		simulate_chapter(ch)


## Bot plays both sides of every combat node; reports hero win rate and length.
func simulate_chapter(ch: Dictionary, games := 20) -> void:
	var run := CampaignRun.start(ch, ch["leader_options"][0], 99)
	for node in ch.get("nodes", []):
		if not (node.get("type", "") in ["fight", "elite", "objective", "boss"]):
			continue
		var wins := 0
		var rounds := 0
		var acts := 0
		var stuck := 0
		for g in games:
			run["node_seed"] = g * 101
			var cfg := CampaignRun.match_config(run, ch, node, {})
			cfg["players"][0]["ai"] = true
			var m := Match.new()
			m.setup(lib, cfg)
			var steps := 0
			while not m.is_over() and steps < 3000:
				steps += 1
				if not m.pending.is_empty():
					AiBot.choose(m)
				elif m.phase == "action":
					AiBot.act(m)
					acts += 1
				else:
					break
			if not m.is_over():
				stuck += 1
				continue
			if m.winner == 0:
				wins += 1
			rounds += m.round_num
		check(stuck == 0, "%s/%s: no stuck games" % [ch["id"], node["id"]])
		# ~1.5 s per action of animation + thinking is a rough proxy for real play time.
		print("  %-22s %-28s hero win %3d%%  avg rounds %.1f  ~%.1f min" % [ch["id"], node.get("title", ""), wins * 100 / games, rounds / float(games), acts / float(games) * 1.5 / 60.0])


## Standard must look like a traditional SWU game; Quick must be single-arena.
func test_formats() -> void:
	print("formats")
	var std := RuleSet.premier()
	check(std.deck_min == 50 and std.max_copies == 3 and std.base_hp_override == 0, "standard: 50 cards, 3 copies, printed base HP")
	check(std.arenas == ["ground", "space"] and std.aspect_penalties, "standard: both arenas + aspect penalties")
	check(std.starting_hand == 6 and std.starting_resources == 2 and std.regroup_draw == 2 and std.regroup_resource == 1, "standard: 6-card hand, 2 resources, regroup draw 2 / resource 1")
	var m := Match.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var deck := DeckBuilder.auto_deck(lib, "SEC_015", "HMW_019", 50, rng)
	check(deck.size() == 50 and DeckBuilder.validate(lib, std, "SEC_015", "HMW_019", deck).is_empty(), "standard auto-deck is legal")
	m.setup(lib, {"seed": 3, "rules": std, "players": [
		{"leader": "SEC_015", "base": "HMW_019", "deck": deck, "ai": true},
		{"leader": "SOR_017", "base": "HMW_028", "deck": deck.duplicate(), "ai": true}]})
	check(m.players[0].base.max_hp() == 30, "standard: Dune Sea keeps its printed 30 HP")
	check(m.players[0].hand.size() == 6, "standard: opening hand of 6 before resourcing")
	for arena in ["ground", "space"]:
		var q := RuleSet.quick(arena)
		check(q.arenas == [arena] and q.base_hp_override == 20 and q.deck_min == 30, "quick %s: one arena, 20 HP, 30 cards" % arena)
		var qd := DeckBuilder.auto_deck(lib, "SEC_015", "HMW_019", 30, rng, q.arenas)
		var ok := qd.size() == 30
		for id in qd:
			var c := lib.get_card(id)
			if c.get("type") == "unit" and c.get("arena") != arena:
				ok = false
			if not DeckBuilder.fits_arena(c, arena):
				ok = false
		check(ok, "quick %s: deck only uses %s-compatible cards" % [arena, arena])
		var qm := Match.new()
		qm.setup(lib, {"seed": 4, "rules": q, "players": [
			{"leader": "SEC_015", "base": "HMW_019", "deck": qd, "ai": true},
			{"leader": "JTL_012", "base": "HMW_028", "deck": qd.duplicate(), "ai": true}]})
		check(qm.players[0].base.max_hp() == 20, "quick %s: bases have 20 HP" % arena)
		check(qm.create_unit_token(0, "tie_fighter" if arena == "ground" else "battle_droid") == null, "quick %s: no off-arena tokens" % arena)


func simulate(n: int, arena := "") -> void:
	print("simulating %d bot-vs-bot games %s" % [n, "(quick " + arena + ")" if arena != "" else "(standard)"])
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var leaders := []
	var bases := []
	for id in lib.cards:
		var c: Dictionary = lib.cards[id]
		if c.get("custom", false):
			continue
		if c.get("type") == "leader":
			leaders.append(id)
		elif c.get("type") == "base":
			bases.append(id)
	var wins := [0, 0, 0]
	var rounds := 0
	var crashed := 0
	var t0 := Time.get_ticks_msec()
	var actions := 0
	for g in n:
		var m := Match.new()
		var rules := RuleSet.premier() if arena == "" else RuleSet.quick(arena)
		var cfg := {"seed": g, "rules": rules, "players": []}
		for p in 2:
			var l: String = leaders[rng.randi_range(0, leaders.size() - 1)]
			var b: String = bases[rng.randi_range(0, bases.size() - 1)]
			cfg["players"].append({"name": "Bot%d" % p, "leader": l, "base": b, "ai": true,
				"profile": ["aggressive", "tempo", "defensive"][rng.randi_range(0, 2)],
				"deck": DeckBuilder.auto_deck(lib, l, b, rules.deck_min, rng, rules.arenas)})
		m.setup(lib, cfg)
		var steps := 0
		while not m.is_over() and steps < 4000:
			steps += 1
			if not m.pending.is_empty():
				AiBot.choose(m)
			elif m.phase == "action":
				AiBot.act(m)
				actions += 1
			else:
				break
		if not m.is_over():
			crashed += 1
			if crashed <= 3:
				print("  stuck game seed=%d phase=%s round=%d pending=%s frames=%d" % [g, m.phase, m.round_num, m.pending.get("kind", ""), m.frames.size()])
		else:
			wins[m.winner] += 1
			rounds += m.round_num
	var ms := Time.get_ticks_msec() - t0
	print("  results: p0 %d / p1 %d / draw %d / stuck %d, avg rounds %.1f, %.2f ms per action" % [
		wins[0], wins[1], wins[2], crashed, rounds / maxf(1.0, n - crashed), ms / maxf(1.0, actions)])
	check(crashed == 0, "no simulated game got stuck (%s)" % (arena if arena != "" else "standard"))


# ---------------------------------------------------------------- option choices, One Lane, Spotlight pool

func test_choose_one() -> void:
	print("choose one / either-or")
	var m := blank_match()
	var ps: PlayerState = m.players[0]
	while ps.resources.size() < 4:
		m.move_to_resources(0, ps.deck.pop_front())
	var leia := m._new_inst("SOR_189", 0)   # When Played: Either ready a resource or exhaust a unit.
	leia.zone = "hand"
	ps.hand.append(leia)
	var enemy := add_unit(m, 1, "SOR_095")
	m.rules.aspect_penalties = false
	check(m.do_action({"a": "play", "uid": leia.uid}), "play Leia")
	check(m.pending.get("kind", "") == "option" and m.pending.get("labels", []).size() == 2, "player is offered both options")
	if m.pending.get("kind", "") == "option":
		m.submit_choice([1])
		check(m.pending.get("kind", "") == "target", "option 2 asks for a unit to exhaust")
		if m.pending.get("kind", "") == "target":
			m.submit_choice([enemy.uid])
			check(enemy.exhausted, "chosen option resolved (unit exhausted)")


func test_one_lane() -> void:
	print("one lane")
	var r := RuleSet.quick_mode("one_lane")
	check(r.single_lane and r.arenas == ["ground"] and r.base_hp_override == 20, "one lane ruleset")
	var m := blank_match(r)
	var ship := add_unit(m, 0, "SOR_237")           # Alliance X-Wing (space)
	check(ship.zone == "ground", "space unit enters the single lane")
	var trooper := add_unit(m, 1, "SOR_095")
	check(trooper.uid in m.attack_targets(ship), "ships and ground units fight each other in one lane")
	var tie_ok := m.create_unit_token(1, "tie_fighter")
	check(tie_ok != null and tie_ok.zone == "ground", "space tokens join the lane too")


func spotlight_pool() -> Array:
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/spotlight_decks.json"))
	return d.get("decks", []) if typeof(d) == TYPE_DICTIONARY else []


func spot_list(cards: Dictionary) -> Array:
	var out: Array = []
	for k in cards:
		for _i in int(cards[k]):
			out.append(k)
	return out


func test_spotlight() -> void:
	print("spotlight decks")
	var pool := spotlight_pool()
	check(pool.size() >= 10, "spotlight pool loaded (%d decks)" % pool.size())
	for d in pool:
		check(lib.has(d["leader"]) and lib.has(d["base"]), "%s: leader/base exist" % d["id"])
		var pilot: bool = "pilot" in lib.get_card(d["leader"]).get("traits", [])
		check(pilot == ("space" in d["modes"]) and (not pilot or d["modes"] == ["space"]), "%s: pilot leaders only in Space Only" % d["id"])
		var variants: Dictionary = d.get("variants", {})
		var lists := {"main": d["cards"]}
		lists.merge(variants)
		for k in lists:
			if lists[k].is_empty():
				continue
			var lst := spot_list(lists[k])
			var errs := DeckBuilder.validate(lib, RuleSet.premier(), d["leader"], d["base"], lst)
			check(errs.is_empty(), "%s/%s legal: %s" % [d["id"], k, errs])
			if k in ["ground", "space"]:
				var ok := true
				for id in lst:
					if not DeckBuilder.fits_arena(lib.get_card(id), k):
						ok = false
				check(ok, "%s/%s only uses %s cards" % [d["id"], k, k])


func simulate_quick_modes(n: int) -> void:
	var pool := spotlight_pool()
	for mode in ["one_lane", "traditional", "ground", "space"]:
		var decks: Array = []
		for d in pool:
			if mode in d["modes"]:
				var cards: Dictionary = d.get("variants", {}).get(mode, d["cards"]) if mode in ["ground", "space"] else d["cards"]
				if not cards.is_empty():
					decks.append([d["leader"], d["base"], spot_list(cards)])
		var rng := RandomNumberGenerator.new()
		rng.seed = 77
		var wins := [0, 0, 0]
		var stuck := 0
		var rounds := 0
		for g in n:
			var a: Array = decks[rng.randi_range(0, decks.size() - 1)]
			var b: Array = decks[rng.randi_range(0, decks.size() - 1)]
			var m := Match.new()
			m.setup(lib, {"seed": g, "rules": RuleSet.quick_mode(mode), "players": [
				{"leader": a[0], "base": a[1], "deck": a[2], "ai": true},
				{"leader": b[0], "base": b[1], "deck": b[2], "ai": true}]})
			var steps := 0
			while not m.is_over() and steps < 4000:
				steps += 1
				if not m.pending.is_empty():
					AiBot.choose(m)
				elif m.phase == "action":
					AiBot.act(m)
				else:
					break
			if m.is_over():
				wins[m.winner] += 1
				rounds += m.round_num
			else:
				stuck += 1
		print("  quick %-11s %d decks: p0 %d / p1 %d / draw %d / stuck %d, avg rounds %.1f" % [mode, decks.size(), wins[0], wins[1], wins[2], stuck, rounds / maxf(1.0, n - stuck)])
		check(stuck == 0, "quick %s: no stuck games" % mode)


func test_leader_actions_and_force() -> void:
	print("leader actions / force")
	var leaders := 0
	var with_action := 0
	for id in lib.cards:
		var c: Dictionary = lib.cards[id]
		if c.get("type") == "leader" and not c.get("custom", false):
			leaders += 1
			for ab in c.get("abilities", []):
				if ab.get("trigger") == "action":
					with_action += 1
					break
	print("  leaders with automated actions: %d / %d" % [with_action, leaders])
	check(with_action >= 70, "most common leader actions are automated")
	# play_from_hand: LOF_013 "Play an event from your hand. It costs 1 less."
	var m := blank_match()
	var ps: PlayerState = m.players[0]
	m.rules.aspect_penalties = false
	var ev := m._new_inst("SOR_172", 0)    # Open Fire, cost 3
	ev.zone = "hand"
	ps.hand.append(ev)
	add_unit(m, 1, "SOR_095")
	while ps.resources.size() < 2:
		m.move_to_resources(0, ps.deck.pop_front())
	m.push_frame([{"op": "play_from_hand", "kind": "event", "discount": 1}], {"ctl": 0, "src": ps.base.uid})
	m.pump()
	check(m.pending.get("kind", "") == "hand" and ev.uid in m.pending.get("options", []), "discounted event is playable for 2")
	if m.pending.get("kind", "") == "hand":
		m.submit_choice([ev.uid])
		check(ev.zone == "discard" and ps.ready_resources() == 0, "event played paying 2")
	# Force: Crystal Caves gives the Force when a friendly Force unit attacks; use_force spends it
	var m2 := Match.new()
	var deck: Array = []
	for i in 20:
		deck.append("SOR_095")
	m2.setup(lib, {"seed": 2, "first": 0, "players": [
		{"leader": "SEC_015", "base": "LOF_029", "deck": deck, "ai": false},
		{"leader": "SOR_017", "base": "HMW_028", "deck": deck.duplicate(), "ai": false}]})
	while not m2.pending.is_empty():
		m2.submit_choice([0] if m2.pending["kind"] == "mulligan" else m2.pending["options"].slice(0, m2.pending["min"]))
	var jedi := add_unit(m2, 0, "HMW_261")   # Ben Kenobi (Force)
	m2.do_action({"a": "attack", "uid": jedi.uid, "target": m2.players[1].base.uid})
	while not m2.pending.is_empty():
		m2.submit_choice(m2.pending["options"].slice(0, maxi(1, m2.pending["min"])))
	check(m2.players[0].force_token, "Force base grants the Force token on a Force unit attack")
	m2.push_frame([{"op": "use_force"}, {"op": "draw", "n": 1, "if_did": true}], {"ctl": 0, "src": jedi.uid})
	var hand_before: int = m2.players[0].hand.size()
	m2.pump()
	check(not m2.players[0].force_token and m2.players[0].hand.size() == hand_before + 1, "use the Force spends the token and 'if you do' resolves")


## Bot plays complete Spotlight Campaign runs (all node types) until the base falls.
func test_spotlight_runs(runs := 4) -> void:
	print("spotlight campaign runs")
	var spots: Array = []
	for d in spotlight_pool():
		if "traditional" in d["modes"] and not d["cards"].is_empty():
			spots.append({"id": d["id"], "name": d["name"], "leader": d["leader"], "base": d["base"], "cards": d["cards"]})
	check(spots.size() >= 8, "spotlight decks available for the campaign")
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	var best := 0
	for ri in runs:
		var spot: Dictionary = spots[ri % spots.size()]
		var run := SpotlightRun.start(spot, lib, 1000 + ri, spots)
		check(SpotlightRun.deck_size(run) == 20, "run starts with 20 cards")
		var locked0 := 0
		for k in run["locked"]:
			locked0 += int(run["locked"][k])
		check(locked0 == 30, "the other 30 Spotlight cards start locked")
		var guard := 0
		var record := {}
		while run["status"] == "active" and guard < 60:
			guard += 1
			var avail := SpotlightRun.available_nodes(run)
			check(not avail.is_empty(), "a next node is always available")
			if avail.is_empty():
				break
			var nid: String = avail[rng.randi_range(0, avail.size() - 1)]
			var n := SpotlightRun.node(run, nid)
			match n["type"]:
				"fight", "elite", "objective", "boss":
					var cfg := SpotlightRun.match_config(run, n)
					cfg["players"][0]["ai"] = true
					var m := Match.new()
					m.setup(lib, cfg)
					var steps := 0
					while not m.is_over() and steps < 4000:
						steps += 1
						if not m.pending.is_empty():
							AiBot.choose(m)
						elif m.phase == "action":
							AiBot.act(m)
						else:
							break
					check(m.is_over(), "%s battle finished" % n["type"])
					SpotlightRun.on_battle_end(run, nid, m.winner == 0, m.players[0].base.damage, lib)
					var rw: Dictionary = run.get("pending_reward", {})
					if run["status"] == "active":
						for c in rw.get("cards", []).slice(0, int(rw.get("picks", 1))):
							SpotlightRun.gain_card(run, c)
						if not rw.get("perks", []).is_empty():
							SpotlightRun.add_perk(run, rw["perks"][0])
						run["pending_reward"] = {}
						if rw.get("boss", false):
							SpotlightRun.next_sector(run, lib, spots)
				_:
					if n["type"] == "shop":
						for c in SpotlightRun.shop_stock(run, lib, nid):
							if int(run["credits"]) >= SpotlightRun.price(lib, c):
								run["credits"] -= SpotlightRun.price(lib, c)
								SpotlightRun.gain_card(run, c)
					elif n["type"] == "treasure":
						var ps := SpotlightRun.random_perks(run, 2, rng)
						if not ps.is_empty():
							SpotlightRun.add_perk(run, ps[0])
					elif n["type"] == "rest":
						SpotlightRun.upgrade_card(run, run["deck"].keys()[0], "experience")
					elif n["type"] == "event":
						SpotlightRun.apply_effect(run, {"credits": 10, "card_loot": 1}, lib, rng)
					run["current"] = nid
					run["visited"].append(nid)
					run["stats"]["nodes"] += 1
		record = SpotlightRun.record({}, run)
		best = maxi(best, int(run["sector"]))
		print("  run %d %-14s sector %d, %d wins, %d bosses, deck %d, %d perks, status %s" % [ri, spot["id"], int(run["sector"]), int(run["stats"]["wins"]), int(run["stats"]["bosses"]), SpotlightRun.deck_size(run), run["perks"].size(), run["status"]])
		check(run["status"] == "dead" or guard >= 60, "run ends in death (or keeps going)")
		check(int(record["runs"]) == 1 and record["history"].size() == 1, "record saved")
	check(best >= 1, "runs progress")
