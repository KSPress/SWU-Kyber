extends Node
## Run as a scene (autoloads active) to compile-check every script:
##   godot --headless --path game res://tests/compile_all.tscn
func _ready() -> void:
	var bad := 0
	var stack := ["res://"]
	while not stack.is_empty():
		var d: String = stack.pop_back()
		var da := DirAccess.open(d)
		if da == null:
			continue
		for sub in da.get_directories():
			if not sub.begins_with(".") and sub != "ip":
				stack.append(d.path_join(sub))
		for f in da.get_files():
			if f.ends_with(".gd"):
				var s = load(d.path_join(f))
				if s == null or not (s as Script).can_instantiate():
					print("BROKEN: ", d.path_join(f))
					bad += 1
	print("compile check: broken scripts = ", bad)
	get_tree().quit(1 if bad else 0)
