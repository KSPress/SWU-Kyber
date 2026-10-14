extends Node
## Local, offline, versioned save (spec 2: "Save data: local only, offline-first").

const PATH := "user://kyber_save.json"
const VERSION := 1

var data: Dictionary = {}


func _ready() -> void:
	load_save()
	for k in data.get("settings", {}):
		Kyber.settings[k] = data["settings"][k]
	Kyber.apply_orientation()


func default_data() -> Dictionary:
	return {
		"version": VERSION,
		"settings": {},
		"vault": [],                 # card ids unlocked for vault / bot / PvP play
		"decks": [],                 # deckbuilder decks (see save_deck)
		"spotlight_runs": {},        # Spotlight Campaign: deck id -> active run
		"spotlight_records": {},     # Spotlight Campaign: deck id -> record (runs, bests, history)
		"campaign": {
			"cleared": [],           # chapter ids
			"run": {},               # active chapter run (see CampaignRun)
		},
		"stats": {"matches": 0, "wins": 0},
	}


func load_save() -> void:
	data = default_data()
	if not FileAccess.file_exists(PATH):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Save: unreadable save, starting fresh")
		return
	data = _migrate(parsed)


func _migrate(d: Dictionary) -> Dictionary:
	var base := default_data()
	for k in base:
		if not d.has(k):
			d[k] = base[k]
	d["version"] = VERSION
	return d


func write() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))


func save_settings(s: Dictionary) -> void:
	data["settings"] = s.duplicate()
	write()


func unlock(ids: Array) -> Array:
	var new: Array = []
	for id in ids:
		if not (id in data["vault"]):
			data["vault"].append(id)
			new.append(id)
	write()
	return new


func run() -> Dictionary:
	return data["campaign"].get("run", {})


func set_run(r: Dictionary) -> void:
	data["campaign"]["run"] = r
	write()


func clear_chapter(ch: String) -> void:
	if not (ch in data["campaign"]["cleared"]):
		data["campaign"]["cleared"].append(ch)
	write()


func is_cleared(ch: String) -> bool:
	return ch in data["campaign"]["cleared"]


# ---------------------------------------------------------------- decks
## deck = {id, name, icon, marked, leader, base, cards: {card_id: count}, updated}

func decks() -> Array:
	return data.get("decks", [])


func get_deck(id: String) -> Dictionary:
	for d in decks():
		if d.get("id", "") == id:
			return d
	return {}


func save_deck(d: Dictionary) -> void:
	if d.get("id", "") == "":
		d["id"] = "deck_%d_%d" % [Time.get_unix_time_from_system(), randi() % 10000]
	d["updated"] = Time.get_unix_time_from_system()
	var list: Array = data.get("decks", [])
	for i in list.size():
		if list[i].get("id", "") == d["id"]:
			list[i] = d
			data["decks"] = list
			write()
			return
	list.append(d)
	data["decks"] = list
	write()


func delete_deck(id: String) -> void:
	var list: Array = data.get("decks", [])
	for i in range(list.size() - 1, -1, -1):
		if list[i].get("id", "") == id:
			list.remove_at(i)
	data["decks"] = list
	write()


static func deck_size(d: Dictionary) -> int:
	var n := 0
	for k in d.get("cards", {}):
		n += int(d["cards"][k])
	return n


static func deck_list(d: Dictionary) -> Array:
	var out: Array = []
	for k in d.get("cards", {}):
		for _i in int(d["cards"][k]):
			out.append(k)
	return out
