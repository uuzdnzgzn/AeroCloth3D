extends SceneTree
const Cloth = preload("res://demo/test_cloth.gd")
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var cloth := Cloth.new()
	root.add_child(cloth)
	cloth.running = false
	check(cloth.points.size()==99,"CPU proxy remains 99 points")
	check(cloth.visual_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()==1353,"GPU visual has 1353 vertices")
	var mesh_id: int = cloth.mesh.get_instance_id()
	var texture_id: int = cloth.proxy_texture.get_instance_id()
	for k in range(10):
		cloth.points[45] += Vector3(.001,.002,.003)
		cloth._upload()
	check(cloth.mesh.get_instance_id()==mesh_id and cloth.mesh_build_count==1,"No mesh recreation in normal GPU updates")
	check(cloth.proxy_texture.get_instance_id()==texture_id,"Texture identity is stable")
	for uv in [Vector2.ZERO,Vector2.ONE,Vector2(.23,.37),Vector2(.9,.02),Vector2(.04,.09)]:
		var sample: Dictionary = cloth.sample_surface(uv)
		check(sample["normal"].is_finite() and sample["position"].is_finite(),"Triangle sampling finite at boundary/interior")
	for i in range(99):
		var data: Color = cloth.proxy_image.get_pixel(i%9,i/9)
		if not Vector3(data.r,data.g,data.b).is_equal_approx(cloth.to_local(cloth.points[i])):
			check(false,"Uploaded positions equal CPU world-to-local transform")
	check(cloth.custom_aabb.has_point(cloth.to_local(cloth.points[45])),"Deformed bounds include displaced proxy")
	cloth.gpu_deformation = false
	cloth._upload()
	var arrays: Array = cloth.mesh.surface_get_arrays(0)
	for i in [0,32,500,1352]:
		check((arrays[Mesh.ARRAY_VERTEX][i] as Vector3).is_equal_approx(cloth.to_local(cloth.sample_surface(cloth.visual_uvs[i])["position"])),"CPU reference shares triangle binding")
	cloth.gpu_deformation = true
	cloth._upload()
	check(cloth.mesh==cloth.visual_mesh,"GPU backend restored without rebinding visual topology")
	cloth.queue_free()
	await process_frame
	print("HYBRID_TESTS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
