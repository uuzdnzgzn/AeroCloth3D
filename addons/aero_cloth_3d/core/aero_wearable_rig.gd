@tool
class_name AeroWearableRig
extends Node3D
## Scene adapter. All mesh variants and index visibility states are prepared on load.
const Controller = preload("res://addons/aero_cloth_3d/core/aero_wearable_controller.gd")
const BodyCollision = preload("res://addons/aero_cloth_3d/core/aero_body_collision.gd")
const MaskJob = preload("res://addons/aero_cloth_3d/core/aero_mask_job.gd")
const Canvas = preload("res://addons/aero_cloth_3d/core/aero_damage_canvas.gd")
const Surface = preload("res://addons/aero_cloth_3d/core/aero_proxy_surface_3d.gd")
const Piece = preload("res://addons/aero_cloth_3d/core/aero_cloth_piece_3d.gd")
const DAMAGE_SHADER = preload("res://addons/aero_cloth_3d/shaders/aero_damage_material.gdshader")
const BOUND_SHADER = preload("res://addons/aero_cloth_3d/shaders/aero_bound_surface.gdshader")
@export var outfit: Resource
@export var async_runtime_masks: bool = true
@export_range(0.001, 2.0) var max_hit_distance: float = 0.15
var controller: Node
var character: Node3D
var skeleton: Skeleton3D
var animation: AnimationPlayer
var slots: Dictionary = {}
var errors := PackedStringArray()
var manual_simulation := false
var simulation_running := true
var animation_name := "Idle"
var animation_time := 0.0
var _syncing := false
var _loading_state := false
var _preparing := false

func _ready() -> void:
	if outfit != null and slots.is_empty(): load_outfit(outfit)

func load_outfit(recipe: Resource) -> PackedStringArray:
	_orphan_mask_jobs()
	_preparing = true
	_syncing = true
	for child in get_children():
		remove_child(child)
		child.queue_free()
	slots.clear()
	errors.clear()
	skeleton = null
	animation = null
	character = null
	outfit = recipe
	controller = Controller.new()
	add_child(controller)
	controller.state_changed.connect(_sync_state)
	controller.damage_applied.connect(_capture_damage_impulse)
	if recipe == null:
		errors.append("Outfit is null")
		_syncing = false
		_preparing = false
		return errors
	errors.append_array(recipe.validate())
	if not errors.is_empty():
		_syncing = false
		_preparing = false
		return errors
	if recipe.character_scene:
		character = recipe.character_scene.instantiate()
		add_child(character)
		skeleton = _find(character, "Skeleton3D") as Skeleton3D
		animation = _find(character, "AnimationPlayer") as AnimationPlayer
		if animation:
			# Loop configuration belongs to this instance, not the imported library.
			for library_name in animation.get_animation_library_list():
				var library: AnimationLibrary = animation.get_animation_library(library_name).duplicate(true)
				animation.remove_animation_library(library_name)
				animation.add_animation_library(library_name, library)
			animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
			for name_value in animation.get_animation_list():
				if name_value != "RESET": animation.get_animation(name_value).loop_mode = Animation.LOOP_LINEAR
			play_animation("Idle")
	for definition in recipe.items:
		var validation: PackedStringArray = definition.validate()
		for bone in definition.required_bones:
			if skeleton == null or skeleton.find_bone(bone) < 0: validation.append("Missing bone: " + bone)
		if not validation.is_empty():
			errors.append_array(validation)
			continue
		_add_item(definition)
	for id in slots: controller.equip(id)
	_syncing = false
	_sync_state()
	_preparing = false
	return errors

func _find(node: Node, kind: String) -> Node:
	if node.is_class(kind): return node
	for child in node.get_children():
		var found: Node = _find(child, kind)
		if found: return found
	return null

func _source_transform(node: Node3D) -> Transform3D:
	var pose: Transform3D = node.transform
	var parent: Node = node.get_parent()
	while parent is Node3D:
		pose = parent.transform * pose
		parent = parent.get_parent()
	return pose

func _extract_visual(scene: PackedScene, mesh_path: NodePath = NodePath()) -> Dictionary:
	var imported: Node = scene.instantiate()
	var source: MeshInstance3D = imported.get_node_or_null(mesh_path) as MeshInstance3D if not mesh_path.is_empty() else _find(imported, "MeshInstance3D") as MeshInstance3D
	if source == null or source.mesh == null:
		imported.free()
		return {}
	var visual := MeshInstance3D.new()
	visual.mesh = source.mesh
	visual.transform = _source_transform(source)
	var materials: Array[Material] = []
	for index in range(source.mesh.get_surface_count()): materials.append(source.get_active_material(index))
	if source.skin:
		var source_skeleton: Skeleton3D = source.get_node_or_null(source.skeleton) as Skeleton3D
		var mapped := Skin.new()
		for index in range(source.skin.get_bind_count()):
			var bone_name: StringName = source.skin.get_bind_name(index)
			if bone_name == &"" and source_skeleton and source.skin.get_bind_bone(index) >= 0: bone_name = source_skeleton.get_bone_name(source.skin.get_bind_bone(index))
			if skeleton == null or bone_name == &"" or skeleton.find_bone(bone_name) < 0:
				errors.append("Selected mesh contains an unmapped skin bone")
				imported.free()
				visual.free()
				return {}
			mapped.add_named_bind(bone_name, source.skin.get_bind_pose(index))
		visual.skin = mapped
	imported.free()
	return {"visual":visual, "source_materials":materials}

func _add_item(definition: Resource) -> void:
	var extracted: Dictionary = _extract_visual(definition.source_scene, definition.mesh_path)
	if extracted.is_empty():
		errors.append("No usable selected mesh: " + str(definition.id))
		return
	var anchor := Node3D.new()
	anchor.name = str(definition.id) + "Anchor"
	if skeleton and skeleton.find_bone(definition.anchor_bone) >= 0 and definition.motion_mode != &"skinned":
		var bone := BoneAttachment3D.new()
		bone.bone_name = definition.anchor_bone
		skeleton.add_child(bone)
		bone.add_child(anchor)
		anchor.global_transform = global_transform * definition.bind_transform
	else:
		add_child(anchor)
		anchor.transform = definition.bind_transform
	var mount := Node3D.new()
	anchor.add_child(mount)
	var canvas: RefCounted = Canvas.new()
	canvas.initialize(definition.mask_resolution)
	canvas.gpu_normal_preview = true
	var slot: Dictionary = {"definition":definition,"anchor":anchor,"mount":mount,"canvas":canvas,"piece":null,"surface":null,"visual":null,"materials":[],"variants":{},"variant":0,"recipe_key":"","applied_recipes":[],"applied_stamps":[],"mask_full_rebuilds":0,"mask_incremental_updates":0,"mask_task":-1,"mask_job":null,"mask_generation":0,"mask_published_generation":0,"mask_requested":{},"mask_started_jobs":0,"mask_incremental_jobs":0,"mask_full_jobs":0,"mask_last_job_incremental":false,"mask_last_first_recipe":0,"mask_last_first_stamp":0,"mask_discarded_jobs":0,"mask_failed_generation":-1,"visibility_cache":{},"source_mesh":null,"last_state":{},"preview_velocity":Vector3.ZERO}
	var base: Dictionary = _prepare_variant(slot, extracted)
	slot["base_variant"] = base
	for key in ["visual","surface","materials","source_mesh"]: slot[key] = base[key]
	# Instantiate and proxy-bind every authored replacement before gameplay.
	for region in definition.regions:
		for stage in region.stages:
			if stage.mesh_variant == null: continue
			var key: int = stage.mesh_variant.get_instance_id()
			if slot["variants"].has(key): continue
			var replacement: Dictionary = _extract_visual(stage.mesh_variant)
			if replacement.is_empty():
				errors.append("Invalid prepared variant: " + str(definition.id))
				continue
			var variant: Dictionary = _prepare_variant(slot, replacement)
			variant["visual"].visible = false
			slot["variants"][key] = variant
	if definition.motion_mode == &"rigid":
		var piece: Node3D = Piece.new()
		add_child(piece)
		var points: Array[Vector3] = []
		for point in definition.connection_points: points.append(point)
		if points.is_empty(): points.append(Vector3.ZERO)
		if points.size() > 2:
			errors.append("Prepared rigid piece supports at most two connections: " + str(definition.id))
			points.resize(2)
		piece.configure(anchor, mount, points)
		piece.set_physics_process(false)
		slot["piece"] = piece
	_prepare_visibility(slot)
	slots[definition.id] = slot
	if not controller.register_item(definition): errors.append_array(controller.validation_errors)

func _prepare_variant(slot: Dictionary, extracted: Dictionary) -> Dictionary:
	var definition: Resource = slot["definition"]
	var visual: MeshInstance3D = extracted["visual"]
	slot["mount"].add_child(visual)
	if visual.skin and skeleton: visual.skeleton = visual.get_path_to(skeleton)
	var surface: Node3D = null
	if definition.motion_mode == &"cloth" and definition.proxy_mesh:
		surface = Surface.new()
		add_child(surface)
		if not surface.configure(visual, definition.proxy_mesh, skeleton): errors.append(surface.last_error)
		elif definition.mobility.size() == surface.points.size():
			surface.base_mobility = definition.mobility.duplicate()
			surface.effective_mobility = definition.mobility.duplicate()
		surface.set_physics_process(false)
	var descriptor: Dictionary = {"visual":visual,"surface":surface,"materials":[],"source_mesh":visual.mesh,"material_sets":{}}
	var overrides: Dictionary = {0:null}
	for region in definition.regions:
		for stage in region.stages:
			if stage.material_override: overrides[stage.material_override.get_instance_id()] = stage.material_override
	for key in overrides:
		var prepared: Array[ShaderMaterial] = []
		for index in range(visual.mesh.get_surface_count()):
			var original: Material = overrides[key] if key != 0 else extracted["source_materials"][index]
			var material := ShaderMaterial.new()
			material.shader = BOUND_SHADER if surface else DAMAGE_SHADER
			material.set_shader_parameter("tint", definition.base_color * (original.albedo_color if original is StandardMaterial3D else Color.WHITE))
			material.set_shader_parameter("base_metallic", original.metallic if original is StandardMaterial3D else (0.75 if definition.material_kind == &"metal" else 0.0))
			if original is StandardMaterial3D:
				material.set_shader_parameter("base_roughness", original.roughness)
				for pair in [["albedo_texture","base_albedo"],["normal_texture","base_normal"],["roughness_texture","base_roughness_texture"],["metallic_texture","base_metallic_texture"]]:
					var texture: Texture2D = original.get(pair[0])
					if texture:
						material.set_shader_parameter(pair[1], texture)
						material.set_shader_parameter("use_" + pair[1], true)
			elif original is ShaderMaterial:
				for uniform in original.shader.get_shader_uniform_list():
					var value: Variant = original.get_shader_parameter(uniform["name"])
					if value != null: material.set_shader_parameter(uniform["name"], value)
			if surface:
				material.set_shader_parameter("proxy_data", surface.proxy_texture)
				material.set_shader_parameter("proxy_rest_data", surface.proxy_rest_texture)
			var arrays: Array = visual.mesh.surface_get_arrays(index)
			material.set_shader_parameter("use_damage_uv2", arrays[Mesh.ARRAY_TEX_UV2] != null and not arrays[Mesh.ARRAY_TEX_UV2].is_empty())
			prepared.append(material)
		descriptor["material_sets"][key] = prepared
	descriptor["materials"] = descriptor["material_sets"][0]
	visual.material_override = null
	return descriptor

func _prepare_visibility(slot: Dictionary) -> void:
	var definition: Resource = slot["definition"]
	if definition.regions.size() > 4:
		errors.append("Visibility prewarm supports up to four regions per mesh")
		return
	var descriptors: Dictionary = slot["variants"].duplicate()
	descriptors[0] = slot["base_variant"]
	for variant_key in descriptors:
		var source: Mesh = descriptors[variant_key]["source_mesh"]
		for mask in range(1 << definition.regions.size()):
			if mask == 0:
				slot["visibility_cache"][str(variant_key) + ":0"] = source
				continue
			var result := ArrayMesh.new()
			if source is ArrayMesh:
				result.blend_shape_mode = source.blend_shape_mode
				for shape in range(source.get_blend_shape_count()): result.add_blend_shape(source.get_blend_shape_name(shape))
			for index in range(source.get_surface_count()):
				var arrays: Array = source.surface_get_arrays(index).duplicate(true)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var uv: PackedVector2Array = _damage_uvs(arrays)
				if uv.is_empty(): continue
				var ids: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
				if ids.is_empty():
					for vertex in range(vertices.size()): ids.append(vertex)
				var kept := PackedInt32Array()
				for triangle in range(0, ids.size(), 3):
					var hidden := false
					for region_index in range(definition.regions.size()):
						if mask & (1 << region_index):
							var rect: Rect2 = definition.regions[region_index].uv_rect.grow(0.00001)
							if rect.has_point(uv[ids[triangle]]) and rect.has_point(uv[ids[triangle+1]]) and rect.has_point(uv[ids[triangle+2]]): hidden = true
					if not hidden: kept.append_array(PackedInt32Array([ids[triangle], ids[triangle+1], ids[triangle+2]]))
				if kept.is_empty(): continue
				arrays[Mesh.ARRAY_INDEX] = kept
				var blends: Array = source.surface_get_blend_shape_arrays(index) if source is ArrayMesh else []
				result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, blends, {}, source.surface_get_format(index))
			slot["visibility_cache"][str(variant_key) + ":" + str(mask)] = result

func _is_repair(slot: Dictionary, state: Dictionary) -> bool:
	var old: Dictionary = slot["last_state"]
	for region in state["regions"]:
		if old.get("regions", {}).get(region, {}).get("stage", 0) > state["regions"][region]["stage"] or old.get("regions", {}).get(region, {}).get("damage",0) > state["regions"][region]["damage"]: return true
	return false

func _update_targets(slot: Dictionary, surface: Node3D) -> void:
	if surface.proxy_bones.is_empty():
		var targets := PackedVector3Array()
		for point in surface.rest: targets.append(surface.visual.global_transform * point)
		surface.set_targets(targets)

func _sync_state(_id: StringName = &"") -> void:
	if _syncing: return
	_syncing = true
	for id in slots:
		var slot: Dictionary = slots[id]
		var definition: Resource = slot["definition"]
		var state: Dictionary = controller.get_item_state(id)
		if state.is_empty(): continue
		var repair: bool = _is_repair(slot, state)
		var desired_broken: Dictionary = {}
		var constraints: Dictionary = {}
		var stamps: Array = []
		var recipes: Array[Dictionary] = [definition.damage_recipe]
		var rects := PackedVector4Array()
		var strengths_a := PackedVector4Array()
		var strengths_b := PackedVector4Array()
		rects.resize(16)
		strengths_a.resize(16)
		strengths_b.resize(16)
		var hidden_mask := 0
		var variant_key := 0
		var override_key := 0
		var maximum_stage := 0
		var variant_stage := -1
		var variant_region := ""
		var override_stage := -1
		var override_region := ""
		for index in range(definition.regions.size()):
			var region: Resource = definition.regions[index]
			var region_state: Dictionary = state["regions"][region.id]
			var stage: Resource = region.stages[region_state["stage"]]
			maximum_stage = maxi(maximum_stage, region_state["stage"])
			stamps.append_array(region_state["stamps"])
			var effect: Dictionary = controller.get_region_effects(id, region.id)
			if not effect.get("visible", true): hidden_mask |= 1 << index
			var cap: float = effect.get("mobility", region.base_mobility)
			if region_state["detached"]:
				cap = 1.0
				for source in effect.get("sources", []): cap = minf(cap, source["mobility_cap"])
			constraints[region.id] = {"indices":region.proxy_indices,"cap":cap}
			for stage_index in range(region_state["stage"] + 1):
				if not region.stages[stage_index].damage_recipe.is_empty(): recipes.append(region.stages[stage_index].damage_recipe)
			if index < 16:
				rects[index] = Vector4(region.uv_rect.position.x,region.uv_rect.position.y,region.uv_rect.size.x,region.uv_rect.size.y)
				strengths_a[index] = Vector4(stage.cut_strength,stage.normal_strength,stage.wear_strength,stage.burn_strength)
				strengths_b[index] = Vector4(stage.blood_strength,0,0,0)
			for connection in region_state["broken_connections"]: desired_broken[connection] = true
			if stage.mesh_variant and (region_state["stage"]>variant_stage or (region_state["stage"]==variant_stage and str(region.id)<variant_region)):
				variant_key = stage.mesh_variant.get_instance_id()
				variant_stage = region_state["stage"]
				variant_region = str(region.id)
			if stage.material_override and (region_state["stage"]>override_stage or (region_state["stage"]==override_stage and str(region.id)<override_region)):
				override_key = stage.material_override.get_instance_id()
				override_stage = region_state["stage"]
				override_region = str(region.id)
		# Match the controller's deterministic ownership of shared UV boundaries.
		var shader_regions: Array = definition.regions.duplicate()
		shader_regions.sort_custom(func(a: Resource,b: Resource)->bool: return str(a.id)<str(b.id))
		for index in range(mini(shader_regions.size(),16)):
			var region: Resource = shader_regions[index]
			var stage: Resource = region.stages[state["regions"][region.id]["stage"]]
			rects[index] = Vector4(region.uv_rect.position.x,region.uv_rect.position.y,region.uv_rect.size.x,region.uv_rect.size.y)
			strengths_a[index] = Vector4(stage.cut_strength,stage.normal_strength,stage.wear_strength,stage.burn_strength)
			strengths_b[index] = Vector4(stage.blood_strength,0,0,0)
		var canvas: RefCounted = slot["canvas"]
		_sync_canvas(slot, recipes, stamps, repair)
		var descriptor: Dictionary = slot["base_variant"] if variant_key == 0 else slot["variants"].get(variant_key, slot["base_variant"])
		if variant_key != slot["variant"]:
			if slot["surface"] and descriptor["surface"]: descriptor["surface"].restore(slot["surface"].snapshot())
			slot["visual"].visible = false
			for key in ["visual","surface","source_mesh"]: slot[key] = descriptor[key]
			slot["variant"] = variant_key
		var visual: MeshInstance3D = slot["visual"]
		slot["materials"] = descriptor["material_sets"].get(override_key, descriptor["material_sets"][0])
		if slot["surface"]:
			var surface: Node3D = slot["surface"]
			_update_targets(slot, surface)
			if repair and not _loading_state: surface.reset_simulation(true)
			surface.set_constraint_sources(constraints)
			for region in definition.regions:
				if state["regions"][region.id]["detached"]: surface.release_region(region.proxy_indices)
			for entry in definition.metadata.get("release_pins", []):
				if maximum_stage >= int(entry["stage"]): surface.release_region(PackedInt32Array(entry["indices"]))
			if maximum_stage >= 3:
				for edge in definition.metadata.get("tear_edges", []): surface.break_edge(int(edge[0]), int(edge[1]))
			if maximum_stage >= 4:
				for edge in definition.metadata.get("tear_bridge", []): surface.break_edge(int(edge[0]), int(edge[1]))
		if slot["piece"] and not _loading_state:
			var piece: Node3D = slot["piece"]
			var piece_repair := false
			for index in range(piece.broken_connections.size()):
				if piece.broken_connections[index] and not desired_broken.has(index): piece_repair = true
			if piece_repair: piece.reset_damage()
			piece.set_equipped(state["equipped"])
			var was_detached: bool = piece.state == Piece.State.DETACHED
			for index in desired_broken:
				if index < piece.broken_connections.size() and not piece.broken_connections[index]: piece.apply_hit(index, slot.get("last_impulse",Vector3(0.05,0.02,0.08)))
			if not was_detached and piece.state == Piece.State.DETACHED:
				slot["preview_velocity"] = slot.get("last_impulse",Vector3(0.05,0.02,0.08))/piece.rigid_body.mass
			piece.rigid_body.freeze = manual_simulation or not state["equipped"] or piece.state != Piece.State.DETACHED
			if piece_repair: slot["preview_velocity"] = Vector3.ZERO
		var cache_key: String = str(slot["variant"]) + ":" + str(hidden_mask)
		visual.mesh = slot["visibility_cache"].get(cache_key, descriptor["source_mesh"])
		visual.visible = state["equipped"] and visual.mesh.get_surface_count() > 0
		for index in range(visual.mesh.get_surface_count()):
			if index < slot["materials"].size(): visual.set_surface_override_material(index, slot["materials"][index])
		for material: ShaderMaterial in slot["materials"]:
			material.set_shader_parameter("mask_texture", canvas.texture)
			material.set_shader_parameter("damage_normal", canvas.normal_texture)
			material.set_shader_parameter("damage_height", canvas.height_texture)
			material.set_shader_parameter("use_damage_height", true)
			material.set_shader_parameter("damage_region_count", mini(definition.regions.size(),16))
			material.set_shader_parameter("damage_region_rects", rects)
			material.set_shader_parameter("damage_region_strength_a", strengths_a)
			material.set_shader_parameter("damage_region_strength_b", strengths_b)
			for key in ["cut_strength","normal_strength","wear_strength","burn_strength","blood_strength"]: material.set_shader_parameter(key,1.0)
		slot["last_state"] = state
	_sync_morphs()
	_syncing = false

func _prefix(earlier: Array, later: Array) -> bool:
	if earlier.size()>later.size(): return false
	for index in range(earlier.size()):
		if earlier[index]!=later[index]: return false
	return true

func _recipes_order_sensitive(recipes: Array) -> bool:
	for recipe in recipes:
		for operation in recipe.get("operations",[]):
			if operation.get("erase",false) or str(operation.get("brush","")) in ["smooth","grow","shrink"]: return true
	return false

func _runtime_stamp(canvas: RefCounted, stamp: Dictionary) -> void:
	var uv: Vector2 = stamp["uv"]
	var kind_name: String = str(stamp.get("type", "cut"))
	var brush: StringName = &"cut" if kind_name in ["slash","cut","pierce"] else (&"burn" if kind_name in ["burn","fire"] else (&"wear" if kind_name in ["wear","abrasion"] else (&"blood" if kind_name=="blood" else &"dent")))
	canvas.stamp(uv,brush,0.045+minf(float(stamp.get("amount",10)),80)*0.001,0.95,float(stamp.get("angle",0.0)),int(stamp.get("seed",0)))

func _sync_canvas(slot: Dictionary, recipes: Array, stamps: Array, force_sync: bool = false) -> void:
	if async_runtime_masks and not manual_simulation and not Engine.is_editor_hint() and not _preparing and not _loading_state and not force_sync:
		_request_mask_job(slot,recipes,stamps)
		return
	# Reset/import/editor work publishes synchronously and invalidates any older job.
	if slot["mask_task"]>=0 or not slot["mask_requested"].is_empty():
		slot["mask_generation"]+=1
		slot["mask_requested"]={}
	var old_recipes: Array = slot["applied_recipes"]
	var old_stamps: Array = slot["applied_stamps"]
	if recipes==old_recipes and stamps==old_stamps: return
	var append_only: bool = _prefix(old_recipes,recipes) and _prefix(old_stamps,stamps)
	# The canonical composition is authored recipes, then runtime hits. Appending
	# erase/filter authoring after existing gameplay stamps would reorder effects.
	if recipes.size()>old_recipes.size() and not old_stamps.is_empty() and _recipes_order_sensitive(recipes): append_only = false
	var canvas: RefCounted = slot["canvas"]
	if not append_only:
		canvas.clear()
		slot["mask_full_rebuilds"] += 1
	else:
		slot["mask_incremental_updates"] += 1
	var first_recipe: int = old_recipes.size() if append_only else 0
	var first_stamp: int = old_stamps.size() if append_only else 0
	for index in range(first_recipe,recipes.size()):
		if not _replay_recipe(canvas,recipes[index]): errors.append("Invalid authored mask recipe: " + str(slot["definition"].id))
	for index in range(first_stamp,stamps.size()): _runtime_stamp(canvas,stamps[index])
	canvas.flush()
	# Resources are editable; keep value snapshots so later brush edits cannot
	# masquerade as an unchanged prefix through shared Dictionary references.
	slot["applied_recipes"] = recipes.duplicate(true)
	slot["applied_stamps"] = stamps.duplicate(true)

func _request_mask_job(slot: Dictionary, recipes: Array, stamps: Array) -> void:
	var requested: Dictionary=slot["mask_requested"]
	if requested.is_empty() and recipes==slot["applied_recipes"] and stamps==slot["applied_stamps"]: return
	if requested.is_empty() or requested["recipes"]!=recipes or requested["stamps"]!=stamps:
		slot["mask_generation"]+=1
		slot["mask_requested"]={"generation":slot["mask_generation"],"recipes":recipes.duplicate(true),"stamps":stamps.duplicate(true)}
	if slot["mask_task"]<0 and slot["mask_generation"]!=slot["mask_published_generation"] and slot["mask_failed_generation"]!=slot["mask_generation"]: _start_mask_job(slot)

func _start_mask_job(slot: Dictionary) -> void:
	if slot["mask_requested"].is_empty(): return
	var snapshot: Dictionary=slot["mask_requested"].duplicate(true)
	var old_recipes: Array=slot["applied_recipes"]
	var old_stamps: Array=slot["applied_stamps"]
	var incremental: bool=_prefix(old_recipes,snapshot["recipes"]) and _prefix(old_stamps,snapshot["stamps"])
	if snapshot["recipes"].size()>old_recipes.size() and not old_stamps.is_empty() and _recipes_order_sensitive(snapshot["recipes"]): incremental=false
	snapshot["incremental"]=incremental
	snapshot["first_recipe"]=old_recipes.size() if incremental else 0
	snapshot["first_stamp"]=old_stamps.size() if incremental else 0
	if incremental:
		var published: Dictionary=slot["canvas"].export_cpu_result()
		var private_images: Dictionary={"size":published["size"],"operations":published["operations"].duplicate(true)}
		for key in ["image","height_image","dent_image"]: private_images[key]=published[key].duplicate()
		snapshot["checkpoint"]=private_images
		slot["mask_incremental_jobs"]+=1
	else:
		slot["mask_full_jobs"]+=1
	slot["mask_last_job_incremental"]=incremental
	slot["mask_last_first_recipe"]=snapshot["first_recipe"]
	slot["mask_last_first_stamp"]=snapshot["first_stamp"]
	var job: RefCounted=MaskJob.new()
	job.configure(snapshot,slot["definition"].mask_resolution)
	slot["mask_job"]=job
	slot["mask_task"]=WorkerThreadPool.add_task(job.run,false,"AeroCloth CPU mask")
	slot["mask_started_jobs"]+=1

func _process(_delta: float) -> void:
	_poll_mask_jobs()

func _poll_mask_jobs() -> void:
	for slot in slots.values():
		var task: int=slot["mask_task"]
		if task<0 or not WorkerThreadPool.is_task_completed(task): continue
		# Already completed: this is bookkeeping cleanup, never a painting wait.
		WorkerThreadPool.wait_for_task_completion(task)
		var job: RefCounted=slot["mask_job"]
		slot["mask_task"]=-1
		slot["mask_job"]=null
		var requested: Dictionary=slot["mask_requested"]
		if job.generation!=slot["mask_generation"] or requested.is_empty():
			slot["mask_discarded_jobs"]+=1
		elif slot["canvas"].publish_cpu_result(job.result):
			slot["applied_recipes"]=requested["recipes"].duplicate(true)
			slot["applied_stamps"]=requested["stamps"].duplicate(true)
			slot["mask_published_generation"]=job.generation
		else:
			slot["mask_failed_generation"]=job.generation
			errors.append("Asynchronous mask failed: "+str(slot["definition"].id)+" "+str(job.result.get("error","Invalid CPU result")))
		if not slot["mask_requested"].is_empty() and slot["mask_published_generation"]!=slot["mask_generation"] and slot["mask_failed_generation"]!=slot["mask_generation"]: _start_mask_job(slot)

func _orphan_mask_jobs() -> void:
	for slot in slots.values():
		if slot.get("mask_task",-1)>=0:
			if is_inside_tree(): slot["mask_job"].orphan_task(slot["mask_task"],get_tree())
			slot["mask_task"]=-1
			slot["mask_job"]=null

func _exit_tree() -> void:
	_orphan_mask_jobs()

func _replay_recipe(canvas: RefCounted, recipe: Dictionary) -> bool:
	if recipe.is_empty(): return true
	if recipe.get("format", "") != "aero_damage_canvas" or recipe.get("version", 0) != 1 or not recipe.get("operations", null) is Array: return false
	# Validate this complete recipe before replaying it onto the composition.
	var operations: Array[Dictionary] = []
	for source in recipe["operations"]:
		if not source is Dictionary: return false
		var operation: Dictionary = canvas._validate_operation(source)
		if operation.is_empty(): return false
		operations.append(operation)
	for operation in operations:
		var uv := Vector2(operation["uv"][0], operation["uv"][1])
		if not canvas.stamp(uv, StringName(operation["brush"]), operation["radius"], operation["strength"], operation["angle"], operation["seed"], operation["erase"]): return false
	return true

func _apply_morphs(visual: MeshInstance3D, values: Dictionary) -> void:
	if not visual.mesh is ArrayMesh:return
	for index in range(visual.mesh.get_blend_shape_count()): visual.set_blend_shape_value(index, values.get(visual.mesh.get_blend_shape_name(index),0.0))

func _sync_morphs() -> void:
	var body_values: Dictionary = {}
	var compression := 0.0
	for id in slots:
		var definition: Resource = slots[id]["definition"]
		var item_state: Dictionary = controller.get_item_state(id)
		var active: bool = item_state.get("equipped",false)
		var all_detached := true
		for region_state in item_state.get("regions",{}).values(): all_detached = all_detached and region_state["detached"]
		if active and not all_detached:
			compression = maxf(compression, definition.compression)
			for channel in [definition.body_morph, definition.fit_morph]:
				if channel != &"": body_values[channel] = maxf(body_values.get(channel,0),definition.compression)
	if character:
		for visual in meshes(character): _apply_morphs(visual, body_values)
	for id in slots:
		var slot: Dictionary = slots[id]
		var definition: Resource = slot["definition"]
		var values: Dictionary = controller.get_item_state(id).get("prepared_morphs",{}).duplicate()
		if definition.fit_morph != &"": values[definition.fit_morph] = compression
		_apply_morphs(slot["base_variant"]["visual"], values)
		for descriptor in slot["variants"].values(): _apply_morphs(descriptor["visual"],values)

func meshes(root_node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if root_node is MeshInstance3D and root_node.mesh: result.append(root_node)
	for child in root_node.get_children(): result.append_array(meshes(child))
	return result

func play_animation(name_value: String) -> void:
	animation_name = name_value
	animation_time = 0.0
	if animation and animation.has_animation(name_value):
		animation.play(name_value)
		animation.seek(0,true)
		if skeleton: skeleton.force_update_all_bone_transforms()

func _physics_process(delta: float) -> void:
	if simulation_running and not manual_simulation: step(delta)

func step(delta: float) -> void:
	if animation:
		animation.advance(delta)
		animation_time += delta
		if skeleton: skeleton.force_update_all_bone_transforms()
	var body_spheres: Array[Vector4] = BodyCollision.sample(outfit.metadata.get("body_colliders",[]),skeleton,global_transform)
	# CPU proxies update before attachments irrespective of outfit list order.
	for id in slots:
		var slot: Dictionary = slots[id]
		if controller.get_item_state(id).get("equipped",false) and slot["surface"]:
			slot["surface"].collision_spheres = body_spheres
			_update_targets(slot,slot["surface"])
			slot["surface"].step(delta)
	for id in slots:
		var slot: Dictionary = slots[id]
		if not slot["piece"]: continue
		var piece: Node3D = slot["piece"]
		var equipped: bool = controller.get_item_state(id).get("equipped",false)
		var attach: StringName = StringName(slot["definition"].metadata.get("attach_item",""))
		if attach != &"" and slots.has(attach):
			equipped = equipped and controller.get_item_state(attach).get("equipped",false)
			if slots[attach]["surface"]:
				var source: Node3D = slots[attach]["surface"]
				var pose: Transform3D = source.get_surface_sample(slot["definition"].metadata.get("triangle",Vector3i(0,1,2)),slot["definition"].metadata.get("barycentric",Vector3(0.3,0.3,0.4)))
				pose.origin += pose.basis.z * 0.04
				slot["anchor"].global_transform = pose
		piece.get_visual_root().visible = equipped
		if not equipped:
			piece.rigid_body.freeze = true
			continue
		piece._physics_process(delta)
		if piece.state == Piece.State.DETACHED:
			piece.rigid_body.freeze = manual_simulation
			if manual_simulation:
				var velocity: Vector3 = slot["preview_velocity"]
				velocity += Vector3(0,-9.8,0) * delta
				var next_position: Vector3 = piece.rigid_body.global_position + velocity * delta
				if next_position.y < 0.06:
					next_position.y = 0.06
					velocity = Vector3.ZERO
				piece.rigid_body.global_position = next_position
				slot["preview_velocity"] = velocity

func reset_preview() -> void:
	_preparing = true
	controller.reset_damage()
	play_animation(animation_name)
	for slot in slots.values():
		var descriptors: Array = slot["variants"].values()
		descriptors.append(slot["base_variant"])
		for descriptor in descriptors:
			if descriptor["surface"]:
				_update_targets(slot,descriptor["surface"])
				descriptor["surface"].reset_simulation(true)
		slot["preview_velocity"] = Vector3.ZERO
	step(0.0)
	_preparing = false

func save_runtime_state() -> Dictionary:
	var saved: Dictionary = {"version":1,"controller":controller.export_state(),"animation":{"name":animation_name,"time":animation_time,"running":simulation_running},"items":{}}
	for id in slots:
		var slot: Dictionary = slots[id]
		var item: Dictionary = {"preview_velocity":_vector_array(slot["preview_velocity"])}
		if slot["piece"]: item["piece"] = _encode_piece(slot["piece"].snapshot())
		if slot["surface"]: item["surface"] = _encode_surface(slot["surface"].snapshot())
		saved["items"][str(id)] = item
	return saved

func _vector_array(value: Vector3) -> Array:
	return [value.x,value.y,value.z]

func _vectors_array(values: PackedVector3Array) -> Array:
	var result: Array = []
	for value in values: result.append(_vector_array(value))
	return result

func _encode_piece(data: Dictionary) -> Dictionary:
	var result: Dictionary = data.duplicate(true)
	for key in ["linear_velocity","angular_velocity","stored_linear_velocity","stored_angular_velocity"]: result[key] = _vector_array(data[key])
	for key in ["swing","swing_velocity"]: result[key] = [data[key].x,data[key].y]
	result["connection_points"] = _vectors_array(PackedVector3Array(data["connection_points"]))
	var pose: Transform3D = data["transform"]
	result["transform"] = [_vector_array(pose.basis.x),_vector_array(pose.basis.y),_vector_array(pose.basis.z),_vector_array(pose.origin)]
	return result

func _encode_surface(data: Dictionary) -> Dictionary:
	var edges: Array = []
	for edge in data["broken_edges"]: edges.append([edge.x,edge.y])
	return {"points":_vectors_array(data["points"]),"previous":_vectors_array(data["previous"]),"mobility":Array(data["mobility"]),"broken_edges":edges,"released_indices":data["released_indices"].keys()}

func _valid_vector(value: Variant, count: int) -> bool:
	if not value is Array or value.size() != count: return false
	for number in value:
		if typeof(number) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(number)): return false
	return true

func _decode_piece(data: Dictionary, piece: Node3D) -> Dictionary:
	var result: Dictionary = data.duplicate(true)
	if not data.get("broken") is Array or data["broken"].size() != piece.broken_connections.size() or typeof(data.get("equipped")) != TYPE_BOOL: return {}
	for broken in data["broken"]:
		if typeof(broken) != TYPE_BOOL: return {}
	for key in ["linear_velocity","angular_velocity","stored_linear_velocity","stored_angular_velocity"]:
		if not _valid_vector(data.get(key),3): return {}
		result[key] = Vector3(data[key][0],data[key][1],data[key][2])
	for key in ["swing","swing_velocity"]:
		if not _valid_vector(data.get(key),2): return {}
		result[key] = Vector2(data[key][0],data[key][1])
	if not data.get("connection_points") is Array or data["connection_points"].size() != piece.connection_points.size(): return {}
	var points: Array[Vector3] = []
	for point in data["connection_points"]:
		if not _valid_vector(point,3): return {}
		points.append(Vector3(point[0],point[1],point[2]))
	result["connection_points"] = points
	if not data.get("transform") is Array or data["transform"].size() != 4: return {}
	var vectors: Array[Vector3] = []
	for vector in data["transform"]:
		if not _valid_vector(vector,3): return {}
		vectors.append(Vector3(vector[0],vector[1],vector[2]))
	var basis: Basis = Basis(vectors[0],vectors[1],vectors[2])
	if absf(basis.determinant()) < 0.000001: return {}
	result["transform"] = Transform3D(basis,vectors[3])
	return result

func _decode_surface(data: Dictionary, surface: Node3D) -> Dictionary:
	var result: Dictionary = {}
	for key in ["points","previous"]:
		if not data.get(key) is Array or data[key].size() != surface.points.size(): return {}
		var points := PackedVector3Array()
		for point in data[key]:
			if not _valid_vector(point,3): return {}
			points.append(Vector3(point[0],point[1],point[2]))
		result[key] = points
	if not data.get("mobility") is Array or data["mobility"].size() != surface.points.size(): return {}
	var mobility := PackedFloat32Array()
	for value in data["mobility"]:
		if typeof(value) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(value)) or value < 0 or value > 1: return {}
		mobility.append(value)
	result["mobility"] = mobility
	result["broken_edges"] = {}
	result["released_indices"] = {}
	if not data.get("broken_edges") is Array or not data.get("released_indices") is Array: return {}
	for edge in data["broken_edges"]:
		if not _valid_vector(edge,2) or edge[0] != floorf(edge[0]) or edge[1] != floorf(edge[1]) or mini(edge[0],edge[1]) < 0 or maxi(edge[0],edge[1]) >= surface.points.size(): return {}
		result["broken_edges"][Vector2i(int(edge[0]),int(edge[1]))] = true
	for index in data["released_indices"]:
		if typeof(index) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(index)) or index != floorf(index) or index < 0 or index >= surface.points.size(): return {}
		result["released_indices"][int(index)] = true
	return result

func load_runtime_state(data: Dictionary) -> bool:
	if data.get("version") != 1 or not data.get("controller") is Dictionary or not data.get("items") is Dictionary or not data.get("animation") is Dictionary or data["items"].size() != slots.size(): return false
	var animation_data: Dictionary = data["animation"]
	if typeof(animation_data.get("name")) != TYPE_STRING or typeof(animation_data.get("running")) != TYPE_BOOL or typeof(animation_data.get("time")) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(animation_data["time"])) or animation_data["time"] < 0: return false
	if animation and not animation.has_animation(animation_data["name"]): return false
	var probe: Node = Controller.new()
	for slot in slots.values():
		if not probe.register_item(slot["definition"]):
			probe.free()
			return false
	if not probe.import_state(data["controller"]):
		probe.free()
		return false
	var decoded: Dictionary = {}
	for id in slots:
		if not data["items"].get(str(id)) is Dictionary:
			probe.free()
			return false
		var source: Dictionary = data["items"][str(id)]
		var item: Dictionary = {}
		if not _valid_vector(source.get("preview_velocity"),3):
			probe.free()
			return false
		item["preview_velocity"] = Vector3(source["preview_velocity"][0],source["preview_velocity"][1],source["preview_velocity"][2])
		if slots[id]["piece"]:
			item["piece"] = _decode_piece(source.get("piece",{}),slots[id]["piece"])
			if item["piece"].is_empty() or item["piece"]["equipped"] != probe.get_item_state(id)["equipped"]:
				probe.free()
				return false
		if slots[id]["surface"]:
			item["surface"] = _decode_surface(source.get("surface",{}),slots[id]["surface"])
			if item["surface"].is_empty():
				probe.free()
				return false
		decoded[id] = item
	probe.free()
	_syncing = true
	controller.import_state(data["controller"])
	_syncing = false
	play_animation(animation_data["name"])
	animation_time = float(animation_data["time"])
	if animation:
		animation.seek(animation_time,true)
		if skeleton: skeleton.force_update_all_bone_transforms()
	_loading_state = true
	_sync_state()
	for id in slots:
		var slot: Dictionary = slots[id]
		var item: Dictionary = decoded[id]
		slot["preview_velocity"] = item["preview_velocity"]
		if slot["surface"]: slot["surface"].restore(item["surface"])
		if slot["piece"]:
			slot["piece"].restore(item["piece"])
			if manual_simulation: slot["piece"].rigid_body.freeze = true
	simulation_running = animation_data["running"]
	_loading_state = false
	return true

func _capture_damage_impulse(result: Dictionary) -> void:
	var id: StringName = result["item_id"]
	if not slots.has(id): return
	var stamps: Array = controller.get_item_state(id)["regions"][result["region_id"]]["stamps"]
	var impulse: Vector3 = stamps.back().get("impulse", Vector3.ZERO) if not stamps.is_empty() else Vector3.ZERO
	slots[id]["last_impulse"] = impulse if impulse.length_squared()>0.000001 else Vector3(0.05,0.02,0.08)

func apply_hit(hit: Dictionary) -> Dictionary:
	if hit.has("item_id") and str(hit["item_id"])!="" and hit.has("uv"):
		return controller.apply_hit(hit)
	if not hit.get("position") is Vector3 or not hit.get("direction") is Vector3:
		return {"accepted":false,"reason":"world_position_and_direction_required"}
	if hit.has("item_id") and typeof(hit["item_id"]) not in [TYPE_STRING,TYPE_STRING_NAME]:
		return {"accepted":false,"reason":"invalid_item_id"}
	var resolved: Dictionary = resolve_hit(hit["position"],hit["direction"],StringName(hit.get("item_id","")))
	if not resolved.get("resolved",false): return {"accepted":false,"reason":resolved.get("reason","miss")}
	var prepared: Dictionary = hit.duplicate(true)
	for key in ["item_id","uv","position"]: prepared[key] = resolved[key]
	if not prepared.has("angle"): prepared["angle"] = resolved["angle"]
	return controller.apply_hit(prepared)

func resolve_hit(position: Vector3, direction: Vector3, item_id: StringName = &"") -> Dictionary:
	if not position.is_finite() or not direction.is_finite() or direction.length_squared()<0.00000001:
		return {"resolved":false,"reason":"invalid_world_contact"}
	if not is_finite(max_hit_distance) or max_hit_distance<=0:
		return {"resolved":false,"reason":"invalid_hit_distance"}
	var ray: Vector3 = direction.normalized()
	var origin: Vector3 = position-ray*(max_hit_distance+0.001)
	return _query_ray(origin,ray,item_id,position,max_hit_distance)

func _sample_vertex(visual: MeshInstance3D, mesh: Mesh, arrays: Array, surface_index: int, index: int) -> Vector3:
	var vertex: Vector3 = arrays[Mesh.ARRAY_VERTEX][index]
	if mesh is ArrayMesh and mesh.get_blend_shape_count()>0:
		var shapes: Array = mesh.surface_get_blend_shape_arrays(surface_index)
		for shape_index in range(mini(shapes.size(),visual.mesh.get_blend_shape_count())):
			var value: float = visual.get_blend_shape_value(shape_index)
			if is_zero_approx(value): continue
			var positions: PackedVector3Array = shapes[shape_index][Mesh.ARRAY_VERTEX]
			if index<positions.size(): vertex += (positions[index]-arrays[Mesh.ARRAY_VERTEX][index] if mesh.blend_shape_mode==Mesh.BLEND_SHAPE_MODE_NORMALIZED else positions[index])*value
	var bones: Variant = arrays[Mesh.ARRAY_BONES]
	var weights: Variant = arrays[Mesh.ARRAY_WEIGHTS]
	if visual.skin and skeleton and bones!=null and weights!=null and bones.size()==weights.size() and bones.size()>=arrays[Mesh.ARRAY_VERTEX].size()*4:
		var count: int = bones.size()/arrays[Mesh.ARRAY_VERTEX].size()
		var world := Vector3.ZERO
		var total := 0.0
		for slot in range(count):
			var bind: int = bones[index*count+slot]
			var weight: float = weights[index*count+slot]
			if weight<=0 or bind<0 or bind>=visual.skin.get_bind_count(): continue
			var bone: int = visual.skin.get_bind_bone(bind)
			var name_value: StringName = visual.skin.get_bind_name(bind)
			if name_value!=&"": bone = skeleton.find_bone(name_value)
			if bone<0 or bone>=skeleton.get_bone_count(): continue
			world += skeleton.global_transform*skeleton.get_bone_global_pose(bone)*visual.skin.get_bind_pose(bind)*vertex*weight
			total += weight
		if total>0.000001: return world/total
	return visual.global_transform*vertex

func _damage_uvs(arrays: Array) -> PackedVector2Array:
	if arrays[Mesh.ARRAY_TEX_UV2]!=null and not arrays[Mesh.ARRAY_TEX_UV2].is_empty(): return arrays[Mesh.ARRAY_TEX_UV2]
	return arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV]!=null else PackedVector2Array()

func _cut_allows_contact(slot: Dictionary, uv: Vector2) -> bool:
	var regions: Array = slot["definition"].regions.duplicate()
	regions.sort_custom(func(a: Resource,b: Resource)->bool: return str(a.id)<str(b.id))
	var strength := 0.0
	var state: Dictionary = controller.get_item_state(slot["definition"].id)
	for region in regions:
		if uv.x>=region.uv_rect.position.x and uv.y>=region.uv_rect.position.y and uv.x<=region.uv_rect.end.x and uv.y<=region.uv_rect.end.y:
			strength = region.stages[state["regions"][region.id]["stage"]].cut_strength
			break
	var alpha: float = 1.0-slot["canvas"].get_coverage(uv).r*strength
	var cutoff: Variant = slot["materials"][0].get_shader_parameter("alpha_cutoff") if not slot["materials"].is_empty() else null
	return alpha>=(0.5 if cutoff==null else float(cutoff))

func _inside_uv_triangle(point: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var ab: Vector2 = b-a
	var ac: Vector2 = c-a
	var determinant: float = ab.cross(ac)
	if absf(determinant)<0.000000000001: return false
	var u: float = (point-a).cross(ac)/determinant
	var v: float = ab.cross(point-a)/determinant
	return u>=-0.00001 and v>=-0.00001 and u+v<=1.00001

func _uv_has_geometry(mesh: Mesh, uv: Vector2) -> bool:
	for surface_index in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface_index)
		var coordinates: PackedVector2Array = _damage_uvs(arrays)
		if coordinates.is_empty(): continue
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
		if indices.is_empty():
			for index in range(coordinates.size()): indices.append(index)
		for triangle in range(0,indices.size(),3):
			if maxi(indices[triangle],maxi(indices[triangle+1],indices[triangle+2]))>=coordinates.size(): continue
			if _inside_uv_triangle(uv,coordinates[indices[triangle]],coordinates[indices[triangle+1]],coordinates[indices[triangle+2]]): return true
	return false

func _query_ray(origin: Vector3, direction: Vector3, item_id: StringName, contact: Variant=null, tolerance: float=INF) -> Dictionary:
	var candidates: Array[Dictionary] = []
	var missing_uv := false
	for id in slots:
		if item_id!=&"" and id!=item_id: continue
		var slot: Dictionary = slots[id]
		if not controller.get_item_state(id).get("equipped",false): continue
		var visual: MeshInstance3D = slot["visual"]
		var proxy: Node3D = slot["surface"]
		var mesh: Mesh = slot["definition"].proxy_mesh if proxy else slot["source_mesh"]
		for surface_index in range(mesh.get_surface_count()):
			var arrays: Array = mesh.surface_get_arrays(surface_index)
			var vertices: PackedVector3Array = proxy.points if proxy else arrays[Mesh.ARRAY_VERTEX]
			var uv: PackedVector2Array = _damage_uvs(arrays)
			if uv.size()!=vertices.size():
				missing_uv = true
				continue
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
			if indices.is_empty():
				for index in range(vertices.size()): indices.append(index)
			if indices.size()%3!=0: continue
			var world_vertices := PackedVector3Array()
			if not proxy:
				for index in range(vertices.size()): world_vertices.append(_sample_vertex(visual,mesh,arrays,surface_index,index))
			for triangle in range(0,indices.size(),3):
				var ia: int = indices[triangle]
				var ib: int = indices[triangle+1]
				var ic: int = indices[triangle+2]
				if mini(ia,mini(ib,ic))<0 or maxi(ia,maxi(ib,ic))>=vertices.size(): continue
				var a: Vector3 = vertices[ia] if proxy else world_vertices[ia]
				var b: Vector3 = vertices[ib] if proxy else world_vertices[ib]
				var c: Vector3 = vertices[ic] if proxy else world_vertices[ic]
				var point: Variant = Geometry3D.ray_intersects_triangle(origin,direction,a,b,c)
				if point==null or (contact is Vector3 and contact.distance_to(point)>tolerance): continue
				var bary: Vector3 = Geometry3D.get_triangle_barycentric_coords(point,a,b,c)
				var coordinates: Vector2 = uv[ia]*bary.x+uv[ib]*bary.y+uv[ic]*bary.z
				if not _cut_allows_contact(slot,coordinates) or (proxy and slot["variant"]!=0 and not _uv_has_geometry(slot["source_mesh"],coordinates)): continue
				var ab: Vector3 = b-a
				var ac: Vector3 = c-a
				var denominator: float = ab.length_squared()*ac.length_squared()-pow(ab.dot(ac),2)
				var attack_uv := Vector2.ZERO
				if absf(denominator)>0.000000000001:
					var u: float = (direction.dot(ab)*ac.length_squared()-direction.dot(ac)*ab.dot(ac))/denominator
					var v: float = (direction.dot(ac)*ab.length_squared()-direction.dot(ab)*ab.dot(ac))/denominator
					attack_uv = (uv[ib]-uv[ia])*u+(uv[ic]-uv[ia])*v
				candidates.append({"resolved":true,"item_id":id,"position":point,"uv":coordinates,"direction":direction,"angle":atan2(attack_uv.y,attack_uv.x) if attack_uv.length_squared()>0.00000001 else 0.0,"distance":origin.distance_squared_to(point)})
	if candidates.is_empty(): return {"resolved":false,"reason":"missing_uv" if missing_uv else "miss"}
	candidates.sort_custom(func(a: Dictionary,b: Dictionary)->bool:
		if not is_equal_approx(a["distance"],b["distance"]): return a["distance"]<b["distance"]
		return str(a["item_id"])<str(b["item_id"])
	)
	return candidates[0]

func pick(camera: Camera3D, screen: Vector2, item_id: StringName=&"") -> Dictionary:
	var result: Dictionary = _query_ray(camera.project_ray_origin(screen),camera.project_ray_normal(screen),item_id)
	return result if result.get("resolved",false) else {}
