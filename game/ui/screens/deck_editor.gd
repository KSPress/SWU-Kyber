extends ScreenBase
## Deck editor: leader + base (radial pickers), name, icon, favourite mark and
## the deck's aspect icons on top; card pool on one side, the deck list with
## curve and legality on the other (tabs in portrait, split in landscape).
## Tap a pool card to add it (max 3), tap -/+ in the list to adjust.

var deck: Dictionary
var dirty := false

var _ident: HBoxContainer
var _leader_slot: SlotCard
var _base_slot: SlotCard
var _name_edit: LineEdit
var _icon_btn: KyberButton
var _mark_btn: KyberButton
var _aspect_box: HBoxContainer
var _tabs: HBoxContainer
var _tab_pool: KyberButton
var _tab_deck: KyberButton
var _pool: Control
var _deck_panel: Control
var _search: LineEdit
var _type := ""
var _my_aspects := true
var _unlocked_only := false
var _pool_grid: GridContainer
var _page := 0
var _results: Array = []
var _page_label: Label
var _list_box: VBoxContainer
var _summary: Label
var _curve: CurveBars
var _problems: Label
var _save_btn: KyberButton
var _show_pool := true
var _per_page := 8
var _cols := 4


func build() -> void:
	var id: String = Router.params.get("deck_id", "")
	deck = Save.get_deck(id).duplicate(true) if id != "" else {}
	if deck.is_empty():
		deck = {"id": "", "name": "New deck", "icon": "star", "marked": false, "leader": "", "base": "", "cards": {}}
	set_header("Deck Editor", "decks")
	# identity row
	_ident = HBoxContainer.new()
	_ident.add_theme_constant_override("separation", 10)
	body.add_child(_ident)
	_leader_slot = SlotCard.new()
	_leader_slot.kind = "leader"
	_leader_slot.pressed.connect(func(): _pick("leader"))
	_ident.add_child(_leader_slot)
	_base_slot = SlotCard.new()
	_base_slot.kind = "base"
	_base_slot.pressed.connect(func(): _pick("base"))
	_ident.add_child(_base_slot)
	var meta := VBoxContainer.new()
	meta.add_theme_constant_override("separation", 6)
	meta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ident.add_child(meta)
	_name_edit = LineEdit.new()
	_name_edit.text = deck.get("name", "")
	_name_edit.placeholder_text = "Deck name"
	_name_edit.custom_minimum_size.y = 48
	_name_edit.text_changed.connect(func(t): deck["name"] = t; dirty = true)
	meta.add_child(_name_edit)
	var row := HBoxContainer.new()
	row.name = "MetaRow"
	row.add_theme_constant_override("separation", 8)
	body.add_child(row)
	_icon_btn = KyberButton.make("", KyberButton.Style.GHOST, deck.get("icon", "star"))
	_icon_btn.custom_minimum_size = Vector2(56, 52)
	_icon_btn.tooltip_text = "Deck icon"
	_icon_btn.pressed.connect(_pick_icon)
	row.add_child(_icon_btn)
	_mark_btn = KyberButton.make("", KyberButton.Style.GOLD if deck.get("marked", false) else KyberButton.Style.GHOST, "star")
	_mark_btn.custom_minimum_size = Vector2(56, 52)
	_mark_btn.tooltip_text = "Mark as favourite"
	_mark_btn.pressed.connect(_toggle_mark)
	row.add_child(_mark_btn)
	_aspect_box = HBoxContainer.new()
	_aspect_box.add_theme_constant_override("separation", 4)
	row.add_child(_aspect_box)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_save_btn = KyberButton.make("Save", KyberButton.Style.PRIMARY, "", true)
	_save_btn.custom_minimum_size = Vector2(110, 52)
	_save_btn.pressed.connect(_save)
	row.add_child(_save_btn)
	# tabs (portrait)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 8)
	_tab_pool = KyberButton.make("Cards", KyberButton.Style.PRIMARY)
	_tab_pool.pressed.connect(func(): _show_pool = true; _on_resize())
	_tab_deck = KyberButton.make("Deck", KyberButton.Style.GHOST)
	_tab_deck.pressed.connect(func(): _show_pool = false; _on_resize())
	_tab_pool.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_deck.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.add_child(_tab_pool)
	_tabs.add_child(_tab_deck)
	body.add_child(_tabs)
	_build_pool()
	_build_deck_panel()
	_refresh_identity()
	_refresh_pool()
	_refresh_list()


# ---------------------------------------------------------------- pool

func _build_pool() -> void:
	_pool = Control.new()
	body.add_child(_pool)
	var v := VBoxContainer.new()
	v.name = "V"
	v.add_theme_constant_override("separation", 6)
	_pool.add_child(v)
	_search = LineEdit.new()
	_search.placeholder_text = "Search name, trait or text…"
	_search.custom_minimum_size.y = 46
	_search.text_changed.connect(func(_t): _page = 0; _refresh_pool())
	v.add_child(_search)
	var f := HBoxContainer.new()
	f.add_theme_constant_override("separation", 6)
	v.add_child(f)
	for t in [["All", ""], ["Units", "unit"], ["Events", "event"], ["Upgrades", "upgrade"]]:
		var b := KyberButton.make(t[0], KyberButton.Style.GHOST)
		b.custom_minimum_size = Vector2(0, 42)
		b.add_theme_font_size_override("font_size", 16)
		var val: String = t[1]
		b.pressed.connect(func(): _type = val; _page = 0; _refresh_pool())
		f.add_child(b)
	var f2 := HBoxContainer.new()
	f2.add_theme_constant_override("separation", 6)
	v.add_child(f2)
	var mine := CheckButton.new()
	mine.text = "In my aspects"
	mine.button_pressed = _my_aspects
	mine.toggled.connect(func(on): _my_aspects = on; _page = 0; _refresh_pool())
	f2.add_child(mine)
	var unl := CheckButton.new()
	unl.text = "Unlocked only"
	unl.toggled.connect(func(on): _unlocked_only = on; _page = 0; _refresh_pool())
	f2.add_child(unl)
	_pool_grid = GridContainer.new()
	_pool_grid.add_theme_constant_override("h_separation", 8)
	_pool_grid.add_theme_constant_override("v_separation", 8)
	_pool_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_pool_grid)
	var pager := HBoxContainer.new()
	pager.alignment = BoxContainer.ALIGNMENT_CENTER
	pager.add_theme_constant_override("separation", 12)
	var prev := KyberButton.make("‹", KyberButton.Style.GHOST)
	prev.custom_minimum_size = Vector2(64, 48)
	prev.pressed.connect(func(): _page = maxi(0, _page - 1); _show_page())
	var nxt := KyberButton.make("›", KyberButton.Style.GHOST)
	nxt.custom_minimum_size = Vector2(64, 48)
	nxt.pressed.connect(func(): _page = mini(_pages() - 1, _page + 1); _show_page())
	_page_label = UIKit.label("", 16, Kyber.C_DIM)
	pager.add_child(prev)
	pager.add_child(_page_label)
	pager.add_child(nxt)
	v.add_child(pager)


func _deck_aspects() -> Array:
	var out: Array = []
	for id in [deck.get("leader", ""), deck.get("base", "")]:
		out.append_array(CardDB.card(id).get("aspects", []))
	return out


func _refresh_pool() -> void:
	var f := {"type": _type}
	if _unlocked_only:
		f["ids"] = Save.data.get("vault", [])
	var res := CardDB.lib.query(_search.text, f)
	var asp := _deck_aspects()
	var hero := "heroism" in asp
	var vill := "villainy" in asp
	_results.clear()
	for id in res:
		var c := CardDB.card(id)
		if not (c.get("type", "") in ["unit", "event", "upgrade"]):
			continue
		if _my_aspects and asp.size() > 0:
			var ok := true
			for a in c.get("aspects", []):
				if not (a in asp):
					ok = false
			if not ok:
				continue
		elif (hero and "villainy" in c.get("aspects", [])) or (vill and "heroism" in c.get("aspects", [])):
			pass
		_results.append(id)
	_results.sort_custom(func(a, b):
		var ca := CardDB.card(a)
		var cb := CardDB.card(b)
		if int(ca.get("cost", 0)) != int(cb.get("cost", 0)):
			return int(ca.get("cost", 0)) < int(cb.get("cost", 0))
		return ca.get("name", "") < cb.get("name", ""))
	_page = mini(_page, _pages() - 1)
	_show_page()


func _pages() -> int:
	return maxi(1, ceili(_results.size() / float(_per_page)))


## Effective cost with aspect penalties (+2 per icon the leader/base don't cover).
func _cost_with_penalty(c: Dictionary) -> int:
	var pool := _deck_aspects()
	var cost := int(c.get("cost", 0))
	for a in c.get("aspects", []):
		var i := pool.find(a)
		if i >= 0:
			pool.remove_at(i)
		else:
			cost += 2
	return cost


func _show_page() -> void:
	for c in _pool_grid.get_children():
		c.queue_free()
	_pool_grid.columns = _cols
	var avail_w := _pool.size.x - (_cols - 1) * 8
	var rows := ceili(_per_page / float(_cols))
	var avail_h := _pool.size.y - 46 - 48 - 46 - 56 - 30 - (rows - 1) * 8
	var sc := maxf(0.2, minf(avail_w / _cols / CardView.PORTRAIT.x, avail_h / rows / CardView.PORTRAIT.y))
	var start := _page * _per_page
	for id in _results.slice(start, start + _per_page):
		var slot := Control.new()
		slot.custom_minimum_size = CardView.PORTRAIT * sc
		var cv := CardView.create(id)
		cv.pivot_offset = Vector2.ZERO
		cv.home_scale = Vector2(sc, sc)
		cv.scale = cv.home_scale
		cv.hover_lift = false
		cv.draggable = false
		var c := CardDB.card(id)
		if deck.get("leader", "") != "":
			cv.cost_override = _cost_with_penalty(c)
		cv.tapped.connect(func(x): _add(id, x))
		cv.inspect_requested.connect(func(x): InspectOverlay.open(self, x.card_id, x.get_global_rect()))
		slot.add_child(cv)
		var badge := CountBadge.new()
		badge.count = int(deck["cards"].get(id, 0))
		badge.position = Vector2(CardView.PORTRAIT.x * sc - 34, CardView.PORTRAIT.y * sc - 34)
		badge.name = "Badge"
		slot.add_child(badge)
		slot.set_meta("id", id)
		_pool_grid.add_child(slot)
	_page_label.text = "%d / %d  ·  %d cards" % [_page + 1, _pages(), _results.size()]


func _add(id: String, cv: CardView) -> void:
	var n := int(deck["cards"].get(id, 0))
	if n >= 3:
		Fx.float_text(self, cv.get_global_rect().get_center(), "Max 3", Kyber.C_EMPIRE, 26)
		return
	deck["cards"][id] = n + 1
	dirty = true
	Sfx.play("draw", 1.2)
	# little fly-to-deck flourish
	var ghost := CardView.create(id)
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ghost)
	ghost.pivot_offset = Vector2.ZERO
	ghost.global_position = cv.global_position
	ghost.scale = cv.scale
	var target := _tab_deck.get_global_rect().get_center() if portrait else _deck_panel.get_global_rect().get_center()
	var tw := ghost.create_tween().set_parallel(true)
	tw.tween_property(ghost, "global_position", target, Kyber.anim(0.3)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(ghost, "scale", cv.scale * 0.2, Kyber.anim(0.3))
	tw.chain().tween_callback(ghost.queue_free)
	for slot in _pool_grid.get_children():
		if slot.get_meta("id", "") == id:
			(slot.get_node("Badge") as CountBadge).count = n + 1
	_refresh_list()


func _remove(id: String) -> void:
	var n := int(deck["cards"].get(id, 0))
	if n <= 1:
		deck["cards"].erase(id)
	else:
		deck["cards"][id] = n - 1
	dirty = true
	Sfx.play("click")
	for slot in _pool_grid.get_children():
		if slot.get_meta("id", "") == id:
			(slot.get_node("Badge") as CountBadge).count = maxi(0, n - 1)
	_refresh_list()


# ---------------------------------------------------------------- deck list

func _build_deck_panel() -> void:
	_deck_panel = UIKit.panel(Color(Kyber.C_PANEL, 0.92), Kyber.C_LINE, 12, 0)
	body.add_child(_deck_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_deck_panel.add_child(v)
	_summary = UIKit.label("", 18, Kyber.C_TEXT)
	v.add_child(_summary)
	_curve = CurveBars.new()
	_curve.custom_minimum_size = Vector2(0, 70)
	v.add_child(_curve)
	_problems = UIKit.label("", 14, Kyber.C_GOLD)
	_problems.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_problems)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 4)
	scroll.add_child(_list_box)


func _refresh_list() -> void:
	for c in _list_box.get_children():
		c.queue_free()
	var ids: Array = deck["cards"].keys()
	ids.sort_custom(func(a, b):
		var ca := CardDB.card(a)
		var cb := CardDB.card(b)
		if int(ca.get("cost", 0)) != int(cb.get("cost", 0)):
			return int(ca.get("cost", 0)) < int(cb.get("cost", 0))
		return ca.get("name", "") < cb.get("name", ""))
	var counts := {"unit": 0, "event": 0, "upgrade": 0}
	var curve := [0, 0, 0, 0, 0, 0, 0, 0]
	var total := 0
	for id in ids:
		var c := CardDB.card(id)
		var n := int(deck["cards"][id])
		total += n
		var t: String = c.get("type", "")
		counts[t] = int(counts.get(t, 0)) + n
		curve[mini(int(c.get("cost", 0)), 7)] += n
		_list_box.add_child(_row(id, c, n))
	_summary.text = "%d / 50 cards   ·   %d units · %d events · %d upgrades" % [total, counts["unit"], counts["event"], counts["upgrade"]]
	_summary.add_theme_color_override("font_color", Kyber.C_GOOD if total >= 50 else Kyber.C_TEXT)
	_curve.values = curve
	_curve.queue_redraw()
	var errs: Array = []
	if deck.get("leader", "") == "":
		errs.append("Choose a leader.")
	if deck.get("base", "") == "":
		errs.append("Choose a base.")
	if errs.is_empty():
		errs = DeckBuilder.validate(CardDB.lib, RuleSet.premier(), deck["leader"], deck["base"], Save.deck_list(deck))
	_problems.text = "✓ Legal Premier deck" if errs.is_empty() else "\n".join(errs.slice(0, 4))
	_problems.add_theme_color_override("font_color", Kyber.C_GOOD if errs.is_empty() else Kyber.C_GOLD)
	_tab_deck.text = "Deck (%d)" % total


func _row(id: String, c: Dictionary, n: int) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var cost := UIKit.label(str(int(c.get("cost", 0))), 18, Kyber.C_COST, HORIZONTAL_ALIGNMENT_CENTER)
	cost.custom_minimum_size.x = 28
	h.add_child(cost)
	for a in c.get("aspects", []):
		h.add_child(AspectIcon.make(a, 20.0))
	var nm := UIKit.label(c.get("name", id) + (" — " + c.get("subtitle", "") if c.get("subtitle", "") != "" else ""), 16, Kyber.C_TEXT)
	nm.clip_text = true
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.mouse_filter = Control.MOUSE_FILTER_STOP
	nm.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed:
			InspectOverlay.open(self, id, nm.get_global_rect()))
	h.add_child(nm)
	var cnt := UIKit.label("×%d" % n, 18, Kyber.C_KYBER)
	h.add_child(cnt)
	var minus := KyberButton.make("−", KyberButton.Style.GHOST)
	minus.custom_minimum_size = Vector2(44, 40)
	minus.pressed.connect(func(): _remove(id))
	h.add_child(minus)
	var plus := KyberButton.make("+", KyberButton.Style.GHOST)
	plus.custom_minimum_size = Vector2(44, 40)
	plus.pressed.connect(func():
		if int(deck["cards"].get(id, 0)) < 3:
			deck["cards"][id] = int(deck["cards"].get(id, 0)) + 1
			dirty = true
			Sfx.play("draw", 1.2)
			_refresh_list()
			_show_page())
	h.add_child(plus)
	return h


# ---------------------------------------------------------------- identity

func _refresh_identity() -> void:
	_leader_slot.set_card(deck.get("leader", ""))
	_base_slot.set_card(deck.get("base", ""))
	for c in _aspect_box.get_children():
		c.queue_free()
	var row := AspectIcon.row_for(deck.get("leader", ""), deck.get("base", ""), 34.0)
	for c in row.get_children():
		row.remove_child(c)
		_aspect_box.add_child(c)
		UIKit.pop_in(c)
	row.queue_free()


func _pick(kind: String) -> void:
	var slot: Control = _leader_slot if kind == "leader" else _base_slot
	var picker := CardPicker.open(self, kind, slot.get_global_rect())
	picker.picked.connect(func(id: String):
		deck[kind] = id
		if kind == "leader" and deck.get("name", "") in ["", "New deck"]:
			deck["name"] = CardDB.card(id).get("name", "Deck")
			_name_edit.text = deck["name"]
		dirty = true
		_refresh_identity()
		_refresh_pool()
		_refresh_list())


func _pick_icon() -> void:
	var mp := ModalPanel.open(self, 520.0, Kyber.C_KYBER)
	mp.dismiss_on_backdrop = true
	mp.text("DECK ICON", 24, Kyber.C_KYBER)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	mp.add(grid)
	for g in Kyber.DECK_ICONS:
		var b := KyberButton.make("", KyberButton.Style.GOLD if g == deck.get("icon", "") else KyberButton.Style.GHOST, g)
		b.custom_minimum_size = Vector2(64, 60)
		b.tooltip_text = g.capitalize()
		b.pressed.connect(func():
			deck["icon"] = g
			dirty = true
			_icon_btn.glyph = g
			if _icon_btn._icon:
				_icon_btn._icon.glyph = g
			mp.close())
		grid.add_child(b)


func _toggle_mark() -> void:
	deck["marked"] = not deck.get("marked", false)
	dirty = true
	if _mark_btn._icon:
		_mark_btn._icon.color = Kyber.C_GOLD if deck["marked"] else Kyber.C_LINE.lightened(0.3)
	Fx.float_text(self, _mark_btn.get_global_rect().get_center(), "Marked" if deck["marked"] else "Unmarked", Kyber.C_GOLD, 22)


func _save() -> void:
	if deck.get("name", "").strip_edges() == "":
		deck["name"] = "Untitled deck"
	Save.save_deck(deck)
	dirty = false
	Sfx.play("deploy", 1.2)
	Fx.float_text(self, _save_btn.get_global_rect().get_center(), "Saved", Kyber.C_GOOD, 26)


# ---------------------------------------------------------------- layout

func relayout(p: bool, r: Rect2) -> void:
	var ident_h := 96.0 if p else 120.0
	_ident.position = Vector2.ZERO
	_ident.size = Vector2(r.size.x, ident_h)
	_leader_slot.custom_minimum_size = Vector2(ident_h * 1.4, ident_h)
	_base_slot.custom_minimum_size = Vector2(ident_h * 1.4, ident_h)
	var meta_row: Control = body.get_node("MetaRow")
	meta_row.position = Vector2(0, ident_h + 8)
	meta_row.size = Vector2(r.size.x, 52)
	var top := ident_h + 70
	if p:
		_tabs.visible = true
		_tabs.position = Vector2(0, top)
		_tabs.size = Vector2(r.size.x, 52)
		top += 60
		_pool.visible = _show_pool
		_deck_panel.visible = not _show_pool
		_pool.position = Vector2(0, top)
		_pool.size = Vector2(r.size.x, r.size.y - top)
		_deck_panel.position = Vector2(0, top)
		_deck_panel.size = Vector2(r.size.x, r.size.y - top)
		_cols = 3
		_per_page = 6
	else:
		_tabs.visible = false
		_pool.visible = true
		_deck_panel.visible = true
		var pw := r.size.x * 0.6
		_pool.position = Vector2(0, top)
		_pool.size = Vector2(pw - 10, r.size.y - top)
		_deck_panel.position = Vector2(pw, top)
		_deck_panel.size = Vector2(r.size.x - pw, r.size.y - top)
		_cols = 5
		_per_page = 5
	var v: Control = _pool.get_node("V")
	v.position = Vector2.ZERO
	v.size = _pool.size
	if _tab_pool:
		_tab_pool.style = KyberButton.Style.PRIMARY if _show_pool else KyberButton.Style.GHOST
	if _results.size() > 0:
		_show_page()


## Leader/base slot: shows the chosen card (or an empty dashed frame).
class SlotCard extends Control:
	signal pressed
	var kind := "leader"
	var _tex: Texture2D
	var _id := ""
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func set_card(id: String) -> void:
		_id = id
		_tex = null
		if id != "":
			var t := Art.request(CardDB.card(id).get("art", id), func(tx): _tex = tx; queue_redraw())
			if t:
				_tex = t
		queue_redraw()

	func _process(dt: float) -> void:
		if _id == "":
			_t += dt
			queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		if _tex and _tex != Art.placeholder:
			draw_texture_rect(_tex, r, false)
		else:
			var k := 0.5 + 0.5 * sin(_t * 3.0)
			draw_rect(r, Color(0.04, 0.07, 0.1, 0.9))
			draw_rect(r, Color(Kyber.C_KYBER, 0.4 + 0.4 * k), false, 2.0)
			UIKit.draw_fit(self, Kyber.font_title, Vector2(0, size.y / 2.0 + 8), "+ " + kind.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, size.x, 20, Kyber.C_KYBER)

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			Sfx.play("click")
			pressed.emit()
			accept_event()


## Small "×N" pip over pool cards already in the deck.
class CountBadge extends Control:
	var count := 0:
		set(v):
			count = v
			visible = v > 0
			queue_redraw()

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size = Vector2(30, 30)
		visible = count > 0

	func _draw() -> void:
		draw_circle(Vector2(15, 15), 15, Kyber.C_KYBER)
		UIKit.draw_fit(self, Kyber.font_title, Vector2(0, 22), "×%d" % count, HORIZONTAL_ALIGNMENT_CENTER, 30, 16, Color.BLACK)


## Mana-curve bars 0..7+.
class CurveBars extends Control:
	var values: Array = [0, 0, 0, 0, 0, 0, 0, 0]

	func _draw() -> void:
		var mx := 1
		for v in values:
			mx = maxi(mx, int(v))
		var w := size.x / values.size()
		for i in values.size():
			var h := (size.y - 18) * float(values[i]) / mx
			draw_rect(Rect2(Vector2(i * w + 4, size.y - 18 - h), Vector2(w - 8, h)), Kyber.C_COST)
			UIKit.draw_fit(self, Kyber.font_title, Vector2(i * w, size.y - 2), str(i) + ("+" if i == 7 else ""), HORIZONTAL_ALIGNMENT_CENTER, w, 13, Kyber.C_DIM)
			if values[i] > 0:
				UIKit.draw_fit(self, Kyber.font_title, Vector2(i * w, size.y - 22 - h), str(values[i]), HORIZONTAL_ALIGNMENT_CENTER, w, 12, Kyber.C_TEXT)
