class_name DeckTile
extends Control
## Deck button: leader art banner, chosen icon, name, mark star, the deck's
## aspect icons (leader + base), card count. Glows when selected.

signal pressed(tile: DeckTile)
signal long_pressed(tile: DeckTile)

var deck: Dictionary = {}       # {name, icon, marked, leader, base, cards|count}
var selected := false:
	set(v):
		selected = v
		queue_redraw()
var subtitle := ""
var _tex: Texture2D
var _t := 0.0
var _press := -1.0
var _icon: IconGlyph
var _aspects: HBoxContainer
var _name: Label
var _sub: Label

const SIZE := Vector2(300, 150)


static func make(d: Dictionary, sub := "") -> DeckTile:
	var t := DeckTile.new()
	t.deck = d
	t.subtitle = sub
	t.custom_minimum_size = SIZE
	return t


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	pivot_offset = SIZE / 2.0
	var lid: String = deck.get("leader", "")
	if lid != "":
		var tx := Art.request(CardDB.card(lid).get("art", lid), func(t): _tex = t; queue_redraw())
		if tx:
			_tex = tx
	_icon = IconGlyph.new()
	_icon.glyph = deck.get("icon", "star")
	_icon.frame = true
	_icon.color = Kyber.C_GOLD if deck.get("marked", false) else Kyber.C_KYBER
	_icon.custom_minimum_size = Vector2(48, 48)
	_icon.position = Vector2(10, 10)
	_icon.size = Vector2(48, 48)
	add_child(_icon)
	_name = UIKit.label(deck.get("name", "Untitled deck"), 20, Kyber.C_TEXT)
	_name.add_theme_constant_override("outline_size", 6)
	_name.add_theme_color_override("font_outline_color", Color.BLACK)
	_name.position = Vector2(66, 12)
	_name.size = Vector2(SIZE.x - 76, 28)
	_name.clip_text = true
	add_child(_name)
	_sub = UIKit.label(subtitle if subtitle != "" else CardDB.card(lid).get("name", "No leader"), 14, Kyber.C_DIM)
	_sub.position = Vector2(66, 40)
	_sub.size = Vector2(SIZE.x - 76, 20)
	_sub.clip_text = true
	add_child(_sub)
	_aspects = AspectIcon.row_for(lid, deck.get("base", ""), 30.0)
	_aspects.position = Vector2(12, SIZE.y - 42)
	add_child(_aspects)
	mouse_entered.connect(func(): create_tween().tween_property(self, "scale", Vector2(1.04, 1.04), 0.1))
	mouse_exited.connect(func(): create_tween().tween_property(self, "scale", Vector2.ONE, 0.1))


func _process(dt: float) -> void:
	_t += dt
	if selected:
		queue_redraw()
	if _press >= 0.0:
		_press += dt
		if _press > 0.45:
			_press = -1.0
			long_pressed.emit(self)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, SIZE)
	draw_rect(r, Color("0b131d"))
	if _tex and _tex != Art.placeholder:
		var ts := _tex.get_size()
		var src := Rect2(Vector2(ts.x * 0.07, ts.y * 0.12), Vector2(ts.x * 0.38, ts.x * 0.38 * SIZE.y / SIZE.x))
		var dst := Rect2(Vector2(SIZE.x * 0.38, 0), Vector2(SIZE.x * 0.62, SIZE.y))
		src.size.y = src.size.x * dst.size.y / dst.size.x
		draw_texture_rect_region(_tex, dst, src, Color(1, 1, 1, 0.75))
		# fade the art into the panel on the left
		for i in 12:
			var x := SIZE.x * 0.38 + i * 6.0
			draw_rect(Rect2(Vector2(x, 0), Vector2(6, SIZE.y)), Color(0.043, 0.075, 0.114, 1.0 - i / 12.0))
	draw_rect(r, Kyber.C_GOLD if deck.get("marked", false) else Kyber.C_LINE, false, 2.0)
	if selected:
		var k2 := 0.5 + 0.5 * sin(_t * 4.0)
		draw_rect(r.grow(-3.0), Color(Kyber.C_KYBER, 0.6 + 0.4 * k2), false, 5.0)
	var n := int(deck.get("count", Save.deck_size(deck)))
	var ok := n >= 50
	UIKit.draw_fit(self, Kyber.font_title, Vector2(SIZE.x - 90, SIZE.y - 14), "%d cards" % n, HORIZONTAL_ALIGNMENT_RIGHT, 80, 16, Kyber.C_GOOD if ok else Kyber.C_GOLD)
	if deck.get("marked", false):
		_star(Vector2(SIZE.x - 22, 22), 12.0)


func _star(c: Vector2, r: float) -> void:
	var sp := PackedVector2Array()
	for k in 10:
		var a := -PI / 2 + k * PI / 5.0
		sp.append(c + Vector2(cos(a), sin(a)) * r * (1.0 if k % 2 == 0 else 0.45))
	draw_colored_polygon(sp, Kyber.C_GOLD)


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			_press = 0.0
		elif _press >= 0.0:
			_press = -1.0
			Sfx.play("click")
			pressed.emit(self)
		accept_event()
	elif ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_RIGHT and ev.pressed:
		long_pressed.emit(self)
		accept_event()
