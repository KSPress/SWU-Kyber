class_name CardView
extends Control
## A full card (hand, rewards, collection, inspect). Uses the real card render
## when art is present, otherwise draws a readable text card.
##
## Interaction (mouse and touch):
##   tap              -> tapped
##   long-press / RMB -> inspect_requested
##   drag             -> drag_started / drag_moved / drag_released; the card
##                       follows the pointer with velocity tilt and springs home
##                       if the receiver doesn't claim it (see spring_home()).

signal tapped(card: CardView)
signal inspect_requested(card: CardView)
signal drag_started(card: CardView)
signal drag_moved(card: CardView, global_pos: Vector2)
signal drag_released(card: CardView, global_pos: Vector2)
signal hover_changed(card: CardView, on: bool)

const PORTRAIT := Vector2(250, 349)
const LANDSCAPE := Vector2(349, 250)
const LONG_PRESS := 0.42
const DRAG_THRESHOLD := 14.0

var card_id := ""
var data: Dictionary = {}
var inst: CardInst          # optional live instance (hand cards)
var face_down := false
var show_back_side := false # leader unit side
var draggable := true
var hover_lift := true
var playable := false:
	set(v):
		playable = v
		queue_redraw()
var selected := false:
	set(v):
		selected = v
		queue_redraw()
var cost_override := -1     # shows effective cost (aspect penalties) when different
var dim := false:
	set(v):
		dim = v
		modulate = Color(0.55, 0.55, 0.6) if v else Color.WHITE

var home_pos := Vector2.ZERO
var home_rot := 0.0
var home_scale := Vector2.ONE

var _tex: Texture2D
var _press := false
var _press_pos := Vector2.ZERO
var _press_time := 0.0
var _dragging := false
var _grab := Vector2.ZERO
var _last_pos := Vector2.ZERO
var _vel := Vector2.ZERO
var _long_fired := false
var _hover := false
var _tw: Tween
var _glow_t := 0.0


static func create(id: String, p_inst: CardInst = null) -> CardView:
	var c := CardView.new()
	c.set_card(id, p_inst)
	return c


func set_card(id: String, p_inst: CardInst = null) -> void:
	card_id = id
	inst = p_inst
	data = CardDB.card(id) if id != "" else {}
	custom_minimum_size = base_size()
	size = base_size()
	pivot_offset = size / 2.0
	_tex = null
	if id != "":
		var t := Art.request(data.get("art", id), _on_art, show_back_side)
		if t:
			_tex = t
	queue_redraw()


func is_landscape() -> bool:
	var t: String = data.get("type", "")
	return (t == "leader" and not show_back_side) or t == "base"


func base_size() -> Vector2:
	return LANDSCAPE if is_landscape() else PORTRAIT


func _on_art(t: Texture2D) -> void:
	if is_instance_valid(self):
		_tex = t
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(_on_hover.bind(true))
	mouse_exited.connect(_on_hover.bind(false))


func _process(dt: float) -> void:
	if playable or selected:
		_glow_t += dt
		queue_redraw()
	if _press and not _dragging and not _long_fired:
		_press_time += dt
		if _press_time >= LONG_PRESS:
			_long_fired = true
			inspect_requested.emit(self)
	if _dragging:
		# tilt with horizontal velocity, ease back to upright
		rotation = lerpf(rotation, clampf(_vel.x * 0.0009, -0.35, 0.35), 0.25)
		_vel *= 0.85


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if playable or selected:
		var k := 0.5 + 0.5 * sin(_glow_t * 4.0)
		var gc := Kyber.C_GOLD if selected else Kyber.C_KYBER
		for i in 4:
			var g := 3.0 + i * 3.0 + k * 2.0
			draw_rect(r.grow(g), Color(gc, 0.16 - i * 0.03), false, 3.0)
		draw_rect(r.grow(2), Color(gc, 0.9), false, 2.5)
	if face_down:
		var back: Texture2D = Art.card_back
		draw_texture_rect(back, r, false)
		return
	if _tex and _tex != Art.placeholder:
		draw_texture_rect(_tex, r, false)
	else:
		_draw_text_card(r)
	if cost_override >= 0 and cost_override != int(data.get("cost", 0)) and not is_landscape():
		var badge := Rect2(Vector2(size.x * 0.03, size.y * 0.02), Vector2(size.x * 0.19, size.x * 0.19))
		draw_rect(badge, Color(0.6, 0.05, 0.05, 0.92))
		var f := Kyber.font_title
		var fs := int(size.x * 0.13)
		UIKit.draw_fit(self, f, badge.position + Vector2(0, badge.size.y * 0.78), str(cost_override), HORIZONTAL_ALIGNMENT_CENTER, badge.size.x, fs, Color.WHITE)


func _draw_text_card(r: Rect2) -> void:
	var aspects: Array = data.get("aspects", [])
	var col := Kyber.aspect_color(aspects[0]) if aspects.size() > 0 else Kyber.C_LINE
	draw_rect(r, Color("0d1520"))
	draw_rect(r.grow(-4), Color(col, 0.35), false, 6.0)
	var f := Kyber.font_body
	var tf := Kyber.font_title
	var w := r.size.x
	var nm: String = data.get("name", card_id if card_id != "" else "?")
	UIKit.draw_fit(self, tf, Vector2(0, w * 0.2), nm, HORIZONTAL_ALIGNMENT_CENTER, w, int(w * 0.075), Kyber.C_TEXT)
	var sub: String = data.get("subtitle", "")
	if sub != "":
		UIKit.draw_fit(self, f, Vector2(0, w * 0.28), sub, HORIZONTAL_ALIGNMENT_CENTER, w, int(w * 0.05), Kyber.C_DIM)
	var t: String = data.get("type", "")
	if t != "base":
		draw_rect(Rect2(Vector2(8, 8), Vector2(w * 0.17, w * 0.17)), Kyber.C_COST)
		UIKit.draw_fit(self, tf, Vector2(8, 8 + w * 0.14), str(data.get("cost", 0)), HORIZONTAL_ALIGNMENT_CENTER, w * 0.17, int(w * 0.12), Color.BLACK)
	if t in ["unit", "leader", "token_unit"] or (t == "upgrade" and (int(data.get("power", 0)) != 0 or int(data.get("hp", 0)) != 0)):
		var y := r.size.y * 0.55
		draw_rect(Rect2(Vector2(8, y), Vector2(w * 0.18, w * 0.18)), Kyber.C_POWER)
		UIKit.draw_fit(self, tf, Vector2(8, y + w * 0.14), str(data.get("power", 0)), HORIZONTAL_ALIGNMENT_CENTER, w * 0.18, int(w * 0.12), Color.WHITE)
		draw_rect(Rect2(Vector2(w - 8 - w * 0.18, y), Vector2(w * 0.18, w * 0.18)), Kyber.C_HP)
		UIKit.draw_fit(self, tf, Vector2(w - 8 - w * 0.18, y + w * 0.14), str(data.get("hp", 0)), HORIZONTAL_ALIGNMENT_CENTER, w * 0.18, int(w * 0.12), Color.WHITE)
	elif t == "base":
		UIKit.draw_fit(self, tf, Vector2(0, r.size.y * 0.6), "%d HP" % int(data.get("hp", 0)), HORIZONTAL_ALIGNMENT_CENTER, w, int(w * 0.09), Kyber.C_HP)
	var text: String = data.get("text", "")
	if text != "":
		var y0 := r.size.y * 0.72
		draw_multiline_string(f, Vector2(10, y0), text, HORIZONTAL_ALIGNMENT_LEFT, w - 20, int(w * 0.048), 6, Kyber.C_TEXT)
	UIKit.draw_fit(self, f, Vector2(0, r.size.y - 8), ("%s · %s" % [UIKit.type_label(t), " ".join(data.get("traits", []))]).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, w, int(w * 0.04), Kyber.C_DIM)


# ---------------------------------------------------------------- interaction

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
				accept_event()
				return
			_press = true
			_press_time = 0.0
			_long_fired = false
			_press_pos = mb.global_position
			_last_pos = mb.global_position
			accept_event()
		else:
			if _dragging:
				_end_drag(mb.global_position)
			elif _press and not _long_fired:
				tapped.emit(self)
			_press = false
			accept_event()
	elif ev is InputEventMouseMotion and _press:
		var mm := ev as InputEventMouseMotion
		if not _dragging and draggable and not _long_fired and mm.global_position.distance_to(_press_pos) > DRAG_THRESHOLD:
			_begin_drag(mm.global_position)
		if _dragging:
			_vel = (mm.global_position - _last_pos) / maxf(get_process_delta_time(), 0.001)
			_last_pos = mm.global_position
			global_position = mm.global_position - _grab
			drag_moved.emit(self, mm.global_position)
		accept_event()


func _begin_drag(at: Vector2) -> void:
	_dragging = true
	var gp := global_position
	_grab = at - gp
	top_level = true
	global_position = gp
	z_index = 100
	_kill_tween()
	_tw = create_tween()
	_tw.tween_property(self, "scale", home_scale * 1.12, Kyber.anim(0.12))
	Sfx.play("draw", 1.2)
	drag_started.emit(self)


func _end_drag(at: Vector2) -> void:
	_dragging = false
	_press = false
	drag_released.emit(self, at)


func is_dragging() -> bool:
	return _dragging


## Return to the home slot (parent-relative) with an elastic spring.
func spring_home(elastic := true) -> void:
	var gp := global_position
	if top_level:
		top_level = false
		var parent_ctrl := get_parent() as Control
		if parent_ctrl:
			position = gp - parent_ctrl.global_position
	z_index = 0
	_kill_tween()
	_tw = create_tween().set_parallel(true)
	var dur := Kyber.anim(0.45 if elastic else 0.22)
	var trans := Tween.TRANS_ELASTIC if elastic else Tween.TRANS_QUAD
	_tw.tween_property(self, "position", home_pos, dur).set_trans(trans).set_ease(Tween.EASE_OUT)
	_tw.tween_property(self, "rotation", home_rot, dur * 0.7).set_trans(Tween.TRANS_QUAD)
	_tw.tween_property(self, "scale", home_scale, dur * 0.6)


func move_home(delay := 0.0) -> void:
	if _dragging:
		return
	_kill_tween()
	_tw = create_tween().set_parallel(true)
	var d := Kyber.anim(0.28)
	var lift := Vector2.ZERO
	var sc := home_scale
	var rot := home_rot
	if _hover and hover_lift:
		lift = Vector2(0, -size.y * home_scale.y * 0.28)
		sc = home_scale * 1.18
		rot = 0.0
	_tw.tween_property(self, "position", home_pos + lift, d).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tw.tween_property(self, "rotation", rot, d).set_delay(delay)
	_tw.tween_property(self, "scale", sc, d).set_delay(delay)


func _on_hover(on: bool) -> void:
	_hover = on
	if _dragging:
		return
	z_index = 10 if on and hover_lift else 0
	hover_changed.emit(self, on)
	if hover_lift:
		move_home()


func _kill_tween() -> void:
	if _tw and _tw.is_valid():
		_tw.kill()


## Flip animation (e.g. reveal from face-down).
func flip_to(face_up: bool) -> void:
	var tw := create_tween()
	tw.tween_property(self, "scale:x", 0.0, Kyber.anim(0.12))
	tw.tween_callback(func():
		face_down = not face_up
		queue_redraw())
	tw.tween_property(self, "scale:x", home_scale.x, Kyber.anim(0.12))
