extends SceneTree
const Rig = preload("res://addons/aero_cloth_3d/core/aero_wearable_rig.gd")
const Factory = preload("res://addons/aero_cloth_3d/core/aero_example_factory.gd")
const Outfit = preload("res://addons/aero_cloth_3d/resources/aero_outfit.gd")
const Definition = preload("res://addons/aero_cloth_3d/resources/aero_wearable_definition.gd")
const MaskJob = preload("res://addons/aero_cloth_3d/core/aero_mask_job.gd")
var checks: int = 0
var failures: Array[String] = []
var rigs: Array[Node3D] = []
func _initialize() -> void: call_deferred("run")
func expect(condition: bool, description: String) -> void:
	checks+=1
	if not condition:
		failures.append(description)
		push_error(description)
func make_rig(recipe: Resource, manual: bool=false) -> Node3D:
	var rig: Node3D=Rig.new()
	rig.manual_simulation=manual
	rig.simulation_running=false
	root.add_child(rig)
	rigs.append(rig)
	expect(rig.load_outfit(recipe).is_empty(),"Mask fixture binds before entering asynchronous gameplay")
	return rig
func event(item: StringName, region: StringName, amount: float, id: String) -> Dictionary:
	return {"item_id":item,"region_id":region,"uv":Vector2(.45,.35),"amount":amount,"type":"cut","hit_id":id,"seed":73}
func busy(rig: Node3D) -> bool:
	for slot in rig.slots.values():
		if slot["mask_task"]>=0: return true
	return false
func settle(rig: Node3D) -> bool:
	var deadline: int=Time.get_ticks_usec()+3000000
	while busy(rig) and Time.get_ticks_usec()<deadline: await process_frame
	return not busy(rig)
func run() -> void:
	var cancelled_job: RefCounted=MaskJob.new()
	cancelled_job.configure({"generation":1,"recipes":[],"stamps":[]},512)
	cancelled_job.request_cancel()
	cancelled_job.run()
	expect(cancelled_job.result.get("cancelled",false) and not cancelled_job.result.has("image"),"Cancelled worker stops before allocating or publishing images")
	var queued_job: RefCounted=MaskJob.new()
	var queued_stamps: Array = []
	for index in range(40): queued_stamps.append({"uv":Vector2(.5,.5),"type":"cut","amount":30,"seed":index})
	queued_job.configure({"generation":2,"recipes":[],"stamps":queued_stamps},512)
	var task: int=WorkerThreadPool.add_task(queued_job.run)
	queued_job.request_cancel()
	var cancel_deadline: int=Time.get_ticks_usec()+3000000
	while not WorkerThreadPool.is_task_completed(task) and Time.get_ticks_usec()<cancel_deadline: await process_frame
	var cancellation_finished: bool=WorkerThreadPool.is_task_completed(task)
	if cancellation_finished: WorkerThreadPool.wait_for_task_completion(task)
	expect(cancellation_finished and queued_job.result.get("cancelled",false) and not queued_job.result.has("image"),"WorkerThreadPool cancellation ends obsolete work without producing publishable images")
	var recipe: Resource=Factory.create()
	var rig: Node3D=make_rig(recipe)
	var reference: Node3D=make_rig(recipe,true)
	expect(rig.async_runtime_masks and not busy(rig),"Default gameplay enables async masks while initial load remains synchronous")
	var slot: Dictionary=rig.slots[&"jacket"]
	var image_before: PackedByteArray=slot["canvas"].image.get_data()
	var texture_id: int=slot["canvas"].texture.get_instance_id()
	var height_id: int=slot["canvas"].height_texture.get_instance_id()
	rig.apply_hit(event(&"jacket",&"body",12,"first"))
	rig.apply_hit(event(&"jacket",&"body",73,"second"))
	expect(rig.controller.get_item_state(&"jacket")["regions"][&"body"]["stage"]==4,"Damage stage and physical release commit immediately before cosmetic painting")
	expect(slot["mask_task"]>=0 and slot["mask_started_jobs"]==1 and slot["mask_generation"]==2,"Two rapid contacts keep one active worker and coalesce the latest generation")
	expect(slot["applied_stamps"].is_empty() and slot["canvas"].image.get_data()==image_before,"Combat returns before main-thread mask publication and keeps the visible CPU mask")
	expect(await settle(rig),"Latest-generation masks finish within a bounded three-second test window")
	expect(slot["mask_discarded_jobs"]>=1 and slot["mask_started_jobs"]==2,"Stale completion is discarded before one replacement worker starts")
	expect(slot["mask_published_generation"]==2 and slot["applied_stamps"].size()==2,"Only the latest complete generation becomes published state")
	reference.apply_hit(event(&"jacket",&"body",12,"first"))
	reference.apply_hit(event(&"jacket",&"body",73,"second"))
	expect(slot["canvas"].image.get_data()==reference.slots[&"jacket"]["canvas"].image.get_data() and slot["canvas"].height_image.get_data()==reference.slots[&"jacket"]["canvas"].height_image.get_data(),"Worker result exactly matches synchronous manual recipe and hit replay")
	expect(slot["canvas"].texture.get_instance_id()==texture_id and slot["canvas"].height_texture.get_instance_id()==height_id,"Main-thread publication keeps bound texture identities stable")
	# Reuse only the published checkpoint: two newer contacts discard their first
	# worker, but the replacement must still start after the last published hit.
	var published_image: Image=slot["canvas"].image
	var published_pixels: PackedByteArray=published_image.get_data()
	var next_hit: Dictionary=event(&"jacket",&"body",1,"checkpoint-third")
	next_hit["uv"]=Vector2(.7,.7)
	rig.apply_hit(next_hit)
	var first_checkpoint_job: RefCounted=slot["mask_job"]
	var fourth_hit: Dictionary=event(&"jacket",&"body",1,"checkpoint-fourth")
	fourth_hit["uv"]=Vector2(.8,.65)
	rig.apply_hit(fourth_hit)
	expect(first_checkpoint_job.incremental and first_checkpoint_job.first_stamp==2 and first_checkpoint_job.checkpoint["image"].get_instance_id()!=published_image.get_instance_id(),"Worker owns an independent Image checkpoint and replays only newly appended stamps")
	expect(await settle(rig),"Coalesced incremental checkpoint work publishes within the bounded window")
	reference.apply_hit(next_hit)
	reference.apply_hit(fourth_hit)
	expect(slot["mask_last_job_incremental"] and slot["mask_last_first_stamp"]==2 and slot["applied_stamps"].size()==4 and slot["canvas"].image.get_data()==reference.slots[&"jacket"]["canvas"].image.get_data() and slot["canvas"].height_image.get_data()==reference.slots[&"jacket"]["canvas"].height_image.get_data(),"Replacement worker uses the published checkpoint, never stale work, and matches canonical mask/height pixels")
	expect(published_image.get_data()==published_pixels,"Painting an owned worker checkpoint cannot mutate the previously published source Image")
	var snapshot: Dictionary=JSON.parse_string(JSON.stringify(rig.save_runtime_state()))
	var final_image: PackedByteArray=slot["canvas"].image.get_data()
	var notifications: Dictionary={"damage":0,"stage":0,"break":0}
	rig.controller.damage_applied.connect(func(_result: Dictionary)->void: notifications["damage"]+=1)
	rig.controller.stage_changed.connect(func(_item: StringName,_region: StringName,_old: int,_new: int)->void: notifications["stage"]+=1)
	rig.controller.attachment_broken.connect(func(_item: StringName,_region: StringName,_index: int)->void: notifications["break"]+=1)
	rig.apply_hit(event(&"jacket",&"body",1,"pending-before-load"))
	var before_load: Dictionary=notifications.duplicate()
	expect(rig.load_runtime_state(snapshot) and slot["canvas"].image.get_data()==final_image,"Runtime load invalidates pending work and restores masks synchronously")
	expect(notifications==before_load,"Load remains quiet for damage and attachment gameplay notifications")
	expect(await settle(rig) and slot["canvas"].image.get_data()==final_image,"Discarded pre-load worker cannot overwrite restored masks later")
	var reset_hit: Dictionary=event(&"jacket",&"body",1,"checkpoint-before-reset")
	reset_hit["uv"]=Vector2(.75,.75)
	rig.apply_hit(reset_hit)
	var reset_job: RefCounted=slot["mask_job"]
	rig.apply_hit(event(&"shirt",&"upper",22,"pending-before-reset"))
	rig.reset_preview()
	expect(slot["applied_stamps"].is_empty() and rig.slots[&"shirt"]["applied_stamps"].is_empty(),"Reset publishes the initial recipe synchronously even while painting is in flight")
	expect(await settle(rig) and rig.controller.get_item_state(&"shirt")["regions"][&"upper"]["damage"]==0.0,"Reset cancels cosmetic generations while preserving repaired gameplay state")
	var reset_private: bool = reset_job.result.get("cancelled",false) or (reset_job.result.has("image") and reset_job.result["image"].get_pixel(int(.45*512),int(.35*512)).r>0.0 and reset_job.result["image"].get_instance_id()!=slot["canvas"].image.get_instance_id())
	expect(slot["canvas"].get_coverage(Vector2(.45,.35)).r==0.0 and reset_private,"Reset cancels obsolete work or discards its independent result without repainting")
	# Exercise the actual six-contact workload without timing assertions tied to hardware.
	var group: Array[Node3D]=[rig,make_rig(recipe),make_rig(recipe)]
	var begin: int=Time.get_ticks_usec()
	for index in range(group.size()):
		group[index].apply_hit(event(&"jacket",&"body",85,"six_jacket_"+str(index)))
		group[index].apply_hit(event(&"shirt",&"upper",85,"six_shirt_"+str(index)))
	var call_ms: float=(Time.get_ticks_usec()-begin)/1000.0
	var queued:=0
	for actor in group:
		for id in [&"jacket",&"shirt"]:
			if actor.slots[id]["mask_task"]>=0 and actor.slots[id]["mask_published_generation"]!=actor.slots[id]["mask_generation"]: queued+=1
	expect(queued==6,"All six synchronous combat calls queue cosmetics instead of publishing images in the caller")
	for actor in group: expect(await settle(actor),"Simultaneous character masks eventually publish their latest results")
	print("ASYNC_SIX_CONTACT_CALL_MS ",call_ms," (diagnostic, not a target-hardware guarantee)")
	# Destroying the scene hands only RefCounted worker state to an orphan reaper.
	var isolated: Resource=Outfit.new()
	var definition: Resource=Definition.make_example(&"orphan",&"rigid")
	definition.source_scene=Factory.pack_mesh(Factory.panel(.5,.5))
	definition.connection_points=PackedVector3Array([Vector3.ZERO])
	for index in range(1,5): definition.regions[0].stages[index].damage_recipe=Factory.recipe("cut",Vector2(.5,.5),.2,90+index)
	isolated.items.append(definition)
	var orphan: Node3D=make_rig(isolated)
	orphan.apply_hit(event(&"orphan",&"body",85,"orphan-hit"))
	var job: RefCounted=orphan.slots[&"orphan"]["mask_job"]
	var weak: WeakRef=weakref(orphan)
	orphan.queue_free()
	await process_frame
	await process_frame
	expect(weak.get_ref()==null,"Scene unload does not wait for or retain a painting scene node")
	var deadline: int=Time.get_ticks_usec()+3000000
	while job._orphan_id>=0 and Time.get_ticks_usec()<deadline: await process_frame
	expect(job._orphan_id<0,"Detached worker task is cleaned up by a RefCounted main-loop reaper without Node callbacks")
	for actor in rigs:
		if is_instance_valid(actor): actor.queue_free()
	await process_frame
	print("ASYNC_MASK_TESTS: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
