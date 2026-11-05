extends SceneTree
## End-to-end authoring client QA. Writes generated resources only to user://.
## Run with timeout 90 and DISPLAY=:99 for an actual GL-backed UI.
const Workspace = preload("res://addons/aero_cloth_3d/editor/aero_authoring_workspace.gd")
const Canvas = preload("res://addons/aero_cloth_3d/core/aero_damage_canvas.gd")

var checks: int = 0
var failures: Array[String] = []
var lab: Control
var runtime: Node3D

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, description: String) -> bool:
	checks += 1
	if not condition:
		failures.append(description)
		push_error(description)
	return condition

func settle() -> void:
	await process_frame
	await process_frame

func first_check(node: Node) -> CheckButton:
	if node is CheckButton:
		return node
	for child: Node in node.get_children():
		var result: CheckButton = first_check(child)
		if result != null:
			return result
	return null

func runtime_only(node: Node) -> bool:
	var script: Script = node.get_script()
	if script != null and "/editor/" in script.resource_path:
		return false
	for child: Node in node.get_children():
		if not runtime_only(child):
			return false
	return true

func write_json(path: String, data: Variant) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))

func state_region(id: StringName, region: StringName) -> Dictionary:
	return lab.rig.controller.get_item_state(id).get("regions", {}).get(region, {})

func strength_at(uv:Vector2) -> Vector4:
	var material:ShaderMaterial=lab.rig.slots[&"shirt"]["materials"][0]
	var rects:PackedVector4Array=material.get_shader_parameter("damage_region_rects")
	var strengths:PackedVector4Array=material.get_shader_parameter("damage_region_strength_a")
	for i in range(int(material.get_shader_parameter("damage_region_count"))):
		if Rect2(rects[i].x,rects[i].y,rects[i].z,rects[i].w).has_point(uv):return strengths[i]
	return Vector4.ZERO

func equivalent(a: Variant, b: Variant) -> bool:
	# .tres prints decimal floats; normalize harmless Vector2 float32 rounding.
	if (a is int or a is float) and (b is int or b is float):
		return is_equal_approx(float(a), float(b))
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for key: Variant in a:
			if not b.has(key) or not equivalent(a[key], b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for index: int in range(a.size()):
			if not equivalent(a[index], b[index]): return false
		return true
	return a == b

func run() -> void:
	root.size = Vector2i(1440, 900)
	lab = Workspace.new()
	lab.size = Vector2(1440, 900)
	root.add_child(lab)
	await settle()
	expect(lab._built and lab.item_list.item_count == 5, "Real authoring UI builds all five example wearables")
	expect(lab.outfit != null and lab.outfit.character_scene != null and lab.rig.skeleton != null, "Authoring preview instantiates its imported GLB character skeleton")
	expect(lab.rig.slots.size() == 5 and lab.validate_recipe().is_empty(), "Example outfit and runtime adapters validate without missing slots")
	expect(lab.viewport.size.x > 300 and lab.viewport.size.y > 300, "Character preview receives usable space in the actual 1440x900 layout")
	expect(lab.item_list.is_visible_in_tree() and lab.tools.is_visible_in_tree() and lab.region_list.item_count == 2 and lab.stage_list.item_count == 5, "Wardrobe, contextual tools, regions and five-stage list are populated")
	expect(not lab.local_history.has_undo(), "Building the UI creates no spurious authoring edits")
	# A complete stroke creates exactly one edit and changes the authored recipe,
	# while runtime damage remains separate from the immutable source definitions.
	lab.select_item(&"shirt")
	lab.selected_tab = 1
	lab._build_tools()
	var item: Resource = lab._item()
	var before_recipe: Dictionary = item.damage_recipe.duplicate(true)
	var before_state: Dictionary = lab.rig.controller.export_state()
	var before_version: int = lab.local_history.get_version()
	lab.radius = 0.1
	lab.strength = 1.0
	lab.brush = &"cut"
	lab._stroke_begin()
	lab._stroke_at(Vector2(0.35, 0.2))
	lab._stroke_at(Vector2(0.40, 0.2))
	lab._stroke_end()
	await settle()
	var painted_recipe: Dictionary = item.damage_recipe.duplicate(true)
	expect(painted_recipe.get("operations", []).size() == 2 and not lab.painting, "Brush start/move/end records all stamped points in one completed stroke")
	expect(lab.local_history.get_version() == before_version + 1, "The complete stroke creates exactly one Undo action")
	expect(lab.rig.controller.export_state() == before_state, "Authoring map edits do not create runtime damage or seen-hit records")
	var preview_canvas: RefCounted = lab.rig.slots[&"shirt"]["canvas"]
	expect(preview_canvas.get_coverage(Vector2(0.38, 0.2)).r > 0.9, "Edited cut mask reaches the shared runtime preview canvas")
	lab._choose_stage(1)
	var preview_strengths: Variant = lab.rig.slots[&"shirt"]["materials"][0].get_shader_parameter("damage_region_strength_a")
	expect(state_region(&"shirt", &"upper").get("stage", -1) == 1 and is_equal_approx(strength_at(Vector2(.5,.25)).x, item.regions[0].stages[1].cut_strength), "Stage selection previews the chosen region alpha strength through the runtime material")
	lab._undo()
	await settle()
	expect(item.damage_recipe == before_recipe, "Brush Undo restores the entire previous authored recipe")
	lab._redo()
	await settle()
	expect(item.damage_recipe == painted_recipe, "Brush Redo restores the complete multi-point stroke")
	expect(lab.canvas.texture.get_image().get_data() == lab.canvas.image.get_data(), "Rebuilt map UI uploads restored paint after Undo/Redo")
	# Roundtrip nested typed authoring resources, including painted maps.
	var recipe_path: String = "user://authoring-workspace-outfit.tres"
	lab._save_recipe_at(recipe_path)
	expect(FileAccess.file_exists(recipe_path) and not lab.dirty, "Workspace saves a validated authoring .tres and clears its dirty marker")
	var loaded: Resource = ResourceLoader.load(recipe_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	expect(loaded != null and loaded.validate().is_empty() and loaded.items.size() == 5, "Saved .tres reloads as a complete valid outfit")
	if loaded != null:
		expect(loaded.items[0].regions.is_typed() and loaded.items[0].regions[0].stages.is_typed(), "Resource roundtrip preserves typed region and stage arrays")
		expect(equivalent(loaded.items[0].damage_recipe, painted_recipe) and equivalent(loaded.timeline, lab.outfit.timeline), "Authoring roundtrip preserves brush recipe and timeline within decimal float precision")
		var saved_canvas: RefCounted = Canvas.new()
		saved_canvas.import_recipe(loaded.items[0].damage_recipe)
		expect(saved_canvas.image.get_data() == lab.canvas.image.get_data(), "Reloaded authoring recipe reproduces the exact painted mask pixels")
	# Add/remove callbacks must safely assign the actual typed arrays and rebuild.
	lab.selected_tab = 2
	lab._build_tools()
	var region: Resource = lab._region()
	var original_count: int = region.stages.size()
	lab._add_stage()
	await settle()
	expect(region.stages.size() == original_count + 1 and region.stages.is_typed() and lab.stage_list.item_count == original_count + 1, "Add stage callback updates typed resource and its rebuilt list")
	lab.selected_stage = region.stages.size() - 1
	lab._remove_stage()
	await settle()
	expect(region.stages.size() == original_count and lab.stage_list.item_count == original_count, "Remove stage callback updates typed resource and contextual controls")
	lab._undo()
	await settle()
	expect(region.stages.size() == original_count + 1, "Undo removal restores the typed stage entry")
	lab._undo()
	await settle()
	expect(region.stages.size() == original_count, "Undo insertion returns to the original five stages")
	lab._redo()
	await settle()
	lab._redo()
	await settle()
	expect(region.stages.size() == original_count and region.validate().is_empty(), "Redo insertion/removal preserves a valid final stage sequence")
	var stage: Resource = region.stages[1]
	var original_cut: float = stage.cut_strength
	lab._commit_value("QA alpha stage", stage, "cut_strength", original_cut, 0.55)
	await settle()
	lab._choose_stage(1)
	preview_strengths = lab.rig.slots[&"shirt"]["materials"][0].get_shader_parameter("damage_region_strength_a")
	expect(is_equal_approx(stage.cut_strength, 0.55) and is_equal_approx(strength_at(Vector2(.5,.25)).x, 0.55), "Stage property edit updates both resource and selected material preview")
	lab._undo()
	await settle()
	lab._choose_stage(1)
	preview_strengths = lab.rig.slots[&"shirt"]["materials"][0].get_shader_parameter("damage_region_strength_a")
	expect(is_equal_approx(stage.cut_strength, original_cut) and is_equal_approx(strength_at(Vector2(.5,.25)).x, original_cut), "Stage property Undo rebuilds the original preview material")
	# Real wardrobe checkbox toggles runtime equipment without resetting damage.
	var authored_after_edit: Dictionary = item.damage_recipe.duplicate(true)
	var hit: Dictionary = lab.hit_selected(20)
	expect(hit.get("accepted", false), "Contextual hit tool calls the shared runtime API")
	var damaged_region: Dictionary = state_region(&"shirt", &"upper")
	lab._build_tools()
	var equipped: CheckButton = first_check(lab.tools)
	expect(equipped != null and equipped.button_pressed, "Contextual wardrobe checkbox reflects current equipment")
	if equipped != null:
		equipped.button_pressed = false
		expect(not lab.rig.controller.get_item_state(&"shirt").get("equipped", true), "Actual checkbox unequips the selected item")
		equipped.button_pressed = true
		expect(state_region(&"shirt", &"upper") == damaged_region, "Actual checkbox re-equips without resetting item damage")
	expect(item.damage_recipe == authored_after_edit, "Runtime hits and equipment changes do not mutate the authored brush recipe")
	# Attachment authoring uses the same 1-based labels as placement, with no
	# free-form indices that can silently target a missing connection.
	lab.select_item(&"jacket")
	lab.selected_tab = 2
	lab._choose_stage(2)
	var attachment_stage: Resource = lab._region().stages[2]
	var first_connection: CheckButton = lab.tools.get_node_or_null("StageConnection0")
	var second_connection: CheckButton = lab.tools.get_node_or_null("StageConnection1")
	expect(first_connection != null and second_connection != null and not first_connection.button_pressed and not second_connection.button_pressed, "Stage editor offers exactly the two real jacket connections")
	if first_connection != null and second_connection != null:
		var connection_version: int = lab.local_history.get_version()
		first_connection.button_pressed = true
		await settle()
		expect(attachment_stage.broken_connections == PackedInt32Array([0]) and lab.local_history.get_version() == connection_version + 1, "Connection checkbox writes one valid break as one Undo action")
		expect(lab.rig.slots[&"jacket"]["piece"].state == 1 and lab.tools.get_node("StageConnection0").button_pressed, "Authored connection break immediately previews the hanging state")
		lab._undo()
		await settle()
		expect(attachment_stage.broken_connections.is_empty() and lab.rig.slots[&"jacket"]["piece"].state == 0, "Undo repairs the connection and restores the attached preview")
		lab._redo()
		await settle()
		expect(attachment_stage.broken_connections == PackedInt32Array([0]) and lab.rig.slots[&"jacket"]["piece"].state == 1, "Redo restores both connection authoring and hanging preview")
		var valid_version: int = lab.local_history.get_version()
		lab._set_stage_connection(lab._item(),attachment_stage,2,true)
		expect(lab.local_history.get_version() == valid_version and attachment_stage.broken_connections == PackedInt32Array([0]), "Missing connection indices cannot alter authoring or Undo history")
		lab._undo()
		await settle()
	# Fixed-step timeline replay is deterministic and layers recompute from all
	# equipped sources; jacket release leaves the independent harness cap active.
	lab.select_item(&"jacket")
	lab.seek_time(3.25)
	expect(is_equal_approx(lab.preview_time, 3.25) and state_region(&"jacket", &"body").get("stage", -1) == 3, "Timeline seek applies all three prepared jacket hits by 3.25 seconds")
	var effects: Dictionary = lab.rig.controller.get_region_effects(&"shirt", &"upper")
	expect(is_equal_approx(effects.get("mobility", -1.0), 0.2) and effects.get("visible", false), "Jacket release exposes the shirt while independent harness still caps mobility at 0.2")
	var proxy: Node3D = lab.rig.slots[&"shirt"]["surface"]
	expect(is_equal_approx(proxy.constraints.get(&"upper", {}).get("cap", -1.0), 0.2), "Layer result reaches the actual CPU proxy constraint source")
	var replay_state: Dictionary = lab.rig.controller.export_state()
	lab.seek_time(1.2)
	expect(state_region(&"jacket", &"body").get("stage", -1) == 1, "Seeking backward rebuilds earlier damage instead of accumulating")
	lab.seek_time(3.25)
	expect(lab.rig.controller.export_state() == replay_state, "Backward/forward seek reproduces identical controller damage and seen-hit state")
	# Generated scene is a runtime rig, not an editor workspace, and starts fresh.
	var game_path: String = "user://authoring-workspace-game.tscn"
	expect(lab.export_game_scene(game_path) == OK, "Workspace exports a runtime game scene")
	var packed: PackedScene = ResourceLoader.load(game_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	expect(packed != null, "Generated game scene parses as a PackedScene")
	if packed != null:
		runtime = packed.instantiate()
		root.add_child(runtime)
		await settle()
		expect(runtime_only(runtime) and runtime.controller != null and runtime.slots.size() == 5, "Generated game scene instantiates independently with no editor script nodes")
		expect(runtime.controller.get_item_state(&"jacket")["regions"][&"body"]["stage"] == 0, "Export contains authoring configuration rather than preview combat state")
		var result: Dictionary = runtime.controller.apply_hit({"item_id":"jacket","region_id":"body","amount":12.0,"type":"slash","seed":8,"hit_id":"export_qa","uv":[0.3,0.3]})
		expect(result.get("accepted", false) and runtime.controller.get_item_state(&"jacket")["regions"][&"body"]["stage"] == 1, "Exported runtime accepts a gameplay apply_hit and changes stage")
		runtime.queue_free()
		await settle()
	# Invalid legacy profiles are atomic and valid legacy data remains undoable.
	lab.select_item(&"shirt")
	var mobility: PackedFloat32Array = lab._item().mobility.duplicate()
	var legacy_path: String = "user://authoring-workspace-legacy.json"
	write_json(legacy_path, {"format":"other", "cloth_weights":[1.0]})
	lab._import_legacy(legacy_path)
	await settle()
	expect(lab._item().mobility == mobility, "Unrecognized legacy profile cannot modify the current recipe")
	write_json(legacy_path, {"format":"AeroCloth3D.profile", "cloth_weights":[1.2, -0.1]})
	var legacy_version: int = lab.local_history.get_version()
	lab._import_legacy(legacy_path)
	await settle()
	var invalid_preserved: bool = lab._item().mobility == mobility and lab.local_history.get_version() == legacy_version
	expect(invalid_preserved, "Out-of-range legacy weights are rejected without changing resource or Undo history")
	if not invalid_preserved:
		lab._undo()
		await settle()
	var legacy_weights: Array[float] = []
	for index: int in range(mobility.size()): legacy_weights.append(0.0 if index < 9 else 0.4)
	write_json(legacy_path, {"format":"AeroCloth3D.profile", "cloth_weights":legacy_weights})
	lab._import_legacy(legacy_path)
	await settle()
	expect(lab._item().mobility.size() == mobility.size() and is_equal_approx(lab._item().mobility[20], 0.4) and lab._item().validate().is_empty(), "Valid legacy mobility profile imports into a validated typed resource")
	lab._undo()
	await settle()
	expect(lab._item().mobility == mobility, "Undo reverses the legacy import without changing prepared damage recipes")
	lab.queue_free()
	await settle()
	print("AUTHORING_WORKSPACE_TESTS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
