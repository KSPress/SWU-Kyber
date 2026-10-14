extends SceneTree
## Cuts the official aspect icons out of leader card renders (top-right hex
## badges) into game/ip/ui/aspects/<aspect>.png. IP stays in the git-ignored ip/.
##   godot --headless --path tools/godot_tool --script res://extract_aspects.gd -- <swu_data/art/full> <out_dir>

# aspect -> [leader card file, badge slot 0|1]
const SOURCES := {
	"cunning": ["SEC_015", 0], "heroism": ["SEC_015", 1],
	"aggression": ["LOF_009", 0], "villainy": ["LOF_009", 1],
	"vigilance": ["ASH_005", 0], "command": ["LAW_010", 0],
}
# badge rects on a 1560x1117 leader front (scaled for other sizes)
const SLOT_RECTS := [Rect2(1356, 36, 158, 172), Rect2(1356, 206, 158, 172)]


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var src: String = a[0]
	var out: String = a[1]
	DirAccess.make_dir_recursive_absolute(out)
	for asp in SOURCES:
		var s: Array = SOURCES[asp]
		var bytes := FileAccess.get_file_as_bytes(src.path_join(s[0] + ".png"))
		var img := Image.new()
		if bytes[0] == 0xFF:
			img.load_jpg_from_buffer(bytes)
		else:
			img.load_png_from_buffer(bytes)
		var k := img.get_width() / 1560.0
		var r: Rect2 = SLOT_RECTS[s[1]]
		var cut := img.get_region(Rect2i(int(r.position.x * k), int(r.position.y * k), int(r.size.x * k), int(r.size.y * k)))
		cut.convert(Image.FORMAT_RGBA8)
		cut.resize(128, 140, Image.INTERPOLATE_LANCZOS)
		cut.save_png(out.path_join(asp + ".png"))
		print("aspect ", asp, " from ", s[0], " ", img.get_size())
	quit()
