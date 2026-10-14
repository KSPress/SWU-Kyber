class_name CardPicker
extends Control
## Radial card menu for choosing a Leader or Base. Cards burst outward from the
## slot that was tapped and settle into a scrollable grid; three aspect filters
## sit at the top and three at the bottom. Tapping aspects filters the cards
## (a card must have every selected aspect) and re-radiates from that icon.
## Tap a card to pick it; long-press / right-click to inspect.

signal picked(id: String)

var kind := "leader"
var filter := {}                 # {"pilot": "only"|"exclude"}
var _origin := Vector2.ZERO
var _all: Array = []
var _sel_aspects: Array = []
var _scroll: ScrollContainer
var _grid: Control
var _top: HBoxContainer
var _bottom: HBoxContainer
var _title: Label
var _count: Label
var _layer: CanvasLayer
var _cards: Array = []


static func open(host: Node, p_kind: String, from_rect: Rect2, p_filter := {}) -> CardPicker:
	var p := CardPicker.new()
	p.kind = p_kind
	p.filter = p_filter
	p._origin = from_rect.get_center()
	p._layer = CanvasLayer.new()
	p._layer.layer = 35
	host.add_child(p._layer)
	p._layer.add_child(p)
	p._build()
	return p


func _build() -> void:
	UIKit.fill_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.01, 0.03, 0.0)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIKit.fill_rect(dim)
	add_child(dim)
	create_tween().tween_property(dim, "color:a", 0.88, Kyber.anim(0.2))
	for id in CardDB.lib.cards:
		var c: Dictionary = CardDB.lib.cards[id]
		if c.get("custom", false) or c.get("type", "") != kind:
			continue
		if filter.get("pilot", "") == "exclude" and "pilot" in c.get("traits", []):
			continue
		if filter.get("pilot", "") == "only" and not ("pilot" in c.get("traits", [])):
			continue
		_all.append(id)
	_all.sort_custom(func(a, b): return CardDB.card(a).get("name", "") < CardDB.card(b).get("name", ""))
	_title = UIKit.title("Choose a %s" % kind, 28, Kyber.C_GOLD)
	add_child(_title)
	_count = UIKit.label("", 15, Kyber.C_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	add_child(_count)
	_top = _aspect_row(["vigilance", "command", "aggression"])
	_bottom = _aspect_row(["cunning", "heroism", "villainy"])
	add_child(_top)
	add_child(_bottom)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_grid = Control.new()
	_grid.mouse_filter = Control.MOUSE_FILTER_PASS
	_scroll.add_child(_grid)
	var close := KyberButton.make("", KyberButton.Style.GHOST, "back")
	close.custom_minimum_size = Vector2(60, 56)
	close.name = "Close"
	close.pressed.connect(close_picker)
	add_child(close)
	get_viewport().size_changed.connect(func(): _layout(); _place(false))
	_layout()
	_populate(_origin)
	Sfx.play("whoosh", 1.3)


func _aspect_row(list: Array) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 22)
	for a in list:
		var ic := AspectIcon.make(a, 54.0, true)
		ic.pressed.connect(_on_aspect)
		h.add_child(ic)
	return h


func _layout() -> void:
	var vs := get_viewport_rect().size
	_title.position = Vector2(0, 10)
	_title.size = Vector2(vs.x, 40)
	_top.position = Vector2(0, 54)
	_top.size = Vector2(vs.x, 60)
	_bottom.position = Vector2(0, vs.y - 74)
	_bottom.size = Vector2(vs.x, 60)
	_count.position = Vector2(0, vs.y - 100)
	_count.size = Vector2(vs.x, 22)
	_scroll.position = Vector2(vs.x * 0.03, 124)
	_scroll.size = Vector2(vs.x * 0.94, vs.y - 124 - 108)
	var close: Control = get_node("Close")
	close.position = Vector2(12, 8)


func _on_aspect(a: String) -> void:
	if a in _sel_aspects:
		_sel_aspects.erase(a)
	else:
		_sel_aspects.append(a)
	var from := _origin
	for row in [_top, _bottom]:
		for ic in row.get_children():
			if ic.aspect == a:
				from = ic.get_global_rect().get_center()
	_populate(from)


func _visible_ids() -> Array:
	var out: Array = []
	for id in _all:
		var asp: Array = CardDB.card(id).get("aspects", [])
		var ok := true
		for a in _sel_aspects:
			if not (a in asp):
				ok = false
		if ok:
			out.append(id)
	return out


func _cell() -> Vector2:
	var vs := get_viewport_rect().size
	var cols := 2 if vs.y >= vs.x else 4
	var w := (_scroll.size.x - 16 - (cols - 1) * 12) / cols
	var base := CardView.LANDSCAPE
	var sc := w / base.x
	return Vector2(w, base.y * sc)


func _populate(from: Vector2) -> void:
	for c in _cards:
		c.queue_free()
	_cards.clear()
	var ids := _visible_ids()
	_count.text = "%d %ss%s" % [ids.size(), kind, ("  ·  " + ", ".join(_sel_aspects).capitalize()) if _sel_aspects.size() > 0 else ""]
	for id in ids:
		var cv := CardView.create(id)
		cv.hover_lift = false
		cv.draggable = false
		cv.pivot_offset = Vector2.ZERO
		cv.tapped.connect(func(_c): _choose(id, cv))
		cv.inspect_requested.connect(func(c): InspectOverlay.open(self, c.card_id, c.get_global_rect()))
		_grid.add_child(cv)
		_cards.append(cv)
	_place(true, from)


func _place(animate: bool, from := Vector2.ZERO) -> void:
	var cell := _cell()
	var vs := get_viewport_rect().size
	var cols := 2 if vs.y >= vs.x else 4
	var i := 0
	var local_from := from - _grid.global_position
	for cv in _cards:
		var col := i % cols
		var row := i / cols
		var cs: Vector2 = cv.base_size()
		var sc := minf(cell.x / cs.x, cell.y / cs.y)
		var slot := Vector2(col * (cell.x + 12) + 8 + (cell.x - cs.x * sc) / 2.0, row * (cell.y + 12) + 8)
		cv.home_pos = slot
		cv.home_scale = Vector2(sc, sc)
		if animate:
			# radiate out from the tapped slot: nearer cards arrive first
			var d := slot.distance_to(local_from)
			cv.position = local_from - cs * sc * 0.05
			cv.scale = Vector2(sc * 0.1, sc * 0.1)
			cv.rotation = randf_range(-0.6, 0.6)
			cv.modulate.a = 0.0
			var delay := minf(d / 2600.0, 0.45)
			var tw: Tween = cv.create_tween().set_parallel(true)
			tw.tween_property(cv, "position", slot, Kyber.anim(0.38)).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(cv, "scale", Vector2(sc, sc), Kyber.anim(0.38)).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(cv, "rotation", 0.0, Kyber.anim(0.38)).set_delay(delay)
			tw.tween_property(cv, "modulate:a", 1.0, Kyber.anim(0.15)).set_delay(delay)
		else:
			cv.position = slot
			cv.scale = Vector2(sc, sc)
		i += 1
	var rows := ceili(_cards.size() / float(cols))
	_grid.custom_minimum_size = Vector2(_scroll.size.x - 12, rows * (cell.y + 12) + 16)


func _choose(id: String, cv: CardView) -> void:
	Sfx.play("deploy", 1.3)
	var tw := cv.create_tween()
	tw.tween_property(cv, "scale", cv.scale * 1.12, 0.08)
	tw.tween_property(cv, "scale", cv.scale, 0.12)
	await tw.finished
	picked.emit(id)
	close_picker()


func close_picker() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# collapse back toward the origin
	var local := _origin - _grid.global_position
	for cv in _cards:
		var tw: Tween = cv.create_tween().set_parallel(true)
		tw.tween_property(cv, "position", local, Kyber.anim(0.2)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(cv, "scale", cv.scale * 0.1, Kyber.anim(0.2))
	var t2 := create_tween()
	t2.tween_property(self, "modulate:a", 0.0, Kyber.anim(0.22))
	await t2.finished
	if is_instance_valid(_layer):
		_layer.queue_free()
