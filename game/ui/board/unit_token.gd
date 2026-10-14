class_name UnitToken
extends Control
## Hex token for a unit in play (spec 8.2): art crop, power/HP, keyword badges,
## shield bubble, upgrade pips, exhausted state. Full card on inspect.

signal pressed(tok: UnitToken)
signal inspect_requested(tok: UnitToken)
signal drag_started(tok: UnitToken)
signal drag_moved(tok: UnitToken, global_pos: Vector2)
signal drag_released(tok: UnitToken, global_pos: Vector2)

const SIZE := Vector2(132, 150)   # hex + name strip
const HEX_H := 116.0
const ART_UV := Rect2(0.12, 0.13, 0.76, 0.46)        # art window on a portrait card render
const LONG_PRESS := 0.42

enum Hi { NONE, CAN_ACT, TARGET, SELECTED, HOSTILE_TARGET }

var inst: CardInst
var friendly := true
var highlight := Hi.NONE:
	set(v):
		highlight = v
		queue_redraw()
var home_pos := Vector2.ZERO
var _tex: Texture2D
var _t := 0.0
var _flash := 0.0
var _flash_col := Color.WHITE
var _badges: HBoxContainer
var _press := false
var _press_t := 0.0
var _press_pos := Vector2.ZERO
var _long := false
var _dragging := false
var _dying := false
var _light := 0.0
var _light_col := Color.WHITE
var _light_from := Vector2.ZERO


static func create(p_inst: CardInst, p_friendly: bool) -> UnitToken:
	var t := UnitToken.new()
	t.inst = p_inst
	t.friendly = p_friendly
	return t


func _ready() -> void:
	custom_minimum_size = SIZE
	size = SIZE
	pivot_offset = Vector2(SIZE.x / 2.0, HEX_H / 2.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_badges = HBoxContainer.new()
	_badges.add_theme_constant_override("separation", 1)
	_badges.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badges.position = Vector2(14, -6)
	add_child(_badges)
	_load_art()
	refresh()


func _load_art() -> void:
	var art: String = inst.data.get("art", inst.id)
	var t := Art.request(art, func(tx): _tex = tx; queue_redraw(), inst.deployed)
	if t:
		_tex = t


func refresh() -> void:
	if not is_instance_valid(_badges):
		return
	for c in _badges.get_children():
		c.queue_free()
	var kws := inst.keyword_list()
	for k in kws.slice(0, 4):
		var ic := IconGlyph.new()
		ic.glyph = k["k"]
		ic.frame = true
		ic.color = Kyber.C_GOLD if k["k"] == "sentinel" else Kyber.C_KYBER
		ic.custom_minimum_size = Vector2(26, 26)
		ic.pulse = k["k"] == "sentinel"
		ic.tooltip_text = k["k"].capitalize()
		_badges.add_child(ic)
	var target_rot := -0.14 if inst.exhausted else 0.0
	if not is_equal_approx(rotation, target_rot) and not _dying:
		create_tween().tween_property(self, "rotation", target_rot, Kyber.anim(0.25)).set_trans(Tween.TRANS_BACK)
	queue_redraw()


## Reflected light from bolts/impacts (see Fx.light_at).
func apply_light(col: Color, amount: float, from: Vector2) -> void:
	if amount > _light:
		_light = minf(amount, 1.2)
		_light_col = col
		_light_from = from
	queue_redraw()


## Hit reaction: knocked back away from the source, squashed, springs back.
func hit_punch(from: Vector2) -> void:
	if _dying:
		return
	var dir := (center_global() - from).normalized() if from != Vector2.INF else Vector2(0, 1)
	var s0 := scale
	var tw := create_tween()
	tw.tween_property(self, "position", home_pos + dir * 16.0, 0.05).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(self, "scale", s0 * Vector2(1.12, 0.86), 0.05)
	tw.tween_property(self, "position", home_pos, 0.32).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(self, "scale", s0, 0.32).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _process(dt: float) -> void:
	_t += dt
	if _light > 0.0:
		_light = maxf(0.0, _light - dt * 4.5)
		queue_redraw()
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - dt * 3.0)
	if highlight != Hi.NONE or _flash > 0.0 or inst.shield_count() > 0:
		queue_redraw()
	if _press and not _dragging and not _long:
		_press_t += dt
		if _press_t > LONG_PRESS:
			_long = true
			inspect_requested.emit(self)


func hex_points(grow := 0.0) -> PackedVector2Array:
	var c := Vector2(SIZE.x / 2.0, HEX_H / 2.0)
	var rx := SIZE.x / 2.0 + grow
	var ry := HEX_H / 2.0 + grow
	var pts := PackedVector2Array()
	for i in 6:
		var a := i * PI / 3.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


func center_global() -> Vector2:
	return global_position + Vector2(SIZE.x / 2.0, HEX_H / 2.0) * scale


func _draw() -> void:
	var pts := hex_points()
	var side_col := Kyber.C_REBEL if friendly else Kyber.C_EMPIRE
	var k := 0.5 + 0.5 * sin(_t * 4.0)
	# highlight glow
	var hc := Color.TRANSPARENT
	match highlight:
		Hi.CAN_ACT:
			hc = Color(Kyber.C_GOOD, 0.35 + 0.35 * k)
		Hi.TARGET:
			hc = Color(Kyber.C_GOLD, 0.45 + 0.4 * k)
		Hi.HOSTILE_TARGET:
			hc = Color(Kyber.C_EMPIRE, 0.45 + 0.45 * k)
		Hi.SELECTED:
			hc = Color(Kyber.C_KYBER, 0.9)
	if hc.a > 0:
		for i in 3:
			var g := hex_points(4.0 + i * 4.0)
			g.append(g[0])
			draw_polyline(g, Color(hc, hc.a * (0.9 - i * 0.28)), 4.0, true)
	# art
	var uvs := PackedVector2Array()
	var c := Vector2(SIZE.x / 2.0, HEX_H / 2.0)
	for p in pts:
		var n := (p - c) / Vector2(SIZE.x, HEX_H) + Vector2(0.5, 0.5)
		uvs.append(ART_UV.position + n * ART_UV.size)
	var tint := Color(0.55, 0.55, 0.62) if inst.exhausted else Color.WHITE
	if _tex and _tex != Art.placeholder:
		draw_colored_polygon(pts, tint, uvs, _tex)
	else:
		draw_colored_polygon(pts, Color("1a2636"))
		UIKit.draw_fit(self, Kyber.font_title, Vector2(6, HEX_H / 2.0), inst.name(), HORIZONTAL_ALIGNMENT_CENTER, SIZE.x - 12, 15, Kyber.C_TEXT)
	if _flash > 0.0:
		draw_colored_polygon(pts, Color(_flash_col, _flash * 0.7))
	if _light > 0.01:
		# tint the art with the light colour, brightest on the side facing the source
		draw_colored_polygon(pts, Color(_light_col.lightened(0.2), 0.32 * minf(_light, 1.0)))
		var local_from := get_global_transform().affine_inverse() * _light_from
		var ldir := (local_from - c).normalized()
		var edge := c + Vector2(ldir.x * SIZE.x * 0.42, ldir.y * HEX_H * 0.42)
		draw_circle(edge, 30.0, Color(_light_col.lightened(0.5), 0.22 * _light))
		draw_circle(edge, 14.0, Color(1, 1, 1, 0.25 * _light))
	# frame
	var outline := pts.duplicate()
	outline.append(pts[0])
	if _light > 0.01:
		draw_polyline(outline, Color(_light_col.lightened(0.4), 0.9 * minf(_light, 1.0)), 8.0, true)
	if inst.is_leader():
		draw_polyline(outline, Kyber.C_GOLD, 6.0, true)
		draw_polyline(outline, Color(1, 0.95, 0.7), 2.0, true)
	else:
		draw_polyline(outline, side_col.darkened(0.2), 6.0, true)
		draw_polyline(outline, side_col.lightened(0.3), 2.0, true)
	# shield bubble
	var sh := inst.shield_count()
	if sh > 0:
		var r := SIZE.x * 0.56
		draw_arc(c, r, 0, TAU, 40, Color(0.45, 0.85, 1.0, 0.35 + 0.2 * k), 4.0, true)
		draw_arc(c, r + 4, _t, _t + PI * 0.6, 16, Color(0.7, 0.95, 1.0, 0.8), 2.0, true)
		if sh > 1:
			UIKit.draw_fit(self, Kyber.font_title, c + Vector2(r - 10, -r + 16), "x%d" % sh, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.7, 0.95, 1))
	# upgrades pips (non-shield)
	var ups: Array = []
	for u in inst.upgrades:
		if u.data.get("name", "") != "Shield":
			ups.append(u)
	for i in ups.size():
		var pc := Vector2(SIZE.x - 18 - i * 14, 10)
		var is_xp: bool = ups[i].data.get("name", "") == "Experience"
		var d := PackedVector2Array([pc + Vector2(0, -6), pc + Vector2(6, 0), pc + Vector2(0, 6), pc + Vector2(-6, 0)])
		draw_colored_polygon(d, Kyber.C_GOLD if is_xp else Kyber.C_KYBER)
	# stats
	_badge(Vector2(4, HEX_H - 38), str(inst.power()), Kyber.C_POWER, inst.power() != inst.printed_power())
	var hp := inst.remaining_hp()
	var hp_col := Kyber.C_HP if inst.damage == 0 else Color(0.85, 0.15, 0.15)
	_badge(Vector2(SIZE.x - 40, HEX_H - 38), str(hp), hp_col, inst.max_hp() != inst.printed_hp())
	# exhausted mark
	if inst.exhausted:
		UIKit.draw_fit(self, Kyber.font_title, Vector2(0, HEX_H * 0.42), "EXHAUSTED", HORIZONTAL_ALIGNMENT_CENTER, SIZE.x, 13, Color(1, 1, 1, 0.75))
	if inst.flags.get("protected", false):
		UIKit.draw_fit(self, Kyber.font_title, Vector2(0, HEX_H * 0.62), "PROTECT", HORIZONTAL_ALIGNMENT_CENTER, SIZE.x, 15, Kyber.C_GOLD)
	# name strip
	var nr := Rect2(Vector2(8, HEX_H + 4), Vector2(SIZE.x - 16, 24))
	draw_rect(nr, Color(0.02, 0.04, 0.07, 0.85))
	draw_rect(nr, Color(side_col, 0.6), false, 1.5)
	UIKit.draw_fit(self, Kyber.font_title, nr.position + Vector2(0, 18), inst.name(), HORIZONTAL_ALIGNMENT_CENTER, nr.size.x, 14, Kyber.C_TEXT)


func _badge(at: Vector2, txt: String, col: Color, modified: bool) -> void:
	var c := at + Vector2(18, 18)
	var oct := PackedVector2Array()
	for i in 8:
		var a := PI / 8.0 + i * PI / 4.0
		oct.append(c + Vector2(cos(a), sin(a)) * 19.0)
	draw_colored_polygon(oct, col.darkened(0.15))
	oct.append(oct[0])
	draw_polyline(oct, Color(1, 1, 1, 0.85) if not modified else Kyber.C_GOLD, 2.0, true)
	UIKit.draw_fit(self, Kyber.font_title, at + Vector2(0, 27), txt, HORIZONTAL_ALIGNMENT_CENTER, 36, 24, Color.WHITE)


# ---------------------------------------------------------------- input

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			inspect_requested.emit(self)
			accept_event()
			return
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			if mb.double_click:
				inspect_requested.emit(self)
				return
			_press = true
			_press_t = 0.0
			_long = false
			_press_pos = mb.global_position
		else:
			if _dragging:
				_dragging = false
				drag_released.emit(self, mb.global_position)
			elif _press and not _long:
				pressed.emit(self)
			_press = false
		accept_event()
	elif ev is InputEventMouseMotion and _press:
		var mm := ev as InputEventMouseMotion
		if not _dragging and not _long and mm.global_position.distance_to(_press_pos) > 16.0:
			_dragging = true
			drag_started.emit(self)
		if _dragging:
			drag_moved.emit(self, mm.global_position)
		accept_event()


# ---------------------------------------------------------------- animation

func flash(col: Color) -> void:
	_flash = 1.0
	_flash_col = col
	queue_redraw()


func pop_in() -> void:
	scale = Vector2(0.2, 0.2)
	modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "scale", Vector2.ONE, Kyber.anim(0.4)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "modulate:a", 1.0, Kyber.anim(0.2))
	flash(Kyber.C_KYBER)


func shake(amount := 8.0) -> void:
	var tw := create_tween()
	var base := position
	for i in 4:
		tw.tween_property(self, "position", base + Vector2(randf_range(-amount, amount), randf_range(-amount, amount) * 0.5), 0.04)
	tw.tween_property(self, "position", home_pos, 0.06)


func lunge(to_global: Vector2) -> void:
	z_index = 20
	var start := position
	var delta := (to_global - center_global()) * 0.78
	var tw := create_tween()
	tw.tween_property(self, "position", start - delta.normalized() * 14.0, Kyber.anim(0.1)).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(self, "position", start + delta, Kyber.anim(0.16)).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	await tw.finished


func lunge_back() -> void:
	var tw := create_tween()
	tw.tween_property(self, "position", home_pos, Kyber.anim(0.3)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tw.finished
	z_index = 0


func die() -> void:
	_dying = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash(Color(1, 0.4, 0.2))
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "scale", Vector2(1.25, 0.2), Kyber.anim(0.35)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "modulate", Color(2.0, 1.2, 0.8, 0.0), Kyber.anim(0.35))
	tw.tween_property(self, "rotation", randf_range(-0.4, 0.4), Kyber.anim(0.35))
	await tw.finished
	queue_free()
