@tool
class_name AeroClothPiece3D
extends Node3D
## Prepared wearable: animation -> one-point swing (two links) -> pooled rigid body.
## Swing is deliberately one-way: it exerts no reaction force on the animated actor.

signal state_changed(piece: AeroClothPiece3D)
signal coverage_changed(piece: AeroClothPiece3D, fully_covering: bool)

enum State { ATTACHED, HANGING, DETACHED }

@export var swing_stiffness: float = 18.0
@export var swing_damping: float = 3.7
@export var maximum_swing_degrees: float = 75.0
@export var hanging_rest_tilt_degrees: Vector2 = Vector2(14.0, 48.0)
@export var collision_size: Vector3 = Vector3(0.36, 0.18, 0.32)

var state: State = State.ATTACHED
var equipped: bool = true
var anchor: Node3D
var broken_connections: Array[bool] = []
var connection_points: Array[Vector3] = []
var rigid_body: RigidBody3D
var _visual_root: Node3D
var _swing: Vector2 = Vector2.ZERO
var _swing_velocity: Vector2 = Vector2.ZERO
var _anchor_velocity: Vector3 = Vector3.ZERO
var _anchor_angular_velocity: Vector3 = Vector3.ZERO
var _previous_anchor_position: Vector3 = Vector3.ZERO
var _previous_anchor_basis: Basis = Basis.IDENTITY
var _anchor_sample_valid: bool = false
var _stored_linear_velocity: Vector3 = Vector3.ZERO
var _stored_angular_velocity: Vector3 = Vector3.ZERO
var _update_usec: int = 0


func configure(target_anchor: Node3D, visual: Node3D, points: Array, piece_mass: float = 0.8) -> void:
	assert(_visual_root == null, "Configure a prepared piece only once")
	assert(is_instance_valid(target_anchor), "A piece requires an animation anchor")
	assert(points.size() >= 1 and points.size() <= 2, "Prepared pieces support one or two connections")
	anchor = target_anchor
	connection_points.assign(points)
	for _point: Vector3 in points:
		broken_connections.append(false)
	_visual_root = Node3D.new()
	_visual_root.name = "VisualRoot"
	add_child(_visual_root)
	if visual.get_parent() != null:
		visual.reparent(_visual_root, false)
	else:
		_visual_root.add_child(visual)
	rigid_body = RigidBody3D.new()
	rigid_body.name = "PreparedDetachedBody"
	rigid_body.mass = maxf(0.01, piece_mass)
	rigid_body.freeze = true
	rigid_body.top_level = true
	rigid_body.collision_layer = 0
	rigid_body.collision_mask = 0
	rigid_body.continuous_cd = true
	add_child(rigid_body)
	var shape_node: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = collision_size.max(Vector3.ONE * 0.01)
	shape_node.shape = box
	rigid_body.add_child(shape_node)
	_previous_anchor_position = anchor.global_position
	_previous_anchor_basis = anchor.global_basis.orthonormalized()
	_anchor_sample_valid = false
	_update_attached_pose()


func _physics_process(delta: float) -> void:
	var started_usec: int = Time.get_ticks_usec()
	if not is_instance_valid(anchor) or _visual_root == null:
		_update_usec = Time.get_ticks_usec() - started_usec
		return
	# Capture animation motion in world space. A rotating attachment also moves
	# the hanging piece's origin, even when the anchor itself does not translate.
	if _anchor_sample_valid and delta > 0.0:
		_anchor_velocity = ((anchor.global_position - _previous_anchor_position) / delta).limit_length(20.0)
		var rotation_delta := (anchor.global_basis.orthonormalized() * _previous_anchor_basis.inverse()).get_rotation_quaternion()
		# q and -q represent the same rotation; use the shortest sampled arc.
		if rotation_delta.w < 0.0: rotation_delta = -rotation_delta
		var rotation_vector := Vector3(rotation_delta.x, rotation_delta.y, rotation_delta.z)
		var angle: float = 2.0 * atan2(rotation_vector.length(), rotation_delta.w)
		_anchor_angular_velocity = (rotation_vector.normalized() * angle / delta).limit_length(40.0)
	else:
		_anchor_velocity = Vector3.ZERO
		_anchor_angular_velocity = Vector3.ZERO
	_previous_anchor_position = anchor.global_position
	_previous_anchor_basis = anchor.global_basis.orthonormalized()
	_anchor_sample_valid = true
	if not equipped or state == State.DETACHED:
		_update_usec = Time.get_ticks_usec() - started_usec
		return
	if state == State.HANGING:
		var step: float = minf(delta, 1.0 / 30.0)
		# Authored hanging equilibrium keeps broken armor open after impact settles.
		# It approximates gravity; it is not a general inertia / joint solver.
		var pivot_side: float = signf(connection_points[_remaining_connection()].x)
		if is_zero_approx(pivot_side):
			pivot_side = 1.0
		var equilibrium: Vector2 = Vector2(deg_to_rad(hanging_rest_tilt_degrees.x), deg_to_rad(hanging_rest_tilt_degrees.y) * pivot_side)
		_swing_velocity += ((equilibrium - _swing) * swing_stiffness - _swing_velocity * swing_damping) * step
		_swing += _swing_velocity * step
		var bound: float = deg_to_rad(maximum_swing_degrees)
		var stopped_x: bool = absf(_swing.x) >= bound
		var stopped_y: bool = absf(_swing.y) >= bound
		_swing.x = clampf(_swing.x, -bound, bound)
		_swing.y = clampf(_swing.y, -bound, bound)
		# A hard swing stop removes outward motion. Keeping the hidden rate here
		# would launch an apparently stationary piece when its last link breaks.
		if stopped_x and _swing.x * _swing_velocity.x > 0.0: _swing_velocity.x = 0.0
		if stopped_y and _swing.y * _swing_velocity.y > 0.0: _swing_velocity.y = 0.0
	_update_attached_pose()
	_update_usec = Time.get_ticks_usec() - started_usec


func _update_attached_pose() -> void:
	if _visual_root == null or not is_instance_valid(anchor) or state == State.DETACHED:
		return
	var pose: Transform3D = anchor.global_transform
	if state == State.HANGING:
		var pivot: Vector3 = connection_points[_remaining_connection()]
		pose.basis = anchor.global_basis * Basis.from_euler(Vector3(_swing.x, 0.0, _swing.y))
		pose.origin = anchor.global_transform * pivot - pose.basis * pivot
	_visual_root.global_transform = pose


func apply_hit(connection_index: int = -1, impulse: Vector3 = Vector3(1.0, 0.0, 1.0)) -> bool:
	if not equipped or state == State.DETACHED or _visual_root == null:
		return false
	var index: int = connection_index
	if index < 0:
		index = _remaining_connection()
	if index < 0 or index >= broken_connections.size() or broken_connections[index]:
		return false
	broken_connections[index] = true
	if get_active_connection_count() > 0:
		state = State.HANGING
		_swing_velocity += Vector2(-impulse.z, impulse.x) * 1.5
		_update_attached_pose()
	else:
		var release_transform: Transform3D = _visual_root.global_transform
		var release_motion: Dictionary = _attachment_motion(release_transform, connection_points[index])
		state = State.DETACHED
		_move_visual_to_body(release_transform)
		rigid_body.collision_layer = 2
		rigid_body.collision_mask = 1
		rigid_body.freeze = false
		rigid_body.sleeping = false
		# A central impulse is delta-v = impulse / mass. Assign it with the
		# inherited velocity so manual preview and same-tick saves see the full
		# release immediately, before the physics server's next integration.
		rigid_body.linear_velocity = release_motion["linear"] + impulse / rigid_body.mass
		rigid_body.angular_velocity = release_motion["angular"]
	_emit_state()
	return true


func _attachment_motion(pose: Transform3D, former_pivot: Vector3) -> Dictionary:
	var linear: Vector3 = _anchor_velocity
	var angular: Vector3 = _anchor_angular_velocity
	# The last link has just been marked broken; state still describes the
	# hanging pose being released, with that link as its former pivot.
	if state == State.HANGING:
		# Godot's default YXZ order becomes Rx * Rz here. Convert Euler rates
		# into an angular velocity before transforming through the animated rig.
		var local_angular := Vector3(_swing_velocity.x, -sin(_swing.x) * _swing_velocity.y, cos(_swing.x) * _swing_velocity.y)
		var world_angular: Vector3 = anchor.global_basis.orthonormalized() * local_angular
		var pivot_world: Vector3 = anchor.global_transform * former_pivot
		linear += _anchor_angular_velocity.cross(pose.origin - anchor.global_position)
		linear += world_angular.cross(pose.origin - pivot_world)
		angular += world_angular
	return {"linear":linear,"angular":angular}


func _move_visual_to_body(pose: Transform3D) -> void:
	rigid_body.global_transform = pose
	if _visual_root.get_parent() != rigid_body:
		_visual_root.reparent(rigid_body, false)
	_visual_root.transform = Transform3D.IDENTITY


func _move_visual_to_piece() -> void:
	if _visual_root.get_parent() != self:
		_visual_root.reparent(self, true)
	rigid_body.freeze = true
	rigid_body.linear_velocity = Vector3.ZERO
	rigid_body.angular_velocity = Vector3.ZERO
	rigid_body.collision_layer = 0
	rigid_body.collision_mask = 0


func reset_damage() -> void:
	if _visual_root == null:
		return
	_move_visual_to_piece()
	broken_connections.fill(false)
	state = State.ATTACHED
	_swing = Vector2.ZERO
	_swing_velocity = Vector2.ZERO
	_stored_linear_velocity = Vector3.ZERO
	_stored_angular_velocity = Vector3.ZERO
	_anchor_velocity = Vector3.ZERO
	_anchor_angular_velocity = Vector3.ZERO
	_anchor_sample_valid = false
	_update_attached_pose()
	_visual_root.visible = equipped
	_emit_state()


func set_equipped(value: bool) -> void:
	if equipped == value:
		return
	equipped = value
	if _visual_root != null:
		_visual_root.visible = value
	if state == State.DETACHED:
		if not value:
			_stored_linear_velocity = rigid_body.linear_velocity
			_stored_angular_velocity = rigid_body.angular_velocity
			rigid_body.freeze = true
			rigid_body.collision_layer = 0
			rigid_body.collision_mask = 0
		else:
			rigid_body.freeze = false
			rigid_body.collision_layer = 2
			rigid_body.collision_mask = 1
			rigid_body.linear_velocity = _stored_linear_velocity
			rigid_body.angular_velocity = _stored_angular_velocity
	else:
		_update_attached_pose()
	_anchor_sample_valid = false
	_anchor_velocity = Vector3.ZERO
	_anchor_angular_velocity = Vector3.ZERO
	_emit_state()


func snapshot() -> Dictionary:
	return {
		"broken": broken_connections.duplicate(), "equipped": equipped,
		"connection_points": connection_points.duplicate(),
		"swing": _swing, "swing_velocity": _swing_velocity,
		"anchor_velocity": _anchor_velocity,
		"anchor_angular_velocity": _anchor_angular_velocity,
		"transform": get_piece_global_transform(),
		"linear_velocity": rigid_body.linear_velocity if rigid_body != null else Vector3.ZERO,
		"angular_velocity": rigid_body.angular_velocity if rigid_body != null else Vector3.ZERO,
		"stored_linear_velocity": _stored_linear_velocity,
		"stored_angular_velocity": _stored_angular_velocity,
	}


func restore(data: Dictionary) -> void:
	if _visual_root == null or not data.has("broken") or data["broken"].size() != connection_points.size():
		return
	if data.has("connection_points") and data["connection_points"].size() == connection_points.size():
		connection_points.assign(data["connection_points"])
	broken_connections.assign(data["broken"])
	equipped = bool(data.get("equipped", true))
	_swing = data.get("swing", Vector2.ZERO)
	_swing_velocity = data.get("swing_velocity", Vector2.ZERO)
	_stored_linear_velocity = data.get("stored_linear_velocity", Vector3.ZERO)
	_stored_angular_velocity = data.get("stored_angular_velocity", Vector3.ZERO)
	var active: int = get_active_connection_count()
	state = State.ATTACHED if active == connection_points.size() else (State.HANGING if active > 0 else State.DETACHED)
	if state == State.DETACHED:
		_move_visual_to_body(data.get("transform", anchor.global_transform))
		rigid_body.freeze = not equipped
		rigid_body.collision_layer = 2 if equipped else 0
		rigid_body.collision_mask = 1 if equipped else 0
		rigid_body.linear_velocity = data.get("linear_velocity", Vector3.ZERO)
		rigid_body.angular_velocity = data.get("angular_velocity", Vector3.ZERO)
	else:
		_move_visual_to_piece()
		_update_attached_pose()
	_visual_root.visible = equipped
	# Keep the saved release rates available for a hit before the next physics
	# step, but start subsequent finite differences at the restored rig pose.
	_anchor_velocity = data.get("anchor_velocity", Vector3.ZERO)
	_anchor_angular_velocity = data.get("anchor_angular_velocity", Vector3.ZERO)
	_previous_anchor_position = anchor.global_position
	_previous_anchor_basis = anchor.global_basis.orthonormalized()
	_anchor_sample_valid = true
	_emit_state()


func _emit_state() -> void:
	state_changed.emit(self)
	coverage_changed.emit(self, is_fully_covering())


func is_fully_covering() -> bool:
	return equipped and state == State.ATTACHED


func _remaining_connection() -> int:
	for i: int in range(broken_connections.size()):
		if not broken_connections[i]:
			return i
	return -1


func get_active_connection_count() -> int:
	var count: int = 0
	for broken: bool in broken_connections:
		if not broken:
			count += 1
	return count


func get_state_label() -> String:
	match state:
		State.ATTACHED: return "%d bağlantı · sabit" % get_active_connection_count()
		State.HANGING: return "1 bağlantı · sarkıyor"
		State.DETACHED: return "0 bağlantı · koptu"
	return ""


func get_visual_root() -> Node3D:
	return _visual_root


func set_connection_point(index: int, point: Vector3) -> void:
	if index >= 0 and index < connection_points.size():
		connection_points[index] = point
		_update_attached_pose()
		state_changed.emit(self)


func get_piece_global_transform() -> Transform3D:
	return _visual_root.global_transform if _visual_root != null else global_transform


func get_update_usec() -> int:
	## Last script update only; excludes PhysicsServer's rigid-body solver and rendering.
	return _update_usec
