class_name SideHud
extends Control
## One player's HUD: leader, base (HP + attack target), resources, deck/hand
## counts. arrange() lays it out as a row (portrait) or a column (landscape).

signal leader_pressed(hud: SideHud)
signal base_pressed(hud: SideHud)
signal resources_pressed(hud: SideHud)
signal inspect(id: String, rect: Rect2, inst: CardInst)

var player_idx := 0
var friendly := true
var base_view: BaseView
var leader_view: LeaderView
var res_view: ResourceView
var info: Label
var _ps: PlayerState


func _init(idx: int, p_friendly: bool) -> void:
	player_idx = idx
	friendly = p_friendly


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	leader_view = LeaderView.new()
	leader_view.friendly = friendly
	leader_view.pressed.connect(func(): leader_pressed.emit(self))
	leader_view.inspect.connect(func(): inspect.emit(leader_view.card_id(), leader_view.get_global_rect(), _ps.leader))
	add_child(leader_view)
	base_view = BaseView.new()
	base_view.friendly = friendly
	base_view.pressed.connect(func(): base_pressed.emit(self))
	base_view.inspect.connect(func(): inspect.emit(_ps.base.id, base_view.get_global_rect(), _ps.base))
	add_child(base_view)
	res_view = ResourceView.new()
	res_view.pressed.connect(func(): resources_pressed.emit(self))
	add_child(res_view)
	info = UIKit.fit_label(UIKit.label("", 16, Kyber.C_DIM))
	add_child(info)


func bind(ps: PlayerState) -> void:
	_ps = ps
	base_view.set_base(ps.base)
	leader_view.set_leader(ps.leader)
	refresh()


func refresh() -> void:
	if _ps == null:
		return
	base_view.queue_redraw()
	leader_view.refresh()
	res_view.ready_n = _ps.ready_resources()
	res_view.total = _ps.resources.size()
	res_view.queue_redraw()
	info.text = "Deck %d   Hand %d   Discard %d%s" % [_ps.deck.size(), _ps.hand.size(), _ps.discard.size(), ("   Credits %d" % _ps.credits) if _ps.credits > 0 else ""]


func arrange(r: Rect2, horizontal: bool) -> void:
	position = r.position
	size = r.size
	if horizontal:
		var h := r.size.y
		var lw := minf(h * 1.4, r.size.x * 0.24)
		leader_view.position = Vector2(0, 0)
		leader_view.size = Vector2(lw, h - 22)
		var bw := r.size.x * 0.42
		base_view.position = Vector2(lw + 10, 0)
		base_view.size = Vector2(bw, h - 22)
		res_view.position = Vector2(lw + bw + 20, 6)
		res_view.size = Vector2(r.size.x - lw - bw - 24, h * 0.5)
		info.position = Vector2(lw + bw + 20, h * 0.55)
		info.size = Vector2(r.size.x - lw - bw - 24, 24)
	else:
		var w := r.size.x
		leader_view.position = Vector2(0, 0)
		leader_view.size = Vector2(w, r.size.y * 0.34)
		base_view.position = Vector2(0, r.size.y * 0.36)
		base_view.size = Vector2(w, r.size.y * 0.34)
		res_view.position = Vector2(0, r.size.y * 0.72)
		res_view.size = Vector2(w, r.size.y * 0.16)
		info.position = Vector2(0, r.size.y * 0.9)
		info.size = Vector2(w, 24)
	leader_view.queue_redraw()
	base_view.queue_redraw()


## Base tile: art, HP readout, target highlight, hit flash.
class BaseView extends Control:
	var _light := 0.0
	var _light_col := Color.WHITE

	func apply_light(col: Color, amount: float, _from: Vector2) -> void:
		if amount > _light:
			_light = minf(amount, 1.0)
			_light_col = col
		queue_redraw()

	func _light_overlay() -> void:
		if _light > 0.01:
			draw_rect(Rect2(Vector2.ZERO, size), Color(_light_col.lightened(0.2), 0.28 * _light))
			draw_rect(Rect2(Vector2.ZERO, size), Color(_light_col.lightened(0.4), 0.8 * _light), false, 4.0)
		if _light > 0.0:
			_light = maxf(0.0, _light - get_process_delta_time() * 4.5)
			queue_redraw()

	signal pressed
	signal inspect
	var inst: CardInst
	var friendly := true
	var targetable := false:
		set(v):
			targetable = v
			queue_redraw()
	var _tex: Texture2D
	var _t := 0.0
	var _flash := 0.0
	var _shown_hp := -1.0
	var _press_t := -1.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func set_base(b: CardInst) -> void:
		inst = b
		var art: String = b.data.get("art", b.id)
		var t := Art.request(art, func(tx): _tex = tx; queue_redraw())
		if t:
			_tex = t
		_shown_hp = b.remaining_hp()

	func _process(dt: float) -> void:
		_t += dt
		if _press_t >= 0.0:
			_press_t += dt
			if _press_t > 0.42:
				_press_t = -1.0
				inspect.emit()
		var target := float(inst.remaining_hp()) if inst else 0.0
		if absf(_shown_hp - target) > 0.01:
			_shown_hp = move_toward(_shown_hp, target, dt * 12.0)
			queue_redraw()
		if _flash > 0.0:
			_flash = maxf(0.0, _flash - dt * 2.5)
			queue_redraw()
		elif targetable:
			queue_redraw()

	func hit() -> void:
		_flash = 1.0
		var tw := create_tween()
		var p := position
		for i in 4:
			tw.tween_property(self, "position", p + Vector2(randf_range(-7, 7), randf_range(-4, 4)), 0.04)
		tw.tween_property(self, "position", p, 0.05)

	func _draw() -> void:
		if inst == null:
			return
		var r := Rect2(Vector2.ZERO, size)
		var side := Kyber.C_REBEL if friendly else Kyber.C_EMPIRE
		if targetable:
			var k := 0.5 + 0.5 * sin(_t * 5.0)
			draw_rect(r.grow(5 + k * 3), Color(Kyber.C_EMPIRE, 0.5 + 0.4 * k), false, 4.0)
		draw_rect(r, Color("0a0f16"))
		if _tex and _tex != Art.placeholder:
			# landscape base render: crop the art band
			var ts := _tex.get_size()
			var src := Rect2(Vector2(ts.x * 0.04, ts.y * 0.06), Vector2(ts.x * 0.92, ts.y * 0.55))
			var asp := r.size.x / r.size.y
			if src.size.x / src.size.y > asp:
				var nw := src.size.y * asp
				src.position.x += (src.size.x - nw) / 2.0
				src.size.x = nw
			else:
				var nh := src.size.x / asp
				src.size.y = nh
			draw_texture_rect_region(_tex, r, src, Color(1, 1, 1, 0.85))
		else:
			# custom / art-less base: faction gradient + Aurebesh watermark
			for i in 8:
				var k := i / 8.0
				draw_rect(Rect2(Vector2(0, r.size.y * k), Vector2(r.size.x, r.size.y / 8.0 + 1)), side.darkened(0.55 + k * 0.35))
			UIKit.draw_fit(self, Kyber.font_aurebesh, Vector2(0, r.size.y * 0.42), str(inst.data.get("name", "")).to_lower(), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, int(r.size.y * 0.22), Color(1, 1, 1, 0.12))
		draw_rect(Rect2(Vector2(0, r.size.y * 0.55), Vector2(r.size.x, r.size.y * 0.45)), Color(0, 0, 0, 0.55))
		if _flash > 0:
			draw_rect(r, Color(1, 0.2, 0.1, _flash * 0.45))
		draw_rect(r, side, false, 3.0)
		var maxhp := inst.max_hp()
		var frac := clampf(_shown_hp / maxf(1.0, maxhp), 0.0, 1.0)
		var bar := Rect2(Vector2(8, r.size.y - 14), Vector2(r.size.x - 16, 8))
		draw_rect(bar, Color(0.1, 0.1, 0.12))
		var bc := Kyber.C_GOOD if frac > 0.5 else (Kyber.C_GOLD if frac > 0.25 else Kyber.C_EMPIRE)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), bc)
		var fs := int(clampf(r.size.y * 0.38, 18, 52))
		var hp_txt := str(roundi(_shown_hp))
		var hp_w := Kyber.font_title.get_string_size(hp_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		UIKit.draw_fit(self, Kyber.font_title, Vector2(10, r.size.y - 22), hp_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
		var max_txt := "/ %d" % maxhp
		var max_fs := int(fs * 0.45)
		var max_w := Kyber.font_body.get_string_size(max_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, max_fs).x
		UIKit.draw_fit(self, Kyber.font_body, Vector2(14 + hp_w, r.size.y - 22), max_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, max_fs, Kyber.C_DIM)
		# name gets only the space to the right of the HP readout
		var name_x := 24.0 + hp_w + max_w
		var nm: String = inst.data.get("name", "")
		UIKit.draw_fit(self, Kyber.font_title, Vector2(name_x, r.size.y - 22), nm.to_upper(), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - name_x - 8, int(clampf(r.size.y * 0.16, 12, 20)), Kyber.C_TEXT)
		_light_overlay()

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton:
			if ev.button_index == MOUSE_BUTTON_RIGHT and ev.pressed:
				inspect.emit()
			elif ev.button_index == MOUSE_BUTTON_LEFT:
				if ev.pressed:
					_press_t = 0.0
				elif _press_t >= 0.0:
					_press_t = -1.0
					pressed.emit()
			accept_event()


## Leader tile: shows leader side (landscape) or "DEPLOYED", epic-ready glow.
class LeaderView extends Control:
	var _light := 0.0
	var _light_col := Color.WHITE

	func apply_light(col: Color, amount: float, _from: Vector2) -> void:
		if amount > _light:
			_light = minf(amount, 1.0)
			_light_col = col
		queue_redraw()

	func _light_overlay() -> void:
		if _light > 0.01:
			draw_rect(Rect2(Vector2.ZERO, size), Color(_light_col.lightened(0.2), 0.28 * _light))
			draw_rect(Rect2(Vector2.ZERO, size), Color(_light_col.lightened(0.4), 0.8 * _light), false, 4.0)
		if _light > 0.0:
			_light = maxf(0.0, _light - get_process_delta_time() * 4.5)
			queue_redraw()

	signal pressed
	signal inspect
	var inst: CardInst
	var friendly := true
	var actionable := false:
		set(v):
			actionable = v
			queue_redraw()
	var _tex: Texture2D
	var _t := 0.0
	var _press_t := -1.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func card_id() -> String:
		return inst.id if inst else ""

	func set_leader(l: CardInst) -> void:
		inst = l
		visible = l != null
		if l == null:
			return
		var t := Art.request(l.data.get("art", l.id), func(tx): _tex = tx; queue_redraw())
		if t:
			_tex = t

	func refresh() -> void:
		queue_redraw()

	func _process(dt: float) -> void:
		_t += dt
		if actionable:
			queue_redraw()
		if _press_t >= 0.0:
			_press_t += dt
			if _press_t > 0.42:
				_press_t = -1.0
				inspect.emit()

	func _draw() -> void:
		if inst == null:
			return
		var r := Rect2(Vector2.ZERO, size)
		if actionable:
			var k := 0.5 + 0.5 * sin(_t * 4.0)
			draw_rect(r.grow(4 + 3 * k), Color(Kyber.C_GOLD, 0.45 + 0.4 * k), false, 4.0)
		var tint := Color(0.5, 0.5, 0.55) if (inst.exhausted or inst.deployed) else Color.WHITE
		if _tex and _tex != Art.placeholder:
			var ts := _tex.get_size()
			# leader front is landscape; crop the portrait art window on its left
			var src := Rect2(Vector2(ts.x * 0.07, ts.y * 0.09), Vector2(ts.x * 0.38, ts.y * 0.72))
			var asp := r.size.x / r.size.y
			if src.size.x / src.size.y > asp:
				var nw := src.size.y * asp
				src.position.x += (src.size.x - nw) / 2.0
				src.size.x = nw
			else:
				var nh := src.size.x / asp
				src.position.y += (src.size.y - nh) * 0.2
				src.size.y = nh
			draw_texture_rect_region(_tex, r, src, tint)
		else:
			draw_rect(r, Color("1a2636"))
		draw_rect(r, Kyber.C_GOLD, false, 3.0)
		var strip := Rect2(Vector2(0, r.size.y - 22), Vector2(r.size.x, 22))
		draw_rect(strip, Color(0, 0, 0, 0.7))
		var label := inst.name()
		if inst.deployed:
			label = "DEPLOYED"
		elif inst.exhausted:
			label = "EXHAUSTED"
		UIKit.draw_fit(self, Kyber.font_title, strip.position + Vector2(0, 16), label, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 14, Kyber.C_GOLD if actionable else Kyber.C_TEXT)
		_light_overlay()

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton:
			if ev.button_index == MOUSE_BUTTON_RIGHT and ev.pressed:
				inspect.emit()
			elif ev.button_index == MOUSE_BUTTON_LEFT:
				if ev.pressed:
					_press_t = 0.0
				elif _press_t >= 0.0:
					_press_t = -1.0
					pressed.emit()
			accept_event()


## Resource pips: gold = ready, dim = exhausted.
class ResourceView extends Control:
	signal pressed
	var ready_n := 0
	var total := 0
	var _shown := -1

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _draw() -> void:
		var n := maxi(total, 1)
		var pip := clampf(minf(size.x / (minf(n, 8) * 1.15 + 2.5), size.y * 0.75), 12.0, 34.0)
		UIKit.draw_fit(self, Kyber.font_title, Vector2(0, pip * 0.8), "%d/%d" % [ready_n, total], HORIZONTAL_ALIGNMENT_LEFT, -1, int(pip * 0.8), Kyber.C_COST)
		var x0 := pip * 2.6
		for i in total:
			var row := i / 8
			var col := i % 8
			var c := Vector2(x0 + col * pip * 1.12, pip * 0.5 + row * pip * 1.05)
			var hexp := PackedVector2Array()
			for k in 6:
				var a := PI / 6 + k * PI / 3.0
				hexp.append(c + Vector2(cos(a), sin(a)) * pip * 0.5)
			var is_ready := i < ready_n
			draw_colored_polygon(hexp, Kyber.C_COST if is_ready else Color(0.25, 0.22, 0.12))
			hexp.append(hexp[0])
			draw_polyline(hexp, Color(1, 0.95, 0.7, 0.9 if is_ready else 0.3), 1.5, true)

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			pressed.emit()
			accept_event()
