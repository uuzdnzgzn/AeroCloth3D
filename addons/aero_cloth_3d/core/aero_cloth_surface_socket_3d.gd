class_name AeroClothSurfaceSocket3D
extends Node3D
## One-way attachment frame from an authoritative CPU proxy triangle.
## No rendering readback and no accessory mass / force feedback into the cloth.

var source_surface: Node3D
var triangle_indices: Vector3i = Vector3i(33, 42, 34)
var barycentric_weights: Vector3 = Vector3(0.3, 0.3, 0.4)
var normal_offset: float = 0.04
var has_valid_pose: bool = false


func _init() -> void:
	process_physics_priority = 1


func configure(source: Node3D, triangle: Vector3i = Vector3i(33, 42, 34), weights: Vector3 = Vector3(0.3, 0.3, 0.4), offset: float = 0.04) -> bool:
	if not is_instance_valid(source) or triangle.x < 0 or triangle.y < 0 or triangle.z < 0:
		return false
	if not weights.is_finite() or weights.x < 0.0 or weights.y < 0.0 or weights.z < 0.0:
		return false
	var total: float = weights.x + weights.y + weights.z
	if total <= 0.000001 or not is_finite(offset):
		return false
	source_surface = source
	triangle_indices = triangle
	barycentric_weights = weights / total
	normal_offset = offset
	return update_from_surface()


func _physics_process(_delta: float) -> void:
	update_from_surface()


func update_from_surface() -> bool:
	if not is_instance_valid(source_surface):
		return false
	var raw_points: Variant = source_surface.get("points")
	if not raw_points is PackedVector3Array:
		return false
	var points: PackedVector3Array = raw_points
	if mini(triangle_indices.x, mini(triangle_indices.y, triangle_indices.z)) < 0 or maxi(triangle_indices.x, maxi(triangle_indices.y, triangle_indices.z)) >= points.size():
		return false
	var a: Vector3 = points[triangle_indices.x]
	var b: Vector3 = points[triangle_indices.y]
	var c: Vector3 = points[triangle_indices.z]
	if not a.is_finite() or not b.is_finite() or not c.is_finite():
		return false
	# Authored triangle order is top-left, bottom-left, top-right. X follows its
	# top edge, Y points up along the cloth, and Z is the outward surface normal.
	var edge: Vector3 = c - a
	var cross_product: Vector3 = (b - a).cross(edge)
	if edge.length_squared() <= 0.000000000001 or cross_product.length_squared() <= 0.000000000001:
		# A collapsed triangle cannot define an orientation. Preserve the last
		# complete valid transform instead of snapping position or emitting NaNs.
		return false
	var x_axis: Vector3 = edge.normalized()
	var z_axis: Vector3 = cross_product.normalized()
	var y_axis: Vector3 = z_axis.cross(x_axis).normalized()
	x_axis = y_axis.cross(z_axis).normalized()
	var position_world: Vector3 = a * barycentric_weights.x + b * barycentric_weights.y + c * barycentric_weights.z + z_axis * normal_offset
	global_transform = Transform3D(Basis(x_axis, y_axis, z_axis), position_world)
	has_valid_pose = true
	return true
