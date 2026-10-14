class_name Starfield
extends Control
## Cheap animated background: parallax star layers, optional hyperspace streaks
## and an optional backdrop image with slow Ken Burns drift. Static in perf mode.

var backdrop: Texture2D
var backdrop_alpha := 0.55
var hyperspace := 0.0     # 0..1 streak amount (animate for transitions)
var drift := Vector2(-6, 2)
var _stars: Array = []
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 160:
		_stars.append({"p": Vector2(rng.randf(), rng.randf()), "z": rng.randf_range(0.2, 1.0), "tw": rng.randf() * TAU})
	resized.connect(queue_redraw)


func _process(dt: float) -> void:
	if Kyber.perf() and hyperspace <= 0.0:
		return
	_t += dt
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Kyber.C_BG)
	if backdrop:
		var ts := backdrop.get_size()
		var sc := maxf(size.x / ts.x, size.y / ts.y) * (1.08 + 0.03 * sin(_t * 0.07))
		var ds := ts * sc
		var off := (size - ds) / 2.0 + Vector2(sin(_t * 0.05), cos(_t * 0.04)) * 12.0
		draw_texture_rect(backdrop, Rect2(off, ds), false, Color(1, 1, 1, backdrop_alpha))
		draw_rect(Rect2(Vector2.ZERO, size), Color(Kyber.C_BG, 0.25))
	var center := size / 2.0
	for s in _stars:
		var p: Vector2 = s["p"]
		var z: float = s["z"]
		var pos := Vector2(fposmod(p.x * size.x + drift.x * _t * z, size.x), fposmod(p.y * size.y + drift.y * _t * z, size.y))
		var tw := 0.6 + 0.4 * sin(_t * 2.0 + s["tw"])
		var col := Color(0.8, 0.9, 1.0, z * tw * (0.5 if backdrop else 0.9))
		if hyperspace > 0.0:
			var dir := (pos - center).normalized()
			draw_line(pos, pos + dir * hyperspace * 120.0 * z, col, 1.5 * z)
		else:
			draw_circle(pos, 1.6 * z, col)
