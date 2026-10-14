class_name SpotlightRun
extends RefCounted
## Spotlight Campaign: an endless roguelike run built around one Expansion
## Spotlight deck. The player starts with its leader, base and a portion of the
## list; the rest of the deck is earned along the way. Sectors of randomized
## battles, missions, elites, events, shops, rests and treasure end in a boss;
## each sector is harder than the last. The run ends when the base is destroyed.
## Pure functions over a plain Dictionary (serialised in Save).
##
## run = {deck_id, name, leader, base, seed, status ("active"|"dead"),
##        owned {id:n}, deck {id:n}, locked {id:n}, upgrades {id:[kind]}, perks [id],
##        credits, base_max, base_damage, sector, map {rows, nodes, edges}, current, visited,
##        stats {wins, elites, bosses, missions, cards, nodes, started}, pending_reward {}}

static var _cfg: Dictionary = {}


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		var p := "res://data/spotlight_campaign.json"
		if FileAccess.file_exists(p):
			var d = JSON.parse_string(FileAccess.get_file_as_string(p))
			if typeof(d) == TYPE_DICTIONARY:
				_cfg = d
	return _cfg


# ---------------------------------------------------------------- start

## spot = Spotlight deck dict {id, name, leader, base, cards{id:n}}
static func start(spot: Dictionary, lib: CardLibrary, seed_value: int, spots: Array) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var st: Dictionary = cfg().get("start", {})
	# the starting portion favours a playable low curve: sort copies by cost + noise
	var copies: Array = []
	for id in spot["cards"]:
		for i in int(spot["cards"][id]):
			copies.append([float(lib.get_card(id).get("cost", 0)) + rng.randf() * 2.5 + i * 0.8, id])
	copies.sort_custom(func(a, b): return a[0] < b[0])
	var deck := {}
	var locked := {}
	var n := int(st.get("cards", 20))
	for i in copies.size():
		var id: String = copies[i][1]
		if i < n:
			deck[id] = int(deck.get(id, 0)) + 1
		else:
			locked[id] = int(locked.get(id, 0)) + 1
	var run := {
		"deck_id": spot["id"], "name": spot.get("name", ""), "leader": spot["leader"], "base": spot["base"],
		"seed": seed_value, "status": "active",
		"owned": deck.duplicate(), "deck": deck, "locked": locked, "upgrades": {}, "perks": [],
		"credits": int(st.get("credits", 20)), "base_max": int(st.get("base_hp", 20)), "base_damage": 0,
		"sector": 0, "map": {}, "current": "", "visited": [],
		"stats": {"wins": 0, "elites": 0, "bosses": 0, "missions": 0, "cards": 0, "nodes": 0,
			"started": Time.get_unix_time_from_system()},
		"pending_reward": {},
	}
	next_sector(run, lib, spots)
	return run


static func rng_for(run: Dictionary, salt: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = int(run["seed"]) * 7919 + int(run.get("sector", 0)) * 104729 + salt * 31 + run.get("visited", []).size()
	return r


# ---------------------------------------------------------------- map

static func next_sector(run: Dictionary, lib: CardLibrary, spots: Array) -> void:
	run["sector"] = int(run.get("sector", 0)) + 1
	run["current"] = ""
	run["visited"] = []
	var rng := rng_for(run, 1)
	var rows_cfg: Array = cfg().get("rows", [])
	var rows: Array = []
	var nodes := {}
	for ri in rows_cfg.size():
		var weights: Dictionary = rows_cfg[ri]
		var count := 1 if weights.has("boss") else rng.randi_range(2, 3)
		var row: Array = []
		var used := {}
		for ci in count:
			var t := _weighted(weights, rng)
			# avoid a row of identical non-fight nodes
			if used.has(t) and t != "fight" and weights.size() > 1:
				t = _weighted(weights, rng)
			used[t] = true
			var id := "r%d_%d" % [ri, ci]
			nodes[id] = _make_node(run, lib, t, ri, rng, spots)
			nodes[id]["id"] = id
			row.append(id)
		rows.append(row)
	# connect each node to 1-2 nodes in the next row (Slay-the-Spire style)
	var edges := {}
	for ri in rows.size() - 1:
		var a: Array = rows[ri]
		var b: Array = rows[ri + 1]
		for i in a.size():
			var targets: Array = []
			var pos := float(i) / maxf(1.0, a.size() - 1) * (b.size() - 1) if a.size() > 1 else (b.size() - 1) / 2.0
			targets.append(b[clampi(roundi(pos), 0, b.size() - 1)])
			if rng.randf() < 0.55:
				var alt := clampi(roundi(pos) + (1 if rng.randf() < 0.5 else -1), 0, b.size() - 1)
				if not (b[alt] in targets):
					targets.append(b[alt])
			edges[a[i]] = targets
		for j in b.size():
			var reached := false
			for k in edges:
				if b[j] in edges[k]:
					reached = true
			if not reached:
				edges[a[mini(j, a.size() - 1)]].append(b[j])
	run["map"] = {"rows": rows, "nodes": nodes, "edges": edges}


static func _weighted(w: Dictionary, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for k in w:
		total += float(w[k])
	var r := rng.randf() * total
	for k in w:
		r -= float(w[k])
		if r <= 0.0:
			return k
	return w.keys()[0]


static func available_nodes(run: Dictionary) -> Array:
	var map: Dictionary = run.get("map", {})
	if run.get("current", "") == "":
		return map.get("rows", [[]])[0]
	return map.get("edges", {}).get(run["current"], [])


static func node(run: Dictionary, id: String) -> Dictionary:
	return run.get("map", {}).get("nodes", {}).get(id, {})


# ---------------------------------------------------------------- enemies & missions

static func _leaders(lib: CardLibrary, exclude: String) -> Array:
	var out: Array = []
	for id in lib.cards:
		var c: Dictionary = lib.cards[id]
		if c.get("type") == "leader" and not c.get("custom", false) and id != exclude \
				and not ("pilot" in c.get("traits", [])) and int(c.get("leader_unit", {}).get("hp", 0)) > 0:
			out.append(id)
	out.sort()
	return out


static func _bases(lib: CardLibrary) -> Array:
	var out: Array = []
	for id in lib.cards:
		var c: Dictionary = lib.cards[id]
		if c.get("type") == "base" and not c.get("custom", false):
			out.append(id)
	out.sort()
	return out


static func _make_node(run: Dictionary, lib: CardLibrary, t: String, row: int, rng: RandomNumberGenerator, spots: Array) -> Dictionary:
	var sector := int(run["sector"])
	var titles: Array = cfg().get("node_titles", {}).get(t, [t.capitalize()])
	var n := {"type": t, "title": titles[rng.randi_range(0, titles.size() - 1)], "row": row}
	if not (t in ["fight", "elite", "objective", "boss"]):
		if t == "event":
			var evs: Array = cfg().get("events", [])
			var ev: Dictionary = evs[rng.randi_range(0, evs.size() - 1)]
			n["event"] = ev["id"]
			n["title"] = ev["title"]
		return n
	var leaders := _leaders(lib, run["leader"])
	var bases := _bases(lib)
	var enemy := {}
	if t == "boss":
		# another Spotlight deck at full strength
		var pool: Array = []
		for d in spots:
			if d["id"] != run["deck_id"]:
				pool.append(d)
		var sd: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
		var lst: Array = []
		for cid in sd["cards"]:
			for i in int(sd["cards"][cid]):
				lst.append(cid)
		enemy = {"leader": sd["leader"], "base": sd["base"], "deck": lst, "name": lib.get_card(sd["leader"]).get("name", "Boss")}
		n["title"] = "Boss: " + lib.get_card(sd["leader"]).get("name", "")
	else:
		var l: String = leaders[rng.randi_range(0, leaders.size() - 1)]
		var b: String = bases[rng.randi_range(0, bases.size() - 1)]
		var size := mini(50, 18 + 5 * (sector - 1) + row)
		# early sectors field cheaper, scrappier decks; the curve opens up as you go deeper
		var max_cost := mini(7, 2 + sector)
		enemy = {"leader": l, "base": b, "deck": DeckBuilder.auto_deck(lib, l, b, size, rng, ["ground", "space"], max_cost), "name": lib.get_card(l).get("name", "Enemy")}
		if t == "elite":
			n["title"] = "%s: %s" % [n["title"], enemy["name"]]
	var hp: int = {"fight": 6 + 3 * sector + row / 2, "objective": 8 + 3 * sector, "elite": 8 + 3 * sector, "boss": 14 + 5 * sector}[t]
	enemy["hp"] = hp
	enemy["extra_resources"] = {"fight": 0, "objective": 0, "elite": mini(sector - 1, 2), "boss": mini(sector - 1, 3)}[t]
	enemy["profile"] = ["aggressive", "tempo", "defensive"][rng.randi_range(0, 2)] if t != "boss" else "tempo"
	# elites and bosses start with their strongest unit on the board
	var pre: Array = []
	if t == "elite" and sector == 1:
		enemy["hp"] = int(enemy["hp"]) + 3
	if t == "boss" or (t == "elite" and sector >= 2):
		var best := ""
		var best_cost := -1
		for id in enemy["deck"]:
			var c := lib.get_card(id)
			if c.get("type") == "unit" and int(c.get("cost", 0)) > best_cost and int(c.get("cost", 0)) <= 2 + sector:
				best = id
				best_cost = int(c.get("cost", 0))
		if best != "":
			enemy["deck"].erase(best)
			pre.append({"id": best, "arena": lib.get_card(best).get("arena", "ground"), "ready": false})
	var obj := {"type": "standard"}
	if t == "objective":
		var kind: String = ["survive_n", "hunt", "attrition"][rng.randi_range(0, 2)]
		if kind == "survive_n":
			obj = {"type": "survive_n", "params": {"rounds": mini(3 + sector, 6)}}
			n["title"] = "Mission: Hold the Line"
			enemy["hp"] = 30
		elif kind == "hunt":
			var tgt := ""
			for id in enemy["deck"]:
				if lib.get_card(id).get("type") == "unit" and int(lib.get_card(id).get("cost", 0)) >= 3:
					tgt = id
					break
			if tgt == "":
				obj = {"type": "standard"}
			else:
				enemy["deck"].erase(tgt)
				pre.append({"id": tgt, "arena": lib.get_card(tgt).get("arena", "ground"), "ready": false})
				obj = {"type": "hunt", "params": {"target": tgt, "target_name": lib.get_card(tgt).get("name", "")}}
				n["title"] = "Mission: Hunt " + lib.get_card(tgt).get("name", "")
		else:
			obj = {"type": "attrition", "params": {"per": 4}}
			n["title"] = "Mission: Supply Raid"
	enemy["preplaced"] = pre
	n["enemy"] = enemy
	n["objective"] = obj
	return n


# ---------------------------------------------------------------- perks

static func perk_effects(run: Dictionary) -> Dictionary:
	var out := {"extra_resources": 0, "first_unit_experience": 0, "first_unit_shield": 0, "extra_hand": 0,
		"tokens": [], "heal_after_win": 0, "credit_mult": 0.0, "start_force": 0}
	var perks: Dictionary = cfg().get("perks", {})
	for p in run.get("perks", []):
		var e: Dictionary = perks.get(p, {}).get("effect", {})
		for k in e:
			if k == "add_token":
				out["tokens"].append(e[k])
			elif k != "max_hp" and out.has(k):
				out[k] += e[k]
	return out


static func random_perks(run: Dictionary, n: int, rng: RandomNumberGenerator) -> Array:
	var all: Array = cfg().get("perks", {}).keys()
	var free: Array = all.filter(func(p): return not (p in run.get("perks", [])))
	var out: Array = []
	while out.size() < n and not free.is_empty():
		var p: String = free[rng.randi_range(0, free.size() - 1)]
		free.erase(p)
		out.append(p)
	return out


static func add_perk(run: Dictionary, p: String) -> void:
	if p in run["perks"]:
		return
	run["perks"].append(p)
	var e: Dictionary = cfg().get("perks", {}).get(p, {}).get("effect", {})
	if e.has("max_hp"):
		run["base_max"] = int(run["base_max"]) + int(e["max_hp"])


# ---------------------------------------------------------------- battles

static func deck_list(run: Dictionary) -> Array:
	var out: Array = []
	for id in run["deck"]:
		for i in int(run["deck"][id]):
			out.append(id)
	return out


static func match_config(run: Dictionary, n: Dictionary) -> Dictionary:
	var rules := RuleSet.premier()
	rules.deck_min = int(cfg().get("start", {}).get("deck_min", 20))
	var pe := perk_effects(run)
	var tokens: Array = ["initiative"]
	for t in pe["tokens"]:
		if not (t in tokens):
			tokens.append(t)
	var en: Dictionary = n["enemy"]
	return {
		"seed": int(run["seed"]) + int(run["stats"]["nodes"]) * 977, "rules": rules, "tokens": tokens,
		"objective": n.get("objective", {"type": "standard"}),
		"players": [
			{"name": "You", "leader": run["leader"], "base": run["base"], "deck": deck_list(run), "ai": false,
				"base_hp": int(run["base_max"]), "base_damage": int(run["base_damage"]),
				"extra_resources": pe["extra_resources"], "first_unit_experience": pe["first_unit_experience"],
				"first_unit_shield": pe["first_unit_shield"], "extra_hand": pe["extra_hand"],
				"start_force": pe["start_force"], "card_upgrades": run.get("upgrades", {})},
			{"name": en.get("name", "Enemy"), "leader": en["leader"], "base": en["base"], "deck": en["deck"], "ai": true,
				"profile": en.get("profile", "tempo"), "base_hp": int(en["hp"]), "preplaced": en.get("preplaced", []),
				"extra_resources": int(en.get("extra_resources", 0))},
		],
	}


## Called when a battle ends. Returns the result; mutates run.
static func on_battle_end(run: Dictionary, node_id: String, won: bool, base_damage: int, lib: CardLibrary) -> Dictionary:
	var n := node(run, node_id)
	var res := {"won": won, "node": node_id, "type": n.get("type", "")}
	run["stats"]["nodes"] = int(run["stats"]["nodes"]) + 1
	if not won:
		run["status"] = "dead"
		run["base_damage"] = int(run["base_max"])
		return res
	var pe := perk_effects(run)
	# field repairs after every win (+ Bacta Tanks perk)
	run["base_damage"] = clampi(base_damage - 3 - int(pe["heal_after_win"]), 0, int(run["base_max"]) - 1)
	run["current"] = node_id
	run["visited"].append(node_id)
	run["stats"]["wins"] = int(run["stats"]["wins"]) + 1
	var t: String = n.get("type", "fight")
	if t == "elite":
		run["stats"]["elites"] = int(run["stats"]["elites"]) + 1
	if t == "boss":
		run["stats"]["bosses"] = int(run["stats"]["bosses"]) + 1
	if t == "objective":
		run["stats"]["missions"] = int(run["stats"]["missions"]) + 1
	var rng := rng_for(run, 7)
	var sector := int(run["sector"])
	var credits: int = {"fight": 12, "objective": 20, "elite": 25, "boss": 50}.get(t, 10) + 3 * sector + rng.randi_range(0, 6)
	credits = int(credits * (1.0 + float(pe["credit_mult"])))
	run["credits"] = int(run["credits"]) + credits
	var reward := {"credits": credits, "cards": roll_cards(run, lib, 3, t in ["elite", "boss"], rng)}
	if t in ["elite", "boss"] or (t == "objective" and rng.randf() < 0.5):
		reward["perks"] = random_perks(run, 2 if t != "boss" else 3, rng)
	if t == "boss":
		reward["boss"] = true
		reward["picks"] = 2
		run["base_damage"] = maxi(0, int(run["base_damage"]) - 8)
	run["pending_reward"] = reward
	res["reward"] = reward
	return res


## Card offers: mostly the Spotlight cards not yet earned, plus loot in the deck's aspects.
static func roll_cards(run: Dictionary, lib: CardLibrary, n: int, rare: bool, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var locked: Array = []
	for id in run["locked"]:
		if int(run["locked"][id]) > 0:
			locked.append(id)
	locked.sort()
	var from_locked := mini(locked.size(), n - 1 if n > 1 else n)
	while out.size() < from_locked:
		var id: String = locked[rng.randi_range(0, locked.size() - 1)]
		locked.erase(id)
		out.append(id)
	var loot := loot_pool(run, lib, rare)
	var guard := 0
	while out.size() < n and not loot.is_empty() and guard < 50:
		guard += 1
		var l: String = loot[rng.randi_range(0, loot.size() - 1)]
		if not (l in out):
			out.append(l)
	return out


static func loot_pool(run: Dictionary, lib: CardLibrary, rare: bool) -> Array:
	var asp: Array = lib.get_card(run["leader"]).get("aspects", []) + lib.get_card(run["base"]).get("aspects", [])
	var out: Array = []
	for id in lib.cards:
		var c: Dictionary = lib.cards[id]
		if c.get("custom", false) or not (c.get("type", "") in ["unit", "event", "upgrade"]):
			continue
		if c.get("implemented", "") == "manual":
			continue
		if c.get("type") == "unit" and not (c.get("arena") in ["ground", "space"]):
			continue
		var ok := true
		for a in c.get("aspects", []):
			if not (a in asp):
				ok = false
		if not ok:
			continue
		if rare and not (c.get("rarity", "") in ["Rare", "Legendary"]):
			continue
		out.append(id)
	out.sort()
	return out


## Adds a card to the run: from the locked Spotlight list if it's there.
static func gain_card(run: Dictionary, id: String) -> void:
	if int(run["locked"].get(id, 0)) > 0:
		run["locked"][id] = int(run["locked"][id]) - 1
		if int(run["locked"][id]) <= 0:
			run["locked"].erase(id)
	run["owned"][id] = int(run["owned"].get(id, 0)) + 1
	if int(run["deck"].get(id, 0)) < 3:
		run["deck"][id] = int(run["deck"].get(id, 0)) + 1
	run["stats"]["cards"] = int(run["stats"]["cards"]) + 1


static func remove_card(run: Dictionary, id: String) -> void:
	for k in ["owned", "deck"]:
		if int(run[k].get(id, 0)) > 0:
			run[k][id] = int(run[k][id]) - 1
			if int(run[k][id]) <= 0:
				run[k].erase(id)


static func upgrade_card(run: Dictionary, id: String, kind: String) -> void:
	var u: Array = run["upgrades"].get(id, [])
	u.append(kind)
	run["upgrades"][id] = u


static func deck_size(run: Dictionary) -> int:
	var n := 0
	for id in run["deck"]:
		n += int(run["deck"][id])
	return n


## Applies an event/shop effect dict. Returns a short summary.
static func apply_effect(run: Dictionary, e: Dictionary, lib: CardLibrary, rng: RandomNumberGenerator) -> String:
	var msg: Array = []
	if e.has("credits"):
		run["credits"] = maxi(0, int(run["credits"]) + int(e["credits"]))
		msg.append("%+d credits" % int(e["credits"]))
	if e.has("damage"):
		run["base_damage"] = mini(int(run["base_max"]) - 1, int(run["base_damage"]) + int(e["damage"]))
		msg.append("%d base damage" % int(e["damage"]))
	if e.has("heal"):
		run["base_damage"] = maxi(0, int(run["base_damage"]) - int(e["heal"]))
		msg.append("healed %d" % int(e["heal"]))
	if e.has("max_hp"):
		run["base_max"] = maxi(8, int(run["base_max"]) + int(e["max_hp"]))
		run["base_damage"] = mini(int(run["base_damage"]), int(run["base_max"]) - 1)
		msg.append("%+d max base HP" % int(e["max_hp"]))
	if e.has("card_locked"):
		var cards := roll_cards(run, lib, 1, false, rng)
		for c in cards:
			gain_card(run, c)
			msg.append("gained " + lib.get_card(c).get("name", c))
	if e.has("card_loot"):
		var loot := loot_pool(run, lib, false)
		if not loot.is_empty():
			var c2: String = loot[rng.randi_range(0, loot.size() - 1)]
			gain_card(run, c2)
			msg.append("gained " + lib.get_card(c2).get("name", c2))
	if e.get("perk", "") == "random":
		var ps := random_perks(run, 1, rng)
		if not ps.is_empty():
			add_perk(run, ps[0])
			msg.append("perk: " + cfg().get("perks", {}).get(ps[0], {}).get("name", ps[0]))
	return ", ".join(msg)


static func can_afford(run: Dictionary, e: Dictionary) -> bool:
	return int(run["credits"]) + int(e.get("credits", 0)) >= 0 or int(e.get("credits", 0)) >= 0


static func price(lib: CardLibrary, id: String) -> int:
	var p: Dictionary = cfg().get("prices", {})
	var c := lib.get_card(id)
	var v := int(p.get("card_base", 18)) + int(p.get("card_per_cost", 5)) * int(c.get("cost", 0))
	if c.get("rarity", "") in ["Rare", "Legendary"]:
		v += int(p.get("card_rare", 12))
	return v


static func shop_stock(run: Dictionary, lib: CardLibrary, node_id: String) -> Array:
	var rng := rng_for(run, hash(node_id))
	return roll_cards(run, lib, 4, false, rng)


# ---------------------------------------------------------------- records

static func summary(run: Dictionary) -> Dictionary:
	return {
		"sector": int(run.get("sector", 1)), "nodes": int(run["stats"]["nodes"]), "wins": int(run["stats"]["wins"]),
		"bosses": int(run["stats"]["bosses"]), "elites": int(run["stats"]["elites"]), "missions": int(run["stats"]["missions"]),
		"cards": int(run["stats"]["cards"]), "deck": deck_size(run), "perks": run.get("perks", []).duplicate(),
		"ended": Time.get_unix_time_from_system(), "status": run.get("status", ""),
	}


## Merge a finished (or abandoned) run into that Spotlight deck's record.
static func record(rec: Dictionary, run: Dictionary) -> Dictionary:
	var s := summary(run)
	rec["runs"] = int(rec.get("runs", 0)) + 1
	rec["best_sector"] = maxi(int(rec.get("best_sector", 0)), s["sector"])
	rec["best_wins"] = maxi(int(rec.get("best_wins", 0)), s["wins"])
	rec["bosses"] = int(rec.get("bosses", 0)) + s["bosses"]
	rec["total_wins"] = int(rec.get("total_wins", 0)) + s["wins"]
	var hist: Array = rec.get("history", [])
	hist.push_front(s)
	rec["history"] = hist.slice(0, 10)
	return rec
