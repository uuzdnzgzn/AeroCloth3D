extends SceneTree
const Rig = preload("res://addons/aero_cloth_3d/core/aero_wearable_rig.gd")
const Factory = preload("res://addons/aero_cloth_3d/core/aero_example_factory.gd")
const Definition = preload("res://addons/aero_cloth_3d/resources/aero_wearable_definition.gd")
const Outfit = preload("res://addons/aero_cloth_3d/resources/aero_outfit.gd")
const Canvas = preload("res://addons/aero_cloth_3d/core/aero_damage_canvas.gd")
var checks: int = 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func expect(condition: bool, message: String) -> void:
	checks+=1
	if not condition:
		failures.append(message)
		push_error(message)
func item(id: StringName) -> Resource:
	var definition: Resource=Definition.make_example(id,&"rigid")
	definition.source_scene=Factory.pack_mesh(Factory.panel(.5,.5,3,3))
	definition.connection_points=PackedVector3Array([Vector3.ZERO])
	definition.mask_resolution=128
	return definition
func fresh_matches(rig: Node3D, slot: Dictionary) -> bool:
	var fresh: RefCounted=Canvas.new()
	fresh.initialize(slot["definition"].mask_resolution)
	fresh.gpu_normal_preview=true
	for recipe in slot["applied_recipes"]: rig._replay_recipe(fresh,recipe)
	for stamp in slot["applied_stamps"]: rig._runtime_stamp(fresh,stamp)
	fresh.flush()
	return fresh.image.get_data()==slot["canvas"].image.get_data() and fresh.height_image.get_data()==slot["canvas"].height_image.get_data()
func run() -> void:
	var outfit: Resource=Outfit.new()
	var target: Resource=item(&"target")
	var untouched: Resource=item(&"untouched")
	for index in range(1,5): target.regions[0].stages[index].damage_recipe=Factory.recipe("cut",Vector2(.5,.5),.04+.035*index,17+index)
	outfit.items.assign([target,untouched])
	var rig: Node3D=Rig.new()
	rig.manual_simulation=true
	root.add_child(rig)
	expect(rig.load_outfit(outfit).is_empty(),"Runtime mask cache fixture loads")
	var slot: Dictionary=rig.slots[&"target"]
	var other: Dictionary=rig.slots[&"untouched"]
	var canvas: RefCounted=slot["canvas"]
	var texture_id: int=canvas.texture.get_instance_id()
	var height_id: int=canvas.height_texture.get_instance_id()
	expect(canvas.gpu_normal_preview and slot["materials"][0].get_shader_parameter("use_damage_height"),"Runtime rig enables GPU height-normal preview")
	expect(slot["materials"][0].get_shader_parameter("damage_height")==canvas.height_texture,"Runtime material receives the authoritative height texture")
	var untouched_flushes: int=other["canvas"].flush_count
	var expected_flushes: int=canvas.flush_count
	for index in range(3):
		var result: Dictionary=rig.apply_hit({"item_id":"target","region_id":"body","uv":Vector2(.5,.5),"amount":[12,16,25][index],"hit_id":"cache_"+str(index),"type":"cut","seed":37+index})
		expect(result["accepted"],"Incremental gameplay hit advances the prepared mask")
		expected_flushes+=1
		expect(canvas.flush_count==expected_flushes and other["canvas"].flush_count==untouched_flushes,"Only the damaged slot uploads one texture batch")
		expect(slot["mask_full_rebuilds"]==0,"Append-only cut recipes and hits do not clear or replay old operations")
		expect(fresh_matches(rig,slot),"Incremental mask and height pixels exactly match canonical fresh replay")
	var before_flush: int=canvas.flush_count
	rig._sync_state()
	rig.controller.unequip(&"untouched")
	rig.controller.equip(&"untouched")
	expect(canvas.flush_count==before_flush and other["canvas"].flush_count==untouched_flushes,"Unchanged masks survive visibility and redundant sync without uploads")
	var full_rebuilds: int=slot["mask_full_rebuilds"]
	target.regions[0].stages[4].damage_recipe=Factory.recipe("grow",Vector2(.5,.5),.22,91)
	rig.controller.set_preview_stage(&"target",&"body",4)
	expect(slot["mask_full_rebuilds"]==full_rebuilds+1,"A newly authored filter before existing hit stamps forces canonical replay")
	expect(fresh_matches(rig,slot),"Order-sensitive filter replay preserves exact mask and height results")
	full_rebuilds=slot["mask_full_rebuilds"]
	rig.controller.set_preview_stage(&"target",&"body",1)
	expect(slot["mask_full_rebuilds"]==full_rebuilds+1 and fresh_matches(rig,slot),"Backward preview repairs non-prefix state by rebuilding the canonical canvas")
	full_rebuilds=slot["mask_full_rebuilds"]
	target.regions[0].stages[1].damage_recipe["operations"][0]["radius"]+=.01
	rig._sync_state()
	expect(slot["mask_full_rebuilds"]==full_rebuilds+1 and fresh_matches(rig,slot),"Deep value snapshots detect in-place authoring recipe edits")
	expect(canvas.texture.get_instance_id()==texture_id and canvas.height_texture.get_instance_id()==height_id,"Incremental and repair paths retain GPU texture identities")
	var saved: Dictionary=JSON.parse_string(JSON.stringify(rig.save_runtime_state()))
	var image_before: PackedByteArray=canvas.image.get_data()
	rig.reset_preview()
	expect(rig.load_runtime_state(saved) and canvas.image.get_data()==image_before,"Incremental runtime mask survives JSON restore through canonical state")
	expect(other["canvas"].flush_count==untouched_flushes,"Every operation leaves unrelated blank canvases untouched")
	rig.queue_free()
	await process_frame
	print("RUNTIME_MASK_CACHE_TESTS: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
