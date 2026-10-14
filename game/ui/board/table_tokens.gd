class_name TableTokens
extends RefCounted
## Physical-feeling tokens on the table:
##   InitiativeCoin — gold coin that sits with whoever holds the initiative,
##     flies (arc + spin + flip) to a player who claims it, shows its dark
##     "claimed" side until the next round. Tap it to claim.
##   ForceOrb — the Force token: gathered from motes of light that stream in,
##     hovers by the base, bursts away when used.


class InitiativeCoin extends Control:
	signal pressed
	const SIZE := 84.0
	var claimed := false
	var holder := 0
	var claimable := false:
		set(v):
			claimable = v
			queue_redraw()
	var _t := 0.0
	var _flip := 1.0          # -1..1, horizontal squash while flipping
	var _flying := false

	func _ready() -> void:
		custom_minimum_size = Vector2(SIZE, SIZE)
		size = Vector2(SIZE, SIZE)
		pivot_offset = size / 2.0
		mouse_filter = Control.MOUSE_FILTER_STOP
		tooltip_text = "Initiative — tap to claim (ends your actions this round)"

	func _process(dt: float) -> void:
		_t += dt
		queue_redraw()

	func _draw() -> void:
		var c := size / 2.0
		var sx := absf(_flip)
		var face_claimed := claimed if _flip >= 0.0 else not claimed
		var tex := Art.ui_texture("tokens/initiative")
		var ts := tex.get_size() if tex else Vector2(174, 140)
		var w := SIZE * 1.25
		var h := w * ts.y / ts.x
		var tr := Transform2D(0.0, Vector2(maxf(0.06, sx), 1.0), 0.0, c)
		draw_set_transform_matrix(tr)
		if claimable and not face_claimed and not _flying:
			var k := 0.5 + 0.5 * sin(_t * 4.0)
			for i in 3:
				draw_circle(Vector2.ZERO, w * (0.5 + i * 0.08) + 4 * k, Color(1.0, 0.8, 0.25, (0.12 + 0.1 * k) / (i + 1)))
		# drop shadow
		if tex:
			draw_texture_rect(tex, Rect2(Vector2(-w / 2.0 + 3, -h / 2.0 + 5), Vector2(w, h)), false, Color(0, 0, 0, 0.5))
			var tint := Color.WHITE if not face_claimed else Color(0.42, 0.42, 0.46, 0.95)
			draw_texture_rect(tex, Rect2(-Vector2(w, h) / 2.0, Vector2(w, h)), false, tint)
		# moving glint across the gold inlay
		if not face_claimed:
			var g := fposmod(_t * 0.5, 2.6) - 1.3
			if absf(g) < 1.0:
				draw_line(Vector2(g * w * 0.5 - w * 0.12, -h * 0.4), Vector2(g * w * 0.5 + w * 0.12, h * 0.4), Color(1, 1, 0.9, 0.28 * (1.0 - absf(g))), 7.0)
		draw_set_transform_matrix(Transform2D.IDENTITY)
		var label := "CLAIMED" if face_claimed else ("TAP TO CLAIM" if claimable else "INITIATIVE")
		UIKit.draw_fit(self, Kyber.font_title, Vector2(-14, size.y + 12), label, HORIZONTAL_ALIGNMENT_CENTER, size.x + 28, 12,
			Kyber.C_GOLD if not face_claimed else Kyber.C_DIM)

	## Flip to the other face with a squash animation.
	func flip_to(p_claimed: bool) -> void:
		if p_claimed == claimed:
			return
		var tw := create_tween()
		tw.tween_property(self, "_flip", -1.0, Kyber.anim(0.3)).from(1.0).set_trans(Tween.TRANS_SINE)
		tw.tween_callback(func():
			claimed = p_claimed
			_flip = 1.0)
		Sfx.play("click", 0.7)

	## Fly in an arc to `dest` (local position in parent), spinning and flipping.
	func fly_to(dest: Vector2, p_holder: int, p_claimed: bool) -> void:
		holder = p_holder
		_flying = true
		var start := position
		# arc out toward the middle of the board, never off-screen
		var mid := (start + dest) / 2.0
		var vs := get_viewport_rect().size
		var peak := Vector2(lerpf(mid.x, vs.x * 0.5, 0.7), mid.y)
		Sfx.play("whoosh", 1.6)
		z_index = 60
		var tw := create_tween().set_parallel(true)
		tw.tween_method(func(k: float):
			var a := start.lerp(peak, k)
			var b := peak.lerp(dest, k)
			position = a.lerp(b, k)
			scale = Vector2.ONE * (1.0 + 0.45 * sin(k * PI)), 0.0, 1.0, Kyber.anim(0.75)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		# spin: several flips in the air, landing on the right face
		tw.tween_method(func(k: float):
			_flip = cos(k * TAU * 3.0), 0.0, 1.0, Kyber.anim(0.75))
		await tw.finished
		claimed = p_claimed
		_flip = 1.0
		z_index = 0
		_flying = false
		Sfx.play("deploy", 1.8)
		var bounce := create_tween()
		bounce.tween_property(self, "scale", Vector2(1.18, 0.85), 0.06)
		bounce.tween_property(self, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_ELASTIC)

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			pressed.emit()
			accept_event()


class ForceOrb extends Control:
	const SIZE := 70.0
	var active := false
	var _t := 0.0
	var _motes: Array = []     # gathering particles: {from, delay}
	var _gather := -1.0
	var _burst := -1.0

	func _ready() -> void:
		size = Vector2(SIZE, SIZE)
		pivot_offset = size / 2.0
		mouse_filter = Control.MOUSE_FILTER_PASS
		tooltip_text = "The Force — your Force token"
		visible = false

	func _process(dt: float) -> void:
		_t += dt
		if _gather >= 0.0:
			_gather += dt / Kyber.anim(0.9)
			if _gather >= 1.0:
				_gather = -1.0
				_motes.clear()
		if _burst >= 0.0:
			_burst += dt / Kyber.anim(0.6)
			if _burst >= 1.0:
				_burst = -1.0
				if not active:
					visible = false
		queue_redraw()

	## Motes of light stream in from around the screen and form the orb.
	func gather() -> void:
		active = true
		visible = true
		_burst = -1.0
		_gather = 0.0
		_motes.clear()
		var vs := get_viewport_rect().size
		var me := global_position + size / 2.0
		for i in (10 if Kyber.perf() else 28):
			var a := randf() * TAU
			var d := randf_range(0.35, 0.8) * maxf(vs.x, vs.y)
			_motes.append({"from": me + Vector2(cos(a), sin(a)) * d - me, "delay": randf() * 0.35})
		Sfx.play("saber_on", 1.6)

	func spend() -> void:
		active = false
		_burst = 0.0
		Sfx.play("shield", 0.7)

	func _draw() -> void:
		var c := size / 2.0
		var r := SIZE * 0.32
		if _gather >= 0.0:
			for mt in _motes:
				var k := clampf((_gather - mt["delay"]) / (1.0 - mt["delay"]), 0.0, 1.0)
				if k <= 0.0:
					continue
				var p: Vector2 = c + (mt["from"] as Vector2) * (1.0 - k) * (1.0 - k)
				var trail: Vector2 = (mt["from"] as Vector2).normalized() * 18.0 * (1.0 - k)
				draw_line(p, p + trail, Color(0.6, 0.85, 1.0, 0.6 * k), 3.0, true)
				draw_circle(p, 3.0, Color(0.85, 0.95, 1.0, k))
		var grow := 1.0
		if _gather >= 0.0:
			grow = clampf((_gather - 0.55) / 0.45, 0.0, 1.0)
		var back := false
		if _burst >= 0.0:
			var b := _burst
			for i in 3:
				draw_arc(c, r * (1.6 + b * (2.0 + i)), 0, TAU, 32, Color(0.6, 0.85, 1.0, (1.0 - b) * 0.6), 3.0, true)
			back = b > 0.25                      # flipped to the blue side as it fades
			grow = 1.0 - maxf(0.0, b - 0.25) / 0.75
		if not active and _burst < 0.0:
			return
		if grow <= 0.0:
			return
		var pulse := 0.5 + 0.5 * sin(_t * 3.0)
		var tok_r := SIZE * 0.5 * grow
		for i in 3:
			draw_circle(c, tok_r * (1.12 + i * 0.12 + pulse * 0.05), Color(1.0, 0.82, 0.4, 0.07) if not back else Color(0.45, 0.7, 1.0, 0.07))
		var tex := Art.ui_texture("tokens/force_back" if back else "tokens/force")
		var flip_sx := 1.0
		if _burst >= 0.0 and _burst < 0.5:
			flip_sx = absf(cos(_burst / 0.5 * PI))   # coin flip
		if tex:
			draw_set_transform(c, sin(_t * 0.7) * 0.05, Vector2(flip_sx, 1.0))
			draw_texture_rect(tex, Rect2(-Vector2(tok_r, tok_r), Vector2(tok_r, tok_r) * 2.0), false, Color(1, 1, 1, 1.0 if not back else 0.85))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# glints orbiting the token
		for i in 3:
			var a2 := _t * 2.2 + i * TAU / 3.0
			draw_circle(c + Vector2(cos(a2), sin(a2) * 0.55) * tok_r * 1.15, 2.2, Color(1.0, 0.92, 0.6, 0.85))


## Claimable token in the tray (Plan, Blast...) shown with its real token art.
class TokenButton extends Control:
	signal pressed
	var tex: Texture2D
	var label := ""
	var claimable := false
	var claimed := false
	var _t := 0.0
	var _hover := false

	func _ready() -> void:
		custom_minimum_size = Vector2(92, 92)
		mouse_filter = Control.MOUSE_FILTER_STOP
		pivot_offset = custom_minimum_size / 2.0
		mouse_entered.connect(func(): _hover = true)
		mouse_exited.connect(func(): _hover = false)

	func _process(dt: float) -> void:
		_t += dt
		queue_redraw()

	func _draw() -> void:
		var s := size
		var ts := tex.get_size()
		var w := s.x * 0.95
		var h := minf(w * ts.y / ts.x, s.y - 22)
		w = h * ts.x / ts.y
		var r := Rect2(Vector2((s.x - w) / 2.0, 2), Vector2(w, h))
		if claimable:
			var k := 0.5 + 0.5 * sin(_t * 4.0)
			draw_circle(r.get_center(), w * 0.62 + 3 * k, Color(1, 0.85, 0.4, 0.12 + 0.1 * k))
		var lift := Vector2(0, -3) if _hover and claimable else Vector2.ZERO
		draw_texture_rect(tex, Rect2(r.position + Vector2(2, 4), r.size), false, Color(0, 0, 0, 0.45))
		draw_texture_rect(tex, Rect2(r.position + lift, r.size), false, Color.WHITE if claimable else Color(0.45, 0.45, 0.5, 0.85))
		UIKit.draw_fit(self, Kyber.font_title, Vector2(0, s.y - 4), ("%s ✓" % label) if claimed else label.to_upper(),
			HORIZONTAL_ALIGNMENT_CENTER, s.x, 12, Kyber.C_GOLD if claimable else Kyber.C_DIM)

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			if claimable:
				Sfx.play("click")
				var tw := create_tween()
				tw.tween_property(self, "scale", Vector2(1.15, 1.15), 0.06)
				tw.tween_property(self, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_ELASTIC)
				pressed.emit()
			accept_event()
