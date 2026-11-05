extends SceneTree
const Factory = preload("res://addons/aero_cloth_3d/core/aero_example_factory.gd")
const Rig = preload("res://addons/aero_cloth_3d/core/aero_wearable_rig.gd")
const Piece = preload("res://addons/aero_cloth_3d/core/aero_cloth_piece_3d.gd")
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")
func expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error(description)
func state_close(a: Variant, b: Variant) -> bool:
	if typeof(a) in [TYPE_FLOAT,TYPE_INT] and typeof(b) in [TYPE_FLOAT,TYPE_INT]:
		return absf(float(a)-float(b)) < 0.000001
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for key in a:
			if not b.has(key) or not state_close(a[key],b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for index in range(a.size()):
			if not state_close(a[index],b[index]): return false
		return true
	return a == b
func event(item: StringName, region: StringName, amount: float, id: String) -> Dictionary:
	return {"item_id":item,"region_id":region,"amount":amount,"hit_id":id,"type":"cut","uv":Vector2(.45,.35),"seed":19}
func mesh_indices(mesh: Mesh) -> int:
	var result: int = 0
	for i in range(mesh.get_surface_count()): result += mesh.surface_get_arrays(i)[Mesh.ARRAY_INDEX].size()
	return result
func proxy_builds(rig: Node3D) -> int:
	var result: int = 0
	for slot in rig.slots.values():
		if slot["base_variant"]["surface"]: result += slot["base_variant"]["surface"].mesh_build_count
		for variant in slot["variants"].values():
			if variant["surface"]: result += variant["surface"].mesh_build_count
	return result
func authoring_state(outfit: Resource) -> Array:
	var result: Array = []
	for item in outfit.items:
		var stages: Array = []
		for region in item.regions:
			for stage in region.stages: stages.append([stage.threshold,stage.cut_strength,stage.morph_values.duplicate(true),stage.damage_recipe.duplicate(true)])
		result.append([item.id,item.mobility.duplicate(),item.connection_points.duplicate(),item.damage_recipe.duplicate(true),stages])
	return result
func shape_value(rig: Node3D, name_value: StringName) -> float:
	if not rig.character: return -1.0
	for visual in rig.meshes(rig.character):
		for index in range(visual.mesh.get_blend_shape_count()):
			if visual.mesh.get_blend_shape_name(index)==name_value: return visual.get_blend_shape_value(index)
	return -1.0
func capture(view: SubViewport) -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return view.get_texture().get_image()
func run() -> void:
	var outfit: Resource = Factory.create()
	expect(outfit.validate().is_empty(), "Factory produces a valid five-item authoring outfit")
	var before_authoring: Array = authoring_state(outfit)
	var rig: Node3D = Rig.new()
	rig.manual_simulation=true
	root.add_child(rig)
	expect(rig.load_outfit(outfit).is_empty(), "Generic rig binds the real factory outfit without errors")
	expect(rig.slots.size()==5 and rig.skeleton!=null, "Factory demo contains five prepared wearables and an actual character rig")
	var shirt: Dictionary = rig.slots[&"shirt"]
	var armor: Dictionary = rig.slots[&"armor"]
	var controller: Node = rig.controller
	expect(shirt["surface"].points.size()==99 and shirt["variants"].size()==2, "Cloth proxy and separate bridge/free dense variants are prepared at load")
	expect(armor["variants"].size()==1, "Rigid visual mesh variant is also prepared before the first hit")
	var builds: int = proxy_builds(rig)
	expect(builds==3, "Base and both cloth variants bind exactly once")
	for descriptor in [shirt["base_variant"]]+shirt["variants"].values():
		expect(descriptor["surface"]!=null and descriptor["surface"].bindings.size()==1353, "Each dense variant has all vertices prebound to the CPU proxy")
	var base_indices: int = mesh_indices(shirt["base_variant"]["source_mesh"])
	var stage3_key: int = shirt["definition"].regions[0].stages[3].mesh_variant.get_instance_id()
	var stage4_key: int = shirt["definition"].regions[0].stages[4].mesh_variant.get_instance_id()
	expect(base_indices>mesh_indices(shirt["variants"][stage3_key]["source_mesh"]) and mesh_indices(shirt["variants"][stage3_key]["source_mesh"])>mesh_indices(shirt["variants"][stage4_key]["source_mesh"]), "Prepared bridge and fully cut variants contain genuinely different tear geometry")
	var material: ShaderMaterial = shirt["materials"][0]
	expect(material.get_shader_parameter("damage_region_rects").size()==16 and material.get_shader_parameter("damage_region_strength_a").size()==16 and material.get_shader_parameter("damage_region_strength_b").size()==16, "Every vec4[16] shader uniform is fully padded")
	expect(controller.get_region_effects(&"shirt",&"upper")["mobility"]==0.0 and not controller.get_region_effects(&"shirt",&"upper")["visible"], "Intact jacket and harness constrain and hide the inner upper region")
	expect(mesh_indices(shirt["visual"].mesh)<base_indices, "Covered geometry is excluded by precomputed indices rather than transparency")
	controller.apply_hit(event(&"shirt",&"upper",12,"shirt-scratch"))
	expect(controller.get_item_state(&"shirt")["regions"][&"upper"]["stage"]==1 and controller.get_item_state(&"shirt")["regions"][&"lower"]["stage"]==0, "Runtime damage remains local in the real visual adapter")
	expect(shirt["canvas"].get_coverage(Vector2(.45,.35)).r>0.0, "Prepared stage recipe and runtime hit build an actual CPU mask")
	var alpha: Image = shirt["canvas"].bake_map(&"alpha")
	expect(alpha.get_pixel(int(.45*alpha.get_width()),int(.35*alpha.get_height())).r<1.0, "Damage mask produces a nonopaque alpha bake")
	expect(shirt["canvas"].operations.size()==2, "Stage recipe and dynamic stamp coexist instead of overwriting one another")
	var signals: Dictionary = {"damage":0,"stage":0,"broken":0}
	controller.damage_applied.connect(func(_result: Dictionary) -> void: signals["damage"]+=1)
	controller.stage_changed.connect(func(_item: StringName,_region: StringName,_old: int,_new: int) -> void: signals["stage"]+=1)
	controller.attachment_broken.connect(func(_item: StringName,_region: StringName,_index: int) -> void: signals["broken"]+=1)
	controller.set_preview_stage(&"shirt",&"upper",3)
	expect(shirt["canvas"].operations.size()==4, "Stage-three canvas composes all three earlier stage recipes plus the preserved runtime stamp")
	expect(shirt["variant"]==stage3_key and shirt["visual"]==shirt["variants"][stage3_key]["visual"], "Stage three swaps to the prebound bridge variant")
	expect(shirt["surface"].broken_edges.size()==shirt["definition"].metadata["tear_edges"].size() and not shirt["surface"].broken_edges.has(Vector2i(40,49)), "Stage three breaks prepared cross-seam edges while retaining one physical bridge")
	expect(shirt["surface"].released_indices.has(0) and shirt["surface"].base_mobility[0]==0.0, "Prepared local pin release preserves authored base mobility")
	rig.step(1.0/60.0)
	expect(shirt["surface"].effective_mobility[0]==0.0, "An intact outer jacket still constrains a locally released inner pin")
	controller.set_preview_stage(&"jacket",&"body",3)
	for i in range(15): rig.step(1.0/60.0)
	expect(is_equal_approx(shirt["surface"].effective_mobility[0],.2), "After jacket break, the second harness still caps the released inner pin at .2")
	expect(controller.get_region_effects(&"shirt",&"upper")["visible"], "Jacket break reveals the inner region before the next frame")
	var jacket_piece: Node3D = rig.slots[&"jacket"]["piece"]
	expect(jacket_piece.state==Piece.State.HANGING, "Stage three prepared rigid piece hangs on its remaining connection")
	var pivot: Vector3 = jacket_piece.connection_points[1]
	expect((jacket_piece.get_piece_global_transform()*pivot).distance_to(jacket_piece.anchor.global_transform*pivot)<0.00001, "Hanging visual preserves its surviving connection on the animated anchor")
	controller.unequip(&"harness")
	for i in range(15): rig.step(1.0/60.0)
	expect(is_equal_approx(shirt["surface"].effective_mobility[0],1.0) and shirt["surface"].base_mobility[0]==0.0, "Removing the second source smoothly releases physics without changing authoring weights")
	controller.equip(&"harness")
	controller.set_preview_stage(&"shirt",&"upper",4)
	for i in range(15): rig.step(1.0/60.0)
	expect(is_equal_approx(shirt["surface"].effective_mobility[0],.2), "Final local release also respects an independent active harness cap")
	controller.unequip(&"harness")
	expect(shirt["variant"]==stage4_key and shirt["surface"].broken_edges.has(Vector2i(40,49)), "Stage four uses the free visual variant and releases the last physical seam bridge")
	controller.set_preview_stage(&"shirt",&"lower",3)
	expect(shirt["variant"]==stage4_key,"A later region cannot replace the stronger full-mesh damage variant with a weaker stage")
	controller.set_preview_stage(&"shirt",&"lower",0)
	expect(shirt["variant"]==stage4_key,"Repairing a second region keeps the first region's stronger variant")
	controller.set_preview_stage(&"jacket",&"body",4)
	expect(jacket_piece.state==Piece.State.DETACHED, "Stage four releases the prepared rigid body")
	expect(rig.slots[&"jacket"]["preview_velocity"].is_equal_approx(jacket_piece.rigid_body.linear_velocity), "Editor release inherits gameplay velocity including hanging motion")
	var release_basis: Basis = jacket_piece.rigid_body.global_basis
	var release_position: Vector3 = jacket_piece.rigid_body.global_position
	var release_velocity: Vector3 = jacket_piece.rigid_body.linear_velocity
	rig.step(1.0/60.0)
	expect(jacket_piece.rigid_body.global_position.is_equal_approx(release_position + (release_velocity + Vector3(0,-9.8,0)/60.0)/60.0), "Manual preview carries release velocity into the first falling step")
	expect(not jacket_piece.rigid_body.global_basis.is_equal_approx(release_basis), "Detached editor preview preserves angular motion instead of freezing rotation")
	expect(jacket_piece.rigid_body.linear_velocity.is_equal_approx(rig.slots[&"jacket"]["preview_velocity"]), "Preview exports its current falling velocity for gameplay saves")
	var detached_y: float = jacket_piece.get_piece_global_transform().origin.y
	for i in range(10): rig.step(1.0/60.0)
	expect(jacket_piece.get_piece_global_transform().origin.y<detached_y, "Detached piece visibly falls in controlled editor simulation")
	controller.set_preview_stage(&"armor",&"body",2)
	var dent_index: int = armor["visual"].find_blend_shape_by_name(&"Dent")
	expect(dent_index>=0 and is_equal_approx(armor["visual"].get_blend_shape_value(dent_index),.7), "Prepared armor Dent morph changes the actual wearable mesh")
	controller.set_preview_stage(&"armor",&"body",3)
	expect(armor["variant"]!=0 and armor["visual"]==armor["variants"][armor["variant"]]["visual"], "Rigid armor selects its preallocated damaged mesh")
	expect(is_equal_approx(armor["materials"][0].get_shader_parameter("base_roughness"),.95), "Prepared material override is translated without dropping damage support")
	expect(proxy_builds(rig)==builds, "Hits and stage changes never rebuild the dense proxy-bound meshes")
	controller.equip(&"harness")
	controller.set_preview_stage(&"harness",&"body",0)
	expect(is_equal_approx(shape_value(rig,&"ChestCompression"),.5) and is_equal_approx(shape_value(rig,&"FitCompression"),.5), "Prepared body and underlying shirt compression channels follow equipped harness")
	controller.unequip(&"harness")
	expect(is_zero_approx(shape_value(rig,&"ChestCompression")) and is_zero_approx(shape_value(rig,&"FitCompression")), "Removing compression source recomputes both morph channels from baseline")
	controller.equip(&"harness")
	controller.set_preview_stage(&"harness",&"body",4)
	expect(is_zero_approx(shape_value(rig,&"ChestCompression")), "Fully detached compression source stops deforming the body")
	var lower_before: Dictionary = controller.get_item_state(&"shirt")["regions"][&"lower"]
	var events_before: Array = [signals["damage"],signals["stage"],signals["broken"]]
	controller.set_preview_stage(&"shirt",&"upper",0)
	expect(controller.get_item_state(&"shirt")["regions"][&"lower"]==lower_before and [signals["damage"],signals["stage"],signals["broken"]]==events_before, "Backward stage preview repairs only its region without gameplay notifications")
	expect(shirt["variant"]==0 and shirt["surface"].broken_edges.is_empty() and shirt["surface"].released_indices.is_empty(), "Backward stage preview restores base geometry, seam and authored pin ownership")
	rig.reset_preview()
	expect(shirt["variant"]==0 and armor["variant"]==0 and jacket_piece.state==Piece.State.ATTACHED, "Full preview reset restores every prepared base variant and rigid connection")
	var rest_ok: bool = true
	for i in range(shirt["surface"].points.size()): rest_ok = rest_ok and shirt["surface"].points[i].is_equal_approx(shirt["surface"].get_target(i))
	expect(rest_ok, "Preview reset restores proxy points to current animation targets")
	rig.step(1.0/60.0)
	var bag: Dictionary = rig.slots[&"bag"]
	var expected_pose: Transform3D = shirt["surface"].get_surface_sample(Vector3i(33,42,34),Vector3(.3,.3,.4))
	expected_pose.origin+=expected_pose.basis.z*.04
	expect(bag["piece"].get_piece_global_transform().is_equal_approx(expected_pose), "Accessory follows the current CPU triangle through the generic adapter")
	controller.set_preview_stage(&"shirt",&"lower",3)
	controller.set_preview_stage(&"armor",&"body",4)
	for i in range(3): rig.step(1.0/60.0)
	rig.simulation_running=false
	var saved: Dictionary = rig.save_runtime_state()
	var saved_mask: PackedByteArray = shirt["canvas"].image.get_data()
	var serialized: Dictionary = JSON.parse_string(JSON.stringify(saved))
	rig.reset_preview()
	var before_load_events: Array = [signals["damage"],signals["stage"],signals["broken"]]
	expect(rig.load_runtime_state(serialized), "Complete rig state imports from real JSON, including physics and paused animation")
	expect([signals["damage"],signals["stage"],signals["broken"]]==before_load_events, "Runtime load does not replay gameplay damage or break notifications")
	expect(not rig.simulation_running and controller.get_item_state(&"shirt")["regions"][&"lower"]["stage"]==3 and armor["piece"].state==Piece.State.DETACHED, "Loaded state restores damage ownership, detached piece and pause state")
	expect(shirt["canvas"].image.get_data()==saved_mask, "Runtime masks rebuild deterministically from authored recipes and stored hits")
	var loaded_state: Dictionary = rig.save_runtime_state()
	expect(loaded_state["items"]["shirt"]["surface"]==saved["items"]["shirt"]["surface"], "Runtime load restores active variant proxy points, previous positions and release ownership")
	expect(state_close(loaded_state["items"]["armor"],saved["items"]["armor"]), "Runtime JSON load restores detached piece pose and velocity to serialized precision")
	var corrupt: Dictionary = serialized.duplicate(true)
	corrupt["items"]["shirt"]["surface"]["points"][0][0]="bad"
	expect(not rig.load_runtime_state(corrupt) and rig.save_runtime_state()==loaded_state, "Malformed physics load is rejected atomically")
	corrupt = serialized.duplicate(true)
	corrupt["items"]["armor"]["piece"]["anchor_velocity"] = [0,"bad",0]
	expect(not rig.load_runtime_state(corrupt) and rig.save_runtime_state()==loaded_state, "Malformed optional release velocity is rejected without changing live state")
	expect(authoring_state(outfit)==before_authoring, "Preview, combat, variant switches and load do not mutate authoring Resources")
	if DisplayServer.get_name()!="headless":
		# Isolate the real rig material on a simple panel to prove stage alpha holes.
		var view:=SubViewport.new()
		view.size=Vector2i(256,256)
		view.own_world_3d=true
		view.transparent_bg=true
		view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
		root.add_child(view)
		var environment:=WorldEnvironment.new()
		environment.environment=Environment.new()
		environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
		environment.environment.ambient_light_color=Color.WHITE
		environment.environment.ambient_light_energy=1.0
		view.add_child(environment)
		var panel:=MeshInstance3D.new()
		panel.mesh=Factory.panel(1.8,1.8,9,11)
		panel.position.y=.9
		view.add_child(panel)
		var camera:=Camera3D.new()
		camera.projection=Camera3D.PROJECTION_ORTHOGONAL
		camera.size=2.2
		camera.position=Vector3(0,0,3)
		view.add_child(camera)
		controller.set_preview_stage(&"jacket",&"body",0)
		panel.material_override=rig.slots[&"jacket"]["materials"][0]
		var intact: Image=await capture(view)
		controller.set_preview_stage(&"jacket",&"body",2)
		var damaged: Image=await capture(view)
		var opaque:=0
		var holes:=0
		for y in range(256):
			for x in range(256):
				if intact.get_pixel(x,y).a>.5:
					opaque+=1
					if damaged.get_pixel(x,y).a<.2: holes+=1
		expect(opaque>10000 and holes>25, "Actual GL rendering uses padded region strengths and produces alpha holes from the rig's prepared mask")
		print("RIG_RENDER_PIXELS opaque=",opaque," holes=",holes)
		view.queue_free()
	else:
		print("RIG_RENDER: skipped in headless mode")
	rig.queue_free()
	await process_frame
	print("WEARABLE_RIG_TESTS: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
