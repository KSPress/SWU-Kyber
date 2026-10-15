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
## Web builds don't pack card art. Each image is fetched on demand straight
## from the official card image server, using the URL index in
## res://data/art_urls.json (tools/web/build_art_map.py); without that index
## they fall back to art/<key>.kart files next to the page.
var remote := false
var _base_url := ""
var _urls: Dictionary = {}     # art key -> path on the official CDN
var _cdn := ""
var _pool: Array = []          # idle HTTPRequest nodes
var _busy: Dictionary = {}     # HTTPRequest -> key
const PARALLEL := 6


func _ready() -> void:
	var img := Image.create(8, 11, false, Image.FORMAT_RGBA8)
	img.fill(Color("142233"))
	placeholder = ImageTexture.create_from_image(img)
	card_back = ui_texture("card_back")
	if card_back == null:
		card_back = placeholder
	remote = OS.has_feature("web") and not FileAccess.file_exists(CARD_DIR + "SOR_095.kart")
	if remote:
		var u = JavaScriptBridge.eval("new URL('art/', window.location.href).href", true)
		_base_url = str(u) if u != null else "art/"
		var f := FileAccess.open("res://data/art_urls.json", FileAccess.READ)
		if f:
			var j = JSON.parse_string(f.get_as_text())
			if j is Dictionary:
				_cdn = j.get("base", "")
				_urls = j.get("art", {})
		for i in PARALLEL:
			var h := HTTPRequest.new()
			h.use_threads = false
			h.timeout = 30.0
			add_child(h)
			h.request_completed.connect(_on_fetched.bind(h))
			_pool.append(h)


func key_for(art: String, back := false) -> String:
	return art + ("_b" if back else "")


func has_art(art: String, back := false) -> bool:
	if remote:
		if not _urls.is_empty():
			return _urls.has(key_for(art, back))
		return art != "" and not art.begins_with("KYB")
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
	if remote:
		if _cache.has(key):
			return _cache[key]
		request(art, func(_t): pass, back)
		return placeholder
	if not _cache.has(key):
		_decode(key)
	return _cache.get(key, placeholder)


func _process(_dt: float) -> void:
	if remote:
		while not _queue.is_empty() and not _pool.is_empty():
			var key: String = _queue.pop_front()
			var h: HTTPRequest = _pool.pop_back()
			_busy[h] = key
			var url := _base_url + key.uri_encode() + ".kart"
			if not _urls.is_empty():
				url = _cdn + str(_urls.get(key, "")) if _urls.has(key) else ""
			if url == "" or h.request(url) != OK:
				_on_fetched(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray(), h)
		return
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


func _on_fetched(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, h: HTTPRequest) -> void:
	var key: String = _busy.get(h, "")
	_busy.erase(h)
	_pool.append(h)
	if key == "":
		return
	var tex: Texture2D = placeholder
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		var img := Image.new()
		if _load_any(img, body) == OK:
			tex = ImageTexture.create_from_image(img)
			_cache[key] = tex
			_touch(key)
			while _order.size() > MAX_CACHE:
				_cache.erase(_order.pop_front())
	for cb in _waiting.get(key, []):
		if cb.is_valid():
			cb.call(tex)
	_waiting.erase(key)


static func _load_any(img: Image, b: PackedByteArray) -> Error:
	if b.size() > 4 and b[0] == 0x89 and b[1] == 0x50:
		return img.load_png_from_buffer(b)
	if b.size() > 3 and b[0] == 0xFF and b[1] == 0xD8:
		return img.load_jpg_from_buffer(b)
	return img.load_webp_from_buffer(b)


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
