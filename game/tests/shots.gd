extends Node
## Visual smoke test: walks the real UI through each screen in portrait and
## landscape, saving screenshots. Not headless (needs a renderer):
##   godot --path game res://tests/shots.tscn -- <out_dir> [only]

var out := "user://shots"
var only := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	if args.size() > 1:
		only = args[1]
	DirAccess.make_dir_recursive_absolute(out)
	print("shots -> ", out)
	# Survive scene changes: hand "current scene" to a dummy and live under root.
	if get_tree().current_scene == self:
		var dummy := Node.new()
		get_tree().root.add_child.call_deferred(dummy)
		await get_tree().process_frame
		get_tree().current_scene = dummy
		reparent.call_deferred(get_tree().root)
		await get_tree().process_frame
	Kyber.settings["anim_speed"] = 2.0
	await _run()
	get_tree().quit()


func _size(w: int, h: int) -> void:
	DisplayServer.window_set_size(Vector2i(w, h))
	await _wait(0.6)


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out.path_join(name + ".png"))
	print("shot ", name)


func _go(screen: String, p := {}) -> void:
	Router.go(screen, p)
	await _wait(1.6)


func _want(n: String) -> bool:
	return only == "" or only == n


func _run() -> void:
	await _size(540, 960)
	if _want("menu"):
		await _go("menu")
		await _shot("01_menu_portrait")
		await _size(1280, 720)
		await _wait(0.5)
		await _shot("02_menu_landscape")
		await _size(540, 960)
	if _want("collection"):
		await _go("collection")
		await _wait(1.0)
		await _shot("03_collection_portrait")
		var cs := get_tree().current_scene
		var first: CardView = _find_card(cs)
		if first:
			InspectOverlay.open(cs, first.card_id, first.get_global_rect())
			await _wait(1.0)
			await _shot("04_inspect_portrait")
	if _want("episodes"):
		await _go("episodes")
		await _shot("05_episodes_portrait")
	if _want("chapter"):
		Save.data["campaign"]["run"] = {}
		await _go("chapter", {"chapter_id": "ep4_ch1_tatooine"})
		await _shot("06_chapter_start_portrait")
		CampaignFlow.start_run(CardDB.chapter("ep4_ch1_tatooine"), "SEC_015")
		await _go("chapter", {"chapter_id": "ep4_ch1_tatooine"})
		await _shot("07_chapter_map_portrait")
		await _size(1280, 720)
		await _wait(0.6)
		await _shot("08_chapter_map_landscape")
		await _size(540, 960)
	if only == "quickspace":
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		await _go("match", {"mode": "quick", "format": 2, "theme": "space", "title": "Quick Battle · Space",
			"cfg": QuickMatch.make_config("JTL_012", "KYB_001" if false else "HMW_019", 2, "tempo", rng)})
		await _play_some(6, "19_quick_space_portrait", "20_quick_space_landscape", false)
	if _want("match"):
		await _go("match")
		await _play_some(6, "10_match_portrait", "11_match_landscape", true)
	if _want("campaign_match"):
		var ch := CardDB.chapter("ep4_ch1_tatooine")
		CampaignFlow.start_run(ch, "SEC_015")
		CampaignFlow.start_node(ch, CampaignRun.node_by_id(ch, "n3"))
		await _wait(2.0)
		await _play_some(3, "15_defend_portrait", "16_defend_landscape", false)
	if only == "input":
		await _input_test()
	if only == "anims":
		await _anims()
	if only == "new":
		await _new_screens()
	if only == "tokens":
		await _tokens_shots()
	if only == "backdrop":
		await _backdrop_shots()
	if only == "spotlight":
		await _spotlight_shots()
	if only == "e2e":
		await _spotlight_e2e()
	if only == "comb":
		await _comb()
	if only == "soak":
		await _soak(6)
	if _want("quick"):
		await _go("quick")
		await _shot("13_quick_portrait")
	if _want("settings"):
		await _go("settings")
		await _shot("14_settings_portrait")


func _find_card(n: Node) -> CardView:
	for c in n.find_children("*", "", true, false):
		if c is CardView:
			return c
	return null


## Auto-plays the human side for `n` actions, then captures both orientations.
func _play_some(n: int, shot_p: String, shot_l: String, inspect: bool) -> void:
	await _wait(2.0)
	var ms := get_tree().current_scene
	var acted := 0
	for i in 80:
		var m: Match = ms.m
		if m.is_over() or acted >= n:
			break
		if not m.pending.is_empty() and m.pending["player"] == 0:
			for c in get_tree().root.find_children("*", "", true, false):
				if c is ChoicePanel:
					c.get_parent().queue_free()
			ms._choice_open = false
			ms.prompt_bar.visible = false
			AiBot.choose(m)
			ms._step()
		elif m.can_act(0) and not ms.busy:
			AiBot.act(m)
			acted += 1
			ms._step()
		await _wait(0.7)
	await _wait(1.5)
	await _shot(shot_p)
	await _size(1280, 720)
	await _wait(1.0)
	await _shot(shot_l)
	if inspect:
		var tok: UnitToken = null
		for t in ms.tokens.values():
			tok = t
		if tok:
			InspectOverlay.open(ms, tok.inst.id, tok.get_global_rect(), tok.inst)
			await _wait(1.0)
			await _shot("12_inspect_token_landscape")
	await _size(540, 960)


# ---------------------------------------------------------------- input test

func _to_screen(p: Vector2) -> Vector2:
	return get_viewport().get_screen_transform() * p


func _mouse(btn_down: bool, at: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = btn_down
	e.position = _to_screen(at)
	e.global_position = e.position
	Input.parse_input_event(e)
	await get_tree().process_frame


func _drag(from: Vector2, to: Vector2) -> void:
	await _mouse(true, from)
	for i in 12:
		var e := InputEventMouseMotion.new()
		var p := from.lerp(to, (i + 1) / 12.0)
		e.position = _to_screen(p)
		e.global_position = e.position
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(e)
		await get_tree().process_frame
	await _mouse(false, to)


## Drives a quick match with real mouse events: drag a card up to play it,
## then drag a ready unit onto the enemy base.
func _input_test() -> void:
	await _go("match")
	await _wait(2.0)
	var ms := get_tree().current_scene
	var m: Match = ms.m
	# resolve setup choices for the human
	for i in 30:
		if m.can_act(0):
			break
		if not m.pending.is_empty() and m.pending["player"] == 0:
			for c in get_tree().root.find_children("*", "", true, false):
				if c is ChoicePanel:
					c.get_parent().queue_free()
			ms._choice_open = false
			AiBot.choose(m)
			ms._step()
		await _wait(0.6)
	await _wait(1.0)
	var played := false
	for uid in ms.hand.order:
		var cv: CardView = ms.hand.cards[uid]
		if cv.playable:
			var hand_before: int = m.players[0].hand.size()
			var start := cv.get_global_rect().get_center()
			var vs := get_viewport().get_visible_rect().size
			await _drag(start, Vector2(vs.x / 2.0, vs.y * 0.45))
			await _wait(1.5)
			played = m.players[0].hand.size() < hand_before
			print("INPUT drag-to-play: ", "PASS" if played else "FAIL")
			break
	if not played:
		print("INPUT drag-to-play: SKIPPED (nothing playable)")
	await _shot("17_after_drag_play")
	# play on until a unit of ours can attack, then drag it at the enemy base
	for i in 60:
		if m.is_over():
			break
		var attacker: UnitToken = null
		if m.can_act(0) and not ms.busy:
			for uid in ms.tokens:
				var tk: UnitToken = ms.tokens[uid]
				if tk.inst.controller == 0 and m.players[1].base.uid in m.attack_targets(tk.inst):
					attacker = tk
					break
			if attacker:
				var hp_before: int = m.players[1].base_remaining()
				await _drag(attacker.center_global(), ms.hud[1].base_view.get_global_rect().get_center())
				await _wait(2.5)
				var ok: bool = m.players[1].base_remaining() < hp_before or attacker.inst.exhausted
				print("INPUT drag-to-attack: ", "PASS" if ok else "FAIL")
				await _shot("18_after_drag_attack")
				return
			AiBot.act(m)
			ms._step()
		elif not m.pending.is_empty() and m.pending["player"] == 0:
			for c in get_tree().root.find_children("*", "", true, false):
				if c is ChoicePanel:
					c.get_parent().queue_free()
			ms._choice_open = false
			ms.prompt_bar.visible = false
			AiBot.choose(m)
			ms._step()
		await _wait(0.7)
	print("INPUT drag-to-attack: SKIPPED")


## Plays whole matches through the real UI (bot on both sides), rotating the
## window every few actions, to shake out crashes.
func _soak(games: int) -> void:
	Kyber.settings["anim_speed"] = 2.5
	for g in games:
		await _go("match")
		await _wait(1.5)
		var ms := get_tree().current_scene
		var m: Match = ms.m
		var steps := 0
		while not m.is_over() and steps < 600:
			steps += 1
			if steps % 15 == 0:
				if (steps / 15) % 2 == 1:
					await _size(1280, 720)
				else:
					await _size(540, 960)
			if not m.pending.is_empty() and m.pending["player"] == 0 and not ms.busy:
				for c in get_tree().root.find_children("*", "", true, false):
					if c is ChoicePanel:
						c.get_parent().queue_free()
				ms._choice_open = false
				ms.prompt_bar.visible = false
				AiBot.choose(m)
				ms._step()
			elif m.can_act(0) and not ms.busy:
				AiBot.act(m)
				ms._step()
			await _wait(0.25)
		print("SOAK game %d done: over=%s round=%d steps=%d" % [g, m.is_over(), m.round_num, steps])
		await _wait(1.5)


# ---------------------------------------------------------------- comb: every panel, both orientations

const SIZES := [[540, 960, "p"], [1280, 720, "l"], [480, 1040, "tall"]]


func _both(prefix: String, setup: Callable) -> void:
	for sz in SIZES:
		await _size(sz[0], sz[1])
		await setup.call()
		await _wait(0.9)
		await _shot("c_%s_%s" % [prefix, sz[2]])
		_close_layers()
	await _size(540, 960)


func _close_layers() -> void:
	for c in get_tree().root.find_children("*", "CanvasLayer", true, false):
		if c.get_parent() != get_tree().root and not (c.get_parent() is Window and c.get_parent() == get_tree().root):
			if c.name != "" and c.get_parent().name != "Router":
				c.queue_free()


func _comb() -> void:
	var ch := CardDB.chapter("ep4_ch1_tatooine")
	CampaignFlow.start_run(ch, "SEC_015")
	for nid in ["n1", "n2", "n3", "rest"]:
		await _both("node_" + nid, func():
			await _go("chapter", {"chapter_id": ch["id"]})
			var cm := get_tree().current_scene
			var n := CampaignRun.node_by_id(ch, nid)
			cm._nodes[nid].state = "available"
			cm._open_node(n)
			await _wait(0.6))
	await _both("deck", func():
		await _go("chapter", {"chapter_id": ch["id"]})
		get_tree().current_scene._show_deck(Save.run()["deck"]))
	await _both("reward", func():
		await _go("reward", {"won": true, "chapter_id": ch["id"], "node_id": "n4", "rewards": ["SOR_205", "HMW_268", "LOF_249"], "treasures": ["kyber_shard", "jawa_salvage"]})
		await _wait(1.0))
	await _both("clear", func():
		await _go("reward", {"won": true, "boss": true, "chapter_id": ch["id"], "node_id": "boss", "unlocked": ["SEC_015", "HMW_261", "HMW_170", "IBH_046"]}))
	await _both("episodes", func(): await _go("episodes"))
	await _both("chapter_start", func():
		Save.data["campaign"]["run"] = {}
		await _go("chapter", {"chapter_id": "ep4_ch2_deathstar"}))
	CampaignFlow.start_run(ch, "SEC_015")
	await _both("quick", func(): await _go("quick", {"format": 1}))
	await _both("settings", func(): await _go("settings"))
	await _both("collection", func(): await _go("collection"))
	await _both("menu", func(): await _go("menu"))
	# match panels
	await _both("mulligan", func():
		await _go("match")
		await _wait(2.5))
	await _both("leader_menu", func():
		await _go("match")
		await _wait(2.0)
		var ms := get_tree().current_scene
		_resolve_setup(ms)
		await _wait(2.0)
		ms._popup_menu(ms.hud[0].leader_view.get_global_rect(), [["Deploy test (Epic Action)", {"a": "pass"}], ["Action [C=1, Exhaust]: If you control an exhausted unit, exhaust a unit.", {"a": "pass"}], ["Inspect leader", {"inspect": ms.m.players[0].leader.uid}]])
		await _wait(0.5))
	await _both("gameover", func():
		await _go("match")
		await _wait(2.0)
		var ms := get_tree().current_scene
		_resolve_setup(ms)
		await _wait(1.0)
		ms.m.set_winner(0, "test")
		ms._step()
		await _wait(1.0))


func _resolve_setup(ms) -> void:
	var m: Match = ms.m
	for i in 6:
		if not m.pending.is_empty() and m.pending["player"] == 0:
			for c in get_tree().root.find_children("*", "", true, false):
				if c is ChoicePanel:
					c.get_parent().queue_free()
			ms._choice_open = false
			AiBot.choose(m)
	ms._step()


# ---------------------------------------------------------------- attack animation frames

## [attacker id (ours), defender id (theirs), label]
const ANIM_CASES := [
	["HMW_261", "SOR_128", "saber_ben"],
	["SOR_095", "SOR_128", "blaster_hero_red"],
	["IBH_103", "SOR_095", "heavy_villain_green"],
	["SOR_164", "SOR_095", "melee_wampa"],
	["SOR_237", "SOR_225", "ship_xwing"],
]


func _anims() -> void:
	Kyber.settings["anim_speed"] = 1.0
	await _size(540, 960)
	for case in ANIM_CASES:
		await _go("match")
		await _wait(2.0)
		var ms := get_tree().current_scene
		var m: Match = ms.m
		_resolve_setup(ms)
		await _wait(2.5)
		for i in 20:
			if m.can_act(0) and not ms.busy:
				break
			if not m.pending.is_empty():
				_resolve_setup(ms)
			elif m.phase == "action" and m.active == 1 and not ms.busy:
				AiBot.act(m)
				ms._step()
			await _wait(0.5)
		# clear the board, then stage the duel
		for u in m.all_units():
			m.players[u.controller].units.erase(u)
			u.zone = "removed"
		var a := m._new_inst(case[0], 0)
		m._put_in_play(a, a.arena(), false)
		var d := m._new_inst(case[1], 1)
		m._put_in_play(d, d.arena(), false)
		m.take_events()
		ms._sync()
		await _wait(0.8)
		if not m.can_act(0) or not (d.uid in m.attack_targets(a)):
			print("ANIM %s: could not stage (can_act=%s)" % [case[2], m.can_act(0)])
			continue
		print("ANIM %s style=%s" % [case[2], AttackStyle.of(a)["style"]])
		ms._act({"a": "attack", "uid": a.uid, "target": d.uid})
		for f in [0.18, 0.42, 0.62, 0.9]:
			await get_tree().create_timer(f - (0.0 if f == 0.18 else 0.0)).timeout
			await _shot("anim_%s_%02d" % [case[2], int(f * 100)])
		await _wait(1.5)


# ---------------------------------------------------------------- new screens

func _new_screens() -> void:
	# a saved deck to show
	var sd: Dictionary = CardDB.spotlight_for_mode("traditional")[0]
	Save.data["decks"] = []
	Save.save_deck({"id": "", "name": "Maul Aggro", "icon": "saber" if false else "fight", "marked": true,
		"leader": sd["leader"], "base": sd["base"], "cards": sd["cards"].duplicate()})
	Save.save_deck({"id": "", "name": "Rebel Swarm", "icon": "ground", "marked": false,
		"leader": "SEC_015", "base": "HMW_019", "cards": {"SOR_095": 3, "SOR_239": 2}})
	var did: String = Save.decks()[0]["id"]
	await _both("n_menu", func(): await _go("menu"))
	await _both("n_decks", func(): await _go("decks"))
	await _both("n_editor", func():
		await _go("deck_editor", {"deck_id": did})
		await _wait(1.0))
	await _both("n_picker", func():
		await _go("deck_editor", {"deck_id": did})
		await _wait(0.6)
		var ed := get_tree().current_scene
		ed._pick("leader")
		await _wait(1.4))
	await _both("n_picker_filtered", func():
		await _go("deck_editor", {"deck_id": did})
		await _wait(0.6)
		var ed := get_tree().current_scene
		ed._pick("leader")
		await _wait(1.2)
		for c in get_tree().root.find_children("*", "", true, false):
			if c is CardPicker:
				c._sel_aspects = ["aggression", "villainy"]
				c._populate(c._origin)
		await _wait(1.2))
	await _both("n_standard", func(): await _go("quick", {"format": 0}))
	await _both("n_quick", func(): await _go("quick", {"format": 1}))
	await _both("n_match_traditional", func():
		await _go("quick", {"format": 0})
		await _wait(0.5)
		get_tree().current_scene._start()
		await _wait(2.5)
		var ms := get_tree().current_scene
		_resolve_setup(ms)
		await _wait(1.0)
		var m: Match = ms.m
		for u in [["SOR_095", 0], ["SOR_237", 0], ["SOR_128", 1], ["SOR_225", 1]]:
			var x := m._new_inst(u[0], u[1])
			m._put_in_play(x, x.arena(), false)
		m.take_events()
		ms._sync()
		await _wait(1.0))


func _tokens_shots() -> void:
	Kyber.settings["anim_speed"] = 1.0
	for sz in [[540, 960, "p"], [1280, 720, "l"]]:
		await _size(sz[0], sz[1])
		await _go("match")
		await _wait(2.5)
		var ms := get_tree().current_scene
		var m: Match = ms.m
		for i in 30:
			if m.can_act(0) and not ms.busy:
				break
			if not m.pending.is_empty():
				_resolve_setup(ms)
			elif m.phase == "action" and m.active == 1 and not ms.busy:
				AiBot.act(m)
				ms._step()
			await _wait(0.4)
		await _wait(0.8)
		await _shot("t_board_%s" % sz[2])
		ms._on_leader_pressed(ms.hud[0])
		await _wait(0.7)
		await _shot("t_leader_menu_%s" % sz[2])
		if ms.menu_popup:
			ms.menu_popup.queue_free()
			ms.menu_popup = null
		# Force token gathered
		m.players[0].force_token = true
		m.events.append({"t": "force", "p": 0})
		ms._step()
		await _wait(0.45)
		await _shot("t_force_gather_%s" % sz[2])
		await _wait(1.0)
		await _shot("t_force_held_%s" % sz[2])
		# claim initiative -> coin flies
		if m.can_act(0):
			ms._on_coin_pressed()
			await _wait(0.35)
			await _shot("t_coin_flight_%s" % sz[2])
			await _wait(1.0)
			await _shot("t_coin_claimed_%s" % sz[2])


func _backdrop_shots() -> void:
	for sz in [[540, 960, "p"], [1280, 720, "l"]]:
		await _size(sz[0], sz[1])
		await _go("match")
		await _wait(2.0)
		var ms := get_tree().current_scene
		for i in 20:
			if ms.m.phase == "action" and ms.m.pending.is_empty():
				break
			_resolve_setup(ms)
			await _wait(0.5)
		for c in get_tree().root.find_children("*", "", true, false):
			if c is ChoicePanel:
				c.get_parent().queue_free()
		await _wait(1.0)
		var bg: BoardTheme = ms.theme_bg
		bg._launch(1, "capital", 1)
		for s in bg._ships:
			s["k"] = 0.45
		bg._launch(0, "fighter", 3)
		await _wait(1.6)
		await _shot("bg_flyby_%s" % sz[2])
		print("factions ", bg._factions)


func _spotlight_shots() -> void:
	Save.data["spotlight_runs"] = {}
	Save.data["spotlight_records"] = {}
	var spot: Dictionary = SpotlightFlow.spots()[0]
	# one finished run so a record shows
	var dead := SpotlightRun.start(spot, CardDB.lib, 77, SpotlightFlow.spots())
	dead["stats"]["wins"] = 6
	dead["sector"] = 2
	dead["status"] = "dead"
	SpotlightFlow.finish(dead)
	var r := SpotlightFlow.start(spot["id"])
	for sz in [[540, 960, "p"], [1280, 720, "l"]]:
		await _size(sz[0], sz[1])
		await _go("spotlight")
		await _shot("sp_select_%s" % sz[2])
		await _go("spotlight_run", {"deck_id": spot["id"]})
		await _shot("sp_map_%s" % sz[2])
		var sc := get_tree().current_scene
		var first: String = SpotlightRun.available_nodes(r)[0]
		sc._open_node(first)
		await _wait(0.8)
		await _shot("sp_node_%s" % sz[2])
		_close_layers()
		await _wait(0.3)
		sc._edit_deck()
		await _wait(0.8)
		await _shot("sp_deck_%s" % sz[2])
		_close_layers()
		# a reward screen
		r = SpotlightFlow.run(spot["id"])
		r["pending_reward"] = {"credits": 21, "cards": SpotlightRun.roll_cards(r, CardDB.lib, 3, false, RandomNumberGenerator.new()), "perks": ["kyber_core", "veteran_crew"]}
		SpotlightFlow.save_run(r)
		await _go("spotlight_run", {"deck_id": spot["id"]})
		await _wait(1.5)
		await _shot("sp_reward_%s" % sz[2])
		_close_layers()
		r["pending_reward"] = {}
		SpotlightFlow.save_run(r)
		# shop on a fresh node
		for nid in r["map"]["nodes"]:
			if r["map"]["nodes"][nid]["type"] == "shop":
				await _go("spotlight_run", {"deck_id": spot["id"]})
				var sc2 := get_tree().current_scene
				r["current"] = ""
				sc2.run["map"]["rows"][0] = [nid]
				sc2._open_node(nid)
				await _wait(0.8)
				await _shot("sp_shop_%s" % sz[2])
				_close_layers()
				break
	await _go("spotlight_run", {"deck_id": "nope", "result": {"summary": SpotlightRun.summary(dead)}})
	await _shot("sp_death_p")


func _spotlight_e2e() -> void:
	await _size(540, 960)
	Save.data["spotlight_runs"] = {}
	var spot: Dictionary = SpotlightFlow.spots()[2]
	var r := SpotlightFlow.start(spot["id"])
	var nid := ""
	for id in SpotlightRun.available_nodes(r):
		if SpotlightRun.node(r, id)["type"] in ["fight", "objective"]:
			nid = id
	if nid == "":
		print("E2E no battle node in first row")
		return
	SpotlightFlow.start_node(r, nid)
	await _wait(3.0)
	var ms := get_tree().current_scene
	ms.m.set_winner(0, "test")
	ms._step()
	await _wait(1.5)
	await _shot("e2e_victory")
	for c in get_tree().root.find_children("*", "", true, false):
		if c is KyberButton and c.text == "Continue":
			c.pressed.emit()
	await _wait(2.5)
	await _shot("e2e_reward")
	var r2 := SpotlightFlow.run(spot["id"])
	print("E2E credits %d visited %s pending %s" % [int(r2["credits"]), r2["visited"], not r2["pending_reward"].is_empty()])
