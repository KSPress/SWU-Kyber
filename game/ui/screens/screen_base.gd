class_name ScreenBase
extends Control
## Common screen scaffold: theme, animated starfield, header with back button,
## safe-area margins and a relayout hook fired on rotation/resize.

var bg: Starfield
var header: HBoxContainer
var body: Control
var title_label: Label
var portrait := true
var _back_target := ""


func _ready() -> void:
	theme = UIKit.build_theme()
	UIKit.fill_rect(self)
	bg = Starfield.new()
	UIKit.fill_rect(bg)
	add_child(bg)
	body = Control.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(body)
	header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	add_child(header)
	get_viewport().size_changed.connect(_on_resize)
	build()
	_on_resize()


## Override: create the screen's content under `body`.
func build() -> void:
	pass


## Override: lay content out for the given orientation.
func relayout(_portrait: bool, _rect: Rect2) -> void:
	pass


func set_header(text: String, back_to := "menu") -> void:
	_back_target = back_to
	for c in header.get_children():
		c.queue_free()
	if back_to != "":
		var b := KyberButton.make("", KyberButton.Style.GHOST, "back")
		b.custom_minimum_size = Vector2(60, 56)
		b.pressed.connect(func(): Router.go(_back_target))
		header.add_child(b)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -4)
	title_label = UIKit.fit_label(UIKit.label(text.to_upper(), 30, Kyber.C_TEXT))
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.add_theme_font_override("font", Kyber.font_title)
	v.add_child(title_label)
	var au := UIKit.aurebesh(text.to_lower(), 14)
	au.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	v.add_child(au)
	header.add_child(v)


func safe_rect() -> Rect2:
	var vs := get_viewport_rect().size
	var safe := DisplayServer.get_display_safe_area()
	var win := DisplayServer.window_get_size()
	var m := 16.0
	var top := m
	if win.x > 0 and safe.size.x > 0:
		var k := vs.x / float(win.x)
		top = maxf(m, safe.position.y * k)
	return Rect2(Vector2(m, top), vs - Vector2(m * 2, top + m))


func _on_resize() -> void:
	var r := safe_rect()
	portrait = r.size.y >= r.size.x
	header.position = r.position
	header.size = Vector2(r.size.x, 64)
	var content := Rect2(r.position + Vector2(0, 76), r.size - Vector2(0, 76))
	body.position = content.position
	body.size = content.size
	relayout(portrait, Rect2(Vector2.ZERO, content.size))
