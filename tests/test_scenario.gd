extends SceneTree
## Integration checks instantiate the shipped GLB character and the actual demo actor.
## These are behavioral checks, not rendering or target-hardware performance claims.

const Actor = preload("res://demo/scenario_character.gd")
const Piece = preload("res://addons/aero_cloth_3d/core/aero_cloth_piece_3d.gd")

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


func sample_animation(actor: Node3D, animation_name: String, time: float) -> void:
	var player: AnimationPlayer = actor.animation
	player.play(animation_name)
	player.seek(time, true)
	player.pause()
	var skeleton: Skeleton3D = actor.skeleton
	skeleton.force_update_all_bone_transforms()
	await process_frame
	actor.shoulder._physics_process(1.0 / 60.0)
	actor.bag._physics_process(1.0 / 60.0)


func run() -> void:
	var floor_body: StaticBody3D = StaticBody3D.new()
	var floor_collision: CollisionShape3D = CollisionShape3D.new()
	var floor_shape: BoxShape3D = BoxShape3D.new()
	floor_shape.size = Vector3(30.0, 0.2, 30.0)
	floor_collision.shape = floor_shape
	floor_body.add_child(floor_collision)
	floor_body.position.y = -0.1
	root.add_child(floor_body)
	var actor: Node3D = make_actor(0)
	expect(ResourceLoader.exists(Actor.MODEL_PATH), "Shipped GLB exists as an imported Godot resource")
	expect(actor.skeleton != null, "Scenario instantiates the real GLB Skeleton3D")
	expect(actor.animation != null, "Scenario instantiates the real GLB AnimationPlayer")
	if actor.skeleton != null and actor.animation != null:
		var skeleton: Skeleton3D = actor.skeleton
		var player: AnimationPlayer = actor.animation
		expect(skeleton.get_bone_count() >= 20, "Test character supplies its rig instead of a static placeholder")
		expect(player.has_animation("Idle") and player.has_animation("Walk"), "Imported character supplies Idle and Walk")
		var chest_index: int = skeleton.find_bone("Chest")
		var shoulder_index: int = skeleton.find_bone("UpperArm_R")
		expect(chest_index >= 0 and shoulder_index >= 0, "Required wearable anchor bones are present")
		expect(actor.shoulder_anchor.get_parent() is BoneAttachment3D, "Shoulder anchor is attached to skeleton")
		await sample_animation(actor, "Idle", 0.0)
		var idle_start: Transform3D = skeleton.get_bone_global_pose(chest_index)
		await sample_animation(actor, "Idle", 0.55)
		var idle_later: Transform3D = skeleton.get_bone_global_pose(chest_index)
		expect(not idle_start.is_equal_approx(idle_later), "Idle animates the character's chest bone matrix")
		await sample_animation(actor, "Walk", 0.0)
		var walk_start: Transform3D = skeleton.get_bone_global_pose(shoulder_index)
		var anchor_start: Transform3D = actor.shoulder_anchor.global_transform
		await sample_animation(actor, "Walk", 0.35)
		var walk_later: Transform3D = skeleton.get_bone_global_pose(shoulder_index)
		expect(not walk_start.is_equal_approx(walk_later), "Walk animates the shoulder bone matrix")
		expect(not anchor_start.is_equal_approx(actor.shoulder_anchor.global_transform), "Wearable shoulder anchor moves with Walk")
		var authored_pose: Transform3D = Transform3D(Basis.IDENTITY, Vector3(-0.285, 1.43, 0.025))
		var expected_anchor: Transform3D = skeleton.global_transform * walk_later * skeleton.get_bone_global_rest(shoulder_index).affine_inverse() * authored_pose
		expect(expected_anchor.is_equal_approx(actor.shoulder_anchor.global_transform), "Animated shoulder anchor preserves the authored rest-space offset")
		expect(actor.shoulder.get_piece_global_transform().is_equal_approx(actor.shoulder_anchor.global_transform), "Intact armor follows the animated bone anchor")
		player.pause()
	expect(not actor.under_shoulder.visible, "Intact shoulder armor hides its safe lower patch")
	expect(not actor.under_front.visible and actor.under_back.visible, "Breastplate covers only its authored front region")
	actor.set_equipped("chest", false)
	expect(actor.under_front.visible and actor.under_back.visible, "Removing breastplate restores front while preserving back")
	actor.set_equipped("chest", true)
	actor.set_selected("shoulder")
	expect(actor.hit_selected(), "First shoulder test strike is accepted")
	expect(actor.shoulder.state == Piece.State.HANGING, "First shoulder strike leaves one surviving connection")
	expect(actor.under_shoulder.visible, "First shoulder strike reveals the real lower patch")
	expect(actor.bag.state == Piece.State.ATTACHED, "Follow rule keeps the accessory connected after first break")
	for _step: int in range(180):
		actor.shoulder._physics_process(1.0 / 60.0)
		actor.bag._physics_process(1.0 / 60.0)
	expect(actor.bag.get_piece_global_transform().is_equal_approx(actor.bag.anchor.global_transform), "Accessory follows the hanging armor socket")
	var remaining: Vector3 = actor.shoulder.connection_points[1]
	var armor_pivot: Vector3 = actor.shoulder.get_piece_global_transform() * remaining
	var animated_pivot: Vector3 = actor.shoulder_anchor.global_transform * remaining
	expect(armor_pivot.distance_to(animated_pivot) < 0.00001, "Hanging armor keeps its surviving connection at the animated anchor")
	expect(actor.hit_selected(), "Second shoulder test strike is accepted")
	expect(actor.shoulder.state == Piece.State.DETACHED, "Second strike detaches the real shoulder armor")
	expect(actor.under_shoulder.visible, "Detached armor leaves the lower layer visible")
	expect(actor.bag.state == Piece.State.ATTACHED, "Follow rule carries accessory on detached armor")
	await physics_frame
	actor.bag._physics_process(1.0 / 60.0)
	expect(actor.bag.get_piece_global_transform().is_equal_approx(actor.bag.anchor.global_transform), "Accessory follows the detached armor socket")
	actor.set_equipped("shoulder", false)
	expect(actor.shoulder.get_active_connection_count() == 0, "Unequipping armor preserves its final broken state")
	expect(not actor.bag.get_visual_root().is_visible_in_tree(), "Accessory hides while its parent armor is unequipped")
	actor.set_equipped("shoulder", true)
	expect(actor.shoulder.state == Piece.State.DETACHED, "Re-equipping damaged armor does not repair it")
	actor.set_selected("bag")
	expect(actor.hit_selected(), "Accessory accepts an independent own-connection strike")
	expect(actor.bag.state == Piece.State.DETACHED, "Accessory own strike detaches its own connection")
	expect(actor.shoulder.state == Piece.State.DETACHED, "Accessory strike preserves parent damage state")
	actor.reset_damage()
	expect(actor.shoulder.get_active_connection_count() == 2 and actor.bag.get_active_connection_count() == 1, "Reset repairs authored armor and accessory connections")
	expect(not actor.under_shoulder.visible, "Reset restores initial conservative coverage")
	actor.accessory_rule = 1
	actor.shoulder.apply_hit()
	actor.shoulder.apply_hit()
	expect(actor.bag.state == Piece.State.DETACHED, "Release rule detaches accessory on parent final break")
	actor.reset_damage()
	actor.accessory_rule = 0
	var saved: Dictionary = actor.snapshot()
	var original_point: Vector3 = actor.shoulder.connection_points[0]
	var original_weight: float = actor.cloth.weights[10]
	actor.shoulder.set_connection_point(0, original_point + Vector3(0.03, 0.02, 0.01))
	actor.cloth.weights[10] = 0.27
	actor.cloth.hit()
	actor.cloth.hit()
	actor.shoulder.apply_hit()
	actor.set_equipped("chest", false)
	actor.restore(saved)
	expect(actor.shoulder.connection_points[0] == original_point, "Actor Undo restores connection placement")
	expect(is_equal_approx(actor.cloth.weights[10], original_weight), "Actor Undo restores cloth painting weights")
	expect(not actor.cloth.broken[0] and not actor.cloth.broken[1], "Actor Undo restores cloth connection damage")
	expect(actor.shoulder.get_active_connection_count() == 2, "Actor Undo restores armor damage")
	expect(actor.chest_equipped and not actor.under_front.visible, "Actor Undo restores equipment and derived coverage")
	actor.set_selected("cloth")
	actor.hit_selected()
	actor.hit_selected()
	expect(actor.cloth.broken[0] and actor.cloth.broken[1], "Prepared cloth accepts two authored connection strikes")
	actor.reset_damage()
	expect(not actor.cloth.broken[0] and not actor.cloth.broken[1], "Reset restores cloth authored pins")
	var point_index: int = 20
	var cloth_rest_world: Vector3 = actor.cloth.global_transform * actor.cloth.rest[point_index]
	expect(actor.cloth.points[point_index].distance_to(cloth_rest_world) < 0.00001, "Reset rebuilds cloth at the current animated anchor")
	var second: Node3D = make_actor(1)
	var third: Node3D = make_actor(2)
	expect(second.skeleton != null and third.skeleton != null, "All three scenario actors instantiate skinned character models")
	if second.skeleton != null and third.skeleton != null and actor.skeleton != null:
		expect(second.skeleton.get_instance_id() != third.skeleton.get_instance_id() and actor.skeleton.get_instance_id() != second.skeleton.get_instance_id(), "Three actors own independent skeleton instances")
	actor.shoulder.apply_hit()
	third.shoulder.apply_hit()
	third.shoulder.apply_hit()
	expect(actor.shoulder.state == Piece.State.HANGING, "First actor retains its independent one-link state")
	expect(second.shoulder.state == Piece.State.ATTACHED and not second.under_shoulder.visible, "Second actor remains intact with hidden lower patch")
	expect(third.shoulder.state == Piece.State.DETACHED and third.under_shoulder.visible, "Third actor independently detaches and reveals its lower patch")
	actor.reset_damage()
	expect(third.shoulder.state == Piece.State.DETACHED, "Resetting one character does not repair a second character")
	for item: Node3D in actors:
		item.reset_damage()
		expect(item.shoulder.state == Piece.State.ATTACHED and not item.under_shoulder.visible, "Each actor resets its own initial equipment visibility")
		item.queue_free()
	floor_body.queue_free()
	await process_frame
	print("SCENARIO_TESTS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
