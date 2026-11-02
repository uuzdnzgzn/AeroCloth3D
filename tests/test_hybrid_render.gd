extends SceneTree
const Cloth = preload("res://demo/test_cloth.gd")
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("This parity test requires a real rendering driver")
		quit(1)
		return
	var view := SubViewport.new()
	view.size = Vector2i(256,256)
	view.own_world_3d = true
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var cloth := Cloth.new()
	view.add_child(cloth)
	cloth.running = false
	for i in range(99): cloth.points[i] += Vector3(sin(i*.3)*.025,cos(i*.25)*.02,sin(i*.11)*.07)
	cloth._upload()
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = .8
	view.add_child(camera)
	camera.position = Vector3(0,-.28,1)
	camera.look_at(Vector3(0,-.28,0))
	await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var gpu: Image = view.get_texture().get_image()
	cloth.gpu_deformation = false
	cloth._upload()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var cpu: Image = view.get_texture().get_image()
	var differences := 0
	var covered := 0
	for y in range(256):
		for x in range(256):
			var a: bool = gpu.get_pixel(x,y).a>.5
			var b: bool = cpu.get_pixel(x,y).a>.5
			if a: covered += 1
			if a != b: differences += 1
	gpu.save_png("res://artifacts/hybrid-parity-gpu.png")
	cpu.save_png("res://artifacts/hybrid-parity-cpu.png")
	var valid: bool = covered>1000 and differences<covered*.01
	print("HYBRID_RENDER_PARITY: covered=%d differing_pixels=%d passed=%s" % [covered,differences,valid])
	view.queue_free()
	await process_frame
	quit(0 if valid else 1)
