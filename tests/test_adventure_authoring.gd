extends SceneTree
const Authoring = preload("res://scripts/adventure_authoring.gd")
const Bridge = preload("res://scripts/wardrobe_bridge.gd")
var failed := false

func check(value: bool, message: String) -> void:
	if not value: failed = true; printerr(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var view := Authoring.new()
	root.add_child(view)
	check(view.catalog.get("garments", []).size() == 5, "Stage adventure set before this integration test")
	if view.catalog.is_empty(): view.free(); quit(1); return
	check(view.originals.size() == 11, "Adventure clothing mesh count differs")
	check(view.assembly.get_child_count() == 6, "Body and five garment sets not loaded")
	var before_frame := Engine.get_process_frames()
	var source_fixture := "user://adventure_source_" + str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(source_fixture))
	var source_project := FileAccess.open(source_fixture.path_join("project.godot"), FileAccess.WRITE)
	source_project.store_string("config_version=5\n"); source_project.close()
	check(Bridge.export_catalog(view.catalog, source_fixture, "res://", "adventure", "body_lab")["error"] == OK, "Independent import source could not be prepared")
	view.source_project.text = ProjectSettings.globalize_path(source_fixture)
	view.target_project.text = ProjectSettings.globalize_path(source_fixture)
	var chosen_source: String = view.source_project.text
	var chosen_target: String = view.target_project.text
	await view._import_set()
	check(not view.busy and view.originals.size() == 11, "Asynchronous import did not finish with a complete set")
	check(Engine.get_process_frames() > before_frame, "Import blocked UI processing")
	check(view.source_project.text == chosen_source and view.target_project.text == chosen_target, "Import lost selected source/target directories")
	_cleanup(ProjectSettings.globalize_path(source_fixture))
	var source := view.catalog.duplicate(true)
	var garment: Dictionary = source["garments"][0]
	var mesh: MeshInstance3D = view.target_mesh
	check(mesh.global_transform.basis.get_scale().is_equal_approx(Vector3.ONE), "Rest preview did not compensate skin bind scale")
	var mesh_path := view.meshes.get_item_text(view.meshes.selected)
	var changed := Authoring.write_face_rule(source, garment["id"], "under_corset", mesh_path, 0, [0, 1], ["adventure_corset"])
	check(changed["errors"].is_empty(), "Face rule rejected")
	changed["catalog"]["garments"][0]["parts"]["under_corset"]["faces"]["topology_sha256"] = Authoring.topology_sha256(mesh.mesh, 0)
	check(not source["garments"][0]["parts"].has("under_corset"), "Face rule mutated source")
	check(changed["catalog"]["garments"][0]["rules"][0]["when"]["all_items"] == ["adventure_corset"], "Outer condition lost")
	check(not Authoring.write_face_rule(source, garment["id"], "bad", mesh_path, 0, [0], ["missing"])["errors"].is_empty(), "Unknown outer garment accepted")
	check(not Authoring.write_face_rule(source, garment["id"], "bad", mesh_path, 0, [-1], ["adventure_corset"])["errors"].is_empty(), "Negative triangle accepted")
	view.group_name.text = "ui_under_corset"
	view.selected = [0, 1]
	for index in view.conditions.item_count:
		if view.conditions.get_item_metadata(index) == "adventure_corset": view.conditions.select(index)
	view._apply_group()
	var faces: Dictionary = view.catalog["garments"][0]["parts"]["ui_under_corset"]["faces"]
	check(faces["topology_sha256"] == Authoring.topology_sha256(mesh.mesh, 0), "UI did not persist mesh topology fingerprint")
	await view._import_set()
	check(view.status.text.begins_with("Kaydet/aktar"), "Import silently discarded applied unsaved edits")
	check(view.catalog["garments"][0]["parts"].has("ui_under_corset"), "Unsaved group lost on blocked import")
	var original_indices: PackedInt32Array = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	var masked := Authoring.filtered_mesh(mesh.mesh, 0, [0, 1])
	check(masked.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() == original_indices.size() - 6, "Preview mask did not remove two triangles")
	check(mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] == original_indices, "Preview changed source topology")
	# Authoring and game import must address the same triangle order.
	for item: Dictionary in source["garments"]:
		var path: String = item["variants"]["default"]["scene"]
		var imported: PackedScene = load(path)
		check(imported != null, "Staged asset must be editor-imported: " + path)
		if imported == null: continue
		var model := imported.instantiate()
		var direct: Node3D = view.garment_roots[item["id"]]
		for node: MeshInstance3D in view.originals:
			if not direct.is_ancestor_of(node): continue
			var other: MeshInstance3D = model.get_node_or_null(direct.get_path_to(node))
			check(other != null, "Editor import mesh path differs")
			if other == null: continue
			check(other.mesh.get_surface_count() == node.mesh.get_surface_count(), "Editor import surface count differs")
			for index in node.mesh.get_surface_count():
				var actual: Array = other.mesh.surface_get_arrays(index)
				var expected: Array = node.mesh.surface_get_arrays(index)
				check(actual[Mesh.ARRAY_INDEX] == expected[Mesh.ARRAY_INDEX], "Triangle order changed on editor import: " + str(node.name))
				check(actual[Mesh.ARRAY_VERTEX].size() == expected[Mesh.ARRAY_VERTEX].size(), "Vertex layout changed on editor import")
		model.free()
	var destination := "user://adventure_authoring_" + str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination))
	var file := FileAccess.open(destination.path_join("project.godot"), FileAccess.WRITE); file.store_string("config_version=5\n"); file.close()
	var exported := Bridge.export_catalog(changed["catalog"], destination, "res://", "adventure", "body_lab")
	check(exported["error"] == OK, "Full adventure export failed")
	var saved := Bridge.load_catalog(destination.path_join("data/wardrobe/adventure.json"))
	check(saved.get("body", {}).get("scene") == "res://assets/body_lab/body.glb", "Body reference not copied/rebased")
	check(saved["garments"][0]["parts"]["under_corset"]["faces"]["triangles"] .map(func(value): return int(value)) == [0, 1], "Authored faces lost on export")
	for name in ["body", "base", "vest", "corset", "skirt", "gaiters"]:
		check(FileAccess.file_exists(destination.path_join("assets/body_lab/" + name + ".glb")), "Missing asset: " + name)
	_verify_fresh_project(destination)
	var stale: Dictionary = changed["catalog"].duplicate(true)
	stale["garments"][0]["variants"]["default"]["source_sha256"] = "stale"
	check(Bridge.export_catalog(stale, destination, "res://", "adventure", "body_lab")["error"] == ERR_INVALID_DATA, "Changed GLB fingerprint accepted")
	var skirt: Node3D = view.garment_roots["adventure_skirt"]
	var skirt_mesh: MeshInstance3D = skirt.get_node("Armature/Skeleton3D/AV_Skirt")
	var filtered_skirt := Authoring.filtered_mesh(skirt_mesh.mesh, 0, [0])
	check(filtered_skirt.get_blend_shape_count() == 3, "Preview mask lost skirt morphs")
	check(filtered_skirt.surface_get_arrays(0)[Mesh.ARRAY_BONES] == skirt_mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_BONES], "Preview mask changed skin bones")
	view.free()
	_cleanup(ProjectSettings.globalize_path(destination))
	print("adventure authoring: " + ("FAIL" if failed else "PASS"))
	quit(1 if failed else 0)

func _cleanup(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null: return
	for file: String in directory.get_files(): DirAccess.remove_absolute(path.path_join(file))
	for folder: String in directory.get_directories(): _cleanup(path.path_join(folder))
	DirAccess.remove_absolute(path)

func _verify_fresh_project(destination: String) -> void:
	var verifier := FileAccess.open(destination.path_join("verify.gd"), FileAccess.WRITE)
	verifier.store_string("""extends SceneTree
func _initialize():
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://data/wardrobe/adventure.json"))
	var garment = data["garments"][0]
	var model = load(garment["variants"]["default"]["scene"]).instantiate()
	var part = garment["parts"]["under_corset"]
	var mesh = model.get_node(part["node"]).mesh
	var arrays = mesh.surface_get_arrays(int(part["faces"]["surface"]))
	var hashing = HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(str(arrays[Mesh.ARRAY_VERTEX].size()).to_utf8_buffer())
	hashing.update(arrays[Mesh.ARRAY_INDEX].to_byte_array())
	var matches = hashing.finish().hex_encode() == part["faces"]["topology_sha256"]
	model.free()
	if not matches: printerr("Fresh game import changed authored triangle order")
	quit(0 if matches else 1)
""")
	verifier.close()
	var output: Array = []
	var absolute := ProjectSettings.globalize_path(destination)
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", absolute, "--editor", "--import"], output, true)
	check(code == 0, "Fresh adventure project import failed: " + str(output))
	output.clear()
	code = OS.execute(OS.get_executable_path(), ["--headless", "--path", absolute, "--script", "verify.gd"], output, true)
	check(code == 0, "Fresh game topology check failed: " + str(output))
