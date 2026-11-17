extends SceneTree
const Bridge = preload("res://scripts/wardrobe_bridge.gd")
var failed := false

func check(condition: bool, message: String) -> void:
	if not condition: failed = true; printerr(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var source := {"version": 1, "garments": [{"id": "shirt", "variants": {"default": {"scene": "res://shirt.glb"}}, "parts": {"collar": {}}, "morph_limits": {"tight": [0, 1]}, "rules": [{"id": "fit", "when": {"any_tags": ["formal"]}, "actions": {"visible": true}}]}, {"id": "corset", "variants": {"default": {"scene": "res://corset.glb"}}, "parts": {}, "rules": []}]}
	var changed := Bridge.update_rule(source, "shirt", "fit", ["corset"], "tight", 0.7, ["collar"])
	check(changed["errors"].is_empty(), "Valid edit rejected")
	var rule: Dictionary = changed["catalog"]["garments"][0]["rules"][0]
	check(rule["when"]["any_tags"] == ["formal"] and rule["actions"]["visible"], "Unedited actions/conditions lost")
	check(not source["garments"][0]["rules"][0]["when"].has("all_items"), "Edit mutated source")
	check(not Bridge.update_rule(source, "shirt", "fit", ["missing"], "tight", 0.5, ["collar"])["errors"].is_empty(), "Unknown garment accepted")
	check(not Bridge.update_rule(source, "shirt", "fit", [], "unknown", 0.5, ["missing"])["errors"].is_empty(), "Unknown morph/part accepted")
	var root := "user://wardrobe_bridge_test_" + str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root))
	for name: String in ["project.godot", "shirt.glb", "corset.glb"]:
		var file := FileAccess.open(root.path_join(name), FileAccess.WRITE)
		file.store_string("test fixture " + name)
		file.close()
	var exported := Bridge.export_catalog(changed["catalog"], root, root)
	check(exported["error"] == OK, "Export failed: " + str(exported))
	var loaded := Bridge.load_catalog(root.path_join("data/wardrobe/aero_trial.json"))
	check(not loaded.is_empty(), "Export JSON missing")
	if not loaded.is_empty():
		check(loaded["garments"][0]["variants"]["default"]["scene"] == "res://assets/aero_trial/shirt.glb", "Scene was not rewritten")
		check(loaded["garments"][0]["rules"][0]["actions"]["morphs"]["tight"] == 0.7, "Edited rule was not exported")
	check(FileAccess.get_file_as_string(root.path_join("assets/aero_trial/shirt.glb")) == "test fixture shirt.glb", "GLB copy differs")
	var invalid := source.duplicate(true)
	invalid["garments"][0]["variants"]["default"]["scene"] = "res://../outside.glb"
	check(Bridge.export_catalog(invalid, root, root)["error"] != OK, "Escaping path accepted")
	var view := Bridge.new()
	view.catalog_path = root.path_join("data/wardrobe/aero_trial.json")
	get_root().add_child(view)
	check(view.garments.item_count == 2 and view.rules.item_count == 1, "GUI failed to load exported catalog")
	view.garments.select(1)
	view._show_garment()
	check(view.rules.selected < 0 and view._apply(), "Rule-free garment prevents save/export")
	view.free()
	var sidecar := ConfigFile.new()
	var import_path := root.path_join("assets/aero_trial/shirt.glb.import")
	check(sidecar.load(import_path) == OK and sidecar.get_value("params", "meshes/generate_lods", true) == false, "Fresh export did not seed LOD=false")
	sidecar.set_value("remap", "uid", "uid://existing_test")
	sidecar.set_value("params", "animation/fps", 24)
	sidecar.set_value("params", "meshes/generate_lods", true)
	sidecar.save(import_path)
	check(Bridge.export_catalog(changed["catalog"], root, root)["error"] == OK, "Existing import export failed")
	sidecar.load(import_path)
	check(sidecar.get_value("remap", "uid") == "uid://existing_test" and sidecar.get_value("params", "animation/fps") == 24 and sidecar.get_value("params", "meshes/generate_lods") == false, "Import ID/settings lost or LOD not disabled")
	check(Bridge.export_catalog(changed["catalog"], root, root)["error"] == OK, "Repeated export failed")
	sidecar.load(import_path)
	check(sidecar.get_value("params", "meshes/generate_lods") == false and sidecar.get_value("remap", "uid") == "uid://existing_test", "Existing false flag/ID not preserved")
	_test_first_import(root.path_join("fresh"))
	_cleanup(ProjectSettings.globalize_path(root))
	print("wardrobe bridge: " + ("FAIL" if failed else "PASS"))
	quit(1 if failed else 0)

func _cleanup(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null: return
	for file: String in directory.get_files(): DirAccess.remove_absolute(path.path_join(file))
	for folder: String in directory.get_directories(): _cleanup(path.path_join(folder))
	DirAccess.remove_absolute(path)

func _test_first_import(root: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root))
	var project := FileAccess.open(root.path_join("project.godot"), FileAccess.WRITE)
	project.store_string('config_version=5\n[application]\nconfig/name="Fresh wardrobe import"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
	project.close()
	var scene := Node3D.new()
	var mesh := MeshInstance3D.new()
	mesh.mesh = SphereMesh.new()
	scene.add_child(mesh)
	mesh.owner = scene
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	check(document.append_from_scene(scene, state) == OK, "GLB fixture generation failed")
	check(document.write_to_filesystem(state, root.path_join("source.glb")) == OK, "GLB fixture write failed")
	scene.free()
	var data := {"version": 1, "garments": [{"id": "test", "variants": {"default": {"scene": "res://source.glb"}}, "parts": {}, "rules": []}]}
	check(Bridge.export_catalog(data, root, root)["error"] == OK, "Fresh project export failed")
	var output: Array = []
	var exit_code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path(root), "--editor", "--import"], output, true)
	check(exit_code == 0, "Fresh Godot import failed: " + str(output))
	var sidecar := ConfigFile.new()
	check(sidecar.load(root.path_join("assets/aero_trial/source.glb.import")) == OK, "First import sidecar missing")
	check(sidecar.get_value("params", "meshes/generate_lods", true) == false, "First import reset LOD=false")
	check(str(sidecar.get_value("remap", "uid", "")).begins_with("uid://"), "Godot did not generate an import UID")
	var imported := str(sidecar.get_value("remap", "path", ""))
	check(not imported.is_empty() and FileAccess.file_exists(root.path_join(imported.trim_prefix("res://"))), "Godot did not import the GLB")
