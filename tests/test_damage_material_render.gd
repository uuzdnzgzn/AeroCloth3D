extends SceneTree
## Requires an actual GL driver (e.g. DISPLAY=:99). Tests rendered alpha holes,
## UV2 selection, source albedo and source/damage normal responses on a mesh.
const Canvas = preload("res://addons/aero_cloth_3d/core/aero_damage_canvas.gd")
const DamageShader = preload("res://addons/aero_cloth_3d/shaders/aero_damage_material.gdshader")
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error(description)

func capture(view: SubViewport) -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return view.get_texture().get_image()

func normal_texture(color: Color) -> ImageTexture:
	var image: Image = Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Damage material render test requires a real rendering driver")
		quit(1)
		return
	var view: SubViewport = SubViewport.new()
	view.size = Vector2i(256, 256)
	view.own_world_3d = true
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var environment: WorldEnvironment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.15
	view.add_child(environment)
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-15, -40, 0)
	light.light_energy = 1.5
	view.add_child(light)
	var geometry: MeshInstance3D = MeshInstance3D.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-0.9,-0.9,0),Vector3(0.9,-0.9,0),Vector3(0.9,0.9,0),Vector3(-0.9,0.9,0)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.FORWARD * -1,Vector3.FORWARD * -1,Vector3.FORWARD * -1,Vector3.FORWARD * -1])
	arrays[Mesh.ARRAY_TANGENT] = PackedFloat32Array([1,0,0,-1,1,0,0,-1,1,0,0,-1,1,0,0,-1])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0,1),Vector2(1,1),Vector2(1,0),Vector2(0,0)])
	# UV2 is mirrored horizontally, so a left authored hole must move right.
	arrays[Mesh.ARRAY_TEX_UV2] = PackedVector2Array([Vector2(1,1),Vector2(0,1),Vector2(0,0),Vector2(1,0)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0,2,1,0,3,2])
	geometry.mesh = ArrayMesh.new()
	geometry.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var canvas = Canvas.new()
	canvas.initialize(128)
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = DamageShader
	material.set_shader_parameter("tint", Color(0.55, 0.55, 0.55))
	material.set_shader_parameter("mask_texture", canvas.texture)
	material.set_shader_parameter("damage_normal", canvas.normal_texture)
	geometry.material_override = material
	view.add_child(geometry)
	var camera: Camera3D = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.2
	view.add_child(camera)
	camera.position = Vector3(0, 0, 2)
	camera.look_at(Vector3.ZERO)
	await process_frame
	var baseline: Image = await capture(view)
	expect(baseline.get_pixel(128,128).a > 0.95 and baseline.get_pixel(128,128).r > 0.1, "Actual shader renders an opaque lit base surface")
	material.set_shader_parameter("mask_texture", null)
	var no_mask: Image = await capture(view)
	expect(absf(no_mask.get_pixel(128,128).r - baseline.get_pixel(128,128).r) < 0.01, "Unassigned semantic mask defaults to transparent zero damage, including zero blood")
	material.set_shader_parameter("mask_texture", canvas.texture)
	canvas.stamp(Vector2(0.3,0.5), &"cut", 0.2, 1.0)
	canvas.flush()
	var cut: Image = await capture(view)
	expect(cut.get_pixel(86,128).a < 0.05 and cut.get_pixel(170,128).a > 0.95, "Cut mask renders an actual alpha-scissored hole and retains intact geometry")
	material.set_shader_parameter("use_damage_uv2", true)
	var second_uv: Image = await capture(view)
	expect(second_uv.get_pixel(86,128).a > 0.95 and second_uv.get_pixel(170,128).a < 0.05, "UV2 damage selection moves the rendered hole independently of UV0")
	material.set_shader_parameter("use_damage_uv2", false)
	canvas.stamp(Vector2(0.7,0.5), &"cut", 0.2, 1.0)
	canvas.flush()
	var both_cuts: Image = await capture(view)
	expect(both_cuts.get_pixel(86,128).a < 0.05 and both_cuts.get_pixel(170,128).a < 0.05, "Both regions contain the same authored full-strength cut mask")
	var region_rects: PackedVector4Array = PackedVector4Array()
	var region_a: PackedVector4Array = PackedVector4Array()
	var region_b: PackedVector4Array = PackedVector4Array()
	region_rects.resize(16)
	region_a.resize(16)
	region_b.resize(16)
	region_rects[0] = Vector4(0, 0, 0.5, 1)
	region_rects[1] = Vector4(0.5, 0, 0.5, 1)
	region_a[0] = Vector4(1, 1, 1, 1)
	region_b[0] = Vector4(1, 0, 0, 0)
	material.set_shader_parameter("damage_region_count", 2)
	material.set_shader_parameter("damage_region_rects", region_rects)
	material.set_shader_parameter("damage_region_strength_a", region_a)
	material.set_shader_parameter("damage_region_strength_b", region_b)
	var region_stage: Image = await capture(view)
	expect(region_stage.get_pixel(86,128).a < 0.05 and region_stage.get_pixel(170,128).a > 0.95, "A later cut stage in one region never cuts an intact region sharing the material")
	material.set_shader_parameter("damage_region_count", 1)
	var unmatched: Image = await capture(view)
	expect(unmatched.get_pixel(170,128).a > 0.95, "Texels outside every active region receive zero damage multipliers")
	material.set_shader_parameter("damage_region_count", 0)
	canvas.clear()
	canvas.flush()
	material.set_shader_parameter("base_albedo", normal_texture(Color(0.08,0.7,0.1,1)))
	material.set_shader_parameter("use_base_albedo", true)
	var albedo: Image = await capture(view)
	expect(albedo.get_pixel(128,128).g > albedo.get_pixel(128,128).r * 1.5, "Original source albedo survives the damage material")
	material.set_shader_parameter("use_base_albedo", false)
	material.set_shader_parameter("base_normal", normal_texture(Color(0.85,0.5,0.86,1)))
	material.set_shader_parameter("use_base_normal", true)
	var source_normal: Image = await capture(view)
	expect(absf(source_normal.get_pixel(128,128).r - baseline.get_pixel(128,128).r) > 0.015, "Source normal map changes rendered surface lighting")
	material.set_shader_parameter("normal_strength", 0.0)
	canvas.stamp(Vector2(0.5,0.5), &"dent", 0.35, 1.0)
	canvas.flush()
	var disabled_detail: Image = await capture(view)
	expect(absf(disabled_detail.get_pixel(160,128).r - source_normal.get_pixel(160,128).r) < 0.015, "Zero damage normal strength preserves original normal response")
	material.set_shader_parameter("normal_strength", 2.0)
	var dent: Image = await capture(view)
	expect(absf(dent.get_pixel(160,128).r - disabled_detail.get_pixel(160,128).r) > 0.015, "Generated dent normals visibly shade the mesh without changing alpha")
	expect(dent.get_pixel(128,128).a > 0.95, "Dent relief never turns into a cut")
	canvas.gpu_normal_preview = true
	canvas.clear()
	canvas.stamp(Vector2(0.5,0.5), &"dent", 0.35, 1.0)
	canvas.flush()
	material.set_shader_parameter("damage_normal", normal_texture(Color(0.5,0.5,1.0,1.0)))
	material.set_shader_parameter("damage_height", canvas.height_texture)
	material.set_shader_parameter("use_damage_height", true)
	var gpu_dent: Image = await capture(view)
	expect(absf(gpu_dent.get_pixel(160,128).r - disabled_detail.get_pixel(160,128).r) > 0.015, "GPU height shading renders a dent while CPU normal generation is deferred")
	expect(absf(gpu_dent.get_pixel(160,128).r - dent.get_pixel(160,128).r) < 0.025 and gpu_dent.get_pixel(128,128).a > 0.95, "Four-tap RF height normal matches the CPU normal-map lighting and preserves alpha")
	baseline.save_png("res://artifacts/damage-material-baseline.png")
	cut.save_png("res://artifacts/damage-material-cut.png")
	second_uv.save_png("res://artifacts/damage-material-uv2.png")
	region_stage.save_png("res://artifacts/damage-material-regions.png")
	dent.save_png("res://artifacts/damage-material-dent.png")
	gpu_dent.save_png("res://artifacts/damage-material-height-dent.png")
	view.queue_free()
	await process_frame
	print("DAMAGE_MATERIAL_RENDER_TESTS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
