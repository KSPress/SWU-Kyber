class_name RuleSet
extends RefCounted
## Every rules knob that a format / campaign node may change (spec 3.7, 5.3, 5.6).

enum TurnMode { ALTERNATING, BURST }

var name := "premier"
var aspect_penalties := true        # +2 cost per missing aspect icon (off in campaign)
var hero_villain_gate := false      # campaign: Heroism/Villainy split is the only hard gate
var deck_min := 50
var max_copies := 3
var base_hp_override := 0           # 0 = printed HP
var starting_hand := 6
var starting_resources := 2
var allow_mulligan := true
var regroup_draw := 2
var regroup_resource := 1
var deck_out_damage := 3            # damage to own base per card that can't be drawn
var turn_mode := TurnMode.ALTERNATING
var arenas: Array = ["ground", "space"]
var single_lane := false            # One Lane: space units fight in the ground lane


static func premier() -> RuleSet:
	return RuleSet.new()


## Quick format: one arena only, 20-HP bases, 30-card decks built from cards
## that work in that arena. Designed for portrait / one-handed play.
static func quick(arena: String) -> RuleSet:
	var r := RuleSet.new()
	r.name = "quick_" + arena
	r.deck_min = 30
	r.base_hp_override = 20
	r.arenas = [arena]
	return r


## Quick play modes (Settings): one_lane | traditional | ground | space.
## All use 20-HP bases; One Lane folds both arenas into a single battlefield.
static func quick_mode(mode: String) -> RuleSet:
	match mode:
		"ground", "space":
			var r := quick(mode)
			r.deck_min = 50
			return r
		"one_lane":
			var r := quick("ground")
			r.name = "quick_one_lane"
			r.single_lane = true
			r.deck_min = 50
			return r
	var t := RuleSet.premier()
	t.name = "quick_traditional"
	t.base_hp_override = 20
	return t


static func campaign() -> RuleSet:
	var r := RuleSet.new()
	r.name = "campaign"
	r.aspect_penalties = false
	r.hero_villain_gate = true
	r.deck_min = 15
	r.base_hp_override = 18
	r.starting_hand = 5
	r.deck_out_damage = 2
	return r


static func from_dict(d: Dictionary) -> RuleSet:
	var r := campaign() if d.get("ruleset", "") == "campaign" else premier()
	for k in ["aspect_penalties", "hero_villain_gate", "deck_min", "max_copies", "base_hp_override",
			"starting_hand", "starting_resources", "allow_mulligan", "regroup_draw", "regroup_resource",
			"deck_out_damage", "arenas"]:
		if d.has(k):
			r.set(k, d[k])
	if d.get("turn_mode", "alternating") == "burst":
		r.turn_mode = TurnMode.BURST
	return r
