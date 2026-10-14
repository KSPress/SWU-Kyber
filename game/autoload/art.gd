extends Node
## Lazy card-art streaming. Card art lives in res://ip/art/cards/<art>.kart
## (lossy WebP bytes, produced by tools/convert_art.gd). Decoding is budgeted
## per frame (no threads, so it also works in single-threaded web exports)
## and results are kept in a small LRU cache.

const CARD_DIR := "res://ip/art/cards/"
const UI_DIR := "res://ip/ui/"
const MAX_CACHE := 220
const DECODES_PER_FRAME := 3

var _cache: Dictionary = {}       # key -> ImageTexture
var _order: Array = []            # LRU keys
var _waiting: Dictionary = {}     # key -> Array[Callable]
var _queue: Array = []
var placeholder: Texture2D
var card_back: Texture2D


func _ready() -> void:
	var img := Image.create(8, 11, false, Image.FORMAT_RGBA8)
	img.fill(Color("142233"))
	placeholder = ImageTexture.create_from_image(img)
	card_back = ui_texture("card_back")
	if card_back == null:
		card_back = placeholder


func key_for(art: String, back := false) -> String:
	return art + ("_b" if back else "")


func has_art(art: String, back := false) -> bool:
	return FileAccess.file_exists(CARD_DIR + key_for(art, back) + ".kart")


## Returns the texture now if cached, otherwise null and calls `cb(texture)` later.
func request(art: String, cb: Callable, back := false) -> Texture2D:
	var key := key_for(art, back)
	if _cache.has(key):
		_touch(key)
		return _cache[key]
	if not _waiting.has(key):
		_waiting[key] = []
		_queue.append(key)
	_waiting[key].append(cb)
	return null


## Synchronous load (used for the inspect view, where we want it immediately).
func get_now(art: String, back := false) -> Texture2D:
	var key := key_for(art, back)
	if not _cache.has(key):
		_decode(key)
	return _cache.get(key, placeholder)


func _process(_dt: float) -> void:
	var n := 0
	while n < DECODES_PER_FRAME and not _queue.is_empty():
		var key: String = _queue.pop_front()
		_decode(key)
		var tex: Texture2D = _cache.get(key, placeholder)
		for cb in _waiting.get(key, []):
			if cb.is_valid():
				cb.call(tex)
		_waiting.erase(key)
		n += 1


func _decode(key: String) -> void:
	var path := CARD_DIR + key + ".kart"
	if not FileAccess.file_exists(path):
		_cache[key] = placeholder
		return
	var img := Image.new()
	if img.load_webp_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
		_cache[key] = placeholder
		return
	_cache[key] = ImageTexture.create_from_image(img)
	_touch(key)
	while _order.size() > MAX_CACHE:
		_cache.erase(_order.pop_front())


func _touch(key: String) -> void:
	_order.erase(key)
	_order.append(key)


## UI art (backgrounds, banner, card back) imported normally by Godot.
func ui_texture(name: String) -> Texture2D:
	if _ui_cache.has(name):
		return _ui_cache[name]
	var tex: Texture2D = null
	for ext in [".png", ".jpg", ".webp"]:
		var p: String = UI_DIR + name + ext
		if ResourceLoader.exists(p):
			tex = load(p)
			break
		if FileAccess.file_exists(p):
			# not imported yet (fresh asset build): decode directly
			var img := Image.load_from_file(ProjectSettings.globalize_path(p))
			if img:
				tex = ImageTexture.create_from_image(img)
				break
	_ui_cache[name] = tex
	return tex


var _ui_cache: Dictionary = {}
