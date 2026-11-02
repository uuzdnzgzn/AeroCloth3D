extends SceneTree
## Exercise the shipped workspace, its actual controls and UndoRedo paths.
## Headless checks verify state and generated geometry, not screenshot appearance.

const Scene = preload("res://demo/CharacterWardrobe.tscn")

var checks: int = 0
var failures: Array[String] = []
var lab: Control


func _initialize() -> void:
	call_deferred("run")


func expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error(description)


func find_type(node: Node, type_name: String) -> Node:
	if node.is_class(type_name):
		return node
	for child: Node in node.get_children():
		var found: Node = find_type(child, type_name)
		if found != null:
			return found
	return null


func find_button(node: Node, title: String) -> Button:
	if node is Button and node.text == title:
		return node
	for child: Node in node.get_children():
		var found: Button = find_button(child, title)
		if found != null:
			return found
	return null


func has_label(node: Node, title: String) -> bool:
	if node is Label and node.text == title:
		return true
	for child: Node in node.get_children():
		if has_label(child, title):
			return true
	return false


func click_tool(title: String) -> void:
	var button: Button = find_button(lab.tools_panel, title)
	expect(button != null, "Tool button exists: " + title)
	if button != null:
		button.pressed.emit()
	await process_frame


func run() -> void:
	lab = Scene.instantiate()
	root.add_child(lab)
	await process_frame
	await process_frame
	expect(lab.actors.size() == 3 and lab.count == 1, "Workspace prepares three independent actors and starts with one active")
	expect(lab.actors[0].skeleton != null, "Workspace preview uses the imported skinned character")
	expect(lab.viewport.size.x > 300 and lab.viewport.size.y > 300, "Preview has a usable viewport after layout")
	var names: Dictionary = lab.NAMES
	for section_index: int in range(6):
		lab._select_section(section_index)
		for id: String in lab.IDS:
			lab._select_item(id)
			var correct_tools: bool = lab.section == section_index and lab.selected == id
			correct_tools = correct_tools and has_label(lab.tools_panel, lab.SECTIONS[section_index].to_upper()) and has_label(lab.tools_panel, names[id])
			expect(correct_tools, "Context tools build for section %d / piece %s" % [section_index, id])
	expect(not lab.history.has_undo(), "Selection and tool-panel rebuilding do not create edit history")
	await process_frame
	# Toggle the real wardrobe CheckButton, then use the real Undo/Redo handlers.
	lab._select_section(3)
	lab._select_item("shoulder")
	var equip_toggle: CheckButton = find_type(lab.tools_panel, "CheckButton") as CheckButton
	expect(equip_toggle != null and equip_toggle.button_pressed, "Wardrobe exposes the selected piece's equipped state")
	if equip_toggle != null:
		equip_toggle.button_pressed = false
	expect(not lab.actors[0].shoulder.equipped and lab.actors[0].under_shoulder.visible, "Wardrobe toggle removes armor and restores its lower patch")
	expect(lab.history.has_undo() and not lab.undo_button.disabled, "Wardrobe edit creates actionable Undo history")
	lab._undo()
	await process_frame
	expect(lab.actors[0].shoulder.equipped and not lab.actors[0].under_shoulder.visible, "Wardrobe Undo restores equipment and derived coverage")
	expect(lab.history.has_redo() and not lab.redo_button.disabled, "Wardrobe Undo enables Redo")
	lab._redo()
	await process_frame
	expect(not lab.actors[0].shoulder.equipped, "Wardrobe Redo reapplies the removal")
	lab._undo()
	await process_frame
	lab.history.clear_history()
	# Edit the first actual placement SpinBox; marker state must follow Undo too.
	lab._select_section(0)
	lab._select_item("shoulder")
	var initial_point: Vector3 = lab.actors[0].shoulder.connection_points[0]
	var placement: SpinBox = find_type(lab.tools_panel, "SpinBox") as SpinBox
	expect(placement != null, "Prepared shoulder exposes editable connection coordinates")
	if placement != null:
		placement.value = initial_point.x + 0.02
	expect(is_equal_approx(lab.actors[0].shoulder.connection_points[0].x, initial_point.x + 0.02), "Placement control updates the selected authored connection")
	expect(lab.actors[0].connection_markers[0].position == lab.actors[0].shoulder.connection_points[0], "Placement control moves its visible connection marker")
	lab._undo()
	await process_frame
	expect(lab.actors[0].shoulder.connection_points[0] == initial_point, "Connection edit Undo restores authored position")
	expect(lab.actors[0].connection_markers[0].position == initial_point, "Connection edit Undo restores marker position")
	var restored_placement: SpinBox = find_type(lab.tools_panel, "SpinBox") as SpinBox
	expect(restored_placement != null and is_equal_approx(restored_placement.value, initial_point.x), "Connection edit Undo refreshes its coordinate control")
	lab._redo()
	await process_frame
	expect(is_equal_approx(lab.actors[0].shoulder.connection_points[0].x, initial_point.x + 0.02), "Connection edit Redo restores the edited position")
	lab._undo()
	await process_frame
	lab.history.clear_history()
	# Exercise the actual geometry buttons and verify their generated geometry.
	for id: String in ["shoulder", "cloth"]:
		lab._select_item(id)
		var target: Node3D = lab.actors[0].shoulder.get_visual_root() if id == "shoulder" else lab.actors[0].cloth
		var expected_vertex_count: int = 0
		for source: MeshInstance3D in lab.actors[0]._collect_meshes(target):
			if source.mesh != null and source.mesh.get_surface_count() > 0:
				var arrays: Array = source.mesh.surface_get_arrays(0)
				expected_vertex_count += arrays[Mesh.ARRAY_VERTEX].size()
		await click_tool("Kenar")
		var debug_root: Node3D = lab.actors[0].debug_root
		var lines: MeshInstance3D = find_type(debug_root, "MeshInstance3D") as MeshInstance3D if debug_root != null else null
		expect(lines != null and lines.mesh is ImmediateMesh and lines.mesh.get_surface_count() > 0, "Wire display generates actual line geometry for " + id)
		await click_tool("Vertex")
		debug_root = lab.actors[0].debug_root
		var marker: MeshInstance3D = find_type(debug_root, "MeshInstance3D") as MeshInstance3D if debug_root != null else null
		expect(marker != null and marker.mesh is SphereMesh, "Vertex display generates actual point markers for " + id)
		expect(debug_root != null and debug_root.get_child_count() == expected_vertex_count, "Vertex display excludes the previous wire overlay from source geometry for " + id)
		await click_tool("Yüzey")
		expect(lab.actors[0].debug_root == null, "Surface display removes optional geometry overlays for " + id)
	# Freeze animation and cloth integration for a deterministic projected brush stroke.
	lab._play(false)
	for actor: Node3D in lab.actors:
		actor.cloth.running = false
	lab._select_section(1)
	lab._select_item("cloth")
	lab._focus_selected()
	await process_frame
	expect(lab.actors[0].cloth.paint_visible, "Cloth painting context enables mobility colors")
	var before_weights: PackedFloat32Array = lab.actors[0].cloth.weights.duplicate()
	var screen_point: Vector2 = lab.camera.unproject_position(lab.actors[0].cloth.points[45])
	expect(Rect2(Vector2.ZERO, Vector2(lab.viewport.size)).has_point(screen_point), "Brush target projects inside the visible preview")
	lab.paint_value = 0.0
	var history_version: int = lab.history.get_version()
	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = screen_point
	press.pressed = true
	lab._preview_input(press)
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = screen_point + Vector2(3.0, 0.0)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	lab._preview_input(motion)
	var release: InputEventMouseButton = InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = motion.position
	release.pressed = false
	lab._preview_input(release)
	var after_weights: PackedFloat32Array = lab.actors[0].cloth.weights.duplicate()
	expect(after_weights != before_weights, "Projected brush stroke changes cloth mobility weights")
	expect(not lab.painting and lab.history.get_version() == history_version + 1, "Press, move and release produce exactly one completed Undo action")
	expect(lab.actors[1].cloth.weights == after_weights and lab.actors[2].cloth.weights == after_weights, "Brush stroke shares prepared weights with all test actors")
	lab._undo()
	await process_frame
	expect(lab.actors[0].cloth.weights == before_weights, "Brush Undo restores all previous mobility weights")
	lab._redo()
	await process_frame
	expect(lab.actors[0].cloth.weights == after_weights, "Brush Redo restores the full stroke")
	lab._select_item("shoulder")
	expect(not lab.actors[0].cloth.paint_visible, "Selecting a different piece clears cloth paint colors")
	for actor: Node3D in lab.actors:
		actor.cloth.running = true
	# Hidden actors must stop actual simulation, including pre-existing detached bodies.
	lab._set_count(1)
	expect(lab.actors[0].can_process() and not lab.actors[1].can_process() and not lab.actors[2].can_process(), "One-character mode disables processing for hidden actors")
	expect(not lab.actors[1].cloth.can_process(), "Hidden actor's cloth inherits disabled processing")
	lab._set_count(3)
	expect(lab.actors[0].can_process() and lab.actors[1].can_process() and lab.actors[2].can_process(), "Three-character mode enables all actors")
	var hidden_actor: Node3D = lab.actors[1]
	hidden_actor.shoulder.apply_hit()
	hidden_actor.shoulder.apply_hit()
	expect(not hidden_actor.shoulder.rigid_body.freeze, "Visible detached armor runs rigid-body physics")
	lab._set_count(1)
	var hidden_body: RigidBody3D = hidden_actor.shoulder.rigid_body
	var frozen_position: Vector3 = hidden_body.global_position
	var frozen_cloth_point: Vector3 = hidden_actor.cloth.points[50]
	expect(hidden_body.freeze and hidden_body.collision_mask == 0, "Hiding detached actor freezes its body and removes collision")
	for _frame: int in range(4):
		await physics_frame
	expect(hidden_body.global_position.is_equal_approx(frozen_position), "Hidden detached armor stays frozen across physics ticks")
	expect(hidden_actor.cloth.points[50].is_equal_approx(frozen_cloth_point), "Hidden actor's cloth performs no deformation updates")
	lab._set_count(3)
	expect(not hidden_body.freeze and hidden_body.collision_mask == 1 and hidden_actor.shoulder.get_active_connection_count() == 0, "Showing actor resumes its detached body without repairing damage")
	var resumed_y: float = hidden_body.global_position.y
	for _frame: int in range(4):
		await physics_frame
	expect(hidden_body.global_position.y < resumed_y, "Reactivated detached armor resumes falling")
	var first_actor: Node3D = lab.actors[0]
	first_actor.bag.apply_hit()
	first_actor.set_equipped("shoulder", false)
	expect(first_actor.bag.rigid_body.freeze and first_actor.bag.rigid_body.collision_layer == 0, "Parent garment removal freezes a hidden detached accessory")
	expect(not first_actor.bag.get_visual_root().is_visible_in_tree(), "Hidden detached accessory submits no visible mesh")
	first_actor.set_equipped("shoulder", true)
	expect(not first_actor.bag.rigid_body.freeze and first_actor.bag.get_active_connection_count() == 0, "Re-equipping parent resumes accessory without repairing its connection")
	var prepared_point := Vector3(-0.13,0.10,0.04)
	first_actor.shoulder.set_connection_point(0, prepared_point)
	first_actor.accessory_rule = 1
	lab._reset_all()
	expect(first_actor.shoulder.get_active_connection_count() == 2 and first_actor.bag.get_active_connection_count() == 1, "Scenario reset repairs both items")
	expect(first_actor.shoulder.connection_points[0] == prepared_point and first_actor.accessory_rule == 1, "Scenario reset preserves authored connections and accessory rules")
	lab.queue_free()
	await process_frame
	print("WORKSPACE_TESTS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
