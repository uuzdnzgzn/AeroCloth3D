extends SceneTree

const Piece = preload("res://addons/aero_cloth_3d/core/aero_cloth_piece_3d.gd")
var checks := 0
var failures := 0
var actors: Array[Node3D] = []

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(description)

func make_piece(two_links := true) -> AeroClothPiece3D:
	var actor := Node3D.new()
	root.add_child(actor)
	actors.append(actor)
	var anchor := Node3D.new()
	actor.add_child(anchor)
	anchor.position = Vector3(0, 3, 0)
	var piece := Piece.new()
	actor.add_child(piece)
	piece.set_physics_process(false)
	piece.swing_stiffness = 0.0
	piece.swing_damping = 0.0
	var points: Array = [Vector3(-0.2, 0.1, 0.0), Vector3(0.2, 0.1, 0.0)] if two_links else [Vector3.ZERO]
	piece.configure(anchor, Node3D.new(), points)
	return piece

func hanging_pose(anchor_pose: Transform3D, angles: Vector2, pivot: Vector3) -> Transform3D:
	var basis: Basis = anchor_pose.basis * Basis.from_euler(Vector3(angles.x, 0, angles.y))
	return Transform3D(basis, anchor_pose * pivot - basis * pivot)

func run() -> void:
	var piece := make_piece()
	piece.anchor.rotation.y = PI * 0.5
	var initial := piece.get_piece_global_transform()
	piece._physics_process(1.0 / 60.0)
	initial = piece.get_piece_global_transform()
	var visual_id := piece.get_visual_root().get_instance_id()
	expect(piece.apply_hit(0, Vector3.ZERO), "First connection breaks")
	expect(piece.get_piece_global_transform().is_equal_approx(initial), "First break preserves world pose on rotated rig")
	var data := piece.snapshot()
	data["swing"] = Vector2(0.25, 0.35)
	data["swing_velocity"] = Vector2(0.8, -1.1)
	piece.restore(data)
	piece._physics_process(1.0 / 60.0)
	var frame := 1.0 / 60.0
	var anchor_omega := Vector3(0, 1.2, 0)
	var anchor_velocity := Vector3(1.4, -0.2, 0.3)
	piece.anchor.global_basis = Basis(Vector3.UP, anchor_omega.y * frame) * piece.anchor.global_basis
	piece.anchor.global_position += anchor_velocity * frame
	piece._physics_process(frame)
	data = piece.snapshot()
	var angles: Vector2 = data["swing"]
	var rates: Vector2 = data["swing_velocity"]
	var pivot: Vector3 = piece.connection_points[1]
	var anchor_pose := piece.anchor.global_transform
	var epsilon := 0.0001
	var next_anchor := Transform3D(Basis(Vector3.UP, anchor_omega.y * epsilon) * anchor_pose.basis, anchor_pose.origin + anchor_velocity * epsilon)
	var prev_anchor := Transform3D(Basis(Vector3.UP, -anchor_omega.y * epsilon) * anchor_pose.basis, anchor_pose.origin - anchor_velocity * epsilon)
	var next_pose := hanging_pose(next_anchor, angles + rates * epsilon, pivot)
	var prev_pose := hanging_pose(prev_anchor, angles - rates * epsilon, pivot)
	var expected_velocity := (next_pose.origin - prev_pose.origin) / (2.0 * epsilon)
	var turn := (next_pose.basis * prev_pose.basis.inverse()).get_rotation_quaternion()
	var rotation_vector := Vector3(turn.x, turn.y, turn.z)
	var expected_angular := rotation_vector.normalized() * atan2(rotation_vector.length(), turn.w) / epsilon
	var release_pose := piece.get_piece_global_transform()
	var hit_impulse := Vector3(0.4,0.2,-0.3)
	expect(piece.apply_hit(1, hit_impulse), "Last connection releases")
	expect(piece.state == Piece.State.DETACHED, "Last break enters detached state")
	expect(piece.get_piece_global_transform().is_equal_approx(release_pose), "Final handoff preserves world pose")
	expect(piece.get_visual_root().get_instance_id() == visual_id, "Release reuses existing visual")
	expect(piece.rigid_body.linear_velocity.distance_to(expected_velocity + hit_impulse / piece.rigid_body.mass) < 0.005, "Release immediately adds combat impulse to translation, rotating anchor and swing tangent velocity")
	expect(piece.rigid_body.angular_velocity.distance_to(expected_angular) < 0.005, "Release angular velocity matches world-space pose derivative")
	expect(piece.rigid_body.linear_velocity.distance_to(anchor_velocity) > 0.1, "Hanging velocity is not reduced to anchor translation")
	var reloaded := make_piece()
	reloaded.anchor.global_transform = piece.anchor.global_transform
	reloaded.restore(data)
	reloaded.apply_hit(1, hit_impulse)
	expect(reloaded.rigid_body.linear_velocity.is_equal_approx(piece.rigid_body.linear_velocity), "Immediate post-load hanging release preserves world linear motion")
	expect(reloaded.rigid_body.angular_velocity.is_equal_approx(piece.rigid_body.angular_velocity), "Immediate post-load hanging release preserves world angular motion")
	piece.reset_damage()
	expect(piece.rigid_body.linear_velocity.is_zero_approx() and piece.rigid_body.angular_velocity.is_zero_approx(), "Reset clears detached motion")
	piece.apply_hit(0, Vector3.ZERO)
	piece.apply_hit(1, Vector3.ZERO)
	expect(piece.rigid_body.linear_velocity.is_zero_approx() and piece.rigid_body.angular_velocity.is_zero_approx(), "Immediate reset and rebreak do not inherit stale anchor samples")
	var attached := make_piece(false)
	attached._physics_process(frame)
	attached.anchor.rotate_y(0.02)
	attached.anchor.position += Vector3(0.03, 0, 0)
	attached._physics_process(frame)
	attached.apply_hit(0, Vector3.ZERO)
	expect(attached.rigid_body.linear_velocity.distance_to(Vector3(1.8, 0, 0)) < 0.001, "Single-connection release inherits animation translation")
	expect(attached.rigid_body.angular_velocity.distance_to(Vector3(0, 1.2, 0)) < 0.001, "Single-connection release inherits animation rotation")
	attached.reset_damage()
	attached._physics_process(frame)
	attached.anchor.position.x += 0.02
	attached._physics_process(frame)
	var saved := attached.snapshot()
	attached.restore(saved)
	attached.apply_hit(0, Vector3.ZERO)
	expect(attached.rigid_body.linear_velocity.distance_to(Vector3(1.2, 0, 0)) < 0.001, "Immediate post-restore release retains saved animation motion")
	saved.erase("anchor_velocity")
	saved.erase("anchor_angular_velocity")
	attached.restore(saved)
	attached.apply_hit(0, Vector3.ZERO)
	expect(attached.rigid_body.linear_velocity.is_zero_approx() and attached.rigid_body.angular_velocity.is_zero_approx(), "Legacy snapshot defaults to zero anchor motion instead of stale pre-load rates")
	var stopped := make_piece()
	stopped.apply_hit(0, Vector3.ZERO)
	var stop_data := stopped.snapshot()
	stop_data["swing"] = Vector2(deg_to_rad(74.0), 0)
	stop_data["swing_velocity"] = Vector2(10, 0)
	stopped.restore(stop_data)
	stopped._physics_process(frame)
	stopped.apply_hit(1, Vector3.ZERO)
	expect(stopped.rigid_body.linear_velocity.is_zero_approx(), "Hard swing stop cannot create phantom tangential release motion")
	expect(stopped.rigid_body.angular_velocity.is_zero_approx(), "Hard swing stop clears outward angular release motion")
	for actor in actors: actor.queue_free()
	await process_frame
	print("ATTACHMENT_CONTINUITY_TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
