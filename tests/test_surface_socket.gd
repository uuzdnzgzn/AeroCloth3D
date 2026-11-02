extends SceneTree
## CPU-authoritative surface attachment and actual character integration checks.

const Socket = preload("res://addons/aero_cloth_3d/core/aero_cloth_surface_socket_3d.gd")
const Actor = preload("res://demo/scenario_character.gd")
const Piece = preload("res://addons/aero_cloth_3d/core/aero_cloth_piece_3d.gd")

class ProxySource:
	extends Node3D
	var points: PackedVector3Array = PackedVector3Array()

var checks: int = 0
var failures: Array[String] = []
var actors: Array[Node3D] = []


func _initialize() -> void:
	call_deferred("run")


func expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error(description)


func make_actor(index: int) -> Node3D:
	var actor: Node3D = Actor.new()
	actor.position.x = float(index) * 2.0
	root.add_child(actor)
	actors.append(actor)
	return actor


func expected_socket_pose(source: Node3D, socket: Node3D) -> Transform3D:
	var indices: Vector3i = socket.triangle_indices
	var a: Vector3 = source.points[indices.x]
	var b: Vector3 = source.points[indices.y]
	var c: Vector3 = source.points[indices.z]
	var x_axis: Vector3 = (c - a).normalized()
	var z_axis: Vector3 = (b - a).cross(c - a).normalized()
	var y_axis: Vector3 = z_axis.cross(x_axis).normalized()
	var weights: Vector3 = socket.barycentric_weights
	var origin: Vector3 = a * weights.x + b * weights.y + c * weights.z + z_axis * socket.normal_offset
	return Transform3D(Basis(x_axis, y_axis, z_axis), origin)


func run() -> void:
	var source: ProxySource = ProxySource.new()
	root.add_child(source)
	source.position = Vector3(19.0, 3.0, -8.0)
	source.points = PackedVector3Array([Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, 0.0), Vector3(1.0, 1.0, 0.0)])
	var socket: Node3D = Socket.new()
	root.add_child(socket)
	socket.set_physics_process(false)
	expect(socket.configure(source, Vector3i(0, 1, 2), Vector3(0.3, 0.3, 0.4), 0.04), "Valid CPU triangle initializes a surface socket")
	expect(socket.has_valid_pose, "Valid triangle records an initialized attachment frame")
	expect(socket.global_position.is_equal_approx(Vector3(0.4, 0.7, 0.04)), "Barycentric anchor includes the authored normal offset")
	expect(socket.global_basis.is_equal_approx(Basis.IDENTITY), "Canonical cloth triangle produces right/up/outward axes")
	expect(socket.global_position.x < 1.0, "CPU world points are not transformed twice by the source node")
	var motion: Transform3D = Transform3D(Basis.from_euler(Vector3(0.2, 0.35, -0.13)), Vector3(2.0, 3.0, 4.0))
	for index: int in range(source.points.size()):
		source.points[index] = motion * source.points[index]
	expect(socket.update_from_surface(), "Moving the CPU triangle updates the attachment")
	expect(socket.global_position.is_equal_approx(motion * Vector3(0.4, 0.7, 0.04)), "Translated and rotated triangle moves the barycentric point correctly")
	expect(socket.global_basis.is_equal_approx(motion.basis), "Socket orientation follows the triangle rotation")
	source.points[2] += Vector3(0.0, 0.2, 0.5)
	socket.update_from_surface()
	expect(socket.global_transform.is_equal_approx(expected_socket_pose(source, socket)), "Deforming a single CPU vertex recomputes position and normal from all three vertices")
	expect(is_equal_approx(socket.global_basis.determinant(), 1.0), "Deformed socket Basis stays orthonormal and right-handed")
	expect(socket.configure(source, Vector3i(0, 1, 2), Vector3(1.0, 1.0, 2.0), 0.04), "Authored non-unit barycentric weights can be normalized")
	expect(socket.barycentric_weights.is_equal_approx(Vector3(0.25, 0.25, 0.5)), "Weights normalize by their sum")
	var last_valid: Transform3D = socket.global_transform
	expect(not socket.configure(source, Vector3i(0, 1, 2), Vector3(-1.0, 1.0, 1.0), 0.04), "Negative authoring weights are rejected")
	expect(socket.global_transform.is_equal_approx(last_valid), "Invalid authoring input preserves the last valid pose")
	source.points = PackedVector3Array([Vector3.ZERO, Vector3.ONE, Vector3.ONE * 2.0])
	expect(not socket.update_from_surface(), "Collinear triangle has no attachment frame")
	expect(socket.global_transform.is_equal_approx(last_valid), "Collinear triangle preserves the complete last valid transform")
	source.points = PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])
	expect(not socket.update_from_surface(), "Collapsed triangle is rejected without normalizing a zero edge")
	source.points[0] = Vector3(INF, 0.0, 0.0)
	expect(not socket.update_from_surface() and socket.global_transform.is_equal_approx(last_valid), "Nonfinite CPU input cannot propagate into the socket transform")
	source.points.resize(1)
	expect(not socket.update_from_surface(), "Out-of-range triangle indices fail safely")
	source.queue_free()
	await process_frame
	expect(not socket.update_from_surface(), "Freed CPU source fails safely")
	socket.queue_free()
	# The real demo actor initializes CPU cloth before creating the optional socket.
	var actor: Node3D = make_actor(0)
	var second: Node3D = make_actor(1)
	var third: Node3D = make_actor(2)
	expect(actor.skeleton != null, "Surface attachment test uses the imported character rig")
	expect(actor.cloth.points.size() == 99 and actor.cloth_socket.has_valid_pose, "CPU proxy exists before the cloth socket initializes")
	expect(actor.cloth.process_physics_priority == 0 and actor.cloth_socket.process_physics_priority == 1 and actor.bag.process_physics_priority == 2, "Physics order is CPU cloth, surface socket, then accessory")
	expect(actor.bag.anchor == actor.shoulder_socket and not actor.cloth_socket.is_physics_processing(), "Default shoulder rule keeps the unused cloth socket inactive")
	actor.accessory_rule = 2
	actor.refresh_coverage()
	expect(actor.bag.anchor == actor.cloth_socket, "Cloth rule changes accessory anchor to the CPU triangle socket")
	expect(actor.cloth_socket.is_physics_processing(), "Cloth rule enables the CPU socket update")
	expect(actor.cloth_socket.global_transform.is_equal_approx(expected_socket_pose(actor.cloth, actor.cloth_socket)), "Real cloth socket matches the authored CPU triangle pose")
	expect(actor.bag.get_piece_global_transform().is_equal_approx(actor.cloth_socket.global_transform), "Attached accessory immediately follows the selected CPU surface frame")
	var starting_socket: Transform3D = actor.cloth_socket.global_transform
	for _frame: int in range(15):
		await physics_frame
	expect(not actor.cloth_socket.global_transform.is_equal_approx(starting_socket), "Simulated cloth motion moves the real surface socket")
	expect(actor.cloth_socket.global_transform.is_equal_approx(expected_socket_pose(actor.cloth, actor.cloth_socket)), "Socket samples the current authoritative CPU triangle after simulation")
	expect(actor.bag.get_piece_global_transform().is_equal_approx(actor.cloth_socket.global_transform), "Accessory follows moving CPU cloth in the same physics step")
	actor.set_equipped("shoulder", false)
	expect(actor.bag.get_visual_root().is_visible_in_tree() and actor.bag.is_physics_processing(), "Cloth-bound accessory remains visible and active when shoulder armor is removed")
	actor.set_equipped("cloth", false)
	expect(not actor.bag.get_visual_root().is_visible_in_tree() and not actor.bag.is_physics_processing(), "Removing cloth hides its accessory and stops its attachment update")
	expect(not actor.cloth_socket.is_physics_processing(), "Removing source cloth stops the socket update")
	expect(actor.bag.equipped and actor.bag.get_active_connection_count() == 1, "Source visibility does not modify accessory item ownership or damage")
	actor.set_equipped("cloth", true)
	expect(actor.bag.get_visual_root().is_visible_in_tree() and actor.bag.anchor == actor.cloth_socket, "Re-equipping cloth restores its accessory without depending on shoulder equipment")
	actor.set_selected("bag")
	expect(actor.hit_selected(), "Cloth-bound accessory accepts its own connection strike")
	expect(actor.bag.state == Piece.State.DETACHED, "Accessory own strike hands off to the prepared rigid body")
	var detached_transform: Transform3D = actor.bag.get_piece_global_transform()
	actor.cloth.points[33] += Vector3(0.0, 0.1, 0.1)
	actor.cloth_socket.update_from_surface()
	actor.bag._physics_process(1.0 / 60.0)
	expect(actor.bag.get_piece_global_transform().is_equal_approx(detached_transform), "Detached accessory no longer follows subsequent triangle movement")
	var detached_snapshot: Dictionary = actor.snapshot()
	actor.accessory_rule = 0
	actor.refresh_coverage()
	expect(actor.bag.get_active_connection_count() == 0, "Changing attachment rule does not repair detached accessory")
	actor.restore(detached_snapshot)
	expect(actor.accessory_rule == 2 and actor.bag.anchor == actor.cloth_socket and actor.bag.state == Piece.State.DETACHED, "Undo restores cloth rule while preserving accessory damage")
	actor.set_equipped("cloth", false)
	expect(actor.bag.rigid_body.freeze and actor.bag.rigid_body.collision_mask == 0, "Hidden detached cloth accessory freezes and leaves collision")
	actor.set_equipped("cloth", true)
	expect(not actor.bag.rigid_body.freeze and actor.bag.get_active_connection_count() == 0, "Source re-equip resumes the detached body without repairing it")
	actor.reset_damage()
	expect(actor.accessory_rule == 2 and actor.bag.get_active_connection_count() == 1, "Explicit repair restores accessory connection and retains selected attachment rule")
	expect(actor.bag.get_piece_global_transform().is_equal_approx(actor.cloth_socket.global_transform), "Reset reattaches accessory to freshly reset CPU cloth")
	var intact_snapshot: Dictionary = actor.snapshot()
	actor.bag.apply_hit()
	actor.accessory_rule = 1
	actor.restore(intact_snapshot)
	expect(actor.bag.state == Piece.State.ATTACHED and actor.bag.anchor == actor.cloth_socket, "Undo can restore an intact cloth connection after independent accessory damage")
	var triangle: Vector3i = actor.cloth_socket.triangle_indices
	var old_triangle: PackedVector3Array = PackedVector3Array([actor.cloth.points[triangle.x], actor.cloth.points[triangle.y], actor.cloth.points[triangle.z]])
	var stable_transform: Transform3D = actor.cloth_socket.global_transform
	actor.cloth.points[triangle.y] = actor.cloth.points[triangle.x]
	actor.cloth.points[triangle.z] = actor.cloth.points[triangle.x]
	expect(not actor.cloth_socket.update_from_surface(), "A collapsed real cloth triangle fails safely")
	actor.bag._physics_process(1.0 / 60.0)
	expect(actor.cloth_socket.global_transform.is_equal_approx(stable_transform) and actor.bag.get_piece_global_transform().is_equal_approx(stable_transform), "Degenerate real triangle keeps the last valid accessory pose")
	actor.cloth.points[triangle.x] = old_triangle[0]
	actor.cloth.points[triangle.y] = old_triangle[1]
	actor.cloth.points[triangle.z] = old_triangle[2]
	actor.cloth_socket.update_from_surface()
	second.accessory_rule = 1
	second.refresh_coverage()
	second.shoulder.apply_hit()
	second.shoulder.apply_hit()
	expect(second.bag.state == Piece.State.DETACHED, "Existing release-with-shoulder rule remains functional")
	third.shoulder.apply_hit()
	third.shoulder.apply_hit()
	expect(third.accessory_rule == 0 and third.bag.state == Piece.State.ATTACHED and third.bag.anchor == third.shoulder_socket, "Existing shoulder-follow rule remains functional")
	expect(actor.accessory_rule == 2 and actor.bag.state == Piece.State.ATTACHED and actor.bag.anchor == actor.cloth_socket, "Three characters retain independent attachment rules and damage")
	actor.set_active(false)
	expect(not actor.cloth_socket.is_physics_processing() and not actor.can_process(), "Hidden character disables its CPU surface socket")
	actor.set_active(true)
	expect(actor.cloth_socket.is_physics_processing() and actor.bag.get_active_connection_count() == 1, "Reactivating character resumes attachment without changing item damage")
	for item: Node3D in actors:
		item.queue_free()
	await process_frame
	print("SURFACE_SOCKET_TESTS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
