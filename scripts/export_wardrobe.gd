extends SceneTree
const Bridge = preload("res://scripts/wardrobe_bridge.gd")

func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	var target := ""
	var source := Bridge.DEFAULT_CATALOG
	for index in range(arguments.size()):
		if arguments[index] == "--target-project" and index + 1 < arguments.size(): target = arguments[index + 1]
		if arguments[index] == "--catalog" and index + 1 < arguments.size(): source = arguments[index + 1]
	if target.is_empty():
		printerr("Usage: godot --headless --path AeroCloth3D --script scripts/export_wardrobe.gd -- --target-project /path/to/game [--catalog res://demo/wardrobe_trial/catalog.json]")
		quit(2)
		return
	var result := Bridge.export_catalog(Bridge.load_catalog(source), target)
	print(result.get("message", ""))
	quit(0 if result["error"] == OK else 1)
