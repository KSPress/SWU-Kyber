class_name AspectIcon
extends Control
## One of the six SWU aspects, shown with the official icon art taken from the
## card renders (see tools/godot_tool/extract_aspects.gd). Toggleable for filters.

signal pressed(aspect: String)

const ORDER := ["vigilance", "command", "aggression", "cunning", "heroism", "villainy"]

var aspect := "vigilance":
	set(v):
		aspect = v
		queue_redraw()
var on := true:
	set(v):
		on = v
		queue_redraw()
var toggle := false
var _hover := false
var _t := 0.0


static func make(a: String, size_px := 40.0, p_toggle := false) -> AspectIcon:
	var i := AspectIcon.new()
	i.aspect = a
	i.toggle = p_toggle
	i.on = not p_toggle
	i.custom_minimum_size = Vector2(size_px, size_px)
	return i


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP if toggle else Control.MOUSE_FILTER_IGNORE
	tooltip_text = aspect.capitalize()
	mouse_entered.connect(func(): _hover = true; queue_redraw())
	mouse_exited.connect(func(): _hover = false; queue_redraw())
	resized.connect(queue_redraw)


func _process(dt: float) -> void:
	if toggle and on:
		_t += dt
		queue_redraw()


static var _tex_cache: Dictionary = {}


## Official aspect icon cut from the card renders (tools/godot_tool/extract_aspects.gd),
## masked to the badge's hex outline. Falls back to a plain coloured hex.
static func texture(a: String) -> Texture2D:
	if _tex_cache.has(a):
		return _tex_cache[a]
	var t: Texture2D = Art.ui_texture("aspects/" + a)
	if t:
		_tex_cache[a] = t
		return t
	var path := "res://ip/ui/aspects/%s.png" % a
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		if img:
			img.convert(Image.FORMAT_RGBA8)
			var w := img.get_width()
			var h := img.get_height()
			# badge = tall hexagon with flat top/bottom chamfers; clear everything outside
			for y in h:
				for x in w:
					var fx := float(x) / w
					var fy := float(y) / h
					var cut := 0.22  # corner chamfer size
					var inside := fx > 0.04 and fx < 0.96 and fy > 0.03 and fy < 0.97
					if fy < cut and (fx < cut - fy or fx > 1.0 - cut + fy):
						inside = false
					if fy > 1.0 - cut and (fx < fy - (1.0 - cut) or fx > 1.0 - (fy - (1.0 - cut))):
						inside = false
					if not inside:
						img.set_pixel(x, y, Color(0, 0, 0, 0))
			t = ImageTexture.create_from_image(img)
	_tex_cache[a] = t
	return t


func _draw() -> void:
	var lit := on or not toggle
	var tex := texture(aspect)
	var s := minf(size.x, size.y)
	var box := Rect2((size - Vector2(s * 0.91, s)) / 2.0, Vector2(s * 0.91, s))
	if toggle and on:
		var k := 0.5 + 0.5 * sin(_t * 4.0)
		draw_rect(box.grow(3 + 2 * k), Color(Kyber.C_GOLD, 0.35 + 0.3 * k), false, 3.0)
	if _hover and toggle:
		draw_rect(box.grow(2), Color(Kyber.C_GOLD, 0.8), false, 2.0)
	if tex:
		draw_texture_rect(tex, box, false, Color(1, 1, 1, 1.0) if lit else Color(0.45, 0.45, 0.5, 0.55))
	else:
		draw_rect(box, Kyber.aspect_color(aspect) if lit else Color(Kyber.aspect_color(aspect), 0.3))


func _gui_input(ev: InputEvent) -> void:
	if toggle and ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		on = not on
		Sfx.play("click")
		var tw := create_tween()
		pivot_offset = size / 2.0
		tw.tween_property(self, "scale", Vector2(1.2, 1.2), 0.07)
		tw.tween_property(self, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_ELASTIC)
		pressed.emit(aspect)
		accept_event()


## Row of the aspect icons a deck uses (leader's + base's), deduplicated in order.
static func row_for(leader: String, base: String, size_px := 30.0) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var seen: Array = []
	for id in [leader, base]:
		for a in CardDB.card(id).get("aspects", []):
			seen.append(a)
	for a in seen:
		h.add_child(make(a, size_px))
	return h
