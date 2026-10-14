extends Control
## The match board. Drives the Match engine, plays its events as animations,
## and turns touch/mouse input into engine actions:
##   drag a hand card up onto the board  -> play it
##   drag (or tap-then-tap) a unit onto an enemy unit/base -> attack
##   tap leader -> leader action / deploy;  tap resources -> smuggle
##   long-press / right-click anything -> inspect
## Layout reflows live between portrait (stacked arenas) and landscape
## (side-by-side arenas with HUD columns).

const HUMAN := 0

var m: Match
var params: Dictionary = {}
var tokens: Dictionary = {}          # uid -> UnitToken
var busy := false
var portrait := true

var theme_bg: BoardTheme
var board_layer: Control             # tokens live here
var fx_layer: Control
var ui_layer: Control
var hud: Array = []                  # SideHud x2 (index = player)
var hand: HandView
var enemy_hand_label: Label
var pass_btn: KyberButton
var tray: BoxContainer
var coin: TableTokens.InitiativeCoin
var force_orbs: Array = []
var prompt_bar: PanelContainer
var prompt_label: Label
var prompt_skip: KyberButton
var prompt_confirm: KyberButton
var tracker: Label
var log_panel: PanelContainer
var log_text: RichTextLabel
var menu_popup: PanelContainer
var arena_rects: Dictionary = {}     # "ground_0" -> Rect2 (player 0 row) etc.
var arena_bands: Dictionary = {}     # "ground" -> Rect2
var _arena_labels: Dictionary = {}
var _hand_top := 0.0

var _selected: UnitToken
var _arrow: Fx.TargetArrow
var _target_sel: Array = []
var _choice_open := false


func _ready() -> void:
	theme = UIKit.build_theme()
	params = Router.params.duplicate()
	var cfg: Dictionary = params.get("cfg", {})
	if cfg.is_empty():
		cfg = QuickMatch.default_config()
		params["mode"] = "quick"
	m = Match.new()
	_build()
	m.setup(CardDB.lib, cfg)
	hud[0].bind(m.players[0])
	hud[1].bind(m.players[1])
	var faces: Array = []
	for ps in m.players:
		if ps.leader:
			faces.append(ps.leader)
		else:
			# leaderless campaign enemies: judge the fleet by their units
			var d: Dictionary = {}
			for c in ps.deck + ps.units:
				if c.card_type() == "unit":
					d = c.data
					break
			faces.append(d)
	theme_bg.set_leaders(faces)
	get_viewport().size_changed.connect(_layout)
	coin.holder = m.initiative
	_layout()
	tracker.text = m.objective.tracker(m)
	Fx.banner(fx_layer, params.get("title", "Battle"), Kyber.C_KYBER, m.objective.describe())
	await get_tree().create_timer(Kyber.anim(0.9)).timeout
	_step()


# ================================================================ build

func _build() -> void:
	theme_bg = BoardTheme.new()
	UIKit.fill_rect(theme_bg)
	add_child(theme_bg)
	theme_bg.setup(params.get("theme", "auto"))
	board_layer = Control.new()
	UIKit.fill_rect(board_layer)
	board_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(board_layer)
	ui_layer = Control.new()
	UIKit.fill_rect(ui_layer)
	ui_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ui_layer)
	for i in 2:
		var h := SideHud.new(i, i == HUMAN)
		ui_layer.add_child(h)
		h.leader_pressed.connect(_on_leader_pressed)
		h.base_pressed.connect(_on_base_pressed)
		h.resources_pressed.connect(_on_resources_pressed)
		h.inspect.connect(func(id, r, inst): InspectOverlay.open(self, id, r, inst))
		hud.append(h)
	for a in ["ground", "space"]:
		var l := UIKit.aurebesh(a, 20, Color(1, 1, 1, 0.18))
		var l2 := UIKit.label(a.to_upper() + " ARENA", 14, Color(1, 1, 1, 0.3))
		board_layer.add_child(l)
		board_layer.add_child(l2)
		_arena_labels[a] = [l, l2]
	enemy_hand_label = UIKit.fit_label(UIKit.label("", 16, Kyber.C_DIM))
	ui_layer.add_child(enemy_hand_label)
	tracker = UIKit.fit_label(UIKit.label("", 18, Kyber.C_GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	tracker.add_theme_constant_override("outline_size", 6)
	tracker.add_theme_color_override("font_outline_color", Color.BLACK)
	ui_layer.add_child(tracker)
	tray = BoxContainer.new()
	tray.add_theme_constant_override("separation", 8)
	ui_layer.add_child(tray)
	coin = TableTokens.InitiativeCoin.new()
	coin.pressed.connect(_on_coin_pressed)
	for i in 2:
		var orb := TableTokens.ForceOrb.new()
		force_orbs.append(orb)
	pass_btn = KyberButton.make("PASS", KyberButton.Style.PRIMARY, "", true)
	pass_btn.custom_minimum_size = Vector2(150, 64)
	pass_btn.pressed.connect(_on_pass)
	ui_layer.add_child(pass_btn)
	var log_btn := KyberButton.make("", KyberButton.Style.GHOST, "log")
	log_btn.custom_minimum_size = Vector2(56, 56)
	log_btn.name = "LogBtn"
	log_btn.pressed.connect(_toggle_log)
	ui_layer.add_child(log_btn)
	var menu_btn := KyberButton.make("", KyberButton.Style.GHOST, "gear")
	menu_btn.custom_minimum_size = Vector2(56, 56)
	menu_btn.name = "MenuBtn"
	menu_btn.pressed.connect(_open_menu)
	ui_layer.add_child(menu_btn)
	hand = HandView.new()
	ui_layer.add_child(hand)
	hand.card_tapped.connect(func(c): InspectOverlay.open(self, c.card_id, c.get_global_rect(), c.inst))
	hand.card_inspect.connect(func(c): InspectOverlay.open(self, c.card_id, c.get_global_rect(), c.inst))
	hand.card_drag_moved.connect(_on_hand_drag_moved)
	hand.card_dropped.connect(_on_hand_drop)
	# prompt bar for board targeting
	prompt_bar = UIKit.panel(Color(0.02, 0.05, 0.09, 0.92), Kyber.C_GOLD, 12, 10)
	var ph := HBoxContainer.new()
	ph.add_theme_constant_override("separation", 10)
	prompt_bar.add_child(ph)
	prompt_label = UIKit.label("", 19, Kyber.C_TEXT)
	prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ph.add_child(prompt_label)
	prompt_confirm = KyberButton.make("OK", KyberButton.Style.PRIMARY)
	prompt_confirm.custom_minimum_size = Vector2(90, 48)
	prompt_confirm.pressed.connect(func(): _submit_targets(_target_sel))
	ph.add_child(prompt_confirm)
	prompt_skip = KyberButton.make("Skip", KyberButton.Style.GHOST)
	prompt_skip.custom_minimum_size = Vector2(90, 48)
	prompt_skip.pressed.connect(func(): _submit_targets([]))
	ph.add_child(prompt_skip)
	prompt_bar.visible = false
	ui_layer.add_child(prompt_bar)
	# log
	log_panel = UIKit.panel(Color(0.02, 0.04, 0.07, 0.95), Kyber.C_LINE, 12)
	log_text = RichTextLabel.new()
	log_text.scroll_following = true
	log_text.add_theme_font_size_override("normal_font_size", 16)
	log_panel.add_child(log_text)
	log_panel.visible = false
	ui_layer.add_child(log_panel)
	ui_layer.add_child(coin)
	for orb in force_orbs:
		ui_layer.add_child(orb)
	fx_layer = Control.new()
	UIKit.fill_rect(fx_layer)
	fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fx_layer)
	_arrow = Fx.TargetArrow.new()
	_arrow.visible = false
	fx_layer.add_child(_arrow)


# ================================================================ layout

func _layout() -> void:
	var vs := get_viewport_rect().size
	portrait = vs.y >= vs.x
	var arenas: Array = m.rules.arenas
	var both := arenas.size() > 1
	var arena_area: Rect2
	if portrait:
		var top_h := vs.y * 0.105
		var hud_h := vs.y * 0.1
		var hand_h := vs.y * 0.13
		hud[1].arrange(Rect2(Vector2(10, 8), Vector2(vs.x - 20, top_h - 8)), true)
		hud[0].arrange(Rect2(Vector2(10, vs.y - hand_h - hud_h), Vector2(vs.x - 20, hud_h - 6)), true)
		arena_area = Rect2(Vector2(0, top_h + 34), Vector2(vs.x, vs.y - top_h - hud_h - hand_h - 34 - 70))
		_hand_top = vs.y - hand_h
		hand.card_scale = clampf(vs.x / 4.6 / CardView.PORTRAIT.x, 0.45, 1.0)
		hand.position = Vector2(0, vs.y - hand_h)
		hand.size = Vector2(vs.x, hand_h)
		var row_y := arena_area.end.y + 8
		pass_btn.position = Vector2(vs.x - 170, row_y)
		tray.vertical = false
		tray.position = Vector2(12 + TableTokens.InitiativeCoin.SIZE + 16, row_y + 4)
		tracker.position = Vector2(0, top_h + 4)
		tracker.size = Vector2(vs.x, 26)
		enemy_hand_label.position = Vector2(vs.x * 0.7, top_h - 26)
		enemy_hand_label.size = Vector2(vs.x * 0.3 - 10, 24)
		ui_layer.get_node("LogBtn").position = Vector2(vs.x - 236, row_y + 4)
		ui_layer.get_node("MenuBtn").position = Vector2(vs.x - 300, row_y + 4)
		prompt_bar.position = Vector2(12, top_h + 32)
		prompt_bar.size = Vector2(vs.x - 24, 70)
		log_panel.position = Vector2(vs.x * 0.05, vs.y * 0.15)
		log_panel.size = Vector2(vs.x * 0.9, vs.y * 0.55)
	else:
		var side_w := clampf(vs.x * 0.17, 220, 420)
		var right_w := clampf(vs.x * 0.13, 190, 320)
		var hand_h := vs.y * 0.2
		hud[1].arrange(Rect2(Vector2(12, 12), Vector2(side_w, vs.y * 0.45)), false)
		hud[0].arrange(Rect2(Vector2(12, vs.y * 0.52), Vector2(side_w, vs.y * 0.45)), false)
		arena_area = Rect2(Vector2(side_w + 30, 50), Vector2(vs.x - side_w - right_w - 60, vs.y - hand_h - 60))
		_hand_top = vs.y - hand_h
		hand.card_scale = clampf(hand_h * 1.25 / CardView.PORTRAIT.y, 0.4, 1.0)
		hand.position = Vector2(side_w + 30, vs.y - hand_h)
		hand.size = Vector2(vs.x - side_w - right_w - 60, hand_h)
		var rx := vs.x - right_w - 12
		pass_btn.position = Vector2(rx, vs.y * 0.5 - 32)
		pass_btn.custom_minimum_size.x = right_w
		tray.vertical = true
		tray.position = Vector2(rx, vs.y * 0.5 + 50)
		tracker.position = Vector2(side_w + 30, 12)
		tracker.size = Vector2(arena_area.size.x, 26)
		enemy_hand_label.position = Vector2(rx, 20)
		enemy_hand_label.size = Vector2(right_w, 24)
		ui_layer.get_node("LogBtn").position = Vector2(rx, vs.y - 80)
		ui_layer.get_node("MenuBtn").position = Vector2(rx + 70, vs.y - 80)
		prompt_bar.position = Vector2(side_w + 30, 44)
		prompt_bar.size = Vector2(arena_area.size.x, 70)
		log_panel.position = Vector2(vs.x * 0.25, vs.y * 0.1)
		log_panel.size = Vector2(vs.x * 0.5, vs.y * 0.7)
	hand.spawn_from = hud[0].global_position + hud[0].size
	coin.position = coin_pos(coin.holder)
	for i in 2:
		var br: Rect2 = hud[i].base_view.get_rect()
		var orb: Control = force_orbs[i]
		orb.position = hud[i].position + br.position + Vector2(br.size.x - orb.size.x - 4, -orb.size.y * 0.35 if i == 0 else br.size.y * 0.3)
	# arena bands
	arena_bands.clear()
	arena_rects.clear()
	var bands: Array = []
	if both:
		if portrait:
			var hh := arena_area.size.y / 2.0
			# Ground sits nearest the player (bottom), space above it.
			bands = [["space", Rect2(arena_area.position, Vector2(arena_area.size.x, hh - 6))],
				["ground", Rect2(arena_area.position + Vector2(0, hh + 6), Vector2(arena_area.size.x, hh - 6))]]
		else:
			var gw := arena_area.size.x * 0.56
			bands = [["ground", Rect2(arena_area.position, Vector2(gw - 8, arena_area.size.y))],
				["space", Rect2(arena_area.position + Vector2(gw + 8, 0), Vector2(arena_area.size.x - gw - 8, arena_area.size.y))]]
	else:
		bands = [[arenas[0], arena_area]]
	for a in ["ground", "space"]:
		for l in _arena_labels[a]:
			l.visible = false
	for b in bands:
		var a: String = b[0]
		var r: Rect2 = b[1]
		arena_bands[a] = r
		arena_rects[a + "_1"] = Rect2(r.position, Vector2(r.size.x, r.size.y / 2.0))
		arena_rects[a + "_0"] = Rect2(r.position + Vector2(0, r.size.y / 2.0), Vector2(r.size.x, r.size.y / 2.0))
		var ls: Array = _arena_labels[a]
		ls[0].visible = true
		ls[1].visible = true
		ls[1].text = "BATTLEFIELD · ONE LANE" if m.rules.single_lane else a.to_upper() + " ARENA"
		ls[0].position = r.position + Vector2(8, r.size.y / 2.0 - 30)
		ls[1].position = r.position + Vector2(8, r.size.y / 2.0 - 8)
	board_layer.queue_redraw()
	if not board_layer.draw.is_connected(_draw_board):
		board_layer.draw.connect(_draw_board)
	_position_tokens(false)
	hand.layout()


func _draw_board() -> void:
	for a in arena_bands:
		var r: Rect2 = arena_bands[a]
		var col := Color(0.4, 0.7, 1.0, 0.06) if a == "space" else Color(1.0, 0.8, 0.5, 0.06)
		board_layer.draw_rect(r, col)
		board_layer.draw_rect(r, Color(1, 1, 1, 0.08), false, 2.0)
		var y := r.position.y + r.size.y / 2.0
		board_layer.draw_line(Vector2(r.position.x + 140, y), Vector2(r.end.x - 20, y), Color(Kyber.C_KYBER, 0.25), 2.0)


func _token_scale() -> float:
	var best := 10.0
	for k in arena_rects:
		var r: Rect2 = arena_rects[k]
		best = minf(best, (r.size.y - 12) / UnitToken.SIZE.y)
	var vs := get_viewport_rect().size
	var widest := 1
	for k in arena_rects:
		var parts: PackedStringArray = k.split("_")
		widest = maxi(widest, m.players[int(parts[1])].units_in(parts[0]).size())
	for k in arena_rects:
		var r2: Rect2 = arena_rects[k]
		best = minf(best, (r2.size.x - 40) / (maxf(widest, 3 if m.rules.arenas.size() == 1 else 4) * (UnitToken.SIZE.x + 10)))
	var cap := 1.2 if vs.x > 1400 else 1.0
	if m.rules.arenas.size() == 1:
		cap = 1.4  # Quick format: one arena gets the whole board, so tokens can be big
	return clampf(best, 0.42, cap)


func _position_tokens(animate := true) -> void:
	var sc := _token_scale()
	for p in 2:
		for a in m.rules.arenas:
			var key: String = a + "_" + str(p)
			if not arena_rects.has(key):
				continue
			var r: Rect2 = arena_rects[key]
			var units: Array = m.players[p].units_in(a)
			var n := units.size()
			var w := UnitToken.SIZE.x * sc + 10
			var x0 := r.position.x + (r.size.x - w * n) / 2.0 + 5
			var y := r.position.y + (r.size.y - UnitToken.SIZE.y * sc) / 2.0
			for i in n:
				var tok: UnitToken = tokens.get(units[i].uid)
				if tok == null:
					continue
				tok.scale = Vector2(sc, sc) if not tok._dying else tok.scale
				tok.home_pos = Vector2(x0 + i * w, y)
				if animate:
					tok.create_tween().tween_property(tok, "position", tok.home_pos, Kyber.anim(0.3)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
				else:
					tok.position = tok.home_pos


# ================================================================ main loop

func _step() -> void:
	if busy:
		return
	busy = true
	while true:
		await _drain()
		_sync()
		if m.is_over():
			busy = false
			_game_over()
			return
		if not m.pending.is_empty():
			var who: int = m.pending["player"]
			if m.players[who].is_ai:
				await get_tree().create_timer(Kyber.anim(0.3)).timeout
				AiBot.choose(m)
				continue
			busy = false
			_show_pending()
			return
		if m.phase == "action" and m.players[m.active].is_ai:
			await get_tree().create_timer(Kyber.anim(0.55)).timeout
			AiBot.act(m)
			continue
		break
	busy = false
	_sync()


func _act(a: Dictionary) -> void:
	if busy or not m.can_act(HUMAN):
		return
	_clear_selection()
	if m.do_action(a):
		_step()


# ================================================================ events -> animation

func _drain() -> void:
	var evs := m.take_events()
	for e in evs:
		match e["t"]:
			"log":
				log_text.append_text(e["text"] + "\n")
			"enter":
				_ensure_token(m.card(e["uid"]), true)
				_position_tokens()
				Sfx.play("play")
				await _wait(0.18)
			"play":
				await _anim_play(e)
			"attack":
				await _anim_attack(m.card(e["a"]), m.card(e["target"]))
			"damage":
				_anim_damage(m.card(e["uid"]), int(e["n"]), m.card(int(e.get("src", 0))))
				await _wait(0.12)
			"heal":
				var hc := m.card(e["uid"])
				Fx.float_text(fx_layer, _card_center(hc), "+%d" % int(e["n"]), Kyber.C_GOOD)
			"shield_break":
				Fx.shatter(fx_layer, _card_center(m.card(e["uid"])))
				await _wait(0.15)
			"token":
				var tk: UnitToken = tokens.get(e["on"])
				if tk:
					tk.refresh()
					tk.flash(Kyber.C_KYBER if e["kind"] == "shield" else Kyber.C_GOLD)
					Fx.float_text(fx_layer, tk.center_global(), e["kind"].capitalize(), Kyber.C_KYBER, 26)
					Sfx.play("shield" if e["kind"] == "shield" else "deploy", 1.3)
				await _wait(0.15)
			"buff":
				var bt: UnitToken = tokens.get(e["uid"])
				if bt:
					bt.refresh()
					var txt: String = e.get("kw", "").capitalize() if e.has("kw") else "%+d/%+d" % [int(e.get("p", 0)), int(e.get("h", 0))]
					Fx.float_text(fx_layer, bt.center_global(), txt, Kyber.C_GOLD, 26)
			"defeat":
				var dt: UnitToken = tokens.get(e["uid"])
				if dt:
					tokens.erase(e["uid"])
					Sfx.play("defeat")
					Fx.impact(fx_layer, dt.center_global(), Color(1, 0.5, 0.2), true)
					dt.die()
				await _wait(0.25)
			"bounce":
				var bt2: UnitToken = tokens.get(e["uid"])
				if bt2:
					tokens.erase(e["uid"])
					bt2.die()
			"exhaust", "ready":
				var et: UnitToken = tokens.get(e["uid"])
				if et:
					et.refresh()
			"deploy":
				var l := m.card(e["uid"])
				Fx.banner(fx_layer, "%s deploys" % l.name(), Kyber.C_GOLD, "deploy")
				Sfx.play("deploy")
				await _wait(0.5)
			"claim":
				var tok_name: String = e["token"]
				if tok_name == "initiative":
					await coin.fly_to(coin_pos(int(e["p"])), int(e["p"]), true)
					continue
				Fx.float_text(fx_layer, hud[e["p"]].get_global_rect().get_center(), tok_name.capitalize().replace("_", " "), Kyber.C_GOLD, 34)
				Sfx.play("turn")
				await _wait(0.3)
			"phase":
				if e["phase"] == "action":
					coin.flip_to(false)
					Fx.banner(fx_layer, "Round %d" % int(e["round"]), Kyber.C_KYBER, "round")
				else:
					Fx.banner(fx_layer, "Regroup", Kyber.C_GOLD, "regroup")
				Sfx.play("turn", 0.8)
				await _wait(0.75)
			"turn":
				if e["p"] == HUMAN:
					Sfx.play("turn")
			"pass":
				if not e.get("auto", false):
					Fx.float_text(fx_layer, hud[e["p"]].get_global_rect().get_center(), "Pass", Kyber.C_DIM, 30)
			"discard":
				pass
			"force":
				force_orbs[int(e["p"])].gather()
				Fx.float_text(fx_layer, force_orbs[int(e["p"])].get_global_rect().get_center(), "The Force is with you", Color(0.7, 0.9, 1.0), 24)
				await _wait(0.6)
			"force_used":
				force_orbs[int(e["p"])].spend()
				await _wait(0.3)
			"ability":
				var at: UnitToken = tokens.get(e["uid"])
				if at:
					at.flash(Kyber.C_GOLD)
				Sfx.play("deploy", 1.6)
				await _wait(0.2)
		hud[0].refresh()
		hud[1].refresh()


func _wait(t: float) -> void:
	await get_tree().create_timer(Kyber.anim(t)).timeout


func _card_center(c: CardInst) -> Vector2:
	if c == null:
		return get_viewport_rect().get_center()
	if tokens.has(c.uid):
		return tokens[c.uid].center_global()
	if c.zone == "base":
		return hud[c.controller].base_view.get_global_rect().get_center()
	return get_viewport_rect().get_center()


func _anim_play(e: Dictionary) -> void:
	var c := m.card(e["uid"])
	if c == null:
		return
	Sfx.play("play")
	# Show the played card large for a beat (enemy plays and all events).
	if e["p"] != HUMAN or c.card_type() == "event":
		var cv := CardView.create(c.id, c)
		cv.draggable = false
		cv.hover_lift = false
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fx_layer.add_child(cv)
		var vs := get_viewport_rect().size
		var sc := clampf(vs.y * 0.34 / CardView.PORTRAIT.y, 0.5, 1.1)
		cv.pivot_offset = cv.size / 2.0
		cv.position = vs / 2.0 - cv.size / 2.0 + Vector2(0, -vs.y * (0.25 if e["p"] != HUMAN else -0.2))
		cv.scale = Vector2(sc * 0.5, sc * 0.5)
		cv.modulate.a = 0.0
		var tw := cv.create_tween().set_parallel(true)
		tw.tween_property(cv, "position", vs / 2.0 - cv.size / 2.0, Kyber.anim(0.25)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(cv, "scale", Vector2(sc, sc), Kyber.anim(0.25)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(cv, "modulate:a", 1.0, Kyber.anim(0.15))
		tw.chain().tween_interval(Kyber.anim(0.65))
		tw.chain().tween_property(cv, "modulate:a", 0.0, Kyber.anim(0.2))
		tw.parallel().tween_property(cv, "scale", Vector2(sc * 0.7, sc * 0.7), Kyber.anim(0.2))
		tw.chain().tween_callback(cv.queue_free)
		await _wait(0.75)


func _anim_attack(a: CardInst, t: CardInst) -> void:
	if a == null or t == null:
		return
	var at: UnitToken = tokens.get(a.uid)
	if at == null:
		return
	var target_pos := _card_center(t)
	var st := AttackStyle.of(a)
	var col: Color = st["color"]
	at.z_index = 20
	match st["style"]:
		"saber":
			await _anim_saber(at, target_pos, col)
		"ship":
			await _anim_ship(at, target_pos, col)
		"heavy":
			await _anim_ranged(at, target_pos, col, true)
		"melee":
			await _anim_melee(at, target_pos)
		_:
			await _anim_ranged(at, target_pos, col, false)
	if is_instance_valid(at):
		at.z_index = 0


## Position that puts the token's centre at global point `p` (tokens scale about their centre).
func _token_pos_for(p: Vector2) -> Vector2:
	return p - board_layer.global_position - Vector2(UnitToken.SIZE.x / 2.0, UnitToken.HEX_H / 2.0)


func _rest_rot(at: UnitToken) -> float:
	return -0.14 if at.inst.exhausted else 0.0


## Lightsaber: the blade ignites beside the unit, the unit dashes in and the
## blade swings through the target in the character's saber colour.
func _anim_saber(at: UnitToken, target: Vector2, col: Color) -> void:
	var s0 := at.scale
	var start := at.position
	var dir := (target - at.center_global()).normalized()
	var side := 1.0 if dir.x >= -0.1 else -1.0
	var blade := Fx.FxSaberBlade.new()
	blade.color = col
	blade.blade_px = 120.0 * s0.x + 40.0
	blade.angle = -PI / 2.0 - 0.4 * side
	fx_layer.add_child(blade)
	blade.follow = at
	blade.offset = Vector2(48.0 * s0.x * side, -18.0 * s0.y)
	# ignite
	Sfx.play("saber_on")
	var t1 := create_tween().set_parallel(true)
	t1.tween_property(blade, "length", 1.0, Kyber.anim(0.26)).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t1.tween_property(at, "scale", s0 * 1.12, Kyber.anim(0.26)).set_trans(Tween.TRANS_BACK)
	await t1.finished
	# dash in
	var t2 := create_tween()
	t2.tween_property(at, "position", _token_pos_for(target - dir * 75.0 * s0.x), Kyber.anim(0.2)).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	await t2.finished
	# swing through the target
	Sfx.play("swing")
	var base_a := dir.angle()
	blade.angle = base_a - 2.3 * side
	var t3 := create_tween().set_parallel(true)
	t3.tween_property(blade, "angle", base_a + 1.3 * side, Kyber.anim(0.2)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t3.tween_property(at, "rotation", 0.25 * side, Kyber.anim(0.2))
	var lit := func(_v):
		if is_instance_valid(blade):
			var tip := blade.global_position + Vector2(cos(blade.angle), sin(blade.angle)) * blade.blade_px * 0.7
			Fx.light_at(tip, col, 170.0, 1.0)
	t3.tween_method(lit, 0.0, 1.0, Kyber.anim(0.2))
	get_tree().create_timer(Kyber.anim(0.11)).timeout.connect(func():
		Fx.punch(fx_layer, target, col, 1.2, at.center_global())
		Sfx.play("hit", 0.8)
		Fx.shake(board_layer, 7.0, 0.2))
	await t3.finished
	await _wait(0.08)
	# retract and return
	var t4 := create_tween().set_parallel(true)
	t4.tween_property(blade, "length", 0.0, Kyber.anim(0.18))
	t4.tween_property(at, "position", start, Kyber.anim(0.3)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t4.tween_property(at, "scale", s0, Kyber.anim(0.3))
	t4.tween_property(at, "rotation", _rest_rot(at), Kyber.anim(0.3))
	await t4.finished
	blade.queue_free()


## Blasters / heavy cannons: the unit rises, recoils with every shot, bolts
## streak across with muzzle flashes and per-bolt impacts.
func _anim_ranged(at: UnitToken, target: Vector2, col: Color, heavy: bool) -> void:
	var s0 := at.scale
	var start := at.position
	var dir := (target - at.center_global()).normalized()
	var ready_pos := start + dir * 18.0
	var t1 := create_tween().set_parallel(true)
	t1.tween_property(at, "scale", s0 * 1.1, Kyber.anim(0.15)).set_trans(Tween.TRANS_BACK)
	t1.tween_property(at, "position", ready_pos, Kyber.anim(0.15))
	await t1.finished
	var shots := 3 if heavy else clampi(2 + at.inst.power(true), 3, 6)
	var gap := Kyber.anim(0.15 if heavy else 0.08)
	var muzzle_at := at.center_global() + dir * 50.0 * s0.x
	var dur := Fx.volley(fx_layer, muzzle_at, target, col, shots, gap, 1.9 if heavy else 1.15, 22.0 if heavy else 14.0)
	var rec := create_tween()
	for i in shots:
		rec.tween_property(at, "position", ready_pos - dir * (11.0 if heavy else 6.0), gap * 0.4)
		rec.tween_property(at, "position", ready_pos, gap * 0.6)
	if heavy:
		get_tree().create_timer(Kyber.anim(0.2)).timeout.connect(func(): Fx.shake(board_layer, 9.0, 0.35))
	await get_tree().create_timer(dur).timeout
	Fx.punch(fx_layer, target, col, 1.25 if heavy else 1.0, at.center_global())
	var t2 := create_tween().set_parallel(true)
	t2.tween_property(at, "position", start, Kyber.anim(0.25)).set_trans(Tween.TRANS_BACK)
	t2.tween_property(at, "scale", s0, Kyber.anim(0.25))
	await t2.finished


## Starships: bank into a strafing run, fire twin lasers in pairs, peel away.
func _anim_ship(at: UnitToken, target: Vector2, col: Color) -> void:
	var s0 := at.scale
	var start := at.position
	var dir := (target - at.center_global()).normalized()
	var side := Vector2(-dir.y, dir.x)
	Sfx.play("whoosh", 1.4)
	var t1 := create_tween().set_parallel(true)
	var gap_px := (target - at.center_global()).length()
	t1.tween_property(at, "position", start + dir * minf(90.0, gap_px * 0.3) + side * 40.0, Kyber.anim(0.22)).set_trans(Tween.TRANS_SINE)
	t1.tween_property(at, "rotation", 0.3 * signf(side.x + 0.01), Kyber.anim(0.22))
	t1.tween_property(at, "scale", s0 * 1.15, Kyber.anim(0.22))
	await t1.finished
	var c := at.center_global()
	var off := side * 14.0 * s0.x
	for i in 3:
		Fx.volley(fx_layer, c + off, target + off * 0.5, col, 1, 0.0, 1.0, 10.0)
		Fx.volley(fx_layer, c - off, target - off * 0.5, col, 1, 0.0, 1.0, 10.0)
		await _wait(0.09)
	await _wait(0.12)
	Fx.punch(fx_layer, target, col, 1.0, c)
	Fx.shake(board_layer, 6.0, 0.18)
	var t2 := create_tween().set_parallel(true)
	t2.tween_property(at, "position", start, Kyber.anim(0.32)).set_trans(Tween.TRANS_SINE)
	t2.tween_property(at, "rotation", _rest_rot(at), Kyber.anim(0.32))
	t2.tween_property(at, "scale", s0, Kyber.anim(0.32))
	await t2.finished


## Melee (no blaster on the card): the card leaps up off the board, hangs for a
## beat, then slams down into the target with a shockwave.
func _anim_melee(at: UnitToken, target: Vector2) -> void:
	var s0 := at.scale
	var start := at.position
	Sfx.play("whoosh", 0.8)
	var t1 := create_tween().set_parallel(true)
	t1.tween_property(at, "position", start + Vector2(0, -80.0 * s0.y), Kyber.anim(0.26)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t1.tween_property(at, "scale", s0 * 1.35, Kyber.anim(0.26)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t1.tween_property(at, "rotation", -0.25, Kyber.anim(0.26))
	await t1.finished
	await _wait(0.06)
	var t2 := create_tween().set_parallel(true)
	t2.tween_property(at, "position", _token_pos_for(target), Kyber.anim(0.15)).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	t2.tween_property(at, "scale", s0 * 1.05, Kyber.anim(0.15))
	t2.tween_property(at, "rotation", 0.12, Kyber.anim(0.15))
	await t2.finished
	Fx.shockwave(fx_layer, target)
	Fx.punch(fx_layer, target, Color(1, 0.8, 0.45), 1.35, at.center_global() + Vector2(0, -120))
	Sfx.play("hit", 0.7)
	Fx.shake(board_layer, 12.0, 0.3)
	await _wait(0.08)
	var t3 := create_tween().set_parallel(true)
	t3.tween_property(at, "position", start, Kyber.anim(0.35)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t3.tween_property(at, "scale", s0, Kyber.anim(0.35))
	t3.tween_property(at, "rotation", _rest_rot(at), Kyber.anim(0.35))
	await t3.finished


func _anim_damage(c: CardInst, n: int, src: CardInst = null) -> void:
	if c == null:
		return
	var pos := _card_center(c)
	var from := _card_center(src) if src and src != c else Vector2.INF
	Fx.float_text(fx_layer, pos, "-%d" % n, Color(1, 0.25, 0.2), 44 + mini(n, 6) * 3)
	if tokens.has(c.uid):
		var tk: UnitToken = tokens[c.uid]
		tk.flash(Color(1, 0.95, 0.85))
		tk.hit_punch(from)
		tk.refresh()
	elif c.zone == "base":
		hud[c.controller].base_view.hit()


# ================================================================ sync

func _ensure_token(c: CardInst, animate: bool) -> UnitToken:
	if c == null or not c.in_play():
		return null
	if tokens.has(c.uid):
		return tokens[c.uid]
	var tok := UnitToken.create(c, c.controller == HUMAN)
	board_layer.add_child(tok)
	tokens[c.uid] = tok
	Fx.light_targets.append(tok)
	tok.pressed.connect(_on_token_pressed)
	tok.inspect_requested.connect(func(t): InspectOverlay.open(self, t.inst.id, t.get_global_rect(), t.inst))
	tok.drag_started.connect(_on_token_drag_start)
	tok.drag_moved.connect(_on_token_drag_moved)
	tok.drag_released.connect(_on_token_drag_released)
	var sc := _token_scale()
	tok.scale = Vector2(sc, sc)
	if animate:
		tok.pop_in()
		create_tween().tween_property(tok, "scale", Vector2(sc, sc), Kyber.anim(0.4)).set_trans(Tween.TRANS_BACK)
	return tok


func _register_lights() -> void:
	var list: Array = tokens.values()
	for h in hud:
		list.append(h.base_view)
		list.append(h.leader_view)
	Fx.light_targets = list


func _sync() -> void:
	_register_lights()
	var alive := {}
	for u in m.all_units():
		alive[u.uid] = true
		var tok := _ensure_token(u, false)
		if tok:
			tok.friendly = u.controller == HUMAN
			tok.refresh()
	for uid in tokens.keys():
		if not alive.has(uid):
			var t: UnitToken = tokens[uid]
			tokens.erase(uid)
			t.die()
	_position_tokens()
	# hand
	var playable := {}
	var costs := {}
	var legal := m.legal_actions(HUMAN)
	for a in legal:
		if a["a"] == "play":
			playable[a["uid"]] = true
	for c in m.players[HUMAN].hand:
		costs[c.uid] = m.play_cost(HUMAN, c)
	hand.sync(m.players[HUMAN].hand, playable, costs)
	# highlights
	var can_attack := {}
	for a in legal:
		if a["a"] in ["attack", "ability"] and a.has("uid"):
			can_attack[a["uid"]] = true
	for uid in tokens:
		var t2: UnitToken = tokens[uid]
		if t2 == _selected:
			continue
		t2.highlight = UnitToken.Hi.CAN_ACT if can_attack.has(uid) and m.pending.is_empty() else UnitToken.Hi.NONE
	var lv: SideHud.LeaderView = hud[HUMAN].leader_view
	lv.actionable = false
	for a in legal:
		if a["a"] == "deploy" or (a["a"] == "ability" and m.players[HUMAN].leader and a["uid"] == m.players[HUMAN].leader.uid):
			lv.actionable = true
	hud[0].refresh()
	hud[1].refresh()
	hud[1].base_view.targetable = false
	hud[0].base_view.targetable = false
	# controls
	var my_turn := m.can_act(HUMAN)
	pass_btn.disabled = not my_turn
	pass_btn.breathe = my_turn
	pass_btn.text = ("END TURN" if m.rules.turn_mode == RuleSet.TurnMode.BURST else "PASS") if my_turn else "ENEMY…"
	_rebuild_tray(legal)
	var can_claim := false
	for a in legal:
		if a["a"] == "claim" and a["token"] == "initiative":
			can_claim = true
	coin.claimable = can_claim
	enemy_hand_label.text = "Enemy hand: %d" % m.players[1].hand.size()
	tracker.text = "%s   ·   Round %d   ·   Initiative: %s" % [m.objective.tracker(m), m.round_num, "You" if m.initiative == HUMAN else "Enemy"]


func _rebuild_tray(legal: Array) -> void:
	for c in tray.get_children():
		c.queue_free()
	for tk in m.tokens:
		if tk["id"] == "initiative":
			continue
		var claimable := false
		for a in legal:
			if a["a"] == "claim" and a["token"] == tk["id"]:
				claimable = true
		var claimed_by: int = m.tokens_claimed.get(tk["id"], -1)
		var art := Art.ui_texture("tokens/" + str(tk["id"])) if tk["id"] in ["plan", "blast"] else null
		if art:
			var tb := TableTokens.TokenButton.new()
			tb.tex = art
			tb.label = tk.get("name", tk["id"])
			tb.claimable = claimable
			tb.claimed = claimed_by >= 0
			tb.tooltip_text = tk.get("desc", "")
			var tid: String = tk["id"]
			tb.pressed.connect(func(): _act({"a": "claim", "token": tid}))
			tray.add_child(tb)
			continue
		var b := KyberButton.make(tk.get("name", tk["id"]), KyberButton.Style.GOLD, tk.get("icon", "initiative"), false)
		b.custom_minimum_size = Vector2(150 if portrait else 0, 52)
		b.add_theme_font_size_override("font_size", 16)
		b.disabled = not claimable
		b.tooltip_text = tk.get("desc", "")
		if claimed_by >= 0:
			b.text = "%s ✓" % tk.get("name", "")
		var id: String = tk["id"]
		b.pressed.connect(func(): _act({"a": "claim", "token": id}))
		tray.add_child(b)


# ================================================================ human input

func _on_pass() -> void:
	_act({"a": "pass"})


func _legal_for(uid: int, kind: String) -> Array:
	var out: Array = []
	for a in m.legal_actions(HUMAN):
		if a["a"] == kind and int(a.get("uid", -1)) == uid:
			out.append(a)
	return out


func _on_hand_drag_moved(card: CardView, at: Vector2) -> void:
	card.selected = at.y < _hand_top - 30 and card.playable


func _on_hand_drop(card: CardView, at: Vector2) -> void:
	card.selected = false
	var uid: int = card.get_meta("uid")
	if at.y < _hand_top - 30 and card.playable and m.can_act(HUMAN):
		var removed := hand.remove_card(uid)
		if removed:
			# fly into the arena then vanish; the token/event animation takes over
			var tw := removed.create_tween().set_parallel(true)
			tw.tween_property(removed, "scale", removed.scale * 0.4, Kyber.anim(0.18))
			tw.tween_property(removed, "modulate:a", 0.0, Kyber.anim(0.18))
			tw.chain().tween_callback(removed.queue_free)
		_act({"a": "play", "uid": uid})
	else:
		if at.y < _hand_top - 30 and not card.playable:
			Fx.float_text(fx_layer, at, "Can't play that now", Kyber.C_EMPIRE, 24)
		card.spring_home()


func _on_token_pressed(tok: UnitToken) -> void:
	# Answering a board-target prompt?
	if prompt_bar.visible and not m.pending.is_empty():
		_toggle_target(tok.inst.uid)
		return
	if not m.can_act(HUMAN):
		InspectOverlay.open(self, tok.inst.id, tok.get_global_rect(), tok.inst)
		return
	if _selected and tok.inst.controller != HUMAN:
		_try_attack(_selected, tok.inst.uid)
		return
	if tok.inst.controller == HUMAN:
		var attacks := _legal_for(tok.inst.uid, "attack")
		var abilities := _legal_for(tok.inst.uid, "ability")
		if abilities.size() > 0:
			_unit_menu(tok, attacks.size() > 0, abilities)
			return
		if attacks.size() > 0:
			_select_attacker(tok)
			return
	InspectOverlay.open(self, tok.inst.id, tok.get_global_rect(), tok.inst)


func _select_attacker(tok: UnitToken) -> void:
	_clear_selection()
	_selected = tok
	tok.highlight = UnitToken.Hi.SELECTED
	Sfx.play("click")
	var targets := m.attack_targets(tok.inst)
	for uid in targets:
		if tokens.has(uid):
			tokens[uid].highlight = UnitToken.Hi.HOSTILE_TARGET
		elif uid == m.players[1].base.uid:
			hud[1].base_view.targetable = true


func _clear_selection() -> void:
	if _selected and is_instance_valid(_selected):
		_selected.highlight = UnitToken.Hi.NONE
	_selected = null
	for uid in tokens:
		if tokens[uid].highlight in [UnitToken.Hi.HOSTILE_TARGET, UnitToken.Hi.SELECTED]:
			tokens[uid].highlight = UnitToken.Hi.NONE
	hud[1].base_view.targetable = false
	_arrow.visible = false


func _try_attack(tok: UnitToken, target_uid: int) -> void:
	if target_uid in m.attack_targets(tok.inst):
		_act({"a": "attack", "uid": tok.inst.uid, "target": target_uid})
	else:
		Fx.float_text(fx_layer, tok.center_global(), "Invalid target", Kyber.C_EMPIRE, 24)
		_clear_selection()


func _on_token_drag_start(tok: UnitToken) -> void:
	if not m.can_act(HUMAN) or tok.inst.controller != HUMAN or _legal_for(tok.inst.uid, "attack").is_empty():
		return
	_select_attacker(tok)
	_arrow.from = tok.center_global()
	_arrow.to = tok.center_global()
	_arrow.color = Kyber.C_EMPIRE
	_arrow.visible = true


func _on_token_drag_moved(tok: UnitToken, at: Vector2) -> void:
	if _arrow.visible and _selected == tok:
		_arrow.from = tok.center_global()
		_arrow.to = at
		_arrow.color = Kyber.C_GOLD if _target_at(at) >= 0 else Kyber.C_EMPIRE


func _on_token_drag_released(tok: UnitToken, at: Vector2) -> void:
	if not _arrow.visible or _selected != tok:
		return
	_arrow.visible = false
	var t := _target_at(at)
	if t >= 0:
		_try_attack(tok, t)
	else:
		_clear_selection()


func _target_at(at: Vector2) -> int:
	if _selected == null:
		return -1
	var legal := m.attack_targets(_selected.inst)
	for uid in tokens:
		var tk: UnitToken = tokens[uid]
		if uid in legal and Rect2(tk.global_position, UnitToken.SIZE * tk.scale).has_point(at):
			return uid
	var b: CardInst = m.players[1].base
	if b.uid in legal and hud[1].base_view.get_global_rect().has_point(at):
		return b.uid
	return -1


func _on_base_pressed(h: SideHud) -> void:
	var b: CardInst = m.players[h.player_idx].base
	if prompt_bar.visible and not m.pending.is_empty():
		_toggle_target(b.uid)
		return
	if _selected and h.player_idx != HUMAN:
		_try_attack(_selected, b.uid)
		return
	InspectOverlay.open(self, b.id, h.base_view.get_global_rect(), b)


func _on_leader_pressed(h: SideHud) -> void:
	var l: CardInst = m.players[h.player_idx].leader
	if l == null:
		return
	if h.player_idx != HUMAN:
		InspectOverlay.open(self, l.id, h.leader_view.get_global_rect(), l)
		return
	_popup_menu(h.leader_view.get_global_rect(), _leader_options(l))


## Every leader ability, usable ones first; others greyed with the reason.
## Entry: [label, action-dict, disabled-reason ("" = enabled)].
func _leader_options(l: CardInst) -> Array:
	var opts: Array = []
	var legal := m.legal_actions(HUMAN)
	var my_turn := m.can_act(HUMAN)
	var ps: PlayerState = m.players[HUMAN]
	if not l.deployed:
		var acts := l.abilities_with("action")
		for i in acts.size():
			var ab: Dictionary = acts[i]
			var act := {"a": "ability", "uid": l.uid, "idx": i}
			var ok := false
			for la in legal:
				if la["a"] == "ability" and la["uid"] == l.uid and int(la["idx"]) == i:
					ok = true
			var why := ""
			if not ok:
				var cost: Dictionary = ab.get("cost", {})
				if not my_turn:
					why = "wait for your action"
				elif cost.get("exhaust", false) and l.exhausted:
					why = "leader is exhausted"
				elif ps.ready_resources() < int(cost.get("resources", 0)):
					why = "needs %d ready resource(s)" % int(cost.get("resources", 0))
				else:
					why = "can't be paid right now"
			opts.append([ab.get("text", "Leader action"), act, why])
		# printed actions the engine can't run yet
		for line in str(l.data.get("text", "")).split("\n"):
			if line.strip_edges().begins_with("Action [") and not _has_compiled(acts, line):
				opts.append([line.strip_edges(), {}, "not automated yet"])
		var epic := int(l.data.get("epic_cost", 0))
		var deploy_ok := false
		for la in legal:
			if la["a"] == "deploy":
				deploy_ok = true
		var dwhy := ""
		if not deploy_ok:
			if l.epic_used:
				dwhy = "Epic Action already used"
			elif not my_turn:
				dwhy = "wait for your action"
			else:
				dwhy = "needs %d resources (you have %d)" % [epic, ps.resources.size()]
		opts.append(["Epic Action: deploy %s" % l.name(), {"a": "deploy"}, dwhy])
	else:
		opts.append(["%s is deployed — tap the unit on the board to attack or use its abilities" % l.name(), {}, "deployed"])
	opts.append(["Inspect leader", {"inspect": l.uid}, ""])
	return opts


func _has_compiled(acts: Array, line: String) -> bool:
	for ab in acts:
		if str(ab.get("text", "")).strip_edges() == line.strip_edges():
			return true
	return false


func _on_resources_pressed(h: SideHud) -> void:
	if h.player_idx != HUMAN:
		return
	var opts: Array = []
	for a in m.legal_actions(HUMAN):
		if a["a"] == "smuggle":
			var c := m.card(a["uid"])
			opts.append(["Smuggle %s (%d)" % [c.name(), m.play_cost(HUMAN, c, true)], a])
	if opts.is_empty():
		Fx.float_text(fx_layer, h.res_view.get_global_rect().get_center(), "%d ready / %d resources" % [m.players[HUMAN].ready_resources(), m.players[HUMAN].resources.size()], Kyber.C_COST, 22)
		return
	_popup_menu(h.res_view.get_global_rect(), opts)


func _unit_menu(tok: UnitToken, can_attack: bool, abilities: Array) -> void:
	var opts: Array = []
	if can_attack:
		opts.append(["Attack", {"select": tok.inst.uid}])
	for a in abilities:
		var ab: Dictionary = tok.inst.abilities_with("action")[int(a["idx"])]
		opts.append([ab.get("text", "Action"), a])
	opts.append(["Inspect", {"inspect": tok.inst.uid}])
	_popup_menu(tok.get_global_rect(), opts)


func _popup_menu(anchor: Rect2, opts: Array) -> void:
	if menu_popup:
		menu_popup.queue_free()
	menu_popup = UIKit.panel(Color(0.03, 0.06, 0.1, 0.97), Kyber.C_GOLD, 12, 12)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	menu_popup.add_child(v)
	var vs := get_viewport_rect().size
	for o in opts:
		var why: String = o[2] if o.size() > 2 else ""
		var label := str(o[0]) if why == "" else "%s\n(%s)" % [o[0], why]
		var b := KyberButton.make(label, KyberButton.Style.GOLD if not o[1].has("inspect") else KyberButton.Style.GHOST)
		b.disabled = why != ""
		b.add_theme_font_size_override("font_size", 17)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(minf(vs.x * 0.8, 460), 54)
		var act: Dictionary = o[1]
		b.pressed.connect(func():
			menu_popup.queue_free()
			menu_popup = null
			if act.has("inspect"):
				var ci := m.card(act["inspect"])
				InspectOverlay.open(self, ci.id, anchor, ci)
			elif act.has("select"):
				_select_attacker(tokens[act["select"]])
			else:
				_act(act))
		v.add_child(b)
	var cancel := KyberButton.make("Cancel", KyberButton.Style.GHOST)
	cancel.pressed.connect(func():
		menu_popup.queue_free()
		menu_popup = null)
	v.add_child(cancel)
	ui_layer.add_child(menu_popup)
	await get_tree().process_frame
	var pos := anchor.position + Vector2(0, -menu_popup.size.y - 8)
	pos.x = clampf(pos.x, 8, vs.x - menu_popup.size.x - 8)
	pos.y = clampf(pos.y, 8, vs.y - menu_popup.size.y - 8)
	menu_popup.position = pos
	UIKit.pop_in(menu_popup)


# ================================================================ pending choices (human)

func _show_pending() -> void:
	var pd := m.pending
	var kind: String = pd["kind"]
	if kind in ["target", "attack_target"]:
		_target_sel = []
		prompt_label.text = pd.get("prompt", "Choose a target")
		prompt_skip.visible = int(pd["min"]) == 0
		prompt_confirm.visible = int(pd["max"]) > 1
		prompt_bar.visible = true
		UIKit.pop_in(prompt_bar)
		_highlight_options()
		return
	if _choice_open:
		return
	_choice_open = true
	var cp := ChoicePanel.open(self, m, pd)
	cp.submitted.connect(func(sel):
		_choice_open = false
		m.submit_choice(sel)
		_step())


func _highlight_options() -> void:
	var pd := m.pending
	var hostile: bool = pd.get("hostile", false)
	for uid in tokens:
		var tk: UnitToken = tokens[uid]
		if uid in _target_sel:
			tk.highlight = UnitToken.Hi.SELECTED
		elif uid in pd["options"]:
			tk.highlight = UnitToken.Hi.HOSTILE_TARGET if hostile else UnitToken.Hi.TARGET
		else:
			tk.highlight = UnitToken.Hi.NONE
	for p in 2:
		hud[p].base_view.targetable = m.players[p].base.uid in pd["options"]


func _toggle_target(uid: int) -> void:
	var pd := m.pending
	if not (uid in pd["options"]):
		return
	if int(pd["max"]) == 1:
		_submit_targets([uid])
		return
	if uid in _target_sel:
		_target_sel.erase(uid)
	elif _target_sel.size() < int(pd["max"]):
		_target_sel.append(uid)
	_highlight_options()


func _submit_targets(sel: Array) -> void:
	if m.pending.is_empty():
		return
	if sel.size() < int(m.pending["min"]):
		return
	prompt_bar.visible = false
	for p in 2:
		hud[p].base_view.targetable = false
	if m.submit_choice(sel):
		_step()


# ================================================================ misc UI

func _toggle_log() -> void:
	log_panel.visible = not log_panel.visible
	if log_panel.visible:
		UIKit.pop_in(log_panel)


func _open_menu() -> void:
	_popup_menu(Rect2(get_viewport_rect().size / 2.0, Vector2.ZERO), [
		["Concede", {"concede": true}],
	])
	# Re-wire the concede button (popup handles actions generically).
	await get_tree().process_frame
	if menu_popup:
		var first: KyberButton = menu_popup.get_child(0).get_child(0)
		for c in first.pressed.get_connections():
			first.pressed.disconnect(c["callable"])
		first.pressed.connect(func():
			menu_popup.queue_free()
			menu_popup = null
			m.set_winner(1, "conceded")
			_step())


func _game_over() -> void:
	var won := m.winner == HUMAN
	for c in get_tree().root.find_children("*", "", true, false):
		if c is ChoicePanel or c is InspectOverlay:
			c.get_parent().queue_free()
	prompt_bar.visible = false
	if menu_popup:
		menu_popup.queue_free()
		menu_popup = null
	Sfx.play("win" if won else "lose")
	var layer := CanvasLayer.new()
	layer.layer = 45
	add_child(layer)
	var root := Control.new()
	UIKit.fill_rect(root)
	layer.add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	UIKit.fill_rect(dim)
	root.add_child(dim)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 18)
	UIKit.fill_rect(v)
	root.add_child(v)
	v.add_child(UIKit.aurebesh("victory" if won else "defeat", 30))
	var t := UIKit.title("Victory" if won else ("Draw" if m.winner == 2 else "Defeat"), 72, Kyber.C_GOLD if won else Kyber.C_EMPIRE)
	v.add_child(t)
	UIKit.pop_in(t)
	v.add_child(UIKit.label(m.log_lines.back() if not m.log_lines.is_empty() else "", 20, Kyber.C_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	v.add_child(row)
	Save.data["stats"]["matches"] += 1
	if won:
		Save.data["stats"]["wins"] += 1
	Save.write()
	if params.get("mode", "quick") == "spotlight":
		var sres := SpotlightFlow.on_match_end(params, m)
		var scont := KyberButton.make("Continue", KyberButton.Style.PRIMARY, "play", true)
		scont.custom_minimum_size.x = 260
		scont.pressed.connect(func(): SpotlightFlow.after_match(sres))
		row.add_child(scont)
	elif params.get("mode", "quick") == "campaign":
		var res := CampaignFlow.on_match_end(params, m)
		var cont := KyberButton.make("Continue", KyberButton.Style.PRIMARY, "play", true)
		cont.custom_minimum_size.x = 260
		cont.pressed.connect(func(): CampaignFlow.after_match(res))
		row.add_child(cont)
	else:
		var again := KyberButton.make("Rematch", KyberButton.Style.PRIMARY, "play", true)
		again.custom_minimum_size.x = 220
		again.pressed.connect(func():
			# fresh shuffle and fresh bot decks for the rematch
			var rng := RandomNumberGenerator.new()
			rng.randomize()
			var p2 := params.duplicate()
			var cfg: Dictionary = p2.get("cfg", {}).duplicate(true)
			if not cfg.is_empty():
				# same decks, new shuffle
				cfg["seed"] = rng.randi()
				cfg["rules"] = params["cfg"]["rules"]
				p2["cfg"] = cfg
			Router.go("match", p2))
		row.add_child(again)
		var menu := KyberButton.make("Menu", KyberButton.Style.GHOST, "back")
		menu.custom_minimum_size.x = 180
		menu.pressed.connect(func(): Router.go("menu"))
		row.add_child(menu)


## Where the initiative coin rests for player p (just inside that player's side).
func coin_pos(p: int) -> Vector2:
	var vs := get_viewport_rect().size
	var c := TableTokens.InitiativeCoin.SIZE
	if portrait:
		if p == HUMAN:
			return Vector2(12, hud[0].position.y - c - 42)
		return Vector2(12, hud[1].position.y + hud[1].size.y + 34)
	# landscape: right-hand column, enemy's near the top, yours just above PASS
	var x: float = pass_btn.position.x + (pass_btn.size.x - c) / 2.0
	if p == HUMAN:
		return Vector2(x, pass_btn.position.y - c - 34)
	return Vector2(x, 56)


func _on_coin_pressed() -> void:
	if coin.claimable:
		_act({"a": "claim", "token": "initiative"})
		return
	var why := "Initiative already claimed this round" if m.tokens_claimed.has("initiative") else "Wait for your action"
	Fx.float_text(fx_layer, coin.get_global_rect().get_center() + Vector2(0, -50), why, Kyber.C_GOLD, 20)
