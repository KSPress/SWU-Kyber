extends ScreenBase
## Collection Vault: browse every imported card (or only unlocked ones), search,
## filter by type/aspect/set, inspect, and drag cards around for fun.

const PAGE_PORTRAIT := 12
const PAGE_LANDSCAPE := 18

var _search: LineEdit
var _filters: HBoxContainer
var _aspects: HBoxContainer
var _set_opt: OptionButton
var _grid: GridContainer
var _pager: HBoxContainer
var _page_label: Label
var _results: Array = []
var _page := 0
var _type := ""
var _aspect := ""
var _set := ""
var _unlocked_only := false
var _count: Label


func build() -> void:
	set_header("Collection Vault")
	_search = LineEdit.new()
	_search.placeholder_text = "Search name, trait or text…"
	_search.custom_minimum_size.y = 52
	_search.text_changed.connect(func(_t): _page = 0; _refresh())
	body.add_child(_search)
	_filters = HBoxContainer.new()
	_filters.add_theme_constant_override("separation", 6)
	body.add_child(_filters)
	for t in [["All", ""], ["Units", "unit"], ["Events", "event"], ["Upgrades", "upgrade"], ["Leaders", "leader"], ["Bases", "base"]]:
		var b := KyberButton.make(t[0], KyberButton.Style.GHOST)
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(0, 46)
		b.add_theme_font_size_override("font_size", 16)
		b.button_pressed = t[1] == _type
		var val: String = t[1]
		b.pressed.connect(func(): _type = val; _page = 0; _sync_toggles(); _refresh())
		b.set_meta("val", val)
		_filters.add_child(b)
	_aspects = HBoxContainer.new()
	_aspects.add_theme_constant_override("separation", 6)
	body.add_child(_aspects)
	for a in ["vigilance", "command", "aggression", "cunning", "heroism", "villainy"]:
		var chip := AspectChip.new()
		chip.aspect = a
		chip.custom_minimum_size = Vector2(46, 46)
		chip.pressed.connect(func():
			_aspect = "" if _aspect == a else a
			for c in _aspects.get_children():
				if c is AspectChip:
					c.on = c.aspect == _aspect
			_page = 0
			_refresh())
		_aspects.add_child(chip)
	_set_opt = OptionButton.new()
	_set_opt.add_item("All sets")
	var sets := {}
	for id in CardDB.lib.cards:
		if not CardDB.lib.cards[id].get("custom", false):
			sets[CardDB.lib.cards[id].get("set", "")] = true
	var keys := sets.keys()
	keys.sort()
	for s in keys:
		_set_opt.add_item(s)
	_set_opt.item_selected.connect(func(i): _set = "" if i == 0 else _set_opt.get_item_text(i); _page = 0; _refresh())
	_aspects.add_child(_set_opt)
	var unl := KyberButton.make("Unlocked only", KyberButton.Style.GOLD)
	unl.toggle_mode = true
	unl.custom_minimum_size = Vector2(0, 46)
	unl.add_theme_font_size_override("font_size", 16)
	unl.toggled.connect(func(on): _unlocked_only = on; _page = 0; _refresh())
	_aspects.add_child(unl)
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	body.add_child(_grid)
	_pager = HBoxContainer.new()
	_pager.alignment = BoxContainer.ALIGNMENT_CENTER
	_pager.add_theme_constant_override("separation", 16)
	var prev := KyberButton.make("‹ Prev", KyberButton.Style.GHOST)
	prev.pressed.connect(func(): _page = maxi(0, _page - 1); _show_page())
	var nxt := KyberButton.make("Next ›", KyberButton.Style.GHOST)
	nxt.pressed.connect(func(): _page = mini(_pages() - 1, _page + 1); _show_page())
	_page_label = UIKit.label("", 18, Kyber.C_DIM)
	_pager.add_child(prev)
	_pager.add_child(_page_label)
	_pager.add_child(nxt)
	body.add_child(_pager)
	_count = UIKit.label("", 15, Kyber.C_DIM)
	body.add_child(_count)
	_refresh()


func _sync_toggles() -> void:
	for c in _filters.get_children():
		(c as Button).button_pressed = c.get_meta("val") == _type


var _rows := 3
var _cols := 4


func _per_page() -> int:
	return _rows * _cols


func _pages() -> int:
	return maxi(1, ceili(_results.size() / float(_per_page())))


func _refresh() -> void:
	var f := {"type": _type, "aspect": _aspect, "set": _set}
	if _unlocked_only:
		f["ids"] = Save.data.get("vault", [])
	_results = CardDB.lib.query(_search.text if _search else "", f)
	_show_page()


func _show_page() -> void:
	for c in _grid.get_children():
		c.queue_free()
	var per := _per_page()
	var start := _page * per
	var cols := _cols
	var rows := _rows
	var avail_w := body.size.x - (cols - 1) * 10
	var avail_h := body.size.y - _grid.position.y - 96
	var sc := minf(avail_w / cols / CardView.PORTRAIT.x, (avail_h - (rows - 1) * 10) / rows / CardView.PORTRAIT.y)
	var i := 0
	for id in _results.slice(start, start + per):
		var slot := Control.new()
		slot.custom_minimum_size = CardView.PORTRAIT * sc
		var cv := CardView.create(id)
		var land := cv.is_landscape()
		var csc := sc * (CardView.PORTRAIT.x / CardView.LANDSCAPE.x) if land else sc
		cv.pivot_offset = Vector2.ZERO
		cv.home_scale = Vector2(csc, csc)
		cv.scale = cv.home_scale
		cv.home_pos = Vector2(0, (CardView.PORTRAIT.y * sc - cv.size.y * csc) / 2.0) if land else Vector2.ZERO
		cv.position = cv.home_pos
		cv.hover_lift = false
		cv.drag_released.connect(func(c, _p): c.spring_home())
		cv.tapped.connect(func(c): InspectOverlay.open(self, c.card_id, c.get_global_rect()))
		cv.inspect_requested.connect(func(c): InspectOverlay.open(self, c.card_id, c.get_global_rect()))
		if _unlocked_only == false and not (id in Save.data.get("vault", [])):
			cv.modulate = Color(0.85, 0.85, 0.9)
		slot.add_child(cv)
		_grid.add_child(slot)
		UIKit.pop_in(cv, i * 0.02)
		i += 1
	_page_label.text = "Page %d / %d" % [_page + 1, _pages()]
	_count.text = "%d cards · %d unlocked in vault" % [_results.size(), Save.data.get("vault", []).size()]


func relayout(p: bool, r: Rect2) -> void:
	var top := 172.0
	if p:
		_search.position = Vector2.ZERO
		_search.size = Vector2(r.size.x, 52)
		_filters.position = Vector2(0, 60)
		_filters.size = Vector2(r.size.x, 46)
		_aspects.position = Vector2(0, 114)
		_aspects.size = Vector2(r.size.x, 46)
	else:
		# one compact row: search | type filters, then aspects/sets
		var sw := r.size.x * 0.32
		_search.position = Vector2.ZERO
		_search.size = Vector2(sw, 52)
		_filters.position = Vector2(sw + 12, 3)
		_filters.size = Vector2(r.size.x - sw - 12, 46)
		_aspects.position = Vector2(0, 60)
		_aspects.size = Vector2(r.size.x, 46)
		top = 116.0
	_grid.position = Vector2(0, top)
	# as many readable cards (>= ~230 px tall) as fit
	var avail_h := r.size.y - top - 96
	_rows = clampi(int(avail_h / 180.0), 1, 3)
	var card_h := (avail_h - (_rows - 1) * 10) / _rows
	var card_w := card_h * CardView.PORTRAIT.x / CardView.PORTRAIT.y
	_cols = clampi(int((r.size.x + 10) / (card_w + 10)), 2, 8)
	_grid.columns = _cols
	_grid.size = Vector2(r.size.x, avail_h)
	_pager.position = Vector2(0, r.size.y - 60)
	_pager.size = Vector2(r.size.x, 56)
	_count.position = Vector2(0, r.size.y - 86)
	_page = mini(_page, _pages() - 1)
	if _results.size() > 0:
		_show_page()


class AspectChip extends Control:
	signal pressed
	var aspect := ""
	var on := false:
		set(v):
			on = v
			queue_redraw()

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		tooltip_text = aspect.capitalize()

	func _draw() -> void:
		var s := minf(size.x, size.y)
		var box := Rect2((size - Vector2(s * 0.91, s)) / 2.0, Vector2(s * 0.91, s))
		var tex := AspectIcon.texture(aspect)
		if on:
			draw_rect(box.grow(3), Color(Kyber.C_GOLD, 0.8), false, 3.0)
		if tex:
			draw_texture_rect(tex, box, false, Color.WHITE if on else Color(0.5, 0.5, 0.55, 0.6))

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			Sfx.play("click")
			pressed.emit()
			accept_event()
