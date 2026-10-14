class_name Objective
extends RefCounted
## Node objectives (spec 5.5) as plug-ins. Player 0 is always the human/hero side.
## Subclasses override the hooks they need; check() returns the winner index or -1.

var type := "standard"
var params: Dictionary = {}


static func create(cfg: Dictionary) -> Objective:
	var o: Objective
	match cfg.get("type", "standard"):
		"survive_n":
			o = SurviveRounds.new()
		"defend_unit":
			o = DefendUnit.new()
		"hunt":
			o = Hunt.new()
		"attrition":
			o = Attrition.new()
		_:
			o = Objective.new()
	o.type = cfg.get("type", "standard")
	o.params = cfg.get("params", {})
	return o


func setup(_m: Match) -> void:
	pass


func on_action_start(_m: Match) -> void:
	pass


func on_round_end(_m: Match) -> void:
	pass


func on_protected_lost(_m: Match, _u: CardInst) -> void:
	pass


func check(_m: Match) -> int:
	return -1


func describe() -> String:
	return "Destroy the enemy base."


func tracker(_m: Match) -> String:
	return "Destroy the enemy base"


func reward_multiplier() -> float:
	return float(params.get("reward_mult", 1.0))


class SurviveRounds extends Objective:
	func on_round_end(m: Match) -> void:
		if m.round_num >= int(params.get("rounds", 4)) and m.players[0].base_remaining() > 0:
			m.set_winner(0, "survived")

	func describe() -> String:
		return "Survive %d rounds." % int(params.get("rounds", 4))

	func tracker(m: Match) -> String:
		return "Survive: round %d / %d" % [m.round_num, int(params.get("rounds", 4))]


class DefendUnit extends Objective:
	var lost := false

	func setup(m: Match) -> void:
		var id: String = params.get("protect_unit", "")
		if id == "":
			return
		var u := m._new_inst(id, 0)
		m._put_in_play(u, u.arena(), true)
		u.flags["protected"] = true
		u.flags["cannot_attack"] = true
		u.exhausted = true
		if params.has("protect_hp"):
			u.mods.append({"h": int(params["protect_hp"]) - u.printed_hp(), "dur": "permanent"})

	func on_protected_lost(_m: Match, _u: CardInst) -> void:
		lost = true

	func on_action_start(m: Match) -> void:
		# The protected unit stays unconscious (exhausted) — it can't help.
		for u in m.players[0].units:
			if u.flags.get("protected", false):
				u.exhausted = true

	func on_round_end(m: Match) -> void:
		if not lost and m.round_num >= int(params.get("rounds", 3)):
			m.set_winner(0, "protected unit survived")

	func check(_m: Match) -> int:
		return 1 if lost else -1

	func describe() -> String:
		return "Keep the protected unit alive for %d rounds." % int(params.get("rounds", 3))

	func tracker(m: Match) -> String:
		return "Protect: round %d / %d" % [m.round_num, int(params.get("rounds", 3))]


class Hunt extends Objective:
	var killed := false

	func check(m: Match) -> int:
		var id: String = params.get("target", "")
		for c in m.players[1].discard:
			if c.id == id:
				return 0
		return -1

	func describe() -> String:
		return "Hunt down %s when it appears." % params.get("target_name", "the target")

	func tracker(_m: Match) -> String:
		return "Hunt: %s" % params.get("target_name", "target")


class Attrition extends Objective:
	## Each regroup the enemy base takes 1 damage per `per` cards left in their deck.
	func on_round_end(m: Match) -> void:
		var per := int(params.get("per", 4))
		var n := int(ceil(m.players[1].deck.size() / float(per)))
		if n > 0:
			m.deal_damage(m.players[1].base, n, null)

	func describe() -> String:
		return "Attrition: the enemy base burns every round based on their remaining deck."

	func tracker(m: Match) -> String:
		return "Attrition: %d cards in enemy deck" % m.players[1].deck.size()
