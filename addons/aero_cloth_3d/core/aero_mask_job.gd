class_name AeroMaskJob
extends RefCounted
## Worker owns CPU-only images and value snapshots; never touches a scene node,
## authoring Resource, GPU object or the live canvas. Publication is main-thread only.
const Canvas = preload("res://addons/aero_cloth_3d/core/aero_damage_canvas.gd")
var generation: int = 0
var resolution: int = 512
var recipes: Array = []
var stamps: Array = []
var result: Dictionary = {}
var incremental: bool = false
var first_recipe: int = 0
var first_stamp: int = 0
var checkpoint: Dictionary = {}
var _cancel_mutex := Mutex.new()
var _cancel_requested := false
var _orphan_id: int = -1
var _orphan_tree: SceneTree

func configure(snapshot: Dictionary, size: int) -> void:
	generation=snapshot["generation"]
	resolution=size
	recipes=snapshot["recipes"].duplicate(true)
	stamps=snapshot["stamps"].duplicate(true)
	incremental=snapshot.get("incremental",false)
	first_recipe=snapshot.get("first_recipe",0)
	first_stamp=snapshot.get("first_stamp",0)
	# Images were duplicated on the main thread and now belong only to this job.
	checkpoint=snapshot.get("checkpoint",{})

func run() -> void:
	if _stop_if_cancelled(): return
	var canvas: RefCounted=Canvas.new()
	canvas.cpu_only=true
	canvas.gpu_normal_preview=true
	if incremental:
		for key in ["image","height_image","dent_image"]:
			if not checkpoint.get(key) is Image or checkpoint[key].get_width()!=resolution or checkpoint[key].get_height()!=resolution:
				result={"error":"Invalid private CPU checkpoint"}
				return
		canvas.size=resolution
		canvas.image=checkpoint["image"]
		canvas.height_image=checkpoint["height_image"]
		canvas._dent_image=checkpoint["dent_image"]
		canvas.operations.assign(checkpoint["operations"])
	else:
		canvas.initialize(resolution)
	for recipe_index in range(first_recipe,recipes.size()):
		var recipe: Dictionary=recipes[recipe_index]
		if recipe.is_empty(): continue
		if recipe.get("format","")!="aero_damage_canvas" or recipe.get("version",0)!=1 or not recipe.get("operations") is Array:
			result={"error":"Invalid authored recipe"}
			return
		for source in recipe["operations"]:
			if _stop_if_cancelled(): return
			if not source is Dictionary:
				result={"error":"Invalid authored operation"}
				return
			var operation: Dictionary=canvas._validate_operation(source)
			if operation.is_empty():
				result={"error":"Invalid authored operation"}
				return
			var uv:=Vector2(operation["uv"][0],operation["uv"][1])
			if not canvas.stamp(uv,StringName(operation["brush"]),operation["radius"],operation["strength"],operation["angle"],operation["seed"],operation["erase"]):
				result={"error":"Authored operation limit exceeded"}
				return
	for stamp_index in range(first_stamp,stamps.size()):
		if _stop_if_cancelled(): return
		var stamp: Dictionary=stamps[stamp_index]
		var type_value: String=str(stamp.get("type","cut"))
		var kind: StringName=&"cut" if type_value in ["slash","cut","pierce"] else (&"burn" if type_value in ["burn","fire"] else (&"wear" if type_value in ["wear","abrasion"] else (&"blood" if type_value=="blood" else &"dent")))
		if not canvas.stamp(stamp["uv"],kind,.045+minf(float(stamp.get("amount",10)),80)*.001,.95,float(stamp.get("angle",0)),int(stamp.get("seed",0))):
			result={"error":"Runtime operation limit exceeded"}
			return
	if _stop_if_cancelled(): return
	canvas.flush()
	result=canvas.export_cpu_result()

func request_cancel() -> void:
	_cancel_mutex.lock()
	_cancel_requested = true
	_cancel_mutex.unlock()

func _stop_if_cancelled() -> bool:
	_cancel_mutex.lock()
	var cancelled := _cancel_requested
	_cancel_mutex.unlock()
	if cancelled: result={"cancelled":true}
	return cancelled

func orphan_task(task_id: int, tree: SceneTree) -> void:
	# Scene unload never waits on painting. A RefCounted main-loop reaper owns the
	# finished task until it can release WorkerThreadPool bookkeeping without blocking.
	request_cancel()
	_orphan_id=task_id
	_orphan_tree=tree
	if not tree.process_frame.is_connected(_poll_orphan): tree.process_frame.connect(_poll_orphan)

func _poll_orphan() -> void:
	if _orphan_id<0 or not WorkerThreadPool.is_task_completed(_orphan_id): return
	WorkerThreadPool.wait_for_task_completion(_orphan_id)
	_orphan_id=-1
	if is_instance_valid(_orphan_tree) and _orphan_tree.process_frame.is_connected(_poll_orphan): _orphan_tree.process_frame.disconnect(_poll_orphan)
	_orphan_tree=null
	result={}
