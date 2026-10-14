class_name DeckBuilder
extends RefCounted
## Deck validation (spec 3.7) and quick auto-built decks for bot matches / sims.


## Returns a list of human-readable problems (empty = legal).
static func validate(lib: CardLibrary, rules: RuleSet, leader: String, base: String, deck: Array) -> Array:
	var errs: Array = []
	if deck.size() < rules.deck_min:
		errs.append("Deck has %d cards; minimum is %d." % [deck.size(), rules.deck_min])
	var counts := {}
	for id in deck:
		counts[id] = counts.get(id, 0) + 1
		var c := lib.get_card(id)
		if c.is_empty():
			errs.append("Unknown card %s." % id)
			continue
		if c.get("type", "") in ["leader", "base"] or str(c.get("type", "")).begins_with("token"):
			errs.append("%s cannot be in a deck." % c.get("name", id))
	for id in counts:
		if counts[id] > rules.max_copies:
			errs.append("%s: %d copies (max %d)." % [lib.get_card(id).get("name", id), counts[id], rules.max_copies])
	if rules.hero_villain_gate:
		var la: Array = lib.get_card(leader).get("aspects", [])
		var side := "heroism" if "heroism" in la else ("villainy" if "villainy" in la else "")
		var other := "villainy" if side == "heroism" else "heroism"
		if side != "":
			for id in counts:
				if other in lib.get_card(id).get("aspects", []):
					errs.append("%s is %s; this campaign is %s." % [lib.get_card(id).get("name", id), other, side])
	if not lib.has(leader):
		errs.append("Missing leader.")
	if not lib.has(base):
		errs.append("Missing base.")
	return errs


## Single-arena formats: drop events/upgrades that only matter in the other arena
## (e.g. "deal 2 damage to a space unit" or TIE Fighter tokens in a ground game).
static func fits_arena(c: Dictionary, arena: String) -> bool:
	var other := "space" if arena == "ground" else "ground"
	if c.get("type", "") == "unit":
		return c.get("arena", "ground") == arena
	var txt: String = c.get("text", "").to_lower()
	if txt.find(other) >= 0 and txt.find(arena) < 0:
		return false
	var other_tokens := ["tie fighter token", "x-wing token"] if arena == "ground" else ["battle droid token", "clone trooper token", "spy token"]
	for t in other_tokens:
		if txt.find(t) >= 0:
			return false
	if arena == "ground" and (txt.find("vehicle") >= 0 and txt.find("attach to a vehicle") >= 0):
		return false
	return true


## Builds a playable deck around a leader+base from fully implemented cards.
static func auto_deck(lib: CardLibrary, leader: String, base: String, size: int, rng: RandomNumberGenerator, arenas := ["ground", "space"], max_cost := 7) -> Array:
	var pool_aspects: Array = lib.get_card(leader).get("aspects", []) + lib.get_card(base).get("aspects", [])
	var hero := "heroism" in pool_aspects
	var vill := "villainy" in pool_aspects
	var cands: Array = []
	for id in lib.cards:
		var c: Dictionary = lib.cards[id]
		if c.get("custom", false) or not (c.get("type", "") in ["unit", "event", "upgrade"]):
			continue
		if c.get("implemented", "") != "full":
			continue
		if c.get("type") == "unit" and not (c.get("arena", "ground") in arenas):
			continue
		if arenas.size() == 1 and not fits_arena(c, arenas[0]):
			continue
		var ok := true
		for a in c.get("aspects", []):
			if not (a in pool_aspects):
				ok = false
			if (a == "heroism" and vill) or (a == "villainy" and hero):
				ok = false
		if ok and int(c.get("cost", 0)) <= max_cost:
			cands.append(id)
	var deck: Array = []
	if cands.is_empty():
		return deck
	# Weighted toward a low curve with mostly units.
	var guard := 0
	while deck.size() < size and guard < 10000:
		guard += 1
		var id: String = cands[rng.randi_range(0, cands.size() - 1)]
		var c: Dictionary = lib.cards[id]
		var cost := int(c.get("cost", 0))
		if c.get("type") != "unit" and rng.randf() < 0.55:
			continue
		if cost >= 5 and rng.randf() < 0.5:
			continue
		if deck.count(id) >= 3:
			continue
		deck.append(id)
	return deck
