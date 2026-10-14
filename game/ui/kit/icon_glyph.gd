class_name IconGlyph
extends Control
## Vector icons drawn in code (keyword badges, node types, HUD). No image assets,
## crisp at any size, and animatable: `pulse` breathes, `spin` rotates the accent ring.

var glyph := "dot":
	set(v):
		glyph = v
		queue_redraw()
var color := Kyber.C_KYBER:
	set(v):
		color = v
		queue_redraw()
var bg := Color(0, 0, 0, 0)
var frame := false          # draw a chamfered badge frame behind the glyph
var pulse := false
var spin := false
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _process(dt: float) -> void:
	if pulse or spin:
		_t += dt
		queue_redraw()


func _oct(c: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 8:
		var a := PI / 8.0 + i * PI / 4.0
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts


func _hex(c: Vector2, r: float, rot := 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		var a := rot + i * PI / 3.0
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts


func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := size / 2.0
	var r := s * 0.5
	var col := color
	if pulse:
		var k := 0.5 + 0.5 * sin(_t * 4.0)
		col = color.lerp(Color.WHITE, k * 0.35)
	if frame:
		var o := _oct(c, r * 0.98)
		draw_colored_polygon(o, bg if bg.a > 0 else Color(0.03, 0.05, 0.08, 0.92))
		o.append(o[0])
		draw_polyline(o, col, maxf(1.5, s * 0.06), true)
		r *= 0.68
	if spin:
		var a0 := _t * 3.0
		draw_arc(c, r * 1.25, a0, a0 + PI * 0.7, 16, Color(col, 0.7), maxf(1.0, s * 0.04), true)
		draw_arc(c, r * 1.25, a0 + PI, a0 + PI * 1.7, 16, Color(col, 0.7), maxf(1.0, s * 0.04), true)
	var w := maxf(1.5, s * 0.08)
	match glyph:
		"sentinel":  # shield with chevron
			var p := PackedVector2Array([c + Vector2(-r * .7, -r * .8), c + Vector2(r * .7, -r * .8), c + Vector2(r * .7, 0), c + Vector2(0, r * .9), c + Vector2(-r * .7, 0)])
			draw_colored_polygon(p, Color(col, 0.25))
			p.append(p[0])
			draw_polyline(p, col, w, true)
			draw_polyline(PackedVector2Array([c + Vector2(-r * .4, -r * .2), c + Vector2(0, r * .2), c + Vector2(r * .4, -r * .2)]), col, w, true)
		"shield", "shielded":
			draw_arc(c, r * .8, PI * 1.1, PI * 1.9, 20, col, w, true)
			draw_arc(c, r * .55, PI * 1.1, PI * 1.9, 20, Color(col, 0.6), w, true)
			draw_colored_polygon(_hex(c + Vector2(0, r * .15), r * .45, PI / 6), Color(col, 0.6))
		"grit":  # cracked diamond
			var d := PackedVector2Array([c + Vector2(0, -r * .85), c + Vector2(r * .7, 0), c + Vector2(0, r * .85), c + Vector2(-r * .7, 0)])
			draw_colored_polygon(d, Color(col, 0.3))
			d.append(d[0])
			draw_polyline(d, col, w, true)
			draw_polyline(PackedVector2Array([c + Vector2(-r * .1, -r * .6), c + Vector2(r * .15, -r * .1), c + Vector2(-r * .15, r * .2), c + Vector2(r * .05, r * .6)]), col, w * .7, true)
		"saboteur":  # dagger
			draw_line(c + Vector2(-r * .6, r * .6), c + Vector2(r * .6, -r * .6), col, w * 1.3, true)
			draw_line(c + Vector2(-r * .55, r * .15), c + Vector2(-r * .15, r * .55), col, w, true)
		"ambush":  # eye
			draw_arc(c + Vector2(0, r * .5), r * .9, PI * 1.2, PI * 1.8, 16, col, w, true)
			draw_arc(c + Vector2(0, -r * .5), r * .9, PI * 0.2, PI * 0.8, 16, col, w, true)
			draw_circle(c, r * .22, col)
		"overwhelm":  # double chevron up
			for k in 2:
				var y := r * (0.35 - k * 0.55)
				draw_polyline(PackedVector2Array([c + Vector2(-r * .6, y + r * .3), c + Vector2(0, y - r * .2), c + Vector2(r * .6, y + r * .3)]), col, w, true)
		"raid":  # crossed blasters / arrow
			draw_line(c + Vector2(-r * .7, r * .5), c + Vector2(r * .5, -r * .5), col, w, true)
			draw_colored_polygon(PackedVector2Array([c + Vector2(r * .75, -r * .75), c + Vector2(r * .2, -r * .55), c + Vector2(r * .55, -r * .2)]), col)
		"restore", "heal":
			draw_rect(Rect2(c - Vector2(r * .18, r * .65), Vector2(r * .36, r * 1.3)), col)
			draw_rect(Rect2(c - Vector2(r * .65, r * .18), Vector2(r * 1.3, r * .36)), col)
		"hidden":
			draw_arc(c + Vector2(0, -r * .4), r * .9, PI * 0.2, PI * 0.8, 16, col, w, true)
			for k in 3:
				var x := (k - 1) * r * .45
				draw_line(c + Vector2(x, r * .35), c + Vector2(x * 1.2, r * .65), col, w * .8, true)
		"smuggle":  # crate
			draw_rect(Rect2(c - Vector2(r * .6, r * .5), Vector2(r * 1.2, r)), col, false, w)
			draw_line(c + Vector2(-r * .6, -r * .5), c + Vector2(r * .6, r * .5), col, w * .7, true)
		"coordinate", "support":  # linked nodes
			for k in 3:
				var a := -PI / 2 + k * TAU / 3.0
				draw_circle(c + Vector2(cos(a), sin(a)) * r * .55, r * .18, col)
			draw_arc(c, r * .55, 0, TAU, 24, Color(col, 0.6), w * .6, true)
		"exploit", "bounty":  # target reticle
			draw_arc(c, r * .6, 0, TAU, 24, col, w, true)
			draw_line(c + Vector2(0, -r * .9), c + Vector2(0, -r * .3), col, w, true)
			draw_line(c + Vector2(0, r * .9), c + Vector2(0, r * .3), col, w, true)
			draw_line(c + Vector2(-r * .9, 0), c + Vector2(-r * .3, 0), col, w, true)
			draw_line(c + Vector2(r * .9, 0), c + Vector2(r * .3, 0), col, w, true)
		"piloting", "space":  # starfighter
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * .8), c + Vector2(r * .25, r * .4), c + Vector2(-r * .25, r * .4)]), col)
			draw_line(c + Vector2(-r * .8, r * .1), c + Vector2(r * .8, r * .1), col, w, true)
			draw_line(c + Vector2(-r * .8, -r * .3), c + Vector2(-r * .8, r * .5), col, w, true)
			draw_line(c + Vector2(r * .8, -r * .3), c + Vector2(r * .8, r * .5), col, w, true)
		"ground":  # walker / mountains
			draw_polyline(PackedVector2Array([c + Vector2(-r * .9, r * .5), c + Vector2(-r * .3, -r * .4), c + Vector2(0, 0), c + Vector2(r * .4, -r * .6), c + Vector2(r * .9, r * .5)]), col, w, true)
			draw_line(c + Vector2(-r * .9, r * .5), c + Vector2(r * .9, r * .5), col, w, true)
		"initiative":  # SWU-style initiative token: diamond with core
			var d2 := PackedVector2Array([c + Vector2(0, -r * .9), c + Vector2(r * .9, 0), c + Vector2(0, r * .9), c + Vector2(-r * .9, 0)])
			draw_colored_polygon(d2, Color(col, 0.25))
			d2.append(d2[0])
			draw_polyline(d2, col, w, true)
			draw_circle(c, r * .3, col)
		"blast":
			for k in 8:
				var a := k * TAU / 8.0
				draw_line(c + Vector2(cos(a), sin(a)) * r * .3, c + Vector2(cos(a), sin(a)) * r * (.9 if k % 2 == 0 else .6), col, w, true)
		"plan":  # holo-map lines
			for k in 3:
				draw_line(c + Vector2(-r * .6, (k - 1) * r * .45), c + Vector2(r * .6, (k - 1) * r * .45), col, w, true)
				draw_circle(c + Vector2(-r * .6, (k - 1) * r * .45), r * .12, col)
		"krayt":  # krayt skull-ish: horns + eyes
			draw_arc(c + Vector2(0, r * .1), r * .55, PI, TAU, 16, col, w, true)
			draw_line(c + Vector2(-r * .55, r * .1), c + Vector2(-r * .85, -r * .7), col, w, true)
			draw_line(c + Vector2(r * .55, r * .1), c + Vector2(r * .85, -r * .7), col, w, true)
			draw_circle(c + Vector2(-r * .22, r * .05), r * .1, col)
			draw_circle(c + Vector2(r * .22, r * .05), r * .1, col)
		"alarm":
			draw_arc(c, r * .45, PI, TAU, 16, col, w, true)
			draw_line(c + Vector2(-r * .45, 0), c + Vector2(-r * .45, r * .4), col, w, true)
			draw_line(c + Vector2(r * .45, 0), c + Vector2(r * .45, r * .4), col, w, true)
			draw_line(c + Vector2(-r * .7, r * .4), c + Vector2(r * .7, r * .4), col, w, true)
			for k in 3:
				var a := PI * (1.15 + k * 0.35)
				draw_line(c + Vector2(cos(a), sin(a)) * r * .65, c + Vector2(cos(a), sin(a)) * r * .9, col, w * .7, true)
		"resource":
			draw_colored_polygon(_hex(c, r * .75, PI / 6), Color(col, 0.3))
			var h := _hex(c, r * .75, PI / 6)
			h.append(h[0])
			draw_polyline(h, col, w, true)
		"deck":
			for k in 3:
				var dr := Rect2(c + Vector2(-r * .45 + k * r * .12, -r * .7 + k * r * .1), Vector2(r * .8, r * 1.2))
				if k == 2:
					draw_rect(dr, Color(col, 0.85))
				else:
					draw_rect(dr, Color(col, 0.35 + k * 0.25), false, w * .6)
		"hand":
			for k in 3:
				var a := (k - 1) * 0.35
				var tr := Transform2D(a, c + Vector2(0, r * .3))
				var p2 := PackedVector2Array([Vector2(-r * .3, -r * .9), Vector2(r * .3, -r * .9), Vector2(r * .3, 0), Vector2(-r * .3, 0), Vector2(-r * .3, -r * .9)])
				draw_polyline(tr * p2, col, w * .7, true)
		"fight":  # crossed sabers
			draw_line(c + Vector2(-r * .7, r * .7), c + Vector2(r * .6, -r * .6), col, w * 1.2, true)
			draw_line(c + Vector2(r * .7, r * .7), c + Vector2(-r * .6, -r * .6), col, w * 1.2, true)
		"elite":
			draw_line(c + Vector2(-r * .7, r * .7), c + Vector2(r * .6, -r * .6), col, w * 1.2, true)
			draw_line(c + Vector2(r * .7, r * .7), c + Vector2(-r * .6, -r * .6), col, w * 1.2, true)
			draw_arc(c, r * .9, 0, TAU, 24, col, w * .7, true)
		"objective":
			draw_arc(c, r * .7, 0, TAU, 24, col, w, true)
			draw_arc(c, r * .35, 0, TAU, 16, col, w, true)
			draw_circle(c, r * .1, col)
		"event":  # holocron
			draw_colored_polygon(_hex(c, r * .7, 0), Color(col, 0.3))
			draw_line(c + Vector2(-r * .6, 0), c + Vector2(r * .6, 0), col, w * .7, true)
			draw_line(c + Vector2(-r * .3, -r * .6), c + Vector2(r * .3, r * .6), col, w * .7, true)
			draw_line(c + Vector2(r * .3, -r * .6), c + Vector2(-r * .3, r * .6), col, w * .7, true)
		"rest":  # campfire / cantina mug
			draw_rect(Rect2(c - Vector2(r * .45, r * .45), Vector2(r * .7, r * .9)), col, false, w)
			draw_arc(c + Vector2(r * .3, 0), r * .25, -PI / 2, PI / 2, 10, col, w, true)
		"boss":  # imperial-ish cog
			for k in 6:
				var a := k * TAU / 6.0
				draw_line(c + Vector2(cos(a), sin(a)) * r * .45, c + Vector2(cos(a), sin(a)) * r * .9, col, w * 1.4, true)
			draw_arc(c, r * .55, 0, TAU, 24, col, w * 1.2, true)
			draw_circle(c, r * .2, col)
		"gear":
			for k in 8:
				var a := k * TAU / 8.0
				draw_line(c + Vector2(cos(a), sin(a)) * r * .5, c + Vector2(cos(a), sin(a)) * r * .85, col, w * 1.3, true)
			draw_arc(c, r * .5, 0, TAU, 24, col, w, true)
		"back":
			draw_polyline(PackedVector2Array([c + Vector2(r * .3, -r * .6), c + Vector2(-r * .3, 0), c + Vector2(r * .3, r * .6)]), col, w * 1.3, true)
		"play":
			draw_colored_polygon(PackedVector2Array([c + Vector2(-r * .4, -r * .6), c + Vector2(r * .6, 0), c + Vector2(-r * .4, r * .6)]), col)
		"log":
			for k in 4:
				draw_line(c + Vector2(-r * .6, -r * .55 + k * r * .37), c + Vector2(r * (.6 if k < 3 else .2), -r * .55 + k * r * .37), col, w * .8, true)
		"lock":
			draw_rect(Rect2(c + Vector2(-r * .5, -r * .1), Vector2(r, r * .8)), col)
			draw_arc(c + Vector2(0, -r * .1), r * .35, PI, TAU, 12, col, w, true)
		"star":
			var sp := PackedVector2Array()
			for k in 10:
				var a := -PI / 2 + k * PI / 5.0
				sp.append(c + Vector2(cos(a), sin(a)) * r * (0.85 if k % 2 == 0 else 0.38))
			draw_colored_polygon(sp, col)
		"collection":
			for k in 4:
				var x := (k % 2) * r * .65 - r * .6
				var y := floori(k / 2.0) * r * .75 - r * .7
				draw_rect(Rect2(c + Vector2(x, y), Vector2(r * .5, r * .6)), col, false, w * .7)
		_:
			draw_circle(c, r * .3, col)
