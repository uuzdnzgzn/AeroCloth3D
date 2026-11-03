extends SceneTree
## Measures the exported runtime path, not a second demo-only damage implementation.
const Rig=preload("res://addons/aero_cloth_3d/core/aero_wearable_rig.gd")
const Factory=preload("res://addons/aero_cloth_3d/core/aero_example_factory.gd")
var rigs:Array[Node3D]=[]
var frame:=0
var last_tick:=0
var times:Array[float]=[]
var events:Array[Dictionary]=[]
var output:="res://artifacts/authoring-benchmark.json"
var max_frames:=720
var begun:=false
func _initialize() -> void:call_deferred("setup")
func setup() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):output=argument.trim_prefix("--report=")
	root.size=Vector2i(1440,900)
	var world:=Node3D.new()
	root.add_child(world)
	var environment:=WorldEnvironment.new()
	var settings:=Environment.new()
	settings.background_mode=Environment.BG_COLOR
	settings.background_color=Color("101c2b")
	settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color=Color("bdcce0")
	settings.ambient_light_energy=.5
	environment.environment=settings
	world.add_child(environment)
	var light:=DirectionalLight3D.new()
	light.rotation_degrees=Vector3(-35,-25,0)
	world.add_child(light)
	var floor_body:=StaticBody3D.new()
	var floor_shape:=CollisionShape3D.new()
	var floor_box:=BoxShape3D.new()
	floor_box.size=Vector3(20,.1,20)
	floor_shape.shape=floor_box
	floor_body.add_child(floor_shape)
	floor_body.position.y=-.05
	world.add_child(floor_body)
	var camera:=Camera3D.new()
	camera.fov=40
	world.add_child(camera)
	camera.position=Vector3(-1,2,5.7)
	camera.look_at(Vector3(1.1,1,0))
	var recipe:Resource=Factory.create()
	for i in range(3):
		var rig:Node3D=Rig.new()
		rig.position.x=i*1.15
		world.add_child(rig)
		var errors:PackedStringArray=rig.load_outfit(recipe)
		if not errors.is_empty():push_error(" · ".join(errors));quit(1);return
		rig.play_animation("Walk")
		rigs.append(rig)
	last_tick=Time.get_ticks_usec()
	begun=true
func _process(_delta:float) -> bool:
	if not begun:return false
	frame+=1
	var now:int=Time.get_ticks_usec()
	var elapsed:float=(now-last_tick)/1000.0
	last_tick=now
	if frame>120:times.append(elapsed)
	for event in events:
		if event.has("mask_publish_latency_ms"):continue
		var ready:=true
		for i in range(rigs.size()):
			for id in [&"jacket",&"shirt"]:
				if rigs[i].slots[id]["mask_published_generation"]<event["generations"][i][str(id)]:ready=false
		if ready:event["mask_publish_latency_ms"]=(now-event["wall_start_usec"])/1000.0
	if frame in [150,330,510]:
		for rig in rigs:rig.reset_preview()
	if frame in [180,210,240,270,360,390,420,450,540,570,600,630]:
		var start:int=Time.get_ticks_usec()
		for i in range(3):
			rigs[i].apply_hit({"hit_id":str(frame),"item_id":"jacket","region_id":"body","uv":Vector2(.45,.5),"amount":22.0,"type":"slash","seed":frame})
			rigs[i].apply_hit({"hit_id":"cloth_"+str(frame),"item_id":"shirt","region_id":"upper","uv":Vector2(.45,.25),"amount":22.0,"type":"slash","seed":frame})
		var duration:float=(Time.get_ticks_usec()-start)/1000.0
		var generations:Array=[]
		for rig in rigs:generations.append({"jacket":rig.slots[&"jacket"]["mask_generation"],"shirt":rig.slots[&"shirt"]["mask_generation"]})
		events.append({"frame":frame,"wall_start_usec":start,"generations":generations,"call_ms":duration,"synchronous_item_hits":6,"stage":rigs[0].controller.get_item_state(&"jacket")["regions"][&"body"]["stage"]})
	if frame>=max_frames:
		var ordered:Array[float]=times.duplicate()
		ordered.sort()
		var sum:=0.0
		for value in times:sum+=value
		for event in events:
			var window:Array[float]=[]
			for index in range(maxi(0,event["frame"]-123),mini(times.size(),event["frame"]-115)):window.append(times[index])
			event["window_ms_minus2_plus5"]=window
			event["window_max_ms"]=window.max()
			event.erase("wall_start_usec")
			event.erase("generations")
		var data:Dictionary={"version":"0.3-authoring","engine":Engine.get_version_info(),"renderer":RenderingServer.get_video_adapter_name(),"headless":DisplayServer.get_name()=="headless","characters":3,"warmup_frames":120,"frames":times.size(),"mean_frame_ms":sum/times.size(),"p95_frame_ms":ordered[int(ceil(times.size()*.95))-1],"p99_frame_ms":ordered[int(ceil(times.size()*.99))-1],"max_frame_ms":ordered[-1],"events":events,"raw_frame_ms":times,"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"static_memory_bytes":Performance.get_monitor(Performance.MEMORY_STATIC),"limitations":"Software driver/headless container is not target GPU or 60FPS approval. 12 synchronous three-character hits; recipe masks, stage model changes, layer release and rigid pieces included. Real-time physics scheduling; engine catch-up is included."}
		var file:=FileAccess.open(output,FileAccess.WRITE)
		data["async_cosmetic_masks"]=true
		data["gpu_height_normals"]=true
		data["pending_masks_at_end"]=0
		data["mask_job_stats"]=[]
		for rig in rigs:
			for slot in rig.slots.values():
				if slot["mask_task"]>=0:data["pending_masks_at_end"]+=1
				data["mask_job_stats"].append({"item":str(slot["definition"].id),"incremental":slot["mask_incremental_jobs"],"full":slot["mask_full_jobs"]})
		if file:file.store_string(JSON.stringify(data,"\t"))
		data.erase("raw_frame_ms")
		print("AUTHORING_BENCHMARK ",JSON.stringify(data))
		quit()
	return false
