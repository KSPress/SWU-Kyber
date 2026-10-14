extends ScreenBase
## Title screen. Floating showcase cards can be grabbed and flung around.

var _title_box: VBoxContainer
var _buttons: GridContainer
var _floaters: Array = []
var _foot: Label
var _t := 0.0


func build() -> void:
	bg.backdrop = Art.ui_texture("swu_background")
	bg.backdrop_alpha = 0.45
	_title_box = VBoxContainer.new()
	_title_box.add_theme_constant_override("separation", 0)
	body.add_child(_title_box)
	var banner := TextureRect.new()
	banner.texture = Art.ui_texture("logo")
	banner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	banner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	banner.custom_minimum_size = Vector2(0, 150)
	banner.name = "Logo"
	banner.pivot_offset = Vector2(0, 75)
	_title_box.add_child(banner)
	var t := UIKit.title(Kyber.GAME_TITLE, 48, Kyber.C_TEXT)
	t.name = "Title"
	_title_box.add_child(t)
	_title_box.add_child(UIKit.aurebesh("kyber", 30))
	_title_box.add_child(UIKit.label(Kyber.GAME_SUBTITLE, 18, Kyber.C_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	_buttons = GridContainer.new()
	_buttons.add_theme_constant_override("h_separation", 16)
	_buttons.add_theme_constant_override("v_separation", 14)
	body.add_child(_buttons)
	var items := [
		["Saga Campaign", KyberButton.Style.PRIMARY, "boss", func(): Router.go("episodes"), true],
		["Spotlight Campaign", KyberButton.Style.PRIMARY, "star", func(): Router.go("spotlight"), false],
		["Standard Battle", KyberButton.Style.REBEL, "fight", func(): Router.go("quick", {"format": 0}), false],
		["Quick Battle", KyberButton.Style.REBEL, "ground", func(): Router.go("quick", {"format": 1}), false],
		["Deck Builder", KyberButton.Style.GOLD, "deck", func(): Router.go("decks"), false],
		["Collection Vault", KyberButton.Style.GOLD, "collection", func(): Router.go("collection"), false],
		["Settings", KyberButton.Style.GHOST, "gear", func(): Router.go("settings"), false],
	]
	var i := 0
	for it in items:
		var b := KyberButton.make(it[0], it[1], it[2], it[4])
		b.custom_minimum_size = Vector2(320, 72)
		b.add_theme_font_size_override("font_size", 26)
		b.pressed.connect(it[3])
		_buttons.add_child(b)
		UIKit.pop_in(b, 0.15 + i * 0.07)
		i += 1
	_foot = UIKit.label("v%s · Unofficial, non-commercial fan project. Star Wars and SWU are © Lucasfilm Ltd. / Fantasy Flight Games." % Kyber.VERSION, 13, Color(Kyber.C_DIM, 0.8), HORIZONTAL_ALIGNMENT_CENTER)
	_foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_foot)
	_spawn_floaters()


func _spawn_floaters() -> void:
	# A fresh random trio every time the menu opens: units and leaders with art.
	var pool: Array = []
	for id in CardDB.lib.cards:
		var c: Dictionary = CardDB.lib.cards[id]
		if c.get("custom", false) or c.get("type", "") != "unit":
			continue
		if c.get("type") == "unit" and int(c.get("cost", 0)) < 2:
			continue
		pool.append(id)
	pool.shuffle()
	var avail: Array = []
	for id in pool:
		if Art.has_art(CardDB.card(id).get("art", id)):
			avail.append(id)
		if avail.size() >= 3:
			break
	for i in mini(3, avail.size()):
		var cv := CardView.create(avail[i])
		cv.hover_lift = false
		cv.home_scale = Vector2(0.42, 0.42)
		cv.scale = cv.home_scale
		cv.drag_released.connect(func(c, _p): c.spring_home())
		cv.tapped.connect(func(c): InspectOverlay.open(self, c.card_id, c.get_global_rect()))
		cv.inspect_requested.connect(func(c): InspectOverlay.open(self, c.card_id, c.get_global_rect()))
		body.add_child(cv)
		body.move_child(cv, 0)
		_floaters.append(cv)


func _process(dt: float) -> void:
	_t += dt
	for i in _floaters.size():
		var cv: CardView = _floaters[i]
		if cv.is_dragging() or cv.top_level:
			continue
		cv.rotation = cv.home_rot + sin(_t * 0.6 + i) * 0.05
		cv.position = cv.position.lerp(cv.home_pos + Vector2(0, sin(_t * 0.9 + i * 2.0) * 10.0), 0.08)
	var t := _title_box.get_node_or_null("Title")
	if t:
		t.modulate = Color(1, 1, 1).lerp(Color(0.75, 0.95, 1.1), 0.5 + 0.5 * sin(_t * 1.5))


func relayout(p: bool, r: Rect2) -> void:
	_buttons.columns = 1 if p else 2
	_title_box.position = Vector2(0, r.size.y * (0.04 if p else 0.0))
	_title_box.size = Vector2(r.size.x, 0)
	await get_tree().process_frame
	var bs := _buttons.get_combined_minimum_size()
	_buttons.size = bs
	_buttons.position = Vector2((r.size.x - bs.x) / 2.0, r.size.y * (0.52 if p else 0.5))
	_foot.position = Vector2(0, r.size.y - 50)
	_foot.size = Vector2(r.size.x, 40)
	# Landscape: cards live in the side gutters left/right of the button grid.
	var gutter := (r.size.x - bs.x) / 2.0 - 20.0
	var fsc := clampf(r.size.y * 0.16 / CardView.PORTRAIT.y, 0.3, 1.0) if p else clampf(minf(r.size.y * 0.34 / CardView.PORTRAIT.y, gutter * 0.75 / CardView.LANDSCAPE.x), 0.25, 1.0)
	for i in _floaters.size():
		var cv: CardView = _floaters[i]
		cv.home_scale = Vector2(fsc, fsc)
		cv.scale = cv.home_scale
		var hp: Vector2
		if p:
			var cw := cv.size.x * fsc
			hp = Vector2(r.size.x * (0.5 + (i - 1) * 0.31) - cw / 2.0, r.size.y * 0.27)
		else:
			var left := i < 2
			var x := gutter * 0.15 if left else r.size.x - gutter * 0.25 - cv.size.x * fsc
			hp = Vector2(x, r.size.y * (0.18 + (i % 2) * 0.36))
		cv.home_pos = hp
		cv.home_rot = (i - 1) * 0.12
		if cv.position == Vector2.ZERO:
			cv.position = hp
