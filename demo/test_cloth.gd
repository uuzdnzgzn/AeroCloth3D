extends MeshInstance3D
## A 9x11 CPU patch, authored weights and a cheap ellipsoid collision proxy.
## One-way animated pins: this solver does not push the character or accessories.

const WIDTH := 9
const HEIGHT := 11
var points := PackedVector3Array()
var previous := PackedVector3Array()
var rest := PackedVector3Array()
var weights := PackedFloat32Array()
var links: Array[Vector2i] = []
var lengths := PackedFloat32Array()
var indices := PackedInt32Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()
var equipped := true
var running := true
var collision_enabled := true
var paint_visible := false
var broken: Array[bool] = [false, false]
var elapsed := 0.0
var update_usec := 0
var initialized := false
const VISUAL_WIDTH := 33
const VISUAL_HEIGHT := 41
const PROXY_SHADER = preload("res://addons/aero_cloth_3d/shaders/proxy_cloth.gdshader")
var gpu_deformation := true
var proxy_image: Image
var proxy_texture: ImageTexture
var gpu_material: ShaderMaterial
var visual_mesh: ArrayMesh
var visual_uvs := PackedVector2Array()
var visual_indices := PackedInt32Array()
var visual_rest := PackedVector3Array()
var upload_usec := 0
var mesh_build_count := 0
var _debug_source: MeshInstance3D

func _ready() -> void:
	for y in range(HEIGHT):
		for x in range(WIDTH):
			var p := Vector3((float(x) / (WIDTH - 1) - 0.5) * 0.36, -float(y) / (HEIGHT - 1) * 0.56, 0.015)
			rest.append(p)
			points.append(global_transform * p)
			previous.append(global_transform * p)
			weights.append(0.0 if y == 0 else minf(1.0, y * 0.5))
			colors.append(Color.WHITE)
			normals.append(Vector3.FORWARD)
			var i: int = y * WIDTH + x
			if x > 0:
				links.append(Vector2i(i - 1, i))
				lengths.append(0.36 / (WIDTH - 1))
			if y > 0:
				links.append(Vector2i(i - WIDTH, i))
				lengths.append(0.56 / (HEIGHT - 1))
			if x < WIDTH - 1 and y < HEIGHT - 1:
				indices.append_array(PackedInt32Array([i, i + WIDTH, i + 1, i + 1, i + WIDTH, i + WIDTH + 1]))
	_build_visual()
	initialized = true
	_upload()

func _physics_process(delta: float) -> void:
	if not initialized or not equipped or not running:
		return
	var start: int = Time.get_ticks_usec()
	elapsed += delta
	var step: float = minf(delta, 1.0 / 30.0)
	for i in range(points.size()):
		var mobility: float = _mobility(i)
		if mobility == 0.0:
			points[i] = global_transform * rest[i]
			previous[i] = points[i]
			continue
		var velocity: Vector3 = (points[i] - previous[i]) * 0.975
		previous[i] = points[i]
		points[i] += velocity + Vector3(sin(elapsed * 2.0) * 0.7, -9.8, 0.7 + sin(elapsed * 3.0) * 1.5) * step * step
	for iteration in range(5):
		for n in range(links.size()):
			var link: Vector2i = links[n]
			var a: float = _mobility(link.x)
			var b: float = _mobility(link.y)
			if a + b == 0.0:
				continue
			var difference: Vector3 = points[link.y] - points[link.x]
			var distance: float = difference.length()
			if distance < 0.00001:
				continue
			var correction: Vector3 = difference * (distance - lengths[n]) / distance
			points[link.x] += correction * a / (a + b)
			points[link.y] -= correction * b / (a + b)
		for i in range(points.size()):
			var mobility: float = _mobility(i)
			if mobility == 0.0:
				points[i] = global_transform * rest[i]
			elif mobility < 1.0:
				points[i] = points[i].lerp(global_transform * rest[i], 0.12 * (1.0 - mobility))
			if collision_enabled and mobility > 0.0:
				# Hip proxy retained even when covered mesh regions are hidden.
				var center: Vector3 = global_position + Vector3(0.10, -0.18, -0.12)
				var radii := Vector3(0.19, 0.36, 0.16)
				var normalized: Vector3 = (points[i] - center) / radii
				if normalized.length_squared() < 1.0:
					points[i] = center + normalized.normalized() * radii
			points[i].y = maxf(0.025, points[i].y)
	_upload()
	update_usec = Time.get_ticks_usec() - start

func _mobility(index: int) -> float:
	if broken[0] and broken[1]:
		return 1.0
	if index < WIDTH:
		return 1.0 if broken[0 if index < WIDTH / 2 else 1] else weights[index]
	return weights[index]

func _upload() -> void:
	var begin: int = Time.get_ticks_usec()
	var local := PackedVector3Array()
	var inverse: Transform3D = global_transform.affine_inverse()
	for i in range(points.size()):
		local.append(inverse * points[i])
		var w: float = weights[i]
		colors[i] = (Color("ffbd69") if w == 0.0 else (Color("5ce0d0") if w < 1.0 else Color("7388a4"))) if paint_visible else Color("a84d3f")
		proxy_image.set_pixel(i % WIDTH, i / WIDTH, Color(local[i].x,local[i].y,local[i].z,w))
	# Only 1,584 bytes of point/weight data; texture identity remains stable.
	proxy_texture.update(proxy_image)
	gpu_material.set_shader_parameter("show_weights", paint_visible)
	if gpu_deformation:
		mesh = visual_mesh
		material_override = gpu_material
	else:
		# Explicit diagnostic reference: same 1,353 vertices mapped on CPU.
		var vertices := PackedVector3Array()
		var vertex_normals := PackedVector3Array()
		var vertex_colors := PackedColorArray()
		for uv in visual_uvs:
			var sample: Dictionary = sample_surface(uv)
			vertices.append(inverse * sample["position"])
			vertex_normals.append((global_basis.inverse() * sample["normal"]).normalized())
			var w: float = sample["weight"]
			vertex_colors.append((Color("ffbd69") if w < 0.01 else (Color("5ce0d0") if w < 0.99 else Color("7388a4"))) if paint_visible else Color("a84d3f"))
		mesh = _mesh(vertices, visual_indices, vertex_normals, vertex_colors, visual_uvs)
		if not material_override is StandardMaterial3D:
			var mat := StandardMaterial3D.new()
			mat.vertex_color_use_as_albedo = true
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mat.roughness = 0.95
			material_override = mat
	# Shader deformation changes bounds. Update small CPU bounds, never read GPU data.
	var bounds := AABB(local[0],Vector3.ZERO)
	for p in local: bounds = bounds.expand(p)
	custom_aabb = bounds.grow(0.025)
	upload_usec = Time.get_ticks_usec() - begin

func _build_visual() -> void:
	for y in range(VISUAL_HEIGHT):
		for x in range(VISUAL_WIDTH):
			var uv := Vector2(float(x)/(VISUAL_WIDTH-1),float(y)/(VISUAL_HEIGHT-1))
			visual_uvs.append(uv)
			visual_rest.append(Vector3((uv.x-0.5)*0.36,-uv.y*0.56,0.015))
			var i: int = y*VISUAL_WIDTH+x
			if x < VISUAL_WIDTH-1 and y < VISUAL_HEIGHT-1:
				visual_indices.append_array(PackedInt32Array([i,i+VISUAL_WIDTH,i+1,i+1,i+VISUAL_WIDTH,i+VISUAL_WIDTH+1]))
	var ns := PackedVector3Array()
	ns.resize(visual_rest.size())
	ns.fill(Vector3.FORWARD)
	visual_mesh = _mesh(visual_rest,visual_indices,ns,PackedColorArray(),visual_uvs)
	proxy_image = Image.create(WIDTH,HEIGHT,false,Image.FORMAT_RGBAF)
	proxy_texture = ImageTexture.create_from_image(proxy_image)
	gpu_material = ShaderMaterial.new()
	gpu_material.shader = PROXY_SHADER
	gpu_material.set_shader_parameter("proxy_data",proxy_texture)

func _mesh(v: PackedVector3Array, ids: PackedInt32Array, ns: PackedVector3Array, cs: PackedColorArray, uvs: PackedVector2Array) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_INDEX] = ids
	arrays[Mesh.ARRAY_NORMAL] = ns
	if not cs.is_empty(): arrays[Mesh.ARRAY_COLOR] = cs
	if not uvs.is_empty(): arrays[Mesh.ARRAY_TEX_UV] = uvs
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	mesh_build_count += 1
	return result

func sample_surface(uv: Vector2) -> Dictionary:
	var cell: Vector2 = uv.clamp(Vector2.ZERO,Vector2.ONE)*Vector2(WIDTH-1,HEIGHT-1)
	var x: int = mini(int(cell.x),WIDTH-2)
	var y: int = mini(int(cell.y),HEIGHT-2)
	var t: Vector2 = cell-Vector2(x,y)
	var a: int = y*WIDTH+x
	var b: int = a+WIDTH
	var c: int = a+1
	var d: int = b+1
	var ids := PackedInt32Array([a,b,c] if t.x+t.y <= 1.0 else [c,b,d])
	var bary: Vector3 = Vector3(1.0-t.x-t.y,t.y,t.x) if t.x+t.y <= 1.0 else Vector3(1.0-t.y,1.0-t.x,t.x+t.y-1.0)
	var position_value: Vector3 = points[ids[0]]*bary.x+points[ids[1]]*bary.y+points[ids[2]]*bary.z
	var normal: Vector3 = (points[ids[1]]-points[ids[0]]).cross(points[ids[2]]-points[ids[0]])
	if normal.length_squared() < 0.00000001: normal = global_basis*Vector3.FORWARD
	return {"position":position_value,"normal":normal.normalized(),"weight":weights[ids[0]]*bary.x+weights[ids[1]]*bary.y+weights[ids[2]]*bary.z}

func get_debug_source() -> MeshInstance3D:
	if not is_instance_valid(_debug_source):
		_debug_source = MeshInstance3D.new()
		add_child(_debug_source)
		_debug_source.visible = false
	var local := PackedVector3Array()
	for p in points: local.append(to_local(p))
	_debug_source.mesh = _mesh(local,indices,normals,PackedColorArray(),PackedVector2Array())
	return _debug_source

func reset_damage() -> void:
	broken = [false, false]
	for i in range(points.size()):
		points[i] = global_transform * rest[i]
		previous[i] = points[i]
	_upload()

func hit() -> bool:
	if not equipped:
		return false
	for i in range(2):
		if not broken[i]:
			broken[i] = true
			return true
	return false

func set_equipped(value: bool) -> void:
	equipped = value
	visible = value

func paint(camera: Camera3D, screen_position: Vector2, value: float, radius: float = 35.0) -> int:
	var count := 0
	for i in range(points.size()):
		if not camera.is_position_behind(points[i]) and camera.unproject_position(points[i]).distance_to(screen_position) < radius:
			weights[i] = value
			count += 1
	_upload()
	return count
