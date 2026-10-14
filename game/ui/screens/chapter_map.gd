extends ScreenBase
## A chapter run: leader choice, then a Slay-the-Spire-style branching node map
## (spec 5.2). Events and rest stops resolve here; fights open the match screen.

var chapter: Dictionary
var run: Dictionary
var _map: Control
var _nodes: Dictionary = {}       # node id -> NodeButton
var _hud: HBoxContainer
var _panel: ModalPanel
var _start_box: VBoxContainer


func build() -> void:
	chapter = CardDB.chapter(Router.params.get("chapter_id", "ep4_ch1_tatooine"))
	set_header("Ep %s · %s" % [CampaignFlow.episode_data(int(chapter.get("episode", 4))).get("roman", ""), chapter.get("title", "")], "episodes")
	var theme_img: String = {"tatooine": "tatooine", "deathstar": "deathstar"}.get(chapter.get("board_theme", ""), "")
	if theme_img != "":
		bg.backdrop = Art.ui_texture(theme_img)
		bg.backdrop_alpha = 0.35
	run = Save.run()
	var active: bool = run.get("chapter", "") == chapter["id"] and run.get("status", "") == "active"
	if not active:
		_build_start(Router.params.get("failed", false))
	else:
		_build_map()


# ---------------------------------------------------------------- start / leader select

func _build_start(failed: bool) -> void:
	_start_box = VBoxContainer.new()
	_start_box.add_theme_constant_override("separation", 14)
	body.add_child(_start_box)
	if failed:
		var f := UIKit.title("Run failed", 40, Kyber.C_EMPIRE)
		_start_box.add_child(f)
		_start_box.add_child(UIKit.label("Your base fell. The chapter resets — try a different route.", 18, Kyber.C_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	var intro := UIKit.label(chapter.get("intro", ""), 20, Kyber.C_GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_start_box.add_child(intro)
	_start_box.add_child(UIKit.label("Choose your leader", 22, Kyber.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	row.name = "Leaders"
	_start_box.add_child(row)
	for lid in chapter.get("leader_options", []):
		if not CardDB.lib.has(lid):
			continue
		var holder := VBoxContainer.new()
		holder.add_theme_constant_override("separation", 8)
		var slot := Control.new()
		slot.custom_minimum_size = CardView.LANDSCAPE * 0.7
		var cv := CardView.create(lid)
		cv.pivot_offset = Vector2.ZERO
		cv.home_scale = Vector2(0.7, 0.7)
		cv.scale = cv.home_scale
		cv.hover_lift = false
		cv.drag_released.connect(func(c, _p): c.spring_home())
		cv.tapped.connect(func(c): InspectOverlay.open(self, c.card_id, c.get_global_rect()))
		slot.add_child(cv)
		holder.add_child(slot)
		var b := KyberButton.make("Lead with %s" % CardDB.card(lid).get("name", lid), KyberButton.Style.PRIMARY, "play", true)
		b.pressed.connect(func():
			CampaignFlow.start_run(chapter, lid)
			Router.go("chapter", {"chapter_id": chapter["id"]}))
		holder.add_child(b)
		row.add_child(holder)
		UIKit.pop_in(holder)
	var deck := KyberButton.make("View starting deck (%d)" % chapter.get("starting_deck", []).size(), KyberButton.Style.GHOST, "deck")
	deck.pressed.connect(func(): _show_deck(chapter.get("starting_deck", [])))
	_start_box.add_child(deck)


# ---------------------------------------------------------------- map

func _build_map() -> void:
	_hud = HBoxContainer.new()
	_hud.add_theme_constant_override("separation", 14)
	body.add_child(_hud)
	var maxhp := CampaignRun.max_base_hp(run, chapter)
	var hp := maxhp - int(run.get("base_damage", 0))
	_hud.add_child(_chip("resource", "Base %d/%d" % [hp, maxhp], Kyber.C_HP))
	var deck_btn := KyberButton.make("Deck %d" % run["deck"].size(), KyberButton.Style.GHOST, "deck")
	deck_btn.pressed.connect(func(): _show_deck(run["deck"]))
	_hud.add_child(deck_btn)
	var tre: Array = run.get("treasures", [])
	if not tre.is_empty():
		var names: Array = []
		var tdefs := CampaignFlow.treasures_for(chapter)
		for t in tre:
			names.append(tdefs.get(t, {}).get("name", t))
		_hud.add_child(_chip("star", ", ".join(names), Kyber.C_GOLD))
	var abandon := KyberButton.make("Abandon", KyberButton.Style.EMPIRE)
	abandon.pressed.connect(func():
		run["status"] = "lost"
		Save.set_run(run)
		Router.go("chapter", {"chapter_id": chapter["id"]}))
	_hud.add_child(abandon)
	_map = Control.new()
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map.draw.connect(_draw_links)
	body.add_child(_map)
	var avail := CampaignRun.available_nodes(run, chapter)
	var visited: Array = run.get("visited", [])
	for n in chapter.get("nodes", []):
		var nb := NodeButton.new()
		nb.node_def = n
		nb.state = "visited" if n["id"] in visited else ("available" if n["id"] in avail else "locked")
		nb.pressed.connect(func(): _open_node(n))
		_map.add_child(nb)
		_nodes[n["id"]] = nb


func _chip(glyph: String, text: String, col: Color) -> Control:
	var h := HBoxContainer.new()
	var ic := IconGlyph.new()
	ic.glyph = glyph
	ic.color = col
	ic.custom_minimum_size = Vector2(28, 28)
	h.add_child(ic)
	h.add_child(UIKit.label(text, 20, col))
	return h


func _draw_links() -> void:
	var edges: Dictionary = chapter.get("map", {}).get("edges", {})
	var visited: Array = run.get("visited", [])
	for a in edges:
		for b in edges[a]:
			if not (_nodes.has(a) and _nodes.has(b)):
				continue
			var pa: Vector2 = _nodes[a].position + _nodes[a].size / 2.0
			var pb: Vector2 = _nodes[b].position + _nodes[b].size / 2.0
			var lit: bool = a in visited
			var col := Color(Kyber.C_KYBER, 0.8) if lit else Color(1, 1, 1, 0.18)
			# dashed holo-line
			var d := pb - pa
			var n := int(d.length() / 14.0)
			for i in n:
				if i % 2 == 0:
					_map.draw_line(pa + d * (i / float(n)), pa + d * ((i + 1) / float(n)), col, 3.0, true)


func relayout(p: bool, r: Rect2) -> void:
	if _start_box:
		_start_box.position = Vector2(r.size.x * 0.04, r.size.y * 0.02)
		_start_box.size = Vector2(r.size.x * 0.92, 0)
		return
	if _hud == null:
		return
	_hud.position = Vector2.ZERO
	_hud.size = Vector2(r.size.x, 56)
	_map.position = Vector2(0, 70)
	_map.size = Vector2(r.size.x, r.size.y - 70)
	var rows: Array = chapter.get("map", {}).get("rows", [])
	var n := rows.size()
	for ri in n:
		var row: Array = rows[ri]
		for ci in row.size():
			var nb: NodeButton = _nodes.get(row[ci])
			if nb == null:
				continue
			var s := clampf(minf(_map.size.x, _map.size.y) * 0.13, 70, 120)
			nb.size = Vector2(s, s)
			var along := (ci + 1.0) / (row.size() + 1.0)
			var step := (ri + 0.5) / float(n)
			if p:
				# bottom -> top
				nb.position = Vector2(_map.size.x * along - s / 2.0, _map.size.y * (1.0 - step) - s / 2.0)
			else:
				# left -> right
				nb.position = Vector2(_map.size.x * step - s / 2.0, _map.size.y * along - s / 2.0)
	_map.queue_redraw()


# ---------------------------------------------------------------- node handling

func _open_node(n: Dictionary) -> void:
	if _panel:
		_panel.close()
		_panel = null
	var nb: NodeButton = _nodes[n["id"]]
	if nb.state != "available":
		return
	var mp := ModalPanel.open(self, 620.0, Kyber.C_EMPIRE if n.get("type") == "boss" else Kyber.C_GOLD)
	mp.dismiss_on_backdrop = true
	_panel = mp
	mp.add(UIKit.aurebesh(n.get("type", ""), 18))
	var t := mp.text(n.get("title", "").to_upper(), 30, Kyber.C_GOLD)
	t.add_theme_font_override("font", Kyber.font_title)
	mp.text(n.get("desc", ""), 18)
	match n.get("type", "fight"):
		"event":
			for ch in n.get("event", {}).get("choices", []):
				var b := _wrap_button(ch.get("label", ""), KyberButton.Style.PRIMARY, "event")
				b.pressed.connect(func(): _resolve_event(n, ch))
				mp.add(b)
		"rest":
			var opts: Array = n.get("rest", {}).get("options", ["heal"])
			if "heal" in opts:
				var h := _wrap_button("Repair base (heal 8)", KyberButton.Style.PRIMARY, "heal")
				h.pressed.connect(func(): _finish_simple(n, {"heal": 8}))
				mp.add(h)
			if "upgrade_hp" in opts:
				var u := _wrap_button("Reinforce (+3 max base HP)", KyberButton.Style.GOLD, "sentinel")
				u.pressed.connect(func(): _finish_simple(n, {"base_hp_bonus": 3}))
				mp.add(u)
			if "remove_card" in opts:
				var rm := _wrap_button("Trim your deck (remove a card)", KyberButton.Style.GHOST, "deck")
				rm.pressed.connect(func(): _remove_card_then(n))
				mp.add(rm)
		_:
			var o := Objective.create(n.get("objective", {"type": "standard"}))
			mp.text("Objective: " + o.describe(), 18, Kyber.C_KYBER)
			var en: Dictionary = n.get("enemy", {})
			mp.text("Enemy: %s · %d HP · %s" % [en.get("name", "?"), int(en.get("hp", 12)), en.get("ai_profile", "tempo")], 16, Kyber.C_DIM)
			if n.has("claimable_tokens"):
				var names: Array = []
				for tk in Tokens.resolve(n["claimable_tokens"]):
					names.append(tk.get("name", ""))
				mp.text("Claimable: " + ", ".join(names), 16, Kyber.C_GOLD)
			if n.has("player_preplaced") or n.has("pickup"):
				var allies: Array = []
				for pp in n.get("player_preplaced", []):
					allies.append(CardDB.card(pp["id"]).get("name", ""))
				if allies.size() > 0:
					mp.text("Allies on the field: " + ", ".join(allies), 16, Kyber.C_GOOD)
			var go := _wrap_button("Engage", KyberButton.Style.EMPIRE if n.get("type") == "boss" else KyberButton.Style.PRIMARY, "fight", true)
			go.custom_minimum_size.y = 68
			go.pressed.connect(func(): CampaignFlow.start_node(chapter, n))
			mp.add(go)
	var close := _wrap_button("Back", KyberButton.Style.GHOST)
	close.pressed.connect(func():
		mp.close()
		_panel = null)
	mp.add(close)


func _wrap_button(label: String, style: KyberButton.Style, glyph := "", breathe := false) -> KyberButton:
	var b := KyberButton.make(label, style, glyph, breathe)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.add_theme_font_size_override("font_size", 20)
	return b


func _resolve_event(n: Dictionary, choice: Dictionary) -> void:
	var e: Dictionary = choice.get("effect", {})
	if e.has("remove_card"):
		_remove_card_then(n)
		return
	_finish_simple(n, e)


func _finish_simple(n: Dictionary, e: Dictionary) -> void:
	var msg := CampaignRun.apply_effect(run, chapter, e)
	CampaignRun.complete_node(run, n["id"])
	Save.set_run(run)
	Sfx.play("deploy")
	if msg != "":
		Fx.banner(self, n.get("title", ""), Kyber.C_GOLD, msg)
	await get_tree().create_timer(Kyber.anim(1.0)).timeout
	Router.go("chapter", {"chapter_id": chapter["id"]})


func _remove_card_then(n: Dictionary) -> void:
	_show_deck(run["deck"], func(id: String):
		run["deck"].erase(id)
		_finish_simple(n, {}))


## Deck viewer; with `pick` set, tapping a card selects it. Reflows on rotation.
func _show_deck(ids: Array, pick := Callable()) -> void:
	var mp := ModalPanel.open(self, 2000.0, Kyber.C_GOLD, true)
	var t := mp.text(("Choose a card to remove" if pick.is_valid() else "Deck (%d)" % ids.size()).to_upper(), 28, Kyber.C_GOLD)
	t.add_theme_font_override("font", Kyber.font_title)
	var grid := GridContainer.new()
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	mp.add(grid)
	var close := _wrap_button("Close", KyberButton.Style.GHOST)
	close.pressed.connect(mp.close)
	mp.add(close)
	var fill := func():
		if not is_instance_valid(grid):
			return
		for c in grid.get_children():
			c.queue_free()
		var vs := get_viewport_rect().size
		var cols := 4 if vs.y >= vs.x else 7
		grid.columns = cols
		var sc := (vs.x * 0.94 - 60 - cols * 8) / cols / CardView.PORTRAIT.x
		var sorted := ids.duplicate()
		sorted.sort_custom(func(x, y): return int(CardDB.card(x).get("cost", 0)) < int(CardDB.card(y).get("cost", 0)))
		for id in sorted:
			var slot := Control.new()
			slot.custom_minimum_size = CardView.PORTRAIT * sc
			var cv := CardView.create(id)
			cv.pivot_offset = Vector2.ZERO
			cv.home_scale = Vector2(sc, sc)
			cv.scale = cv.home_scale
			cv.hover_lift = false
			cv.draggable = false
			cv.inspect_requested.connect(func(c): InspectOverlay.open(self, c.card_id, c.get_global_rect()))
			if pick.is_valid():
				cv.tapped.connect(func(_c):
					mp.close()
					pick.call(id))
			else:
				cv.tapped.connect(func(c): InspectOverlay.open(self, c.card_id, c.get_global_rect()))
			slot.add_child(cv)
			grid.add_child(slot)
	fill.call()
	get_viewport().size_changed.connect(fill)
	mp.closed.connect(func(): get_viewport().size_changed.disconnect(fill))


## Animated map node: chamfered badge with type glyph; available nodes pulse.
class NodeButton extends Control:
	signal pressed
	var node_def: Dictionary
	var state := "locked"
	var _t := 0.0
	var _icon: IconGlyph

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		_icon = IconGlyph.new()
		_icon.glyph = node_def.get("glyph", node_def.get("type", "fight"))
		_icon.frame = true
		_icon.pulse = state == "available"
		_icon.spin = state == "available" and node_def.get("type", "") == "boss"
		var col: Color = {"boss": Kyber.C_EMPIRE, "elite": Kyber.C_GOLD, "rest": Kyber.C_GOOD, "event": Kyber.C_KYBER, "objective": Kyber.C_GOLD, "shop": Kyber.C_COST, "treasure": Kyber.C_GOLD}.get(node_def.get("type", ""), Kyber.C_REBEL)
		_icon.color = col if state != "locked" else Color(0.4, 0.45, 0.5)
		add_child(_icon)
		var l := UIKit.label(node_def.get("title", ""), 14, Kyber.C_TEXT if state != "locked" else Kyber.C_DIM, HORIZONTAL_ALIGNMENT_CENTER)
		l.name = "L"
		add_child(l)
		resized.connect(_fit)
		_fit()
		if state == "visited":
			modulate = Color(0.6, 0.7, 0.75)
		mouse_entered.connect(func():
			if state == "available":
				Sfx.play("hover")
				create_tween().tween_property(self, "scale", Vector2(1.1, 1.1), 0.12))
		mouse_exited.connect(func(): create_tween().tween_property(self, "scale", Vector2.ONE, 0.12))

	func _fit() -> void:
		pivot_offset = size / 2.0
		_icon.size = size
		var l: Label = get_node("L")
		l.position = Vector2(-40, size.y + 2)
		l.size = Vector2(size.x + 80, 20)

	func _process(dt: float) -> void:
		if state == "available":
			_t += dt
			queue_redraw()

	func _draw() -> void:
		if state == "available":
			var k := 0.5 + 0.5 * sin(_t * 3.0)
			draw_arc(size / 2.0, size.x * (0.55 + 0.08 * k), 0, TAU, 32, Color(Kyber.C_KYBER, 0.5 * (1.0 - k) + 0.2), 3.0, true)
		elif state == "visited":
			UIKit.draw_fit(self, Kyber.font_title, Vector2(size.x * 0.62, size.y * 0.3), "✓", HORIZONTAL_ALIGNMENT_LEFT, -1, int(size.x * 0.3), Kyber.C_GOOD)

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed:
			Sfx.play("click")
			pressed.emit()
			accept_event()
