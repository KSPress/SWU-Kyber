class_name Fx
extends RefCounted

## Controls that react to light from bolts and impacts (UnitToken, base and
## leader tiles). Each implements apply_light(color: Color, amount: float, from: Vector2).
static var light_targets: Array = []


static func light_at(pos: Vector2, col: Color, radius: float, strength: float) -> void:
	for t in light_targets:
		if not is_instance_valid(t) or not t.is_visible_in_tree():
			continue
		var r: Rect2 = t.get_global_rect()
		var d := r.get_center().distance_to(pos) - maxf(r.size.x, r.size.y) * 0.35
		var k := clampf(1.0 - d / radius, 0.0, 1.0)
		if k > 0.0:
			t.apply_light(col, k * k * strength, pos)
## GPU-cheap combat effects (spec 8.4): lightsaber swipes coloured per character,
## blaster bolts, impact rings/sparks, shield shatter, floating numbers, banners.
## All effects are self-freeing nodes added to an fx layer Control.


static func float_text(layer: Control, at: Vector2, text: String, col: Color, size := 40) -> void:
	var l := UIKit.label(text, size, col, HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_font_override("font", Kyber.font_title)
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.size = Vector2(160, 60)
	l.pivot_offset = l.size / 2.0
	layer.add_child(l)
	l.global_position = at - l.size / 2.0
	l.scale = Vector2(0.4, 0.4)
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector2(1.25, 1.25), Kyber.anim(0.14)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "scale", Vector2.ONE, Kyber.anim(0.1))
	tw.parallel().tween_property(l, "position:y", l.position.y - 70, Kyber.anim(0.9)).set_delay(Kyber.anim(0.1))
	tw.tween_property(l, "modulate:a", 0.0, Kyber.anim(0.3))
	tw.tween_callback(l.queue_free)


static func banner(layer: Control, text: String, col: Color, sub := "") -> void:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vs := layer.get_viewport_rect().size
	box.size = Vector2(vs.x, 140)
	box.position = Vector2(0, vs.y * 0.42 - 70)
	var bar := ColorRect.new()
	bar.color = Color(0, 0, 0, 0.6)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.size = box.size
	bar.position = box.position
	layer.add_child(bar)
	var l := UIKit.title(text, 56, col)
	box.add_child(l)
	if sub != "":
		box.add_child(UIKit.aurebesh(sub, 22))
	layer.add_child(box)
	box.modulate.a = 0.0
	bar.modulate.a = 0.0
	box.position.x = -vs.x * 0.3
	var tw := box.create_tween().set_parallel(true)
	tw.tween_property(box, "position:x", 0.0, Kyber.anim(0.25)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(box, "modulate:a", 1.0, Kyber.anim(0.2))
	tw.tween_property(bar, "modulate:a", 1.0, Kyber.anim(0.2))
	tw.chain().tween_interval(Kyber.anim(0.6))
	tw.chain().tween_property(box, "position:x", vs.x * 0.3, Kyber.anim(0.25)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(box, "modulate:a", 0.0, Kyber.anim(0.25))
	tw.parallel().tween_property(bar, "modulate:a", 0.0, Kyber.anim(0.25))
	tw.chain().tween_callback(func():
		box.queue_free()
		bar.queue_free())


static func impact(layer: Control, at: Vector2, col: Color, big := false) -> void:
	var n := FxImpact.new()
	n.color = col
	n.big = big
	layer.add_child(n)
	n.global_position = at


static func blaster(layer: Control, from: Vector2, to: Vector2, col: Color, bolts := 3) -> float:
	for i in bolts:
		var b := FxBolt.new()
		b.from = from + Vector2(randf_range(-10, 10), randf_range(-10, 10))
		b.to = to + Vector2(randf_range(-14, 14), randf_range(-14, 14))
		b.color = col
		b.delay = i * 0.07
		layer.add_child(b)
	Sfx.play("blaster")
	return 0.25 + bolts * 0.07


static func saber(layer: Control, at: Vector2, col: Color) -> float:
	var s := FxSaber.new()
	s.color = col
	layer.add_child(s)
	s.global_position = at
	Sfx.play("saber")
	return 0.32


static func shatter(layer: Control, at: Vector2) -> void:
	var s := FxImpact.new()
	s.color = Color(0.5, 0.9, 1.0)
	s.shards = true
	layer.add_child(s)
	s.global_position = at
	Sfx.play("shield")


## Arrow used while dragging an attacker toward a target.
class TargetArrow extends Node2D:
	var from := Vector2.ZERO
	var to := Vector2.ZERO
	var color := Kyber.C_EMPIRE
	var _t := 0.0

	func _process(dt: float) -> void:
		_t += dt
		queue_redraw()

	func _draw() -> void:
		var d := to - from
		var len := d.length()
		if len < 4:
			return
		var dir := d / len
		var n := Vector2(-dir.y, dir.x)
		var mid := from + d * 0.5 + n * minf(len * 0.18, 80.0)
		var pts := PackedVector2Array()
		for i in 21:
			var t := i / 20.0
			pts.append(from.lerp(mid, t).lerp(mid.lerp(to, t), t))
		draw_polyline(pts, Color(color, 0.35), 14.0, true)
		draw_polyline(pts, color, 5.0, true)
		# moving chevrons
		for i in 5:
			var t := fposmod(_t * 0.8 + i / 5.0, 1.0)
			var p := from.lerp(mid, t).lerp(mid.lerp(to, t), t)
			draw_circle(p, 4.0, Color.WHITE)
		var tip_dir := (to - pts[18]).normalized()
		var tn := Vector2(-tip_dir.y, tip_dir.x)
		draw_colored_polygon(PackedVector2Array([to + tip_dir * 8, to - tip_dir * 22 + tn * 16, to - tip_dir * 22 - tn * 16]), color)
		draw_arc(to, 30.0 + 4.0 * sin(_t * 8.0), 0, TAU, 32, Color(color, 0.8), 3.0, true)


class FxImpact extends Node2D:
	var color := Color.WHITE
	var big := false
	var shards := false
	var _t := 0.0
	var _sparks: Array = []

	func _ready() -> void:
		var n := 0 if Kyber.perf() else (14 if big else 8)
		for i in n:
			var a := randf() * TAU
			_sparks.append({"v": Vector2(cos(a), sin(a)) * randf_range(120, 380), "p": Vector2.ZERO})

	func _process(dt: float) -> void:
		_t += dt
		for s in _sparks:
			s["p"] += s["v"] * dt
			s["v"] *= 0.9
		queue_redraw()
		if _t > 0.5:
			queue_free()

	func _draw() -> void:
		var k := _t / 0.5
		var r := (60.0 if big else 38.0) * (0.3 + k)
		draw_arc(Vector2.ZERO, r, 0, TAU, 32, Color(color, 1.0 - k), 6.0 * (1.0 - k) + 1.0, true)
		draw_circle(Vector2.ZERO, r * 0.35 * (1.0 - k), Color(1, 1, 1, 0.8 * (1.0 - k)))
		for s in _sparks:
			var p: Vector2 = s["p"]
			if shards:
				var d: Vector2 = s["v"].normalized() * 10.0
				draw_line(p, p + d, Color(color, 1.0 - k), 3.0)
			else:
				draw_line(p, p - s["v"] * 0.03, Color(color.lightened(0.4), 1.0 - k), 2.0)


class FxBolt extends Node2D:
	var from := Vector2.ZERO
	var to := Vector2.ZERO
	var color := Color.RED
	var delay := 0.0
	var _t := 0.0

	func _process(dt: float) -> void:
		_t += dt
		queue_redraw()
		if _t > delay + 0.3:
			queue_free()

	func _draw() -> void:
		var k := (_t - delay) / 0.2
		if k < 0.0 or k > 1.2:
			return
		var head := from.lerp(to, clampf(k, 0, 1))
		var tail := from.lerp(to, clampf(k - 0.25, 0, 1))
		var gp := get_global_transform().affine_inverse()
		draw_line(gp * tail, gp * head, Color(color, 0.35), 10.0, true)
		draw_line(gp * tail, gp * head, color.lightened(0.5), 3.5, true)


class FxSaber extends Node2D:
	var color := Color(0.3, 0.6, 1.0)
	var _t := 0.0

	func _process(dt: float) -> void:
		_t += dt
		queue_redraw()
		if _t > 0.4:
			queue_free()

	func _draw() -> void:
		var k := clampf(_t / 0.22, 0.0, 1.0)
		var fade := 1.0 - clampf((_t - 0.22) / 0.18, 0.0, 1.0)
		var a0 := -2.4
		var a1 := lerpf(a0, 0.7, k)
		var r := 70.0
		for i in 4:
			draw_arc(Vector2.ZERO, r - i * 6, a0 + (a1 - a0) * 0.2 * i, a1, 24, Color(color, (0.25 + i * 0.18) * fade), 10.0 - i * 2, true)
		draw_arc(Vector2.ZERO, r - 6, a1 - 0.5, a1, 12, Color(1, 1, 1, fade), 3.0, true)


# ================================================================ dramatic attack FX

## Lightsaber: hilt + blade whose `length` (0..1) ignites/retracts and whose
## `angle` sweeps for the swing; keeps after-images for a glowing trail.
class FxSaberBlade extends Node2D:
	var color := Color(0.35, 0.65, 1.0)
	var length := 0.0         # 0..1 ignition
	var angle := -PI / 2.0    # radians, 0 = pointing right
	var blade_px := 130.0
	var follow: Control       # keeps the hilt beside this token
	var offset := Vector2.ZERO
	var _trail: Array = []    # [angle, alpha]
	var _flicker := 0.0

	func _process(dt: float) -> void:
		_flicker += dt
		if is_instance_valid(follow) and follow.has_method("center_global"):
			global_position = follow.center_global() + offset
		_trail.push_front([angle, 1.0])
		for t in _trail:
			t[1] -= dt * 5.0
		while _trail.size() > 0 and _trail.back()[1] <= 0.0:
			_trail.pop_back()
		queue_redraw()

	func _blade_pts(a: float, l: float) -> Array:
		var dir := Vector2(cos(a), sin(a))
		return [dir * 14.0, dir * (14.0 + blade_px * l)]

	func _draw() -> void:
		var fl := 0.92 + 0.08 * sin(_flicker * 47.0)
		# swing trail: filled glowing wedges between successive blade positions
		if length > 0.5:
			for i in range(_trail.size() - 1):
				var a0: float = _trail[i][0]
				var a1: float = _trail[i + 1][0]
				if absf(a0 - a1) < 0.01:
					continue
				var al: float = _trail[i][1]
				var p0: Array = _blade_pts(a0, length)
				var p1: Array = _blade_pts(a1, length)
				var quad := PackedVector2Array([p0[0], p0[1], p1[1], p1[0]])
				draw_colored_polygon(quad, Color(color, 0.42 * al))
				draw_line(p0[1], p1[1], Color(1, 1, 1, 0.5 * al), 3.0, true)
		var b: Array = _blade_pts(angle, length)
		if length > 0.02:
			draw_line(b[0], b[1], Color(color, 0.18 * fl), 30.0, true)
			draw_line(b[0], b[1], Color(color, 0.45 * fl), 16.0, true)
			draw_line(b[0], b[1], color.lightened(0.5), 8.0, true)
			draw_line(b[0], b[1], Color(1, 1, 1, 0.95), 3.5, true)
			draw_circle(b[1], 4.0, Color(1, 1, 1, 0.9))
		# hilt
		var dir := Vector2(cos(angle), sin(angle))
		var n := Vector2(-dir.y, dir.x)
		var hilt := PackedVector2Array([-dir * 22.0 + n * 4.0, dir * 14.0 + n * 4.5, dir * 14.0 - n * 4.5, -dir * 22.0 - n * 4.0])
		draw_colored_polygon(hilt, Color(0.75, 0.78, 0.82))
		draw_line(-dir * 6.0 + n * 5.0, -dir * 6.0 - n * 5.0, Color(0.2, 0.2, 0.22), 3.0)
		draw_line(dir * 10.0 + n * 5.0, dir * 10.0 - n * 5.0, Color(0.2, 0.2, 0.22), 2.0)


## Muzzle flash: a quick star burst.
class FxMuzzle extends Node2D:
	var color := Color.ORANGE
	var dir := Vector2.RIGHT
	var _t := 0.0

	func _process(dt: float) -> void:
		_t += dt
		queue_redraw()
		if _t > 0.12:
			queue_free()

	func _draw() -> void:
		var k := 1.0 - _t / 0.12
		var n := Vector2(-dir.y, dir.x)
		draw_colored_polygon(PackedVector2Array([dir * 34.0 * k, n * 9.0 * k, -dir * 6.0, -n * 9.0 * k]), Color(1, 1, 0.85, k))
		draw_circle(Vector2.ZERO, 12.0 * k, Color(color.lightened(0.4), 0.8 * k))


## Shockwave for melee slams: expanding double ring + flying debris.
class FxShockwave extends Node2D:
	var color := Color(1, 0.85, 0.6)
	var _t := 0.0
	var _rocks: Array = []

	func _ready() -> void:
		var n := 0 if Kyber.perf() else 12
		for i in n:
			var a := randf() * TAU
			_rocks.append({"p": Vector2.ZERO, "v": Vector2(cos(a), sin(a) * 0.6) * randf_range(160, 420), "s": randf_range(3, 7)})

	func _process(dt: float) -> void:
		_t += dt
		for r in _rocks:
			r["p"] += r["v"] * dt
			r["v"] = r["v"] * 0.88 + Vector2(0, 600) * dt
		queue_redraw()
		if _t > 0.6:
			queue_free()

	func _draw() -> void:
		var k := _t / 0.6
		draw_arc(Vector2.ZERO, 30.0 + k * 140.0, 0, TAU, 48, Color(color, (1.0 - k) * 0.9), 10.0 * (1.0 - k) + 1.0, true)
		draw_arc(Vector2.ZERO, 15.0 + k * 90.0, 0, TAU, 48, Color(1, 1, 1, (1.0 - k) * 0.6), 4.0, true)
		for r in _rocks:
			draw_rect(Rect2(r["p"], Vector2(r["s"], r["s"])), Color(0.55, 0.45, 0.35, 1.0 - k))


## Heavier blaster bolt: glow + white core, impact burst on arrival.
class FxBolt2 extends Node2D:
	var from := Vector2.ZERO
	var to := Vector2.ZERO
	var color := Color.RED
	var delay := 0.0
	var speed := 0.16          # seconds of flight
	var thickness := 1.0
	var host: Control
	var _t := 0.0
	var _hit := false

	func _process(dt: float) -> void:
		_t += dt
		queue_redraw()
		var k := (_t - delay) / speed
		if k >= 0.0 and k < 1.0:
			# bolt light spills onto the cards it passes over
			Fx.light_at(from.lerp(to, k), color, 120.0 * thickness, 0.85)
		if k >= 1.0 and not _hit:
			_hit = true
			if host:
				Fx.punch(host, to, color, 0.55 + 0.25 * thickness, from)
				Sfx.play("hit", randf_range(1.1, 1.4))
		if _t > delay + speed + 0.12:
			queue_free()

	func _draw() -> void:
		var k := (_t - delay) / speed
		if k < 0.0 or k > 1.15:
			return
		var head := from.lerp(to, clampf(k, 0, 1))
		var tail := from.lerp(to, clampf(k - 0.35, 0, 1))
		var gp := get_global_transform().affine_inverse()
		var a := gp * tail
		var b := gp * head
		draw_line(a, b, Color(color, 0.25), 18.0 * thickness, true)
		draw_line(a, b, Color(color, 0.7), 9.0 * thickness, true)
		draw_line(a, b, Color(1, 1, 1, 0.95), 3.0 * thickness, true)


static func muzzle(layer: Control, at: Vector2, dir: Vector2, col: Color) -> void:
	var m := FxMuzzle.new()
	m.color = col
	m.dir = dir.normalized()
	layer.add_child(m)
	m.global_position = at


## Volley of heavy bolts; returns the total duration.
static func volley(layer: Control, from: Vector2, to: Vector2, col: Color, count: int, gap := 0.08, thickness := 1.0, spread := 16.0) -> float:
	for i in count:
		var b := FxBolt2.new()
		b.from = from + Vector2(randf_range(-6, 6), randf_range(-6, 6))
		b.to = to + Vector2(randf_range(-spread, spread), randf_range(-spread, spread))
		b.color = col
		b.delay = i * gap
		b.thickness = thickness
		b.host = layer
		layer.add_child(b)
		layer.get_tree().create_timer(i * gap).timeout.connect(func():
			if is_instance_valid(layer):
				muzzle(layer, from, to - from, col)
				Sfx.play("blaster", randf_range(0.85, 1.15) / maxf(0.8, thickness)))
	return count * gap + 0.18


static func shockwave(layer: Control, at: Vector2) -> void:
	var s := FxShockwave.new()
	layer.add_child(s)
	s.global_position = at
	Sfx.play("defeat", 1.6)


## Shakes a control around its current position.
static func shake(c: Control, amount := 10.0, dur := 0.25) -> void:
	if Kyber.perf() or c == null:
		return
	var base := c.position
	var tw := c.create_tween()
	var steps := 6
	for i in steps:
		var k := 1.0 - float(i) / steps
		tw.tween_property(c, "position", base + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * amount * k, dur / steps)
	tw.tween_property(c, "position", base, 0.04)



# ================================================================ punchy impact

## Hard-hitting impact: white-hot core flash, light burst on nearby cards,
## a thick shock ring, fast spark streaks thrown away from the shooter,
## glowing embers and a puff of smoke. `power` ~0.5 (single bolt) .. 1.5 (finisher).
static func punch(layer: Control, at: Vector2, col: Color, power := 1.0, from := Vector2.INF) -> void:
	var n := FxPunch.new()
	n.color = col
	n.power = power
	n.away = (at - from).normalized() if from != Vector2.INF else Vector2.ZERO
	layer.add_child(n)
	n.global_position = at
	light_at(at, col.lightened(0.35), 240.0 * power, 1.4 * power)


class FxPunch extends Node2D:
	var color := Color.WHITE
	var power := 1.0
	var away := Vector2.ZERO
	var _t := 0.0
	var _sparks: Array = []
	var _embers: Array = []
	var _smoke: Array = []
	const LIFE := 0.6

	func _ready() -> void:
		var perf := Kyber.perf()
		var n := 6 if perf else int(10 + 10 * power)
		for i in n:
			var a := randf() * TAU
			var v := Vector2(cos(a), sin(a))
			if away != Vector2.ZERO:
				v = (v + away * 1.3).normalized()
			_sparks.append({"p": Vector2.ZERO, "v": v * randf_range(380, 900) * (0.6 + 0.4 * power), "len": randf_range(10, 26)})
		if not perf:
			for i in int(4 + 4 * power):
				var a2 := randf() * TAU
				_embers.append({"p": Vector2.ZERO, "v": Vector2(cos(a2), sin(a2)) * randf_range(60, 220), "s": randf_range(2, 4)})
			for i in 4:
				var a3 := randf() * TAU
				_smoke.append({"p": Vector2(cos(a3), sin(a3)) * randf_range(4, 16), "s": randf_range(14, 26)})

	func _process(dt: float) -> void:
		_t += dt
		for s in _sparks:
			s["p"] += s["v"] * dt
			s["v"] *= 0.86
		for e in _embers:
			e["p"] += e["v"] * dt
			e["v"] = e["v"] * 0.95 + Vector2(0, 380) * dt
		for m in _smoke:
			m["p"] += m["p"].normalized() * 26.0 * dt
		queue_redraw()
		if _t > LIFE:
			queue_free()

	func _draw() -> void:
		var k := _t / LIFE
		var pw := power
		var core := clampf(1.0 - _t / 0.14, 0.0, 1.0)
		if core > 0.0:
			var grow := minf(_t / 0.04, 1.0)
			draw_circle(Vector2.ZERO, 70.0 * pw * grow, Color(color.lightened(0.5), 0.35 * core))
			draw_circle(Vector2.ZERO, 40.0 * pw * grow, Color(1, 1, 1, 0.95 * core))
		var bloom := clampf(1.0 - _t / 0.3, 0.0, 1.0)
		draw_circle(Vector2.ZERO, 120.0 * pw, Color(color, 0.12 * bloom))
		var ring_k := 1.0 - pow(1.0 - minf(_t / 0.35, 1.0), 3.0)
		var ring_a := clampf(1.0 - _t / 0.35, 0.0, 1.0)
		if ring_a > 0.0:
			draw_arc(Vector2.ZERO, 18.0 + 110.0 * pw * ring_k, 0, TAU, 48, Color(color.lightened(0.3), ring_a), 9.0 * ring_a * pw + 1.0, true)
			draw_arc(Vector2.ZERO, 10.0 + 70.0 * pw * ring_k, 0, TAU, 40, Color(1, 1, 1, ring_a * 0.7), 3.0, true)
		for m in _smoke:
			draw_circle(m["p"], m["s"] * (1.0 + k * 1.5) * pw, Color(0.25, 0.22, 0.2, 0.22 * (1.0 - k)))
		for s in _sparks:
			var v: Vector2 = s["v"]
			var a := clampf(1.0 - _t / 0.4, 0.0, 1.0)
			if a <= 0.0:
				continue
			var p: Vector2 = s["p"]
			var tail: Vector2 = p - v.normalized() * s["len"] * (0.5 + v.length() / 900.0)
			draw_line(tail, p, Color(color.lightened(0.6), a), 2.5, true)
			draw_line(tail, p, Color(1, 1, 1, a * 0.8), 1.0, true)
		for e in _embers:
			draw_circle(e["p"], e["s"] * (1.0 - k), Color(1.0, 0.7, 0.3, 1.0 - k))
