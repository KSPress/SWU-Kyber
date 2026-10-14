class_name CampaignFlow
extends RefCounted
## Glue between campaign screens, the save file and the match screen.


static func episode_data(ep: int) -> Dictionary:
	return CardDB.episodes.get(ep, {})


static func treasures_for(chapter: Dictionary) -> Dictionary:
	return episode_data(int(chapter.get("episode", 4))).get("treasures", {})


static func chapter_unlocked(chapter: Dictionary) -> bool:
	if int(chapter.get("number", 1)) == 1:
		return true
	var ep := episode_data(int(chapter.get("episode", 4)))
	for ch in ep.get("chapters", []):
		if int(ch.get("number", 0)) == int(chapter.get("number", 1)) - 1:
			return Save.is_cleared(ch["id"])
	return false


static func start_run(chapter: Dictionary, leader: String) -> void:
	var run := CampaignRun.start(chapter, leader, randi())
	Save.set_run(run)


static func start_node(chapter: Dictionary, node: Dictionary) -> void:
	var run := Save.run()
	var cfg := CampaignRun.match_config(run, chapter, node, treasures_for(chapter))
	var theme: String = node.get("board_theme", chapter.get("board_theme", "space"))
	Router.go("match", {
		"mode": "campaign", "cfg": cfg, "theme": theme, "title": node.get("title", "Battle"),
		"chapter_id": chapter["id"], "node_id": node["id"],
	})


## Called once when a campaign match ends. Mutates and saves the run.
static func on_match_end(params: Dictionary, m: Match) -> Dictionary:
	var chapter := CardDB.chapter(params["chapter_id"])
	var node := CampaignRun.node_by_id(chapter, params["node_id"])
	var run := Save.run()
	var won := m.winner == 0
	var res := {"won": won, "chapter_id": chapter["id"], "node_id": node["id"], "boss": node.get("type", "") == "boss"}
	run["fights"] = int(run.get("fights", 0)) + 1
	if won:
		var maxhp := CampaignRun.max_base_hp(run, chapter)
		run["base_damage"] = clampi(m.players[0].base.damage, 0, maxhp - 1)
		CampaignRun.complete_node(run, node["id"])
		if node.has("pickup"):
			run["deck"].append(node["pickup"])
			res["pickup"] = node["pickup"]
		if res["boss"]:
			run["status"] = "won"
			Save.clear_chapter(chapter["id"])
			res["unlocked"] = Save.unlock(chapter.get("unlocks_on_clear", []) + run["deck"])
		else:
			res["rewards"] = CampaignRun.roll_rewards(run, chapter, node, CardDB.lib)
			if int(node.get("reward_tier", 1)) >= 3:
				res["treasures"] = CampaignRun.roll_treasures(run, chapter)
	else:
		run["status"] = "lost"
	Save.set_run(run)
	return res


static func after_match(res: Dictionary) -> void:
	if res.get("won", false):
		Router.go("reward", res)
	else:
		Router.go("chapter", {"chapter_id": res["chapter_id"], "failed": true})
