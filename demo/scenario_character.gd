extends Node3D

signal changed

const Geometry = preload("res://demo/scenario_meshes.gd")
const Cloth = preload("res://demo/test_cloth.gd")
const Piece = preload("res://addons/aero_cloth_3d/core/aero_cloth_piece_3d.gd")
const SurfaceSocket = preload("res://addons/aero_cloth_3d/core/aero_cloth_surface_socket_3d.gd")
const MODEL_PATH := "res://demo/assets/recovery_character/character.glb"

var skeleton: Skeleton3D
var animation: AnimationPlayer
var shoulder: Node3D
var bag: Node3D
var cloth: MeshInstance3D
var chestplate: Node3D
var under_front: MeshInstance3D
var under_back: MeshInstance3D
var under_shoulder: MeshInstance3D
var shoulder_anchor: Node3D
var chest_anchor: Node3D
var hip_anchor: Node3D
var shoulder_socket: Node3D
var cloth_socket: Node3D
var connection_markers: Array[MeshInstance3D] = []
var selected := "shoulder"
var accessory_rule := 0 # 0: shoulder follow; 1: release with shoulder; 2: CPU cloth triangle.
var chest_equipped := true
var inner_equipped := true
var shoulder_covers_inner := true
var playing := true
var debug_mode := 0
var debug_root: Node3D
var outline: MeshInstance3D
var active_in_lab := true

func _ready() -> void:
	if ResourceLoader.exists(MODEL_PATH):
		var packed: PackedScene = load(MODEL_PATH)
		var model: Node3D = packed.instantiate()
		add_child(model)
		skeleton = _find_type(model, "Skeleton3D") as Skeleton3D
		animation = _find_type(model, "AnimationPlayer") as AnimationPlayer
		if animation:
			animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
			for animation_name in ["Idle", "Walk"]:
				if animation.has_animation(animation_name):
					animation.get_animation(animation_name).loop_mode = Animation.LOOP_LINEAR
			animation.play("Idle")
	else:
		push_error("Character GLB is not imported. Run godot --headless --editor --import --quit before opening the lab.")
	chest_anchor = _anchor("Chest", Vector3(0, 1.25, 0))
	shoulder_anchor = _anchor("UpperArm_R", Vector3(-0.285, 1.43, 0.025))
	hip_anchor = _anchor("Hips", Vector3(-0.27, 1.00, 0.16))
	_build_layers()
	_build_shoulder()
	cloth = Cloth.new()
	hip_anchor.add_child(cloth)
	cloth.name = "PreparedClothPatch"
	_build_cloth_socket()
	_build_bag()
	set_selected("shoulder")
	refresh_coverage()

func _find_type(node: Node, type_name: String) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var result: Node = _find_type(child, type_name)
		if result:
			return result
	return null

func _anchor(bone: String, character_point: Vector3) -> Node3D:
	var parent_node: Node3D = self
	if skeleton and skeleton.find_bone(bone) >= 0:
		var attachment := BoneAttachment3D.new()
		attachment.bone_name = bone
		skeleton.add_child(attachment)
		parent_node = attachment
	var anchor := Node3D.new()
	parent_node.add_child(anchor)
	anchor.global_transform = Transform3D(global_basis, global_transform * character_point)
	return anchor

func _build_layers() -> void:
	var inner_rings: Array[Vector3] = [Vector3(0.191, -0.28, 0.124), Vector3(0.219, 0.025, 0.145), Vector3(0.175, 0.19, 0.12)]
	under_front = Geometry.shell(inner_rings, Color("24968f"), 10, PI)
	chest_anchor.add_child(under_front)
	under_front.name = "InnerFrontRegion"
	under_back = Geometry.shell(inner_rings, Color("24968f"), 10, PI)
	chest_anchor.add_child(under_back)
	under_back.rotation.y = PI
	under_back.name = "InnerBackRegion"
	chestplate = Geometry.shell([Vector3(0.211, -0.275, 0.15), Vector3(0.242, 0.027, 0.178), Vector3(0.199, 0.204, 0.148)], Color("40516b"), 10, PI)
	chest_anchor.add_child(chestplate)
	chestplate.name = "PreparedBreastplate"
	var trim: MeshInstance3D = Geometry.box(Vector3(0.025, 0.39, 0.018), Color("f3b770"), 0.5)
	chestplate.add_child(trim)
	trim.position = Vector3(0, -0.01, 0.183)
	under_shoulder = Geometry.shell([Vector3(0.15, -0.05, 0.135), Vector3(0.162, 0.025, 0.142), Vector3(0.08, 0.08, 0.08)], Color("2dd6bf"), 10)
	shoulder_anchor.add_child(under_shoulder)
	under_shoulder.name = "InnerShoulderRegion"

func _build_shoulder() -> void:
	shoulder = Piece.new()
	add_child(shoulder)
	shoulder.name = "TwoLinkShoulderArmor"
	shoulder.collision_size = Vector3(0.40, 0.22, 0.36)
	var visual := Node3D.new()
	var armor: MeshInstance3D = Geometry.shell([Vector3(0.19, -0.045, 0.17), Vector3(0.20, 0.06, 0.18), Vector3(0.12, 0.145, 0.12)], Color("64738b"), 10)
	visual.add_child(armor)
	var stripe: MeshInstance3D = Geometry.box(Vector3(0.22, 0.025, 0.027), Color("edaf68"), 0.6)
	visual.add_child(stripe)
	stripe.position = Vector3(0, 0.07, 0.173)
	shoulder.configure(shoulder_anchor, visual, [Vector3(-0.11, 0.09, 0.035), Vector3(0.11, 0.09, 0.035)], 0.8)
	shoulder.state_changed.connect(_on_piece_changed)
	connection_markers = Geometry.markers(visual, [Vector3(-0.11, 0.09, 0.035), Vector3(0.11, 0.09, 0.035)], Color("52e4ce"))
	for marker in connection_markers:
		marker.material_override.no_depth_test = true
		marker.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var box_points := PackedVector3Array()
	var a := Vector3(-0.215, -0.06, -0.19)
	var b := Vector3(0.215, 0.16, 0.19)
	var corners: Array[Vector3] = [Vector3(a.x,a.y,a.z),Vector3(b.x,a.y,a.z),Vector3(b.x,a.y,b.z),Vector3(a.x,a.y,b.z),Vector3(a.x,b.y,a.z),Vector3(b.x,b.y,a.z),Vector3(b.x,b.y,b.z),Vector3(a.x,b.y,b.z)]
	for pair in [Vector2i(0,1),Vector2i(1,2),Vector2i(2,3),Vector2i(3,0),Vector2i(4,5),Vector2i(5,6),Vector2i(6,7),Vector2i(7,4),Vector2i(0,4),Vector2i(1,5),Vector2i(2,6),Vector2i(3,7)]:
		box_points.append(corners[pair.x])
		box_points.append(corners[pair.y])
	outline = Geometry.line(box_points, Color("43e1c8"))
	visual.add_child(outline)

func _build_cloth_socket() -> void:
	cloth_socket = SurfaceSocket.new()
	cloth_socket.name = "CPUClothTriangleSocket"
	add_child(cloth_socket)
	cloth_socket.configure(cloth, Vector3i(33, 42, 34), Vector3(0.3, 0.3, 0.4), 0.04)
	cloth_socket.set_physics_process(false)

func _build_bag() -> void:
	shoulder_socket = Node3D.new()
	shoulder_socket.name = "ShoulderAccessorySocket"
	shoulder.get_visual_root().add_child(shoulder_socket)
	shoulder_socket.position = Vector3(-0.14, -0.16, 0.23)
	bag = Piece.new()
	add_child(bag)
	bag.name = "IndependentAccessory"
	bag.process_physics_priority = 2
	bag.collision_size = Vector3(0.12, 0.18, 0.08)
	var visual := Node3D.new()
	var pouch: MeshInstance3D = Geometry.box(Vector3(0.12, 0.16, 0.07), Color("ad7656"))
	visual.add_child(pouch)
	pouch.position.y = -0.06
	var flap: MeshInstance3D = Geometry.box(Vector3(0.125, 0.045, 0.075), Color("d69a69"))
	visual.add_child(flap)
	flap.position.y = -0.005
	bag.configure(shoulder_socket, visual, [Vector3(0, 0.03, 0)], 0.2)
	bag.state_changed.connect(_on_piece_changed)

func _accessory_parent_equipped() -> bool:
	return cloth.equipped if accessory_rule == 2 and is_instance_valid(cloth) else shoulder.equipped

func _sync_accessory_anchor() -> void:
	var target: Node3D = cloth_socket if accessory_rule == 2 else shoulder_socket
	if accessory_rule == 2:
		cloth_socket.update_from_surface()
	if bag.anchor != target:
		bag.anchor = target
		# Changing an authored attachment is not an impact or an item repair.
		# Invalidate the anchor-velocity sample to avoid a spurious release impulse.
		bag._anchor_sample_valid = false
		bag._anchor_velocity = Vector3.ZERO
	bag._update_attached_pose()

func _on_piece_changed(_piece: Node = null) -> void:
	if is_instance_valid(bag) and accessory_rule == 1 and shoulder.get_active_connection_count() == 0 and bag.get_active_connection_count() > 0:
		bag.apply_hit()
	refresh_coverage()
	changed.emit()

func refresh_coverage() -> void:
	if not is_instance_valid(under_shoulder):
		return
	under_shoulder.visible = inner_equipped and not (shoulder_covers_inner and shoulder.equipped and shoulder.get_active_connection_count() == 2)
	under_front.visible = inner_equipped and not chest_equipped
	under_back.visible = inner_equipped
	chestplate.visible = chest_equipped
	# The bag owns its damage/equipped state; parent visibility only gates its display.
	if is_instance_valid(bag):
		_sync_accessory_anchor()
		bag.get_visual_root().visible = bag.equipped and _accessory_parent_equipped()
		_sync_effective_activity()
	if is_instance_valid(outline):
		outline.visible = selected == "shoulder" and shoulder.equipped
	for i in range(connection_markers.size()):
		connection_markers[i].position = shoulder.connection_points[i]
		connection_markers[i].visible = selected == "shoulder" and shoulder.equipped
		var mat: StandardMaterial3D = connection_markers[i].material_override
		mat.albedo_color = Color("ff6c6c") if shoulder.broken_connections[i] else Color("52e4ce")

func set_selected(id: String) -> void:
	selected = id
	if cloth:
		cloth.paint_visible = false
	refresh_coverage()

func set_equipped(id: String, value: bool) -> void:
	match id:
		"shoulder": shoulder.set_equipped(value)
		"bag": bag.set_equipped(value)
		"cloth": cloth.set_equipped(value)
		"chest": chest_equipped = value
		"inner": inner_equipped = value
	refresh_coverage()
	changed.emit()

func set_active(value: bool) -> void:
	active_in_lab = value
	visible = value
	process_mode = Node.PROCESS_MODE_INHERIT if value else Node.PROCESS_MODE_DISABLED
	_sync_effective_activity()

func _sync_effective_activity() -> void:
	if is_instance_valid(cloth_socket):
		cloth_socket.set_physics_process(active_in_lab and accessory_rule == 2 and cloth.equipped)
	for piece in [shoulder, bag]:
		var effective: bool = active_in_lab and piece.equipped and (_accessory_parent_equipped() if piece == bag else true)
		piece.set_physics_process(effective)
		if piece.get_active_connection_count() == 0:
			piece.rigid_body.freeze = not effective
			piece.rigid_body.collision_layer = 2 if effective else 0
			piece.rigid_body.collision_mask = 1 if effective else 0

func is_equipped(id: String) -> bool:
	match id:
		"shoulder": return shoulder.equipped
		"bag": return bag.equipped
		"cloth": return cloth.equipped
		"chest": return chest_equipped
		"inner": return inner_equipped
	return false

func hit_selected() -> bool:
	match selected:
		"shoulder": return shoulder.apply_hit(-1, Vector3(-0.7, 0.25, 0.8))
		"bag": return bag.apply_hit(-1, Vector3(-0.5, 0.2, 0.5))
		"cloth": return cloth.hit()
	return false

func reset_damage() -> void:
	shoulder.reset_damage()
	bag.reset_damage()
	cloth.reset_damage()
	refresh_coverage()
	changed.emit()

func set_animation(name_value: String) -> void:
	if animation and animation.has_animation(name_value):
		animation.play(name_value)
		playing = true

func set_playing(value: bool) -> void:
	playing = value
	if animation:
		if value:
			animation.play()
		else:
			animation.pause()

func snapshot() -> Dictionary:
	return {"shoulder": shoulder.snapshot(), "bag": bag.snapshot(), "cloth_broken": cloth.broken.duplicate(), "cloth_equipped": cloth.equipped, "weights": cloth.weights.duplicate(), "cloth_points": cloth.points.duplicate(), "cloth_previous": cloth.previous.duplicate(), "chest": chest_equipped, "inner": inner_equipped, "rule": accessory_rule,"shoulder_covers_inner":shoulder_covers_inner}

func restore(data: Dictionary) -> void:
	accessory_rule = data["rule"]
	chest_equipped = data["chest"]
	inner_equipped = data["inner"]
	shoulder_covers_inner = data.get("shoulder_covers_inner", true)
	shoulder.restore(data["shoulder"])
	bag.restore(data["bag"])
	cloth.broken.assign(data["cloth_broken"])
	cloth.set_equipped(data["cloth_equipped"])
	cloth.weights = data["weights"].duplicate()
	cloth.points = data["cloth_points"].duplicate()
	cloth.previous = data["cloth_previous"].duplicate()
	cloth._upload()
	refresh_coverage()
	changed.emit()

func selected_world_position() -> Vector3:
	match selected:
		"shoulder": return shoulder.get_visual_root().global_position
		"bag": return bag.get_visual_root().global_position
		"cloth": return cloth.global_position + Vector3(0,-0.25,0)
	return chest_anchor.global_position

func set_debug(mode: int) -> void:
	debug_mode = mode
	if is_instance_valid(debug_root):
		debug_root.get_parent().remove_child(debug_root)
		debug_root.queue_free()
		debug_root = null
	if mode == 0:
		return
	var target: Node3D = shoulder.get_visual_root() if selected == "shoulder" else (bag.get_visual_root() if selected == "bag" else (cloth if selected == "cloth" else (under_back if selected == "inner" else chestplate)))
	debug_root = Node3D.new()
	target.add_child(debug_root)
	var points := PackedVector3Array()
	var vertices: Array[Vector3] = []
	for child in _collect_meshes(target):
		if child.mesh and child.mesh.get_surface_count() > 0 and (not child.mesh is ArrayMesh or child.mesh.surface_get_primitive_type(0) == Mesh.PRIMITIVE_TRIANGLES):
			var local_transform: Transform3D = target.global_transform.affine_inverse() * child.global_transform
			var arrays: Array = child.mesh.surface_get_arrays(0)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var ids: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			for v in verts:
				vertices.append(local_transform * v)
			for k in range(0, ids.size() if ids.size() else verts.size(), 3):
				var a: Vector3 = local_transform * verts[ids[k] if ids.size() else k]
				var b: Vector3 = local_transform * verts[ids[k+1] if ids.size() else k+1]
				var c: Vector3 = local_transform * verts[ids[k+2] if ids.size() else k+2]
				points.append_array(PackedVector3Array([a,b,b,c,c,a]))
	if mode == 1 and not points.is_empty():
		debug_root.add_child(Geometry.line(points, Color("55ffe0")))
	elif mode == 2 and not vertices.is_empty():
		Geometry.markers(debug_root, vertices, Color("55ffe0"), 0.004)

func _collect_meshes(node: Node3D) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if node == cloth:
		return [cloth.get_debug_source()]
	if node.is_queued_for_deletion() or node == debug_root or node == outline or (node is MeshInstance3D and node in connection_markers):
		return result
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		if child is Node3D:
			result.append_array(_collect_meshes(child))
	return result
