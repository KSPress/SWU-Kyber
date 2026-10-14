extends SceneTree
## Builds the official-asset UI set from the reference images in the project
## proj into game/ip/ui (git-ignored):
##   logo.png, card_back.png (+ card_backs/*), aspects/*.png, tokens/*.png,
##   ships/*.png (backgrounds keyed out), planets/*.png (disc-masked).
##   godot --headless --path tools/godot_tool --script res://build_assets.gd -- "<project root>"

const SHEET1 := "Untitled design (2)/1.png"
const SHEET2 := "Untitled design (2)/2.png"
const SHEET3 := "Untitled design (2)/3.png"
const SHEET4 := "Untitled design (2)/4.png"

# name -> [source, Rect2i]   (transparent sheet crops, trimmed to alpha)
const UI := {
	"logo": [SHEET1, Rect2i(42, 36, 342, 324)],
	"card_backs/blue": [SHEET1, Rect2i(510, 48, 264, 366)],
	"card_backs/gold": [SHEET1, Rect2i(786, 48, 258, 366)],
	"card_backs/red": [SHEET1, Rect2i(1062, 48, 258, 366)],
	"card_backs/green": [SHEET1, Rect2i(1338, 48, 258, 366)],
	"aspects/cunning": [SHEET1, Rect2i(508, 444, 82, 90)],
	"aspects/villainy": [SHEET1, Rect2i(596, 444, 78, 90)],
	"aspects/command": [SHEET1, Rect2i(682, 444, 82, 90)],
	"aspects/aggression": [SHEET1, Rect2i(766, 444, 82, 90)],
	"aspects/vigilance": [SHEET1, Rect2i(860, 444, 90, 90)],
	"aspects/heroism": [SHEET1, Rect2i(958, 444, 82, 90)],
	"tokens/initiative": [SHEET1, Rect2i(512, 578, 176, 140)],
	"tokens/plan": [SHEET1, Rect2i(412, 734, 184, 148)],
	"tokens/blast": [SHEET1, Rect2i(620, 734, 182, 146)],
}

# ships: name -> [source, Rect2i (zero = whole image), key ("alpha"|"black")]
const SHIPS := {
	"rebel_xwing": [SHEET2, Rect2i(734, 58, 140, 80), "black"],
	"rebel_bwing": [SHEET2, Rect2i(738, 138, 86, 140), "black"],
	"rebel_awing": [SHEET2, Rect2i(824, 244, 120, 52), "black"],
	"rebel_ywing": [SHEET2, Rect2i(734, 338, 184, 86), "black"],
	"rebel_xwing_top": [SHEET2, Rect2i(1266, 510, 354, 324), "black"],
	"rebel_tantive": [SHEET4, Rect2i(918, 522, 888, 474), "alpha"],
	"imperial_tie": [SHEET2, Rect2i(1216, 106, 360, 104), "black"],
	"imperial_interceptor": [SHEET2, Rect2i(1192, 288, 372, 104), "black"],
	"firstorder_silencer": [SHEET2, Rect2i(1102, 204, 494, 94), "black"],
	"imperial_stardestroyer": ["b2ad702718e83075796341a6851f7a03.jpg", Rect2i(), "black"],
	"republic_arc170_top": [SHEET3, Rect2i(18, 30, 326, 558), "alpha"],
	"republic_arc170": [SHEET3, Rect2i(336, 132, 600, 384), "alpha"],
	"republic_venator": [SHEET4, Rect2i(30, 24, 684, 408), "alpha"],
	"separatist_vulture": [SHEET3, Rect2i(480, 534, 786, 492), "alpha"],
	"separatist_trifighter": ["2106c1d9039c99f29b890a9fde3057ed.jpg", Rect2i(), "black"],
	"separatist_frigate": ["9fa18c146d5a68b39371689cc3198679.jpg", Rect2i(), "black"],
}

# planets: name -> source (disc fitted automatically); "ring" also keeps bright ring pixels
const PLANETS := {
	"dathomir": "Dathomir.jpg",
	"kessel": "Kessel.jpg",
	"tatooine": "Tatooine.jpg",
	"geonosis": "Corisant.jpg",
	"felucia": "shiny-man-felucia-icon-black.jpg",
	"kuat": "shiny-man-kuat-icon-02-b.jpg",
	"kuat_ring": "shiny-man-kuat-icon-ring-02-b.jpg",
	"nar_shaddaa": "shiny-man-nar-shaddaa-icon-1-b.jpg",
	"kamino": "kevin-scheiman-oceanic-01-icon-black.jpg",
	"mustafar": "4b7e0781908cad8885f89554d57ded9e.jpg",
}

# fixed disc (cx, cy, r) as fractions of image width, for planets the auto-fit can't read
const DISC_OVERRIDE := {"kuat_ring": Vector3(0.4845, 0.5185 * 0.5625, 0.2475)}

var proj := ""
var out := ""


func _init() -> void:
	proj = OS.get_cmdline_user_args()[0]
	out = proj.path_join("game/ip/ui")
	for k in UI:
		var img := _load(UI[k][0]).get_region(UI[k][1])
		img = _trim(img)
		_save(img, k)
	# default card back + logo also at the names the game already uses
	_save(Image.load_from_file(out.path_join("card_backs/blue.png")), "card_back")
	_force()
	for k in SHIPS:
		var s: Array = SHIPS[k]
		var img := _load(s[0])
		var r: Rect2i = s[1]
		if r.size != Vector2i.ZERO:
			img = img.get_region(r)
		if k == "republic_venator":
			# the Star Destroyer overlaps the Venator's lower-right corner on the sheet
			for y in range(230, img.get_height()):
				for x in range(400, img.get_width()):
					img.set_pixel(x, y, Color(0, 0, 0, 0))
		_fit(img, 720)
		if s[2] == "black":
			_key_black(img)
		_keep_main_parts(img)
		img = _trim(img)
		_save(img, "ships/" + k)
	for k in PLANETS:
		var img := _load(PLANETS[k])
		_fit(img, 1024)
		_disc(img, k == "kuat_ring", DISC_OVERRIDE.get(k, Vector3.ZERO))
		img = _trim(img)
		_save(img, "planets/" + k)
	print("assets built")
	quit()


func _load(rel: String) -> Image:
	var bytes := FileAccess.get_file_as_bytes(proj.path_join(rel))
	var img := Image.new()
	if bytes[0] == 0xFF and bytes[1] == 0xD8:
		img.load_jpg_from_buffer(bytes)
	elif bytes[0] == 0x89:
		img.load_png_from_buffer(bytes)
	else:
		img.load_webp_from_buffer(bytes)
	img.convert(Image.FORMAT_RGBA8)
	return img


func _save(img: Image, name: String) -> void:
	var p := out.path_join(name + ".png")
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	img.save_png(p)
	print("  ", name, " ", img.get_size())


func _fit(img: Image, mx: int) -> void:
	var s := float(mx) / maxf(img.get_width(), img.get_height())
	if s < 1.0:
		img.resize(int(img.get_width() * s), int(img.get_height() * s), Image.INTERPOLATE_LANCZOS)


func _trim(img: Image) -> Image:
	var r := img.get_used_rect()
	if r.size.x <= 0:
		return img
	return img.get_region(r.grow(2).intersection(Rect2i(Vector2i.ZERO, img.get_size())))


## Space background -> transparent: flood from the borders through dark pixels,
## with a soft alpha ramp so engine glows and hull edges stay smooth.
func _key_black(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var seen := PackedByteArray()
	seen.resize(w * h)
	var stack: Array = []
	for x in w:
		stack.append(x)
		stack.append((h - 1) * w + x)
	for y in h:
		stack.append(y * w)
		stack.append(y * w + w - 1)
	while not stack.is_empty():
		var i: int = stack.pop_back()
		if seen[i] == 1:
			continue
		var x := i % w
		var y := i / w
		var c := img.get_pixel(x, y)
		var m := maxf(c.r, maxf(c.g, c.b))
		if m > 0.24:
			continue
		seen[i] = 1
		img.set_pixel(x, y, Color(c.r, c.g, c.b, smoothstep(0.07, 0.24, m)))
		if x > 0: stack.append(i - 1)
		if x < w - 1: stack.append(i + 1)
		if y > 0: stack.append(i - w)
		if y < h - 1: stack.append(i + w)


## Drop stray stars: keep only opaque components at least 4% of the largest.
func _keep_main_parts(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var label := PackedInt32Array()
	label.resize(w * h)
	var sizes: Array = [0]
	var n := 0
	for start in w * h:
		if label[start] != 0 or img.get_pixel(start % w, start / w).a < 0.5:
			continue
		n += 1
		var cnt := 0
		var stack := [start]
		label[start] = n
		while not stack.is_empty():
			var i: int = stack.pop_back()
			cnt += 1
			var x := i % w
			var y := i / w
			for j in [i - 1 if x > 0 else -1, i + 1 if x < w - 1 else -1, i - w if y > 0 else -1, i + w if y < h - 1 else -1]:
				if j >= 0 and label[j] == 0 and img.get_pixel(j % w, j / w).a >= 0.5:
					label[j] = n
					stack.append(j)
		sizes.append(cnt)
	var big := 0
	for s in sizes:
		big = maxi(big, s)
	for i in w * h:
		var l := label[i]
		var c := img.get_pixel(i % w, i / w)
		if c.a <= 0.0:
			continue
		if l == 0:
			# soft, unlabelled pixel: keep only if next to a kept part
			continue
		if sizes[l] < big * 0.06:
			img.set_pixel(i % w, i / w, Color(c, 0.0))


## Fit a disc to the planet (lit side defines the edge; the dark side is
## completed from the bounding box) and clear everything outside it.
func _disc(img: Image, keep_ring: bool, fixed := Vector3.ZERO) -> void:
	var w := img.get_width()
	var h := img.get_height()
	if fixed != Vector3.ZERO:
		_mask_disc(img, Vector2(fixed.x * w, fixed.y * w), fixed.z * w, keep_ring)
		return
	var x0 := w
	var y0 := h
	var x1 := 0
	var y1 := 0
	var left := 0.0
	var right := 0.0
	var top := 0.0
	var bottom := 0.0
	for y in range(0, h, 2):
		for x in range(0, w, 2):
			var c := img.get_pixel(x, y)
			var m := maxf(c.r, maxf(c.g, c.b))
			if m > 0.16:
				x0 = mini(x0, x); x1 = maxi(x1, x); y0 = mini(y0, y); y1 = maxi(y1, y)
				if x < w / 2: left += m
				else: right += m
				if y < h / 2: top += m
				else: bottom += m
	var d := maxi(x1 - x0, y1 - y0)
	var cx := float(x0 + x1) / 2.0
	var cy := float(y0 + y1) / 2.0
	if x1 - x0 < d:
		cx = (x1 - d / 2.0) if left < right else (x0 + d / 2.0)
	if y1 - y0 < d:
		cy = (y1 - d / 2.0) if top < bottom else (y0 + d / 2.0)
	_mask_disc(img, Vector2(cx, cy), d / 2.0 * 0.985, keep_ring)


func _mask_disc(img: Image, c0: Vector2, r: float, keep_ring: bool) -> void:
	var cx := c0.x
	var cy := c0.y
	var w := img.get_width()
	var h := img.get_height()
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			var dist := Vector2(x - cx, y - cy).length()
			var a := clampf((r - dist) / 2.5, 0.0, 1.0)
			if keep_ring and a < 1.0:
				var m := maxf(c.r, maxf(c.g, c.b))
				a = maxf(a, smoothstep(0.10, 0.35, m))
			img.set_pixel(x, y, Color(c, a))


## The Force token photo: gold front and blue back, each cut with a circle.
func _force() -> void:
	var src := _load("SWU-Force-Token-Black-Gold.webp")
	var front_c := Vector2(487, 567)
	var back_c := Vector2(703, 293)
	var r := 209.0
	for side in [["tokens/force", front_c, Vector2(-1, -1)], ["tokens/force_back", back_c, front_c]]:
		var c: Vector2 = side[1]
		var reg := Rect2i(int(c.x - r - 4), int(c.y - r - 4), int(r * 2 + 8), int(r * 2 + 8))
		var img := src.get_region(reg)
		var occl: Vector2 = side[2]
		for y in img.get_height():
			for x in img.get_width():
				var p := Vector2(reg.position) + Vector2(x, y)
				var a := clampf((r - p.distance_to(c)) / 2.0, 0.0, 1.0)
				if occl.x >= 0.0:
					# the back token is partly hidden by the front one: rebuild it as plain black rim
					var under := clampf((r + 6.0 - p.distance_to(occl)) / 2.0, 0.0, 1.0)
					if under > 0.0:
						var mirror := c + (c - p)          # point-mirror through the centre
						var mc := src.get_pixelv(Vector2i(clampi(int(mirror.x), 0, src.get_width() - 1), clampi(int(mirror.y), 0, src.get_height() - 1)))
						img.set_pixel(x, y, mc)
				var px := img.get_pixel(x, y)
				img.set_pixel(x, y, Color(px, a))
		_save(img, side[0])
