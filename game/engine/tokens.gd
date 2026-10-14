class_name Tokens
extends RefCounted
## Claimable tokens (spec 3.9 / 7.4). Claiming one is an action that ends your
## actions for the round; each token can be claimed once per round.
## Campaign nodes reference these by id, or define their own inline.

const INITIATIVE := {
	"id": "initiative", "name": "Initiative", "icon": "initiative", "side_claimable": "both",
	"desc": "Take the initiative: you act first next round. You pass for the rest of this round.",
	"effects": [],
}

const BLAST := {
	"id": "blast", "name": "Blast", "icon": "blast", "side_claimable": "both",
	"desc": "Deal 1 damage to each other base. Ends your actions this round.",
	"effects": [{"op": "base_damage", "n": 1}],
}

const PLAN := {
	"id": "plan", "name": "Plan", "icon": "plan", "side_claimable": "both",
	"desc": "Draw a card, then put a card from your hand on the bottom of your deck. Ends your actions this round.",
	"effects": [{"op": "draw", "n": 1}, {"op": "_bottom_from_hand"}],
}

const KRAYT_CALL := {
	"id": "krayt_call", "name": "Krayt Call", "icon": "krayt", "side_claimable": "player",
	"desc": "Obi-Wan's krayt dragon call: defeat an enemy non-leader Tusken unit. Ends your actions this round.",
	"effects": [{"op": "defeat", "t": {"s": "choose", "kind": "unit", "side": "enemy", "nonleader": true, "trait": "tusken"}}],
}

const ALARM := {
	"id": "alarm", "name": "Alarm", "icon": "alarm", "side_claimable": "enemy",
	"desc": "Imperial alarm: the enemy calls a Death Star Stormtrooper into play. Ends their actions this round.",
	"effects": [{"op": "summon", "id": "SOR_128", "n": 1}],
}

const ALL := {"initiative": INITIATIVE, "blast": BLAST, "plan": PLAN, "krayt_call": KRAYT_CALL, "alarm": ALARM}


static func resolve(list: Array) -> Array:
	var out: Array = []
	for t in list:
		if typeof(t) == TYPE_DICTIONARY:
			out.append(t)
		elif ALL.has(t):
			out.append(ALL[t])
	if out.is_empty():
		out.append(INITIATIVE)
	return out
