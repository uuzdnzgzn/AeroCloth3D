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
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.95
	material_override = mat
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
	var local := PackedVector3Array()
	var inverse: Transform3D = global_transform.affine_inverse()
	for i in range(points.size()):
		local.append(inverse * points[i])
		var w: float = weights[i]
		colors[i] = (Color("ffbd69") if w == 0.0 else (Color("5ce0d0") if w < 1.0 else Color("7388a4"))) if paint_visible else Color("a84d3f")
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = local
	arrays[Mesh.ARRAY_INDEX] = indices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	# Small prototype buffer upload. Allocation cost included in benchmark; no zero-cost claim.
	var surface := ArrayMesh.new()
	surface.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = surface

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
