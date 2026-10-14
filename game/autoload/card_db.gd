extends Node
## Holds the shared CardLibrary plus campaign content.

const CARDS_PATH := "res://ip/data/cards.json"
const CUSTOM_PATH := "res://data/custom_cards.json"

var lib := CardLibrary.new()
var episodes: Dictionary = {}   # episode number -> parsed json
var spotlight: Array = []       # Quick Play deck pool (data/spotlight_decks.json)
var loaded := false


func _ready() -> void:
	var n := lib.load_file(CARDS_PATH)
	lib.load_file(CUSTOM_PATH, true)
	loaded = n > 0
	if not loaded:
		push_warning("No card database found. Run: python -I tools/import_cards.py")
	var sp := "res://data/spotlight_decks.json"
	if FileAccess.file_exists(sp):
		var sd = JSON.parse_string(FileAccess.get_file_as_string(sp))
		if typeof(sd) == TYPE_DICTIONARY:
			spotlight = sd.get("decks", [])
	for ep in range(1, 10):
		var path := "res://data/campaign/ep%d.json" % ep
		if FileAccess.file_exists(path):
			var d = JSON.parse_string(FileAccess.get_file_as_string(path))
			if typeof(d) == TYPE_DICTIONARY:
				episodes[ep] = d


func card(id: String) -> Dictionary:
	return lib.get_card(id)


func chapter(chapter_id: String) -> Dictionary:
	for ep in episodes.values():
		for ch in ep.get("chapters", []):
			if ch.get("id", "") == chapter_id:
				return ch
	return {}


func node_def(chapter_id: String, node_id: String) -> Dictionary:
	for n in chapter(chapter_id).get("nodes", []):
		if n.get("id", "") == node_id:
			return n
	return {}


## Quick Play decks usable in a mode, as plain deck dicts {id, name, leader, base, cards, icon}.
func spotlight_for_mode(mode: String) -> Array:
	var out: Array = []
	for d in spotlight:
		if not (mode in d.get("modes", [])):
			continue
		var cards: Dictionary = d.get("cards", {})
		if mode in ["ground", "space"] and d.get("variants", {}).has(mode):
			cards = d["variants"][mode]
		if cards.is_empty() or not (lib.has(d["leader"]) and lib.has(d["base"])):
			continue
		var set_label: String = str(d["name"]).split(" — ")[0] if str(d["name"]).find(" — ") >= 0 else str(d.get("set", ""))
		out.append({"id": d["id"], "name": lib.get_card(d["leader"]).get("name", d["name"]), "set_label": set_label, "full_name": d["name"],
			"leader": d["leader"], "base": d["base"],
			"cards": cards, "icon": "space" if mode == "space" else "star", "spotlight": true,
			"provisional": d.get("provisional", true)})
	return out
