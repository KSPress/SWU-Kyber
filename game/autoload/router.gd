extends Node
## Screen navigation with a hyperspace-style fade. Screens read Router.params.

signal screen_changed(path: String)

const SCREENS := {
	"menu": "res://ui/screens/main_menu.tscn",
	"episodes": "res://ui/screens/episode_select.tscn",
	"chapter": "res://ui/screens/chapter_map.tscn",
	"match": "res://ui/screens/match_screen.tscn",
	"reward": "res://ui/screens/reward_screen.tscn",
	"collection": "res://ui/screens/collection.tscn",
	"settings": "res://ui/screens/settings_screen.tscn",
	"quick": "res://ui/screens/quick_match.tscn",
	"decks": "res://ui/screens/decks.tscn",
	"spotlight": "res://ui/screens/spotlight_select.tscn",
	"spotlight_run": "res://ui/screens/spotlight_map.tscn",
	"deck_editor": "res://ui/screens/deck_editor.tscn",
}

var params: Dictionary = {}
var _layer: CanvasLayer
var _fade: ColorRect
var _busy := false


func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 100
	add_child(_layer)
	_fade = ColorRect.new()
	_fade.color = Color(0.0, 0.0, 0.0, 0.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(_fade)


func go(screen: String, p := {}) -> void:
	if _busy:
		return
	_busy = true
	params = p
	var path: String = SCREENS.get(screen, screen)
	Sfx.play("whoosh")
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, Kyber.anim(0.18))
	await tw.finished
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	var tw2 := create_tween()
	tw2.tween_property(_fade, "color:a", 0.0, Kyber.anim(0.25))
	await tw2.finished
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_busy = false
	screen_changed.emit(path)
