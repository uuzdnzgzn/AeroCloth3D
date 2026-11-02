extends SceneTree

const Piece = preload("res://addons/aero_cloth_3d/core/aero_cloth_piece_3d.gd")
const Layers = preload("res://addons/aero_cloth_3d/core/aero_cloth_layer_state.gd")

var checks: int = 0
var failures: Array[String] = []
var actors: Array[Node3D] = []
var pieces: Array[AeroClothPiece3D] = []


func _initialize() -> void:
	call_deferred("run")


func expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error(description)


func make_piece(actor_index: int, points: Array[Vector3]) -> AeroClothPiece3D:
	var actor: Node3D = Node3D.new()
	actor.name = "Actor%d" % actor_index
	root.add_child(actor)
	actors.append(actor)
	var animation_anchor: Node3D = Node3D.new()
	animation_anchor.name = "AnimatedSocket"
	actor.add_child(animation_anchor)
	animation_anchor.position = Vector3(float(actor_index) * 2.0, 2.0, 0.0)
	var piece: AeroClothPiece3D = Piece.new()
	actor.add_child(piece)
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	piece.configure(animation_anchor, mesh, points)
	pieces.append(piece)
	return piece


func run() -> void:
	var points: Array[Vector3] = [Vector3(-0.12, 0.03, 0.0), Vector3(0.12, 0.03, 0.0)]
	var piece: AeroClothPiece3D = make_piece(0, points)
	expect(piece.state == Piece.State.ATTACHED, "Prepared armor starts attached")
	expect(piece.get_active_connection_count() == 2, "Prepared armor has two intact links")
	expect(piece.is_fully_covering(), "Intact equipped armor safely covers authored patch")
	expect(piece.rigid_body.freeze, "Detached body is prepared and frozen")
	var body_id: int = piece.rigid_body.get_instance_id()
	var visual_id: int = piece.get_visual_root().get_instance_id()
	var saved: Dictionary = piece.snapshot()
	piece.set_connection_point(1, Vector3(0.20, 0.09, 0.02))
	expect(piece.connection_points[1] == Vector3(0.20, 0.09, 0.02), "Connection placement updates authored local point")
	expect(saved["connection_points"][1] == points[1], "Connection history does not alias editable authored points")
	piece.restore(saved)
	expect(piece.connection_points[1] == points[1], "Undo restores authored connection placement")
	var before: Transform3D = piece.get_piece_global_transform()
	expect(piece.apply_hit(0, Vector3(0.8, 0.0, 0.4)), "First valid strike breaks a link")
	expect(piece.state == Piece.State.HANGING, "First break leaves hanging state")
	expect(piece.get_active_connection_count() == 1, "One link remains")
	expect(not piece.is_fully_covering(), "First break immediately restores lower patch")
	expect(before.is_equal_approx(piece.get_piece_global_transform()), "First break preserves visual transform without a jump")
	expect(not piece.apply_hit(0), "Broken link cannot be damaged twice")
	expect(not piece.apply_hit(9), "Invalid selected link is rejected")
	expect(not bool(saved["broken"][0]), "History snapshot does not alias live broken state")
	var hanging: Dictionary = piece.snapshot()
	piece.anchor.position += Vector3(0.03, 0.02, 0.01)
	piece.anchor.rotation.y = 0.2
	piece._physics_process(1.0 / 60.0)
	var surviving: Vector3 = points[1]
	var actual_pivot: Vector3 = piece.get_piece_global_transform() * surviving
	var desired_pivot: Vector3 = piece.anchor.global_transform * surviving
	expect(actual_pivot.distance_to(desired_pivot) < 0.00001, "Surviving pivot stays on animated socket during swing")
	expect(not piece.get_piece_global_transform().basis.is_equal_approx(piece.anchor.global_basis), "Hanging piece develops secondary motion")
	for _step: int in range(240):
		piece._physics_process(1.0 / 60.0)
	var settled_basis: Basis = piece.anchor.global_basis.inverse() * piece.get_piece_global_transform().basis
	expect(absf(settled_basis.get_euler().z) > 0.5, "Hanging equilibrium remains open after the strike settles")
	expect((piece.get_piece_global_transform() * surviving).distance_to(piece.anchor.global_transform * surviving) < 0.00001, "Authored hanging tilt preserves surviving connection pivot")
	piece.set_equipped(false)
	expect(not piece.get_visual_root().visible, "Unequip suppresses drawing")
	expect(piece.get_active_connection_count() == 1, "Unequip preserves item damage")
	piece.set_equipped(true)
	expect(piece.state == Piece.State.HANGING, "Re-equip retains hanging state")
	expect(not piece.is_fully_covering(), "Re-equip does not incorrectly restore coverage")
	var release: Transform3D = piece.get_piece_global_transform()
	expect(piece.apply_hit(1, Vector3.ZERO), "Second valid strike releases armor")
	expect(piece.state == Piece.State.DETACHED, "Final break switches to detached state")
	expect(piece.get_active_connection_count() == 0, "Detached armor has no active links")
	expect(release.is_equal_approx(piece.get_piece_global_transform()), "Rigid-body handoff preserves transform")
	expect(not piece.rigid_body.freeze, "Released body runs physics")
	expect(piece.rigid_body.collision_mask == 1, "Released piece collides with floor layer")
	expect(piece.get_visual_root().get_parent() == piece.rigid_body, "Visual is attached to prebuilt rigid body")
	expect(piece.rigid_body.get_instance_id() == body_id, "Break reuses prebuilt rigid body")
	expect(piece.get_visual_root().get_instance_id() == visual_id, "Break reuses prepared visual geometry")
	expect(not piece.apply_hit(), "Already detached item ignores additional hits")
	# Remove inherited anchor velocity so gravity's downward displacement is unambiguous.
	piece.rigid_body.linear_velocity = Vector3.ZERO
	var release_y: float = piece.get_piece_global_transform().origin.y
	for _frame: int in range(12):
		await physics_frame
	expect(piece.get_piece_global_transform().origin.y < release_y - 0.05, "Detached rigid body actually falls under gravity")
	var body_position: Vector3 = piece.rigid_body.global_position
	piece.anchor.position += Vector3(1.0, 0.0, 0.0)
	piece._physics_process(1.0 / 60.0)
	expect(piece.rigid_body.global_position.is_equal_approx(body_position), "Detached armor stops following animation anchor")
	piece.set_equipped(false)
	expect(piece.rigid_body.freeze and piece.rigid_body.collision_layer == 0, "Unequipped detached body is paused and removed from collision")
	piece.set_equipped(true)
	expect(piece.state == Piece.State.DETACHED and not piece.rigid_body.freeze, "Re-equipping a detached item does not repair it")
	piece.restore(hanging)
	expect(piece.state == Piece.State.HANGING and piece.get_active_connection_count() == 1, "Undo restores one-link state")
	expect(piece.get_visual_root().get_parent() == piece, "Undo returns visual from body to animated piece")
	expect(piece.rigid_body.freeze, "Undo disables detached simulation")
	piece.restore(saved)
	expect(piece.state == Piece.State.ATTACHED and piece.is_fully_covering(), "Undo restores intact damage and coverage together")
	piece.set_equipped(false)
	piece.reset_damage()
	expect(not piece.equipped and not piece.get_visual_root().visible, "Repair does not silently equip an unequipped item")
	piece.set_equipped(true)
	expect(piece.get_active_connection_count() == 2, "Explicit repair restores both links")
	expect(piece.get_piece_global_transform().is_equal_approx(piece.anchor.global_transform), "Reset uses current animated anchor pose")
	var layers: AeroClothLayerState = Layers.new()
	var patch: Node3D = Node3D.new()
	root.add_child(patch)
	layers.set_region(&"shoulder", patch)
	var region_ids: Array[StringName] = [&"shoulder"]
	layers.set_cover(&"armor", region_ids, true)
	expect(not patch.visible and layers.get_hidden_region_count() == 1, "Safe cover hides only registered lower region")
	layers.set_cover(&"second_cover", region_ids, true)
	layers.set_cover(&"armor", region_ids, false)
	expect(not patch.visible, "A second intact covering layer continues to hide the region")
	layers.remove_cover(&"second_cover")
	expect(patch.visible, "Removing the last safe cover restores lower layer")
	layers.set_cover(&"armor", region_ids, true)
	layers.set_cover(&"armor", region_ids, false)
	expect(patch.visible, "Coverage recomputation clears stale damage masks")
	layers.set_region_enabled(&"shoulder", false)
	expect(not patch.visible, "Removing the lower garment overrides uncovered visibility")
	layers.set_region_enabled(&"shoulder", true)
	expect(patch.visible, "Re-equipping lower garment rebuilds correct visibility")
	var one_point: Array[Vector3] = [Vector3(0.0, 0.08, 0.0)]
	var accessory: AeroClothPiece3D = make_piece(1, one_point)
	expect(accessory.state == Piece.State.ATTACHED and accessory.get_active_connection_count() == 1, "Single-connection accessory starts stable")
	expect(accessory.apply_hit(0), "Own strike releases single-connection accessory")
	expect(accessory.state == Piece.State.DETACHED, "Accessory releases on its own final connection")
	accessory.reset_damage()
	expect(accessory.state == Piece.State.ATTACHED and accessory.get_active_connection_count() == 1, "Accessory reset restores its authored connection count")
	var third: AeroClothPiece3D = make_piece(2, points)
	piece.apply_hit()
	third.apply_hit()
	third.apply_hit()
	expect(piece.state == Piece.State.HANGING, "First character independently retains one link")
	expect(accessory.state == Piece.State.ATTACHED, "Second character's item remains intact")
	expect(third.state == Piece.State.DETACHED, "Third character independently detaches")
	piece.reset_damage()
	expect(third.state == Piece.State.DETACHED, "One actor's reset does not alter another actor's item")
	patch.queue_free()
	for actor: Node3D in actors:
		actor.queue_free()
	await process_frame
	print("DAMAGE_TESTS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
