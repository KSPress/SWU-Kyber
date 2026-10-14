class_name ChoicePanel
extends Control
## Modal picker for engine choices that aren't board targets: mulligan, yes/no,
## resource selection, discard, scry and search. Cards pop in staggered; tap to
## toggle, long-press to inspect.

signal submitted(selection: Array)

var pending: Dictionary
var m: Match
var _sel: Array = []
var _views: Dictionary = {}
var _confirm: KyberButton
var _count: Label


static func open(host: Node, p_match: Match, p_pending: Dictionary) -> ChoicePanel:
	var c := ChoicePanel.new()
	c.m = p_match
	c.pending = p_pending
	var layer := CanvasLayer.new()
	layer.layer = 40
	host.add_child(layer)
	layer.add_child(c)
	c._build()
	return c


func _build() -> void:
	UIKit.fill_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0.01, 0.03, 0.78)
	UIKit.fill_rect(dim)
	add_child(dim)
	var v := VBoxContainer.new()
	v.name = "Box"
	v.add_theme_constant_override("separation", 14)
	add_child(v)
	_fit()
	get_viewport().size_changed.connect(_fit)
	v.add_child(UIKit.aurebesh("choose", 22))
	var kind: String = pending.get("kind", "")
	var title := UIKit.title(_title_for(kind), 34, Kyber.C_KYBER)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(title)
	var prompt := UIKit.label(pending.get("prompt", ""), 20, Kyber.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(prompt)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	if kind == "option":
		var src := m.card(pending.get("src", 0))
		if src:
			_add_cards(v, [src.uid], false)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 10)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var labels: Array = pending.get("labels", [])
		for i in labels.size():
			var b := KyberButton.make(str(labels[i]), KyberButton.Style.PRIMARY if i == 0 else KyberButton.Style.GOLD)
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var idx: int = i
			b.pressed.connect(func(): _submit([idx]))
			col.add_child(b)
		if int(pending.get("min", 1)) == 0:
			var skip := KyberButton.make("Skip", KyberButton.Style.GHOST)
			skip.pressed.connect(func(): _submit([]))
			col.add_child(skip)
		v.add_child(col)
	elif kind in ["yesno", "mulligan"]:
		if kind == "mulligan":
			_add_cards(v, _hand_uids(), false)
		var yes := KyberButton.make("Mulligan" if kind == "mulligan" else "Yes", KyberButton.Style.GOLD if kind == "mulligan" else KyberButton.Style.PRIMARY)
		var no := KyberButton.make("Keep hand" if kind == "mulligan" else "No", KyberButton.Style.PRIMARY if kind == "mulligan" else KyberButton.Style.GHOST, "", kind == "mulligan")
		yes.custom_minimum_size.x = 220
		no.custom_minimum_size.x = 220
		yes.pressed.connect(func(): _submit([1]))
		no.pressed.connect(func(): _submit([0]))
		buttons.add_child(no)
		buttons.add_child(yes)
	else:
		var shown: Array = pending.get("reveal", pending.get("options", []))
		_add_cards(v, shown, true)
		_count = UIKit.label("", 18, Kyber.C_DIM, HORIZONTAL_ALIGNMENT_CENTER)
		v.add_child(_count)
		_confirm = KyberButton.make("Confirm", KyberButton.Style.PRIMARY, "", true)
		_confirm.custom_minimum_size.x = 240
		_confirm.pressed.connect(func(): _submit(_sel))
		buttons.add_child(_confirm)
		_update()
	v.add_child(buttons)
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, Kyber.anim(0.2))


func _fit() -> void:
	var vs := get_viewport_rect().size
	var v: Control = get_node("Box")
	v.position = Vector2(vs.x * 0.04, vs.y * 0.08)
	v.size = Vector2(vs.x * 0.92, vs.y * 0.84)


func _title_for(kind: String) -> String:
	if kind == "hand" and pending.get("op", "") == "play_from_hand":
		return "Play a card"
	return {"option": "Choose one", "mulligan": "Opening hand", "resource": "Resources", "hand": "Discard", "scry": "Look at the top of your deck",
		"search": "Search your deck", "yesno": "Optional ability"}.get(kind, "Choose")


func _hand_uids() -> Array:
	var out: Array = []
	for c in m.players[pending["player"]].hand:
		out.append(c.uid)
	return out


func _add_cards(v: VBoxContainer, uids: Array, selectable: bool) -> void:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = (CardView.PORTRAIT.y * _scale() + 32) * _rows()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	# portrait: two rows of cards so they stay readable; landscape: one row
	var row := GridContainer.new()
	row.columns = _cols()
	row.add_theme_constant_override("h_separation", 12)
	row.add_theme_constant_override("v_separation", 12)
	center.add_child(row)
	v.add_child(scroll)
	var i := 0
	for uid in uids:
		var ci := m.card(uid)
		if ci == null:
			continue
		var holder := Control.new()
		holder.custom_minimum_size = CardView.PORTRAIT * _scale() + Vector2(0, 20)
		row.add_child(holder)
		var cv := CardView.create(ci.id, ci)
		cv.draggable = false
		cv.hover_lift = false
		cv.pivot_offset = Vector2.ZERO
		cv.home_scale = Vector2(_scale(), _scale())
		cv.scale = cv.home_scale
		cv.home_pos = Vector2(0, 10)
		cv.position = cv.home_pos
		holder.add_child(cv)
		var selectable_card: bool = selectable and uid in pending.get("options", [])
		cv.dim = selectable and not selectable_card
		if selectable_card:
			cv.tapped.connect(func(_c): _toggle(uid))
		cv.inspect_requested.connect(func(c): InspectOverlay.open(self, c.card_id, c.get_global_rect(), ci))
		_views[uid] = cv
		UIKit.pop_in(cv, i * 0.05)
		i += 1


func _count_cards() -> int:
	if pending.get("kind", "") == "mulligan":
		return maxi(1, m.players[pending["player"]].hand.size())
	return maxi(1, pending.get("reveal", pending.get("options", [])).size())


func _rows() -> int:
	var vs := get_viewport_rect().size
	return 2 if vs.y >= vs.x and _count_cards() > 3 else 1


func _cols() -> int:
	return ceili(_count_cards() / float(_rows()))


func _scale() -> float:
	var vs := get_viewport_rect().size
	var cols := _cols()
	var rows := _rows()
	var by_w := (vs.x * 0.9 - (cols - 1) * 12) / cols / CardView.PORTRAIT.x
	var by_h := (vs.y * (0.5 if vs.y >= vs.x else 0.5) - (rows - 1) * 12) / rows / CardView.PORTRAIT.y
	return clampf(minf(by_w, by_h), 0.3, 1.0)


func _toggle(uid: int) -> void:
	if uid in _sel:
		_sel.erase(uid)
	else:
		if _sel.size() >= int(pending["max"]):
			if int(pending["max"]) == 1:
				_sel.clear()
			else:
				return
		_sel.append(uid)
	Sfx.play("click")
	for k in _views:
		var cv: CardView = _views[k]
		cv.selected = k in _sel
		var target := Vector2(0, -8 if k in _sel else 10)
		cv.create_tween().tween_property(cv, "position", target, Kyber.anim(0.15)).set_trans(Tween.TRANS_BACK)
	_update()


func _update() -> void:
	if _confirm == null:
		return
	var mn := int(pending["min"])
	var mx := int(pending["max"])
	_confirm.disabled = _sel.size() < mn or _sel.size() > mx
	_count.text = ("Select %d" % mn if mn == mx else "Select %d–%d" % [mn, mx]) + "   (%d chosen)" % _sel.size()
	if mn == 0 and _sel.is_empty():
		_confirm.text = "Skip"
	else:
		_confirm.text = "Confirm"


func _submit(sel: Array) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, Kyber.anim(0.15))
	await tw.finished
	submitted.emit(sel)
	get_parent().queue_free()
