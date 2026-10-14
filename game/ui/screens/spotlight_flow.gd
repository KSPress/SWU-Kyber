class_name SpotlightFlow
extends RefCounted
## Glue between the Spotlight Campaign screens, Save and the match screen.


static func spots() -> Array:
	return CardDB.spotlight_for_mode("traditional")


static func spot(deck_id: String) -> Dictionary:
	for d in spots():
		if d["id"] == deck_id:
			return d
	return {}


static func run(deck_id: String) -> Dictionary:
	return Save.data.get("spotlight_runs", {}).get(deck_id, {})


static func save_run(r: Dictionary) -> void:
	Save.data["spotlight_runs"][r["deck_id"]] = r
	Save.write()


static func record(deck_id: String) -> Dictionary:
	return Save.data.get("spotlight_records", {}).get(deck_id, {})


static func start(deck_id: String) -> Dictionary:
	var r := SpotlightRun.start(spot(deck_id), CardDB.lib, randi(), spots())
	save_run(r)
	return r


## Ends a run (death or abandon): folds it into the deck's record and clears it.
static func finish(r: Dictionary) -> void:
	var rec := SpotlightRun.record(record(r["deck_id"]), r)
	Save.data["spotlight_records"][r["deck_id"]] = rec
	Save.data["spotlight_runs"].erase(r["deck_id"])
	Save.unlock(r["owned"].keys())
	Save.write()


static func start_node(r: Dictionary, node_id: String) -> void:
	var n := SpotlightRun.node(r, node_id)
	var cfg := SpotlightRun.match_config(r, n)
	Router.go("match", {"mode": "spotlight", "cfg": cfg, "theme": "auto", "title": n.get("title", "Battle"),
		"deck_id": r["deck_id"], "node_id": node_id})


static func on_match_end(params: Dictionary, m: Match) -> Dictionary:
	var r := run(params["deck_id"])
	var res := SpotlightRun.on_battle_end(r, params["node_id"], m.winner == 0, m.players[0].base.damage, CardDB.lib)
	if r["status"] == "dead":
		res["summary"] = SpotlightRun.summary(r)
		finish(r)
	else:
		save_run(r)
	res["deck_id"] = params["deck_id"]
	return res


static func after_match(res: Dictionary) -> void:
	Router.go("spotlight_run", {"deck_id": res["deck_id"], "result": res})
