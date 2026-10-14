class_name PlayerState
extends RefCounted

var index := 0
var display_name := "Player"
var is_ai := false
var ai_profile := "tempo"
var leader: CardInst
var base: CardInst
var deck: Array = []
var hand: Array = []
var discard: Array = []
var resources: Array = []
var units: Array = []          # CardInst in ground/space
var out_of_round := false      # claimed initiative / a claimable token this round
var turn_done := false         # BURST turn mode
var force_token := false
var credits := 0
var base_hp_bonus := 0
var first_unit_experience := 0  # campaign treasure
var first_unit_shield := 0
var card_upgrades: Dictionary = {}  # Spotlight run: card id -> ["experience"|"shield"] on every copy
var hero_skin := ""


## Ready resources plus Credit tokens (each Credit can be defeated to pay 1).
func available() -> int:
	return ready_resources() + credits


func ready_resources() -> int:
	var n := 0
	for r in resources:
		if not r.exhausted:
			n += 1
	return n


func units_in(arena: String) -> Array:
	var out: Array = []
	for u in units:
		if u.zone == arena:
			out.append(u)
	return out


## Aspect icons available for cost purposes: leader + base (a multiset).
func aspect_pool() -> Array:
	var out: Array = []
	if leader:
		out.append_array(leader.aspects())
	if base:
		out.append_array(base.aspects())
	return out


func base_max_hp() -> int:
	return base.max_hp() if base else 0


func base_remaining() -> int:
	return base.remaining_hp() if base else 0
