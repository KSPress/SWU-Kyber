class_name InspectOverlay
extends Control
## Full-screen card inspector. The card zooms out of wherever it was tapped,
## can be dragged freely around the screen (springs back to centre), and shows
## rules text, keyword reminders and engine coverage. Leaders get a flip button.
## Tap the backdrop to close.

signal closed

var _card: CardView
var _info: PanelContainer
var _back := false
var _id := ""
var _inst: CardInst
var _center := Vector2.ZERO
var _scale := 1.0


static func open(host: Node, id: String, from_rect := Rect2(), p_inst: CardInst = null) -> InspectOverlay:
	var o := InspectOverlay.new()
	o._id = id
	o._inst = p_inst
	o._back = p_inst != null and p_inst.deployed
	var layer := CanvasLayer.new()
	layer.layer = 50
	host.add_child(layer)
	layer.add_child(o)
	o._build(from_rect)
	return o


func _build(from_rect: Rect2) -> void:
	UIKit.fill_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dimmer := ColorRect.new()
	dimmer.color = Color(0.0, 0.01, 0.03, 0.0)
	UIKit.fill_rect(dimmer)
	dimmer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dimmer)
	create_tween().tween_property(dimmer, "color:a", 0.82, Kyber.anim(0.2))
	Sfx.play("whoosh", 1.5)
	_make_card()
	_layout()
	# zoom out of the source rect
	if from_rect.size.x > 0:
		var start_scale := from_rect.size.x / _card.size.x
		_card.global_position = from_rect.position
		_card.scale = Vector2(start_scale, start_scale)
		_card.pivot_offset = Vector2.ZERO
		var tw := create_tween().set_parallel(true)
		tw.tween_property(_card, "position", _card.home_pos, Kyber.anim(0.32)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(_card, "scale", _card.home_scale, Kyber.anim(0.32)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		UIKit.pop_in(_card)
	_info.modulate.a = 0.0
	create_tween().tween_property(_info, "modulate:a", 1.0, Kyber.anim(0.3)).set_delay(Kyber.anim(0.15))
	get_viewport().size_changed.connect(_layout)


func _make_card() -> void:
	if _card:
		_card.queue_free()
	_card = CardView.new()
	_card.show_back_side = _back
	_card.set_card(_id)
	_card.hover_lift = false
	_card.drag_released.connect(func(c: CardView, _p: Vector2): c.spring_home())
	_card.tapped.connect(func(_c): pass)
	add_child(_card)
	var tex := Art.get_now(_card.data.get("art", _id), _back)
	_card._tex = tex
	if tex == Art.placeholder:
		# streamed art (web): fill in when it arrives
		var cv := _card
		Art.request(_card.data.get("art", _id), func(t):
			if is_instance_valid(cv):
				cv._tex = t
				cv.queue_redraw(), _back)
	if _info:
		_info.queue_free()
	_info = _make_info()
	add_child(_info)


func _layout() -> void:
	var vs := get_viewport_rect().size
	var portrait := vs.y >= vs.x
	var cs := _card.base_size()
	var avail := Vector2(vs.x * 0.86, vs.y * 0.55) if portrait else Vector2(vs.x * 0.45, vs.y * 0.86)
	_scale = minf(avail.x / cs.x, avail.y / cs.y)
	_card.pivot_offset = Vector2.ZERO
	_card.home_scale = Vector2(_scale, _scale)
	_card.scale = _card.home_scale
	var shown := cs * _scale
	if portrait:
		_card.home_pos = Vector2((vs.x - shown.x) / 2.0, vs.y * 0.04)
		_info.position = Vector2(vs.x * 0.05, _card.home_pos.y + shown.y + 16)
		_info.size = Vector2(vs.x * 0.9, vs.y - _info.position.y - 16)
	else:
		_card.home_pos = Vector2(vs.x * 0.05, (vs.y - shown.y) / 2.0)
		_info.position = Vector2(vs.x * 0.53, vs.y * 0.08)
		_info.size = Vector2(vs.x * 0.42, vs.y * 0.84)
	_card.position = _card.home_pos


func _make_info() -> PanelContainer:
	var d: Dictionary = CardDB.card(_id)
	var p := UIKit.panel(Color(Kyber.C_PANEL, 0.96), Kyber.C_KYBER, 14, 10)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	scroll.add_child(v)
	var title := UIKit.label(d.get("name", _id), 30, Kyber.C_TEXT)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(title)
	if d.get("subtitle", "") != "":
		v.add_child(UIKit.label(d["subtitle"], 20, Kyber.C_KYBER))
	var meta := "%s  ·  %s  ·  %s %s" % [UIKit.type_label(d.get("type", "")), ", ".join(d.get("aspects", [])).capitalize(), d.get("set", ""), d.get("number", "")]
	v.add_child(UIKit.label(meta, 16, Kyber.C_DIM))
	if _inst and _inst.in_play():
		v.add_child(UIKit.label("In play: %d power · %d / %d HP%s" % [_inst.power(), _inst.remaining_hp(), _inst.max_hp(), "  · exhausted" if _inst.exhausted else ""], 18, Kyber.C_GOLD))
	var text: String = d.get("leader_unit", {}).get("text", "") if _back else d.get("text", "")
	if text != "":
		var rt := RichTextLabel.new()
		rt.fit_content = true
		rt.bbcode_enabled = true
		rt.text = _format_rules(text)
		rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(rt)
	var kws: Array = d.get("leader_unit", {}).get("keywords", []) if _back else d.get("keywords", [])
	if _inst:
		kws = _inst.keyword_list()
	for k in kws:
		var row := HBoxContainer.new()
		var ic := IconGlyph.new()
		ic.glyph = k["k"]
		ic.frame = true
		ic.custom_minimum_size = Vector2(34, 34)
		row.add_child(ic)
		var kl := UIKit.label("%s%s — %s" % [k["k"].capitalize(), (" %d" % int(k["v"])) if k.has("v") and int(k["v"]) > 1 else "", UIKit.KEYWORD_HELP.get(k["k"], "")], 17, Kyber.C_TEXT)
		kl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		kl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(kl)
		v.add_child(row)
	var impl: String = d.get("implemented", "manual")
	var impl_col: Color = {"full": Kyber.C_GOOD, "partial": Kyber.C_GOLD}.get(impl, Kyber.C_EMPIRE)
	var il := UIKit.label("Engine support: %s" % impl.to_upper(), 15, impl_col)
	v.add_child(il)
	for u in d.get("unparsed", []):
		var ul := UIKit.label("• not yet automated: " + u, 14, Kyber.C_DIM)
		ul.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(ul)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 10)
	if d.get("type", "") == "leader":
		var flip := KyberButton.make("Flip", KyberButton.Style.GOLD)
		flip.pressed.connect(_flip)
		row2.add_child(flip)
	var close := KyberButton.make("Close", KyberButton.Style.GHOST)
	close.pressed.connect(close_overlay)
	row2.add_child(close)
	v.add_child(row2)
	return p


func _format_rules(t: String) -> String:
	var out := t
	for k in ["When Played", "On Attack", "When Defeated", "Action", "Epic Action", "When Deployed", "When Attack Ends", "Attached unit gains", "Bounty", "Coordinate", "Smuggle", "Piloting"]:
		out = out.replace(k, "[b][color=#4fe3ff]%s[/color][/b]" % k)
	return out


func _flip() -> void:
	_back = not _back
	var tw := create_tween()
	tw.tween_property(_card, "scale:x", 0.0, Kyber.anim(0.14))
	tw.tween_callback(func():
		_make_card()
		_layout()
		_card.scale.x = 0.0
		var t2 := create_tween()
		t2.tween_property(_card, "scale:x", _scale, Kyber.anim(0.14)))
	Sfx.play("deploy", 1.4)


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		close_overlay()


func _unhandled_input(ev: InputEvent) -> void:
	if ev.is_action_pressed("ui_cancel"):
		close_overlay()


func close_overlay() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 0.0, Kyber.anim(0.15))
	tw.tween_property(_card, "scale", _card.scale * 0.8, Kyber.anim(0.15))
	await tw.finished
	closed.emit()
	get_parent().queue_free()
