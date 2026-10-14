extends Node
## Global config, palette and user settings. Rename the game here only.

const GAME_TITLE := "SWU Kyber"
const GAME_SUBTITLE := "A Star Wars: Unlimited fan project"
const VERSION := "0.1.0-foundation"

# Palette — dark HUD with Rebel blue / Imperial red / kyber cyan accents.
const C_BG := Color("05080d")
const C_PANEL := Color("0b131d")
const C_PANEL_HI := Color("142233")
const C_LINE := Color("2b3d52")
const C_TEXT := Color("e8eef5")
const C_DIM := Color("8796a8")
const C_KYBER := Color("4fe3ff")
const C_REBEL := Color("3d8bff")
const C_EMPIRE := Color("ff3b30")
const C_GOLD := Color("f5c518")
const C_POWER := Color("d8322b")
const C_HP := Color("2f8fe0")
const C_COST := Color("e6b422")
const C_GOOD := Color("49d17d")

const ASPECT_COLORS := {
	"vigilance": Color("2f7fe0"), "command": Color("2f9e4f"), "aggression": Color("d8322b"),
	"cunning": Color("e6b422"), "heroism": Color("e9e3cf"), "villainy": Color("2a2a2a"),
}
const DECK_ICONS := ["star", "sentinel", "saboteur", "ambush", "overwhelm", "raid", "restore", "hidden",
	"initiative", "blast", "plan", "krayt", "alarm", "fight", "elite", "objective", "boss", "space",
	"ground", "piloting", "bounty", "event", "resource", "gear"]
const QUICK_MODES := {
	"one_lane": ["One Lane", "Every unit fights in one battlefield — space cards play as ground."],
	"traditional": ["Traditional", "Two arenas, Space and Ground, like tabletop SWU."],
	"ground": ["Ground Only", "Balanced decks of ground cards only."],
	"space": ["Space Only", "Balanced decks of space cards; pilot leaders only."],
}

const SABER_COLORS := {
	"blue": Color(0.35, 0.65, 1.0), "green": Color(0.35, 1.0, 0.45), "red": Color(1.0, 0.18, 0.15),
	"purple": Color(0.75, 0.35, 1.0), "yellow": Color(1.0, 0.85, 0.25), "white": Color(0.95, 0.97, 1.0),
}

signal settings_changed

var settings := {
	"perf_mode": false,        # fewer particles, static backgrounds
	"anim_speed": 1.0,
	"text_scale": 1.0,
	"sfx_volume": 0.7,
	"music_volume": 0.5,
	"orientation": "auto",     # auto | portrait | landscape
	"show_aurebesh": true,
	"quick_mode": "traditional",  # one_lane | traditional | ground | space
}

var font_aurebesh: Font
var font_title: Font
var font_body: Font


func _ready() -> void:
	font_body = ThemeDB.fallback_font
	var title := SystemFont.new()
	title.font_names = PackedStringArray(["Bahnschrift", "Eurostile", "Orbitron", "Arial Narrow", "Roboto Condensed", "sans-serif"])
	title.font_weight = 700
	font_title = title
	for p in ["res://ip/fonts/Aurebesh-English.ttf", "res://ip/fonts/aurebesh.ttf"]:
		if ResourceLoader.exists(p):
			font_aurebesh = load(p)
			break
	if font_aurebesh == null:
		font_aurebesh = font_title
	get_tree().root.size_changed.connect(_update_ui_scale)
	_update_ui_scale()


## Keep UI the same physical size in both orientations: the stretch base is
## 720x1280 in portrait and 1280x720 in landscape (aspect "expand" fills the rest).
func _update_ui_scale() -> void:
	var win := get_tree().root
	var s := win.size
	var want := Vector2i(720, 1280) if s.y >= s.x else Vector2i(1280, 720)
	if win.content_scale_size != want:
		win.content_scale_size = want


func set_setting(key: String, value) -> void:
	settings[key] = value
	if key == "orientation":
		apply_orientation()
	settings_changed.emit()
	Save.save_settings(settings)


func apply_orientation() -> void:
	if not OS.has_feature("mobile"):
		return
	match settings.get("orientation", "auto"):
		"portrait":
			DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_PORTRAIT)
		"landscape":
			DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_LANDSCAPE)
		_:
			DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR)


func anim(t: float) -> float:
	return t / maxf(0.1, float(settings.get("anim_speed", 1.0)))


func perf() -> bool:
	return settings.get("perf_mode", false)


## True when the visible area is taller than wide.
func is_portrait(node: Node) -> bool:
	var s := node.get_viewport().get_visible_rect().size
	return s.y >= s.x


func aspect_color(a: String) -> Color:
	return ASPECT_COLORS.get(a, C_DIM)
