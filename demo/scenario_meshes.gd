extends RefCounted
## Small authored test surfaces; no runtime cutting or per-hit mesh allocation.

static func material(color: Color, metal: float = 0.0) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.metallic = metal
	result.roughness = 0.58
	result.cull_mode = BaseMaterial3D.CULL_DISABLED
	return result

static func box(size: Vector3, color: Color, metal: float = 0.0) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = material(color, metal)
	return node

static func shell(rings: Array[Vector3], color: Color, segments: int = 12, arc: float = TAU) -> MeshInstance3D:
	# Ring = (horizontal radius, vertical position, depth radius); front is +Z.
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for ring in rings:
		for i in range(segments + 1):
			var angle: float = -arc * 0.5 + arc * float(i) / segments
			vertices.append(Vector3(sin(angle) * ring.x, ring.y, cos(angle) * ring.z))
	for row in range(rings.size() - 1):
		for i in range(segments):
			var a: int = row * (segments + 1) + i
			var b: int = a + segments + 1
			indices.append_array(PackedInt32Array([a, b, a + 1, a + 1, b, b + 1]))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in indices:
		st.add_vertex(vertices[index])
	st.generate_normals()
	var node := MeshInstance3D.new()
	node.mesh = st.commit()
	node.material_override = material(color)
	return node

static func line(points: PackedVector3Array, color: Color) -> MeshInstance3D:
	var immediate := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	immediate.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	for point in points:
		immediate.surface_add_vertex(point)
	immediate.surface_end()
	var node := MeshInstance3D.new()
	node.mesh = immediate
	return node

static func markers(parent: Node3D, points: Array[Vector3], color: Color, radius: float = 0.018) -> Array[MeshInstance3D]:
	var nodes: Array[MeshInstance3D] = []
	for point in points:
		var marker := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = radius
		sphere.height = radius * 2.0
		sphere.radial_segments = 8
		sphere.rings = 4
		marker.mesh = sphere
		marker.material_override = material(color)
		parent.add_child(marker)
		marker.position = point
		nodes.append(marker)
	return nodes
