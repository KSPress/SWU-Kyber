extends SceneTree
## Splits sheets with transparent backgrounds into one PNG per connected piece.
##   godot --headless --path tools/godot_tool --script res://split_sheet.gd -- <out_dir> <sheet.png>...
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0]
	DirAccess.make_dir_recursive_absolute(out)
	for si in range(1, a.size()):
		var img := Image.load_from_file(a[si])
		img.convert(Image.FORMAT_RGBA8)
		var w := img.get_width()
		var h := img.get_height()
		var g := 6
		var gw := w / g + 1
		var gh := h / g + 1
		var grid := PackedByteArray()
		grid.resize(gw * gh)
		for y in range(0, h, 2):
			for x in range(0, w, 2):
				if img.get_pixel(x, y).a > 0.08:
					grid[(y / g) * gw + x / g] = 1
		var seen := PackedByteArray()
		seen.resize(gw * gh)
		var n := 0
		for start in gw * gh:
			if grid[start] == 0 or seen[start] == 1:
				continue
			var stack := [start]
			seen[start] = 1
			var x0 := gw
			var y0 := gh
			var x1 := 0
			var y1 := 0
			var cnt := 0
			while not stack.is_empty():
				var i: int = stack.pop_back()
				var cx := i % gw
				var cy := i / gw
				cnt += 1
				x0 = mini(x0, cx); x1 = maxi(x1, cx); y0 = mini(y0, cy); y1 = maxi(y1, cy)
				for dy in [-2, -1, 0, 1, 2]:
					for dx in [-2, -1, 0, 1, 2]:
						var nx: int = cx + dx
						var ny: int = cy + dy
						if nx < 0 or ny < 0 or nx >= gw or ny >= gh:
							continue
						var j := ny * gw + nx
						if grid[j] == 1 and seen[j] == 0:
							seen[j] = 1
							stack.append(j)
			if cnt < 30:
				continue
			var r := Rect2i(x0 * g, y0 * g, (x1 - x0 + 1) * g, (y1 - y0 + 1) * g).intersection(Rect2i(0, 0, w, h))
			var piece := img.get_region(r)
			var name := "s%d_%02d.png" % [si, n]
			piece.save_png(out.path_join(name))
			print(name, " ", r)
			n += 1
	quit()
