extends SceneTree
## Gameplay hits on an animated character, including a paused mid-damage reload.
## This deliberately uses no editor preview-stage shortcuts.
const Factory = preload("res://addons/aero_cloth_3d/core/aero_example_factory.gd")
const Rig = preload("res://addons/aero_cloth_3d/core/aero_wearable_rig.gd")
const Piece = preload("res://addons/aero_cloth_3d/core/aero_cloth_piece_3d.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func hit(rig: Node3D, item: StringName, region: StringName, amount: float, id: String) -> Dictionary:
	return rig.apply_hit({"item_id":item,"region_id":region,"uv":Vector2(.4,.3) if region != &"lower" else Vector2(.4,.7),"amount":amount,"hit_id":id,"type":"slash","impulse":Vector3(.12,.02,.08),"seed":31})

func advance(rig: Node3D, frames: int) -> void:
	for _frame in range(frames): rig.step(1.0/60.0)

func pose_close(a: Transform3D, b: Transform3D, epsilon := .00001) -> bool:
	return a.origin.distance_to(b.origin) < epsilon and a.basis.x.distance_to(b.basis.x) < epsilon and a.basis.y.distance_to(b.basis.y) < epsilon and a.basis.z.distance_to(b.basis.z) < epsilon

func attachment_pose(rig: Node3D) -> Transform3D:
	var pose: Transform3D = rig.slots[&"shirt"]["surface"].get_surface_sample(Vector3i(33,42,34),Vector3(.3,.3,.4))
	pose.origin += pose.basis.z * .04
	return pose

func run() -> void:
	var outfit: Resource = Factory.create()
	var rig: Node3D = Rig.new()
	rig.manual_simulation = true
	rig.async_runtime_masks = false
	root.add_child(rig)
	expect(rig.load_outfit(outfit).is_empty(), "Animated lifecycle fixture loads all prepared wearables")
	expect(rig.skeleton != null and rig.animation != null and rig.animation.has_animation("Walk"), "Lifecycle runs on the imported rigged character with Walk animation")
	rig.play_animation("Walk")
	var jacket: Node3D = rig.slots[&"jacket"]["piece"]
	var bag: Node3D = rig.slots[&"bag"]["piece"]
	var armor: Node3D = rig.slots[&"armor"]["piece"]
	var initial_armor_anchor: Transform3D = armor.anchor.global_transform
	var initial_bones: Array[Transform3D] = []
	for index in range(rig.skeleton.get_bone_count()): initial_bones.append(rig.skeleton.get_bone_global_pose(index))
	advance(rig, 17)
	var moved_bone := false
	for index in range(initial_bones.size()): moved_bone = moved_bone or not pose_close(initial_bones[index],rig.skeleton.get_bone_global_pose(index))
	expect(moved_bone, "Walk actually changes skeleton poses before combat")
	expect(not pose_close(initial_armor_anchor,armor.anchor.global_transform) and pose_close(armor.get_piece_global_transform(),armor.anchor.global_transform), "Shoulder armor follows an actually moving Walk bone")
	expect(pose_close(jacket.get_piece_global_transform(),jacket.anchor.global_transform), "Intact jacket follows its animated anchor")
	var intact_pose: Transform3D = jacket.get_piece_global_transform()
	expect(hit(rig,&"jacket",&"body",12.0,"jacket-scratch")["accepted"], "First gameplay hit is accepted")
	expect(jacket.state == Piece.State.ATTACHED and pose_close(intact_pose,jacket.get_piece_global_transform()), "Material-only damage preserves the current attached pose")
	expect(not rig.controller.get_region_effects(&"shirt",&"upper")["visible"], "Small alpha damage does not prematurely disable the prepared coverage rule")
	expect(hit(rig,&"jacket",&"body",43.0,"jacket-link")["accepted"], "Further gameplay damage reaches the first prepared link break")
	expect(jacket.state == Piece.State.HANGING and jacket.get_active_connection_count() == 1, "Jacket transitions to a single surviving connection through the game API")
	expect(pose_close(intact_pose,jacket.get_piece_global_transform()), "Breaking the first link has no instantaneous pose jump")
	expect(rig.controller.get_region_effects(&"shirt",&"upper")["visible"], "Link damage reveals the underlying region immediately")
	advance(rig, 18)
	var pivot: Vector3 = jacket.connection_points[1]
	expect((jacket.get_piece_global_transform()*pivot).distance_to(jacket.anchor.global_transform*pivot) < .00001, "Surviving link remains attached while Walk and hanging motion both run")
	expect(hit(rig,&"shirt",&"upper",55.0,"shirt-tear")["accepted"], "Underlying cloth receives its own prepared tear hit")
	advance(rig, 18)
	expect(is_equal_approx(rig.slots[&"shirt"]["surface"].effective_mobility[0],.2), "A torn inner cloth still respects the independent intact harness")
	rig.controller.unequip(&"harness")
	advance(rig, 18)
	expect(is_equal_approx(rig.slots[&"shirt"]["surface"].effective_mobility[0],1.0), "Removing the last restraint releases the damaged cloth")
	expect(bag.state == Piece.State.ATTACHED and pose_close(bag.get_piece_global_transform(),attachment_pose(rig)), "Accessory remains attached to the current deforming cloth until its own connection is damaged")
	rig.simulation_running = false
	var saved: Dictionary = JSON.parse_string(JSON.stringify(rig.save_runtime_state()))
	var saved_jacket_pose: Transform3D = jacket.get_piece_global_transform()
	var saved_bag_pose: Transform3D = bag.get_piece_global_transform()
	var saved_armor_pose: Transform3D = armor.get_piece_global_transform()
	var loaded: Node3D = Rig.new()
	loaded.manual_simulation = true
	loaded.async_runtime_masks = false
	root.add_child(loaded)
	expect(loaded.load_outfit(outfit).is_empty(), "Second character instance loads the same immutable outfit")
	var replay_events := {"damage":0,"break":0}
	loaded.controller.damage_applied.connect(func(_result: Dictionary) -> void: replay_events["damage"] += 1)
	loaded.controller.attachment_broken.connect(func(_item: StringName,_region: StringName,_index: int) -> void: replay_events["break"] += 1)
	expect(loaded.load_runtime_state(saved), "Paused hanging-and-torn gameplay state reloads from actual JSON")
	expect(not loaded.simulation_running and replay_events == {"damage":0,"break":0}, "Reload keeps pause state and emits no duplicate damage/break events")
	expect(pose_close(loaded.slots[&"jacket"]["piece"].get_piece_global_transform(),saved_jacket_pose), "Paused reload restores the animated hanging jacket before any simulation step")
	expect(pose_close(loaded.slots[&"armor"]["piece"].get_piece_global_transform(),saved_armor_pose), "Paused reload restores an intact piece on an animated shoulder bone")
	expect(pose_close(loaded.slots[&"bag"]["piece"].get_piece_global_transform(),saved_bag_pose), "Paused reload restores the cloth-mounted accessory before any simulation step")
	expect(pose_close(loaded.slots[&"bag"]["piece"].get_piece_global_transform(),attachment_pose(loaded)), "Loaded accessory and restored cloth agree in the same paused frame")
	expect(hit(rig,&"armor",&"body",85.0,"armor-immediate")["accepted"] and hit(loaded,&"armor",&"body",85.0,"armor-immediate")["accepted"], "Both moving-shoulder states accept immediate detachment without a warm-up frame")
	expect((rig.slots[&"armor"]["preview_velocity"] as Vector3).distance_to(loaded.slots[&"armor"]["preview_velocity"]) < .00001, "Immediate post-load detachment preserves inherited linear velocity")
	expect(armor.rigid_body.angular_velocity.distance_to(loaded.slots[&"armor"]["piece"].rigid_body.angular_velocity) < .00001, "Immediate post-load detachment preserves inherited angular velocity")
	for _frame in range(12):
		rig.step(1.0/60.0)
		loaded.step(1.0/60.0)
	expect(pose_close(jacket.get_piece_global_transform(),loaded.slots[&"jacket"]["piece"].get_piece_global_transform()), "Hanging motion continues identically after reload")
	expect(pose_close(bag.get_piece_global_transform(),loaded.slots[&"bag"]["piece"].get_piece_global_transform()), "Cloth-mounted accessory continues identically after reload")
	var release_pose: Transform3D = jacket.get_piece_global_transform()
	expect(hit(rig,&"jacket",&"body",30.0,"jacket-final")["accepted"], "Final gameplay hit releases the last jacket connection")
	expect(jacket.state == Piece.State.DETACHED and pose_close(jacket.get_piece_global_transform(),release_pose), "Rigid detachment preserves the hanging world pose")
	advance(rig, 8)
	expect(jacket.get_piece_global_transform().origin.y < release_pose.origin.y, "Detached jacket falls during preview simulation")
	expect(hit(rig,&"shirt",&"lower",85.0,"shirt-final")["accepted"], "Prepared cloth separation can occur while the accessory is still attached")
	advance(rig, 8)
	expect(bag.state == Piece.State.ATTACHED and pose_close(bag.get_piece_global_transform(),attachment_pose(rig)), "Parent cloth tearing does not silently break the accessory's independently owned connection")
	var bag_release: Transform3D = bag.get_piece_global_transform()
	expect(hit(rig,&"bag",&"body",85.0,"bag-final")["accepted"], "Accessory accepts its own connection-breaking hit")
	expect(bag.state == Piece.State.DETACHED and pose_close(bag.get_piece_global_transform(),bag_release), "Accessory releases at its current moving surface pose")
	rig.reset_preview()
	expect(jacket.state == Piece.State.ATTACHED and bag.state == Piece.State.ATTACHED, "Reset restores jacket and accessory connection ownership")
	expect(not rig.controller.get_region_effects(&"shirt",&"upper")["visible"], "Reset restores jacket coverage")
	expect(rig.slots[&"shirt"]["surface"].broken_edges.is_empty() and rig.slots[&"shirt"]["variant"] == 0, "Reset restores the prepared cloth seam and base mesh")
	expect(pose_close(bag.get_piece_global_transform(),attachment_pose(rig)), "Reset leaves the accessory attached to the reset cloth in the same frame")
	rig.queue_free()
	loaded.queue_free()
	await process_frame
	print("DAMAGE_LIFECYCLE_TESTS: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
