class_name BoardTheme
extends Control
## Animated match backdrop (spec 8.1), subtle by design:
##   * three star layers drifting slowly (parallax by depth)
##   * usually one planet, large and partly off-screen, drifting slower than the stars
##   * ship fly-bys chosen from the two leaders' factions (Rebel, Imperial,
##     Republic, Separatist, First Order...), see data/flyby.json:
##       fighters cross every several seconds in small groups, occasionally
##       trading a few laser bolts; a capital ship crawls past now and then.
##   * the pointer (or nothing, on touch) nudges every layer for depth parallax.
## Performance mode freezes everything into a static frame.

const SHIP_DIR := "res://ip/ui/ships/"
const PLANET_DIR := "res://ip/ui/planets/"

var theme_id := "auto"
var _t := 0.0
var _stars: Array = []          # {p: Vector2 (0..1), z: depth 0.2..1, tw}
var _planet: Texture2D
var _planet_rect := Rect2()     # in 0..1 viewport units (position + size by height)
var _planet_spin := 0.0
var _photo: Texture2D            # special backdrops (Death Star chapter)
var _ships: Array = []          # active fly-bys
var _bolts: Array = []
var _factions: Array = []       # [player faction, enemy faction]
var _aligned: Array = ["heroism", "villainy"]
var _manifest: Dictionary = {}
var _next_fighter := 3.0
var _next_capital := 12.0
var _side := 0
var _par := Vector2.ZERO        # smoothed pointer parallax offset (-1..1)
var _rng := RandomNumberGenerator.new()


func setup(id: String) -> void:
	theme_id = id
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.randomize()
	for i in 220:
		_stars.append({"p": Vector2(_rng.randf(), _rng.randf()), "z": _rng.randf_range(0.15, 1.0), "tw": _rng.randf() * TAU})
	var path := "res://data/flyby.json"
	if FileAccess.file_exists(path):
		var d = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(d) == TYPE_DICTIONARY:
			_manifest = d
	if id == "deathstar":
		_photo = Art.ui_texture("deathstar")
	else:
		var planet := ""
		var tp: Dictionary = _manifest.get("theme_planet", {})
		if tp.has(id):
			planet = tp[id]
		elif _rng.randf() < 0.8:
			var all: Array = _manifest.get("planets", [])
			if not all.is_empty():
				planet = all[_rng.randi_range(0, all.size() - 1)]
		if planet != "":
			_planet = Art.ui_texture("planets/" + planet)
	# planet placement: big, hugging a random corner, mostly in view
	var sz := _rng.randf_range(0.55, 0.85)
	var corner := Vector2(_rng.randf_range(-0.25, 0.55), _rng.randf_range(-0.2, 0.35))
	_planet_rect = Rect2(corner, Vector2(sz, sz))
	_planet_spin = _rng.randf_range(-0.004, 0.004)


## Leaders decide which fleets fly past. Call after the match is set up.
func set_leaders(leaders: Array) -> void:
	_factions.clear()
	_aligned.clear()
	for l in leaders:
		var data: Dictionary = l.data if l is CardInst else (l if l is Dictionary else {})
		_factions.append(faction_for(data, _manifest))
		var asp: Array = data.get("aspects", [])
		_aligned.append("heroism" if "heroism" in asp else ("villainy" if "villainy" in asp else ""))


static func faction_for(data: Dictionary, manifest: Dictionary) -> String:
	var map: Dictionary = manifest.get("trait_to_faction", {})
	for t in data.get("traits", []):
		if map.has(t):
			return map[t]
	var asp: Array = data.get("aspects", [])
	if "villainy" in asp:
		return "imperial"
	if "heroism" in asp:
		return "rebel"
	return "rebel" if randf() < 0.5 else "imperial"


func _process(dt: float) -> void:
	if Kyber.perf():
		if _t == 0.0:
			_t = 0.001
			queue_redraw()
		return
	_t += dt
	# pointer parallax (desktop); on touch the pointer rarely moves, which is fine
	var vs := size
	if vs.x > 0:
		var mp := get_local_mouse_position()
		var target := Vector2(clampf(mp.x / vs.x * 2.0 - 1.0, -1, 1), clampf(mp.y / vs.y * 2.0 - 1.0, -1, 1))
		_par = _par.lerp(target, 1.0 - exp(-dt * 1.5))
	_spawn(dt)
	for s in _ships:
		s["k"] += dt / s["dur"]
	_ships = _ships.filter(func(s): return s["k"] < 1.0)
	for b in _bolts:
		b["k"] += dt / 0.35
	_bolts = _bolts.filter(func(b): return b["k"] < 1.0)
	queue_redraw()


func _spawn(dt: float) -> void:
	if _factions.is_empty():
		return
	_next_fighter -= dt
	_next_capital -= dt
	if _next_fighter <= 0.0:
		_next_fighter = _rng.randf_range(6.0, 13.0)
		_side = 1 - _side
		_launch(_side % _factions.size(), "fighter", _rng.randi_range(1, 3))
	if _next_capital <= 0.0:
		_next_capital = _rng.randf_range(40.0, 70.0)
		_launch(_rng.randi_range(0, _factions.size() - 1), "capital", 1)


func _launch(side: int, kind: String, count: int) -> void:
	var list: Array = _manifest.get("factions", {}).get(_factions[side], [])
	var pool: Array = list.filter(func(s): return s.get("kind", "fighter") == kind)
	if pool.is_empty():
		return
	var pick: Dictionary = pool[_rng.randi_range(0, pool.size() - 1)]
	var tex := Art.ui_texture("ships/" + pick["file"])
	if tex == null:
		return
	# fly roughly along the art's nose direction, randomly mirrored for variety
	var heading := deg_to_rad(float(pick.get("heading", 0)))
	var mirror := _rng.randf() < 0.5 and kind == "fighter"
	var dir := Vector2(cos(heading), sin(heading))
	if mirror:
		dir.x = -dir.x
	dir = dir.rotated(_rng.randf_range(-0.12, 0.12))
	# path crosses the viewport: start off-screen against the direction of travel
	var mid := Vector2(_rng.randf_range(0.2, 0.8), _rng.randf_range(0.15, 0.85))
	var span := 1.5
	var from := mid - dir * span * 0.5
	var to := mid + dir * span * 0.5
	var col := Color(1.0, 0.2, 0.15) if _aligned[side] == "heroism" else (Color(0.3, 1.0, 0.35) if _aligned[side] == "villainy" else Color(1.0, 0.6, 0.2))
	for i in count:
		var off := Vector2(-dir.y, dir.x) * (i - (count - 1) / 2.0) * 0.07 - dir * i * 0.05
		_ships.append({
			"tex": tex, "from": from + off, "to": to + off, "k": -i * 0.04,
			"dur": _rng.randf_range(3.2, 5.0) if kind == "fighter" else _rng.randf_range(45.0, 65.0),
			"w": (_rng.randf_range(0.06, 0.1) if kind == "fighter" else _rng.randf_range(0.32, 0.45)),
			"mirror": mirror, "heading": heading, "dir": dir, "kind": kind,
			"alpha": 0.55 if kind == "fighter" else 0.28, "col": col,
			"fire": kind == "fighter" and _rng.randf() < 0.45, "fired": false, "z": 0.75 if kind == "fighter" else 0.35,
		})


func _vp(p: Vector2, z: float) -> Vector2:
	return Vector2(p.x * size.x, p.y * size.y) + _par * 14.0 * z


func _draw() -> void:
	var s := size
	draw_rect(Rect2(Vector2.ZERO, s), Kyber.C_BG)
	# faint nebula wash
	draw_circle(Vector2(s.x * 0.2, s.y * 0.25), s.length() * 0.35, Color(0.18, 0.12, 0.35, 0.10))
	draw_circle(Vector2(s.x * 0.85, s.y * 0.8), s.length() * 0.3, Color(0.35, 0.1, 0.15, 0.07))
	# far stars
	for st in _stars:
		if st["z"] > 0.5:
			continue
		_star(st, s)
	if _photo:
		var ts := _photo.get_size()
		var sc := maxf(s.x / ts.x, s.y / ts.y) * 1.06
		var off := (s - ts * sc) / 2.0 + Vector2(sin(_t * 0.03), cos(_t * 0.025)) * 10.0 + _par * 6.0
		draw_texture_rect(_photo, Rect2(off, ts * sc), false, Color(1, 1, 1, 0.7))
	if _planet:
		var ph := minf(s.x, s.y) * _planet_rect.size.y * 1.2
		var drift := Vector2(sin(_t * 0.011), cos(_t * 0.008)) * 18.0 + Vector2(_t * 0.6, 0.0)
		var pos := Vector2(_planet_rect.position.x * s.x, _planet_rect.position.y * s.y) + drift + _par * 6.0
		var c := pos + Vector2(ph, ph) / 2.0
		draw_set_transform(c, _t * _planet_spin, Vector2.ONE)
		draw_circle(Vector2.ZERO, ph * 0.52, Color(0.5, 0.7, 1.0, 0.05))   # atmosphere haze
		draw_texture_rect(_planet, Rect2(-Vector2(ph, ph) / 2.0, Vector2(ph, ph)), false, Color(0.85, 0.85, 0.92, 0.5))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# capital ships behind fighters
	for sh in _ships:
		if sh["kind"] == "capital":
			_ship(sh, s)
	# near stars
	for st in _stars:
		if st["z"] <= 0.5:
			continue
		_star(st, s)
	for sh in _ships:
		if sh["kind"] == "fighter":
			_ship(sh, s)
	for b in _bolts:
		var k: float = b["k"]
		var a: Vector2 = b["from"].lerp(b["to"], clampf(k, 0, 1))
		var t: Vector2 = b["from"].lerp(b["to"], clampf(k - 0.25, 0, 1))
		draw_line(t, a, Color(b["col"], 0.18 * (1.0 - k)), 4.0, true)
		draw_line(t, a, Color(b["col"].lightened(0.5), 0.5 * (1.0 - k)), 1.4, true)
	# readability veil + vignette
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.01, 0.02, 0.04, 0.28))
	draw_rect(Rect2(Vector2.ZERO, Vector2(s.x, s.y * 0.07)), Color(0, 0, 0, 0.3))
	draw_rect(Rect2(Vector2(0, s.y * 0.93), Vector2(s.x, s.y * 0.07)), Color(0, 0, 0, 0.3))


func _star(st: Dictionary, s: Vector2) -> void:
	var z: float = st["z"]
	var p: Vector2 = st["p"]
	var drift := Vector2(-4.0, 1.2) * _t * z      # slow
	var pos := Vector2(fposmod(p.x * s.x + drift.x, s.x), fposmod(p.y * s.y + drift.y, s.y)) + _par * 10.0 * z
	var tw := 0.65 + 0.35 * sin(_t * (0.6 + z) + st["tw"])
	draw_circle(pos, 0.6 + 1.3 * z, Color(0.82, 0.9, 1.0, (0.25 + 0.6 * z) * tw))


func _ship(sh: Dictionary, s: Vector2) -> void:
	var k: float = sh["k"]
	if k < 0.0:
		return
	var tex: Texture2D = sh["tex"]
	var p: Vector2 = _vp(sh["from"].lerp(sh["to"], k), sh["z"])
	var w: float = s.x * sh["w"] if s.x < s.y else s.y * sh["w"] * 1.2
	var ts := tex.get_size()
	var h := w * ts.y / ts.x
	var dir: Vector2 = sh["dir"]
	var heading: float = sh["heading"]
	# rotate the art so its nose follows the flight direction
	var art_dir := Vector2(cos(heading), sin(heading))
	if sh["mirror"]:
		art_dir.x = -art_dir.x
	var rot := art_dir.angle_to(dir)
	var fade := minf(1.0, minf(k, 1.0 - k) * 8.0)
	draw_set_transform(p, rot, Vector2(-1.0 if sh["mirror"] else 1.0, 1.0))
	draw_texture_rect(tex, Rect2(-Vector2(w, h) / 2.0, Vector2(w, h)), false, Color(1, 1, 1, sh["alpha"] * fade))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if sh["fire"] and not sh["fired"] and k > 0.35:
		sh["fired"] = true
		for i in 2:
			var start := p + dir * w * 0.4
			_bolts.append({"from": start + Vector2(-dir.y, dir.x) * (i * 2 - 1) * 4.0, "to": start + dir * s.length() * 0.35, "k": -i * 0.15, "col": sh["col"]})
