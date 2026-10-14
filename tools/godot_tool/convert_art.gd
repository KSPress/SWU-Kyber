extends SceneTree
## Converts the raw card PNGs (swu_data/art) into small lossy WebP blobs that the
## game streams at runtime (game/ip/art/cards/*.kart).
##
## The ".kart" extension is deliberate: Godot does not import it, so the editor
## never builds 2,700 texture imports, while export presets can still pack it
## (include_filter "ip/art/*"). Art.gd decodes it lazily with Image.load_webp_from_buffer.
##
## Usage (from repo root):
##   godot --headless --path tools/godot_tool --script res://convert_art.gd -- <src_art_dir> <out_dir> [max_px] [quality]

const DEFAULT_MAX := 460
const DEFAULT_Q := 0.78


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("usage: -- <src_art_dir> <out_dir> [max_px] [quality]")
		quit(1)
		return
	var src: String = args[0]
	var out: String = args[1]
	var max_px := int(args[2]) if args.size() > 2 else DEFAULT_MAX
	var q := float(args[3]) if args.size() > 3 else DEFAULT_Q
	DirAccess.make_dir_recursive_absolute(out)
	var done := 0
	var skipped := 0
	for sub in ["full", "back"]:
		var dir := DirAccess.open(src.path_join(sub))
		if dir == null:
			continue
		for f in dir.get_files():
			if not f.to_lower().ends_with(".png"):
				continue
			var stem := f.get_basename()
			var dst := out.path_join(stem + ("_b" if sub == "back" else "") + ".kart")
			if FileAccess.file_exists(dst):
				skipped += 1
				continue
			# The SWU-DB dump ships many JPEGs with a .png extension: sniff the magic bytes.
			var bytes := FileAccess.get_file_as_bytes(src.path_join(sub).path_join(f))
			var img := Image.new()
			var err := ERR_FILE_UNRECOGNIZED
			if bytes.size() > 4 and bytes[0] == 0xFF and bytes[1] == 0xD8:
				err = img.load_jpg_from_buffer(bytes)
			elif bytes.size() > 4 and bytes[0] == 0x89 and bytes[1] == 0x50:
				err = img.load_png_from_buffer(bytes)
			elif bytes.size() > 12 and bytes[8] == 0x57 and bytes[9] == 0x45:
				err = img.load_webp_from_buffer(bytes)
			if err != OK or img.is_empty():
				push_warning("could not load " + f)
				continue
			var w := img.get_width()
			var h := img.get_height()
			# portrait cards -> max_px wide; landscape leaders/bases -> 1.4x that wide
			var s := minf(float(max_px) * (1.0 if w < h else 1.4) / float(w), 1.0)
			img.resize(int(w * s), int(h * s), Image.INTERPOLATE_LANCZOS)
			var buf := img.save_webp_to_buffer(true, q)
			var fa := FileAccess.open(dst, FileAccess.WRITE)
			fa.store_buffer(buf)
			fa.close()
			done += 1
			if done % 200 == 0:
				print("converted ", done)
	print("art conversion complete: %d converted, %d already present" % [done, skipped])
	quit(0)
