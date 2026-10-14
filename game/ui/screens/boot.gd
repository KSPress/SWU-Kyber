extends Control
## Splash: animated kyber crystal, then the main menu. Explains how to import
## card data if it's missing (the repo ships without IP).


func _ready() -> void:
	theme = UIKit.build_theme()
	var bg := Starfield.new()
	UIKit.fill_rect(bg)
	add_child(bg)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 12)
	UIKit.fill_rect(v)
	add_child(v)
	var logo := TextureRect.new()
	logo.texture = Art.ui_texture("logo")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(260, 245)
	logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(logo)
	logo.modulate.a = 0.0
	create_tween().tween_property(logo, "modulate:a", 1.0, 0.4)
	v.add_child(UIKit.title(Kyber.GAME_TITLE, 56, Kyber.C_TEXT))
	v.add_child(UIKit.aurebesh("kyber", 26))
	if not CardDB.loaded:
		var msg := UIKit.label("No card database found.\nRun:  python -I tools/import_cards.py\nthen the art converter (see README).", 20, Kyber.C_GOLD, HORIZONTAL_ALIGNMENT_CENTER)
		v.add_child(msg)
		return
	var tw := create_tween()
	tw.tween_property(bg, "hyperspace", 1.0, 0.6).set_delay(0.5)
	await tw.finished
	Router.go("menu")
