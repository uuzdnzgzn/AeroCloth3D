@tool
class_name AeroProxySurface3D
extends Node3D
## Arbitrary prepared triangle proxy. CPU points are authoritative; dense vertices
## are bound once, then moved by the vertex shader without GPU readback.

const BOUND_SHADER = preload("res://addons/aero_cloth_3d/shaders/aero_bound_surface.gdshader")
@export var release_seconds: float = 0.15
@export var iterations: int = 5
@export var gravity := Vector3(0,-9.8,0)
@export var damping: float = 0.975
var points := PackedVector3Array()
var previous := PackedVector3Array()
var rest := PackedVector3Array()
var base_mobility := PackedFloat32Array()
var effective_mobility := PackedFloat32Array()
var desired_targets := PackedVector3Array()
var triangles := PackedInt32Array()
var constraints: Dictionary = {}
var broken_edges: Dictionary = {}
var released_indices: Dictionary = {}
var collision_spheres: Array[Vector4] = []
var running := true
var configured := false
var visual: MeshInstance3D
var skeleton: Skeleton3D
var source_skin: Skin
var proxy_bones := PackedInt32Array()
var proxy_weights := PackedFloat32Array()
var proxy_image: Image
var proxy_texture: ImageTexture
var proxy_rest_texture: ImageTexture
var bound_mesh: ArrayMesh
var materials: Array[ShaderMaterial] = []
var bindings: Array[Dictionary] = []
var edges: Array[Vector2i] = []
var edge_lengths := PackedFloat32Array()
var update_usec := 0
var mesh_build_count := 0
var last_error := ""
var _source_mesh: Mesh
var _source_skin: Skin
var _source_material_override: Material
var _source_aabb: AABB
var _source_overrides: Array[Material] = []
var _proxy_bind_transform := Transform3D.IDENTITY
var _maximum_offset := 0.025
var _maximum_bary_sum := 1.0

func configure(visual_mesh: MeshInstance3D, proxy_mesh: ArrayMesh, target_skeleton: Skeleton3D = null) -> bool:
	if configured:
		last_error = "Surface is already configured; restore_source() before rebinding"
		return false
	if not is_instance_valid(visual_mesh) or visual_mesh.mesh == null or proxy_mesh == null or proxy_mesh.get_surface_count() != 1:
		last_error = "A visual mesh and a single-surface triangle proxy are required"
		return false
	if proxy_mesh.surface_get_primitive_type(0) != Mesh.PRIMITIVE_TRIANGLES:
		last_error = "Proxy must contain triangles"
		return false
	var arrays: Array = proxy_mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if vertices.size() < 3 or vertices.size() > 1024:
		last_error = "Proxy must contain 3..1024 vertices; prefer <=256 for authoring"
		return false
	var ids: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if ids.is_empty():
		for i in range(vertices.size()): ids.append(i)
	if ids.size()%3 != 0:
		last_error = "Incomplete proxy triangle"
		return false
	for index in ids:
		if index < 0 or index >= vertices.size():
			last_error = "Proxy triangle index out of bounds"
			return false
	var valid_triangles := 0
	for i in range(0,ids.size(),3):
		if (vertices[ids[i+1]]-vertices[ids[i]]).cross(vertices[ids[i+2]]-vertices[ids[i]]).length_squared()>1e-12:
			valid_triangles += 1
	if valid_triangles == 0:
		last_error = "Proxy has no non-degenerate triangles"
		return false
	for s in range(visual_mesh.mesh.get_surface_count()):
		var source_arrays: Array = visual_mesh.mesh.surface_get_arrays(s)
		for custom_channel in [Mesh.ARRAY_CUSTOM0,Mesh.ARRAY_CUSTOM1]:
			if source_arrays[custom_channel] != null and not source_arrays[custom_channel].is_empty():
				last_error = "Visual CUSTOM0/CUSTOM1 channels are already occupied; prepare a copy for proxy binding"
				return false
	points.clear()
	previous.clear()
	base_mobility.clear()
	effective_mobility.clear()
	desired_targets.clear()
	materials.clear()
	bindings.clear()
	edges.clear()
	edge_lengths.clear()
	_source_overrides.clear()
	constraints.clear()
	broken_edges.clear()
	released_indices.clear()
	_maximum_offset = 0.025
	_maximum_bary_sum = 1.0
	visual = visual_mesh
	skeleton = target_skeleton
	_source_mesh = visual.mesh
	_source_skin = visual.skin
	_source_material_override = visual.material_override
	_source_aabb = visual.custom_aabb
	source_skin = visual.skin
	_proxy_bind_transform = visual.transform
	rest = vertices.duplicate()
	triangles = ids.duplicate()
	proxy_bones = arrays[Mesh.ARRAY_BONES] if arrays[Mesh.ARRAY_BONES] != null else PackedInt32Array()
	proxy_weights = arrays[Mesh.ARRAY_WEIGHTS] if arrays[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
	for p in rest:
		points.append(visual.global_transform*p)
		previous.append(visual.global_transform*p)
		base_mobility.append(1.0)
		effective_mobility.append(1.0)
	proxy_image = Image.create(points.size(),1,false,Image.FORMAT_RGBAF)
	proxy_texture = ImageTexture.create_from_image(proxy_image)
	var rest_image := Image.create(points.size(),1,false,Image.FORMAT_RGBAF)
	for i in range(rest.size()): rest_image.set_pixel(i,0,Color(rest[i].x,rest[i].y,rest[i].z,1))
	proxy_rest_texture = ImageTexture.create_from_image(rest_image)
	_build_edges()
	bound_mesh = ArrayMesh.new()
	for surface_index in range(_source_mesh.get_surface_count()):
		var src: Array = _source_mesh.surface_get_arrays(surface_index).duplicate(true)
		if src[Mesh.ARRAY_NORMAL] == null:
			var fallback_normals := PackedVector3Array()
			fallback_normals.resize(src[Mesh.ARRAY_VERTEX].size())
			fallback_normals.fill(Vector3(0,0,1))
			src[Mesh.ARRAY_NORMAL] = fallback_normals
		if src[Mesh.ARRAY_TEX_UV] != null and (src[Mesh.ARRAY_TANGENT] == null or src[Mesh.ARRAY_TANGENT].is_empty()):
			src[Mesh.ARRAY_TANGENT] = _generate_tangents(src)
		var src_vertices: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
		var custom0 := PackedFloat32Array()
		var custom1 := PackedFloat32Array()
		for vertex in src_vertices:
			var binding: Dictionary = bind_vertex(vertex)
			bindings.append(binding)
			_maximum_offset = maxf(_maximum_offset,absf(binding["offset"])+0.025)
			var tri: Vector3i = binding["indices"]
			var bary: Vector3 = binding["barycentric"]
			_maximum_bary_sum = maxf(_maximum_bary_sum,absf(bary.x)+absf(bary.y)+absf(bary.z))
			custom0.append_array(PackedFloat32Array([float(tri.x),float(tri.y),float(tri.z),binding["offset"]]))
			custom1.append_array(PackedFloat32Array([bary.x,bary.y,bary.z,0.0]))
		src[Mesh.ARRAY_CUSTOM0] = custom0
		src[Mesh.ARRAY_CUSTOM1] = custom1
		# CPU proxy already contains skeletal motion. Never apply skinning twice.
		src[Mesh.ARRAY_BONES] = null
		src[Mesh.ARRAY_WEIGHTS] = null
		var flags: int = (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
		bound_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,src,[],{},flags)
		var original: Material = visual.get_active_material(surface_index)
		_source_overrides.append(visual.get_surface_override_material(surface_index))
		var material := ShaderMaterial.new()
		material.shader = BOUND_SHADER
		material.set_shader_parameter("proxy_data",proxy_texture)
		material.set_shader_parameter("proxy_rest_data",proxy_rest_texture)
		if original is StandardMaterial3D:
			material.set_shader_parameter("tint",original.albedo_color)
			material.set_shader_parameter("base_roughness",original.roughness)
			material.set_shader_parameter("base_metallic",original.metallic)
			if original.albedo_texture:
				material.set_shader_parameter("base_albedo",original.albedo_texture)
				material.set_shader_parameter("use_base_albedo",true)
			if original.normal_enabled and original.normal_texture:
				material.set_shader_parameter("base_normal",original.normal_texture)
				material.set_shader_parameter("use_base_normal",true)
		materials.append(material)
	visual.mesh = bound_mesh
	visual.skin = null
	visual.material_override = null
	for i in range(materials.size()): visual.set_surface_override_material(i,materials[i])
	mesh_build_count += 1
	configured = true
	upload()
	return true

func _generate_tangents(arrays: Array) -> PackedFloat32Array:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var ids: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if ids.is_empty():
		for i in range(vertices.size()): ids.append(i)
	var tangents: Array[Vector3] = []
	var bitangents: Array[Vector3] = []
	for _vertex in vertices:
		tangents.append(Vector3.ZERO)
		bitangents.append(Vector3.ZERO)
	for i in range(0,ids.size(),3):
		var a: int = ids[i]
		var b: int = ids[i+1]
		var c: int = ids[i+2]
		var p: Vector3 = vertices[b]-vertices[a]
		var q: Vector3 = vertices[c]-vertices[a]
		var u: Vector2 = uvs[b]-uvs[a]
		var v: Vector2 = uvs[c]-uvs[a]
		var determinant: float = u.x*v.y-u.y*v.x
		if absf(determinant)<0.000001: continue
		var t: Vector3 = (p*v.y-q*u.y)/determinant
		var bt: Vector3 = (q*u.x-p*v.x)/determinant
		for index in [a,b,c]:
			tangents[index] += t
			bitangents[index] += bt
	var result := PackedFloat32Array()
	for i in range(vertices.size()):
		var normal: Vector3 = normals[i] if normals.size()==vertices.size() else Vector3(0,0,1)
		var tangent: Vector3 = tangents[i]-normal*normal.dot(tangents[i])
		if tangent.length_squared()<1e-12: tangent = normal.cross(Vector3.UP if absf(normal.y)<.9 else Vector3.RIGHT)
		tangent = tangent.normalized()
		var handedness: float = -1.0 if normal.cross(tangent).dot(bitangents[i])<0 else 1.0
		result.append_array(PackedFloat32Array([tangent.x,tangent.y,tangent.z,handedness]))
	return result

func restore_source() -> void:
	if is_instance_valid(visual) and _source_mesh:
		visual.mesh = _source_mesh
		visual.skin = _source_skin
		visual.material_override = _source_material_override
		visual.custom_aabb = _source_aabb
		for i in range(_source_overrides.size()): visual.set_surface_override_material(i,_source_overrides[i])
	configured = false

func bind_vertex(vertex: Vector3) -> Dictionary:
	var best := INF
	var result: Dictionary = {}
	for i in range(0,triangles.size(),3):
		var tri := Vector3i(triangles[i],triangles[i+1],triangles[i+2])
		var a: Vector3 = rest[tri.x]
		var b: Vector3 = rest[tri.y]
		var c: Vector3 = rest[tri.z]
		var cross_value: Vector3 = (b-a).cross(c-a)
		if cross_value.length_squared()<1e-12: continue
		var closest: Vector3 = closest_on_triangle(vertex,a,b,c)
		var distance: float = closest.distance_squared_to(vertex)
		if distance < best:
			best = distance
			var normal: Vector3 = cross_value.normalized()
			var offset: float = (vertex-a).dot(normal)
			# Use plane barycentrics after choosing the closest triangle. Clamping
			# barycentrics would shrink visual vertices outside the proxy boundary.
			var projected: Vector3 = vertex-normal*offset
			var bary: Vector3 = Geometry3D.get_triangle_barycentric_coords(projected,a,b,c)
			result = {"indices":tri,"barycentric":bary,"offset":offset}
	return result

static func closest_on_triangle(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var n: Vector3 = (b-a).cross(c-a).normalized()
	var projected: Vector3 = p-n*(p-a).dot(n)
	var bary: Vector3 = Geometry3D.get_triangle_barycentric_coords(projected,a,b,c)
	if bary.x>=0 and bary.y>=0 and bary.z>=0: return projected
	var best: Vector3 = a
	var distance := INF
	for edge in [[a,b],[b,c],[c,a]]:
		var start: Vector3 = edge[0]
		var d: Vector3 = edge[1]-start
		var candidate: Vector3 = start+d*clampf((p-start).dot(d)/maxf(d.length_squared(),1e-12),0,1)
		var next_distance: float = p.distance_squared_to(candidate)
		if next_distance<distance:
			distance = next_distance
			best = candidate
	return best

func _build_edges() -> void:
	var seen: Dictionary = {}
	for n in range(0,triangles.size(),3):
		for pair in [Vector2i(triangles[n],triangles[n+1]),Vector2i(triangles[n+1],triangles[n+2]),Vector2i(triangles[n+2],triangles[n])]:
			var edge := Vector2i(mini(pair.x,pair.y),maxi(pair.x,pair.y))
			if not seen.has(edge):
				seen[edge] = true
				edges.append(edge)
				edge_lengths.append(points[edge.x].distance_to(points[edge.y]))

func set_targets(targets: PackedVector3Array) -> bool:
	if targets.size()!=points.size(): return false
	for target in targets:
		if not target.is_finite(): return false
	desired_targets = targets.duplicate()
	return true

func set_running(value: bool) -> void: running = value

func set_region_constraint(indices: PackedInt32Array, cap: float) -> void:
	var id: String = str(indices)
	constraints[id] = {"indices":indices.duplicate(),"cap":clampf(cap,0.0,1.0)}

func clear_constraints() -> void: constraints.clear()

func set_constraint_sources(sources: Dictionary) -> void:
	constraints = sources.duplicate(true)

func release_region(indices: PackedInt32Array) -> void:
	for i in indices:
		if i>=0 and i<base_mobility.size(): released_indices[i] = true

func break_edge(a: int, b: int) -> void:
	broken_edges[Vector2i(mini(a,b),maxi(a,b))] = true

func reset_simulation(repair_tears: bool = true) -> void:
	if not configured: return
	if repair_tears:
		broken_edges.clear()
		released_indices.clear()
	for i in range(points.size()):
		points[i] = get_target(i)
		previous[i] = points[i]
		effective_mobility[i] = base_mobility[i]
	upload()

func snapshot() -> Dictionary:
	return {"points":points.duplicate(),"previous":previous.duplicate(),"mobility":effective_mobility.duplicate(),"broken_edges":broken_edges.duplicate(),"released_indices":released_indices.duplicate()}

func restore(data: Dictionary) -> bool:
	if not data.get("points") is PackedVector3Array or data["points"].size()!=points.size(): return false
	if not data.get("previous") is PackedVector3Array or data["previous"].size()!=previous.size(): return false
	if not data.get("mobility") is PackedFloat32Array or data["mobility"].size()!=effective_mobility.size(): return false
	for p in data["points"]:
		if not p.is_finite(): return false
	for p in data["previous"]:
		if not p.is_finite(): return false
	for m in data["mobility"]:
		if not is_finite(m) or m<0 or m>1: return false
	points = data["points"].duplicate()
	previous = data["previous"].duplicate()
	effective_mobility = data["mobility"].duplicate()
	broken_edges = data.get("broken_edges",{}).duplicate()
	released_indices = data.get("released_indices",{}).duplicate()
	upload()
	return true

func get_target(index: int) -> Vector3:
	if desired_targets.size()==points.size(): return desired_targets[index]
	if is_instance_valid(skeleton) and proxy_bones.size()>=rest.size()*4 and proxy_weights.size()>=rest.size()*4 and source_skin:
		var position_value := Vector3.ZERO
		var total := 0.0
		for slot in range(4):
			var weight: float = proxy_weights[index*4+slot]
			var bind: int = proxy_bones[index*4+slot]
			if weight<=0 or bind<0 or bind>=source_skin.get_bind_count(): continue
			var bone: int = source_skin.get_bind_bone(bind)
			var named: StringName = source_skin.get_bind_name(bind)
			if not named.is_empty(): bone = skeleton.find_bone(named)
			if bone<0 or bone>=skeleton.get_bone_count(): continue
			position_value += skeleton.global_transform*skeleton.get_bone_global_pose(bone)*source_skin.get_bind_pose(bind)*rest[index]*weight
			total += weight
		if total>0.000001: return position_value/total
	return visual.global_transform*rest[index]

func _physics_process(delta: float) -> void:
	if configured and running: step(delta)

func step(delta: float) -> void:
	if not configured or delta<=0: return
	var begin: int = Time.get_ticks_usec()
	var dt: float = minf(delta,1.0/30.0)
	var caps: PackedFloat32Array = base_mobility.duplicate()
	var targets := PackedVector3Array()
	for i in range(points.size()):
		targets.append(get_target(i))
		if released_indices.has(i): caps[i] = 1.0
	for entry in constraints.values():
		if not entry is Dictionary: continue
		for index in entry.get("indices",PackedInt32Array()):
			if index>=0 and index<caps.size(): caps[index] = minf(caps[index],clampf(float(entry.get("cap",1.0)),0,1))
	for i in range(points.size()):
		var target_cap: float = clampf(caps[i],0,1)
		effective_mobility[i] = target_cap if target_cap<effective_mobility[i] else move_toward(effective_mobility[i],target_cap,dt/maxf(release_seconds,0.001))
		var target: Vector3 = targets[i]
		if effective_mobility[i]<=0:
			previous[i] = points[i]
			points[i] = target
		else:
			var velocity: Vector3 = (points[i]-previous[i]).limit_length(20.0*dt)*damping
			previous[i] = points[i]
			points[i] += velocity+gravity*dt*dt
	for _iteration in range(maxi(1,iterations)):
		for i in range(edges.size()):
			var edge: Vector2i = edges[i]
			if broken_edges.has(edge): continue
			var a: float = effective_mobility[edge.x]
			var b: float = effective_mobility[edge.y]
			if a+b<=0: continue
			var difference: Vector3 = points[edge.y]-points[edge.x]
			var length_value: float = difference.length()
			if length_value<0.000001: continue
			var correction: Vector3 = difference*(length_value-edge_lengths[i])/length_value
			points[edge.x] += correction*a/(a+b)
			points[edge.y] -= correction*b/(a+b)
		for i in range(points.size()):
			var m: float = effective_mobility[i]
			if m<=0: points[i] = targets[i]
			elif m<1: points[i] = points[i].lerp(targets[i],0.12*(1.0-m))
			for sphere in collision_spheres:
				if m<=0: continue
				var center := Vector3(sphere.x,sphere.y,sphere.z)
				var offset: Vector3 = points[i]-center
				if offset.length_squared()<sphere.w*sphere.w:
					points[i] = center+(offset.normalized() if offset.length_squared()>1e-12 else Vector3.UP)*sphere.w
	upload()
	update_usec = Time.get_ticks_usec()-begin

func upload() -> void:
	if not configured: return
	var inverse: Transform3D = visual.global_transform.affine_inverse()
	var bounds := AABB(inverse*points[0],Vector3.ZERO)
	for i in range(points.size()):
		var p: Vector3 = inverse*points[i]
		proxy_image.set_pixel(i,0,Color(p.x,p.y,p.z,effective_mobility[i]))
		bounds = bounds.expand(p)
	proxy_texture.update(proxy_image)
	# Include authored offsets from the proxy plane.
	# Negative barycentrics extrapolate outside the proxy; conservatively retain
	# those render vertices without scanning the dense mesh every physics tick.
	visual.custom_aabb = bounds.grow(_maximum_offset+(_maximum_bary_sum-1.0)*bounds.size.length())

func get_surface_sample(triangle: Variant, barycentric: Vector3) -> Transform3D:
	var ids: Vector3i
	if triangle is Vector3i:
		ids = triangle
	elif triangle is int and triangle>=0 and triangle*3+2<triangles.size():
		ids = Vector3i(triangles[triangle*3],triangles[triangle*3+1],triangles[triangle*3+2])
	else: return Transform3D.IDENTITY
	if mini(ids.x,mini(ids.y,ids.z))<0 or maxi(ids.x,maxi(ids.y,ids.z))>=points.size() or not barycentric.is_finite(): return Transform3D.IDENTITY
	var a: Vector3 = points[ids.x]
	var b: Vector3 = points[ids.y]
	var c: Vector3 = points[ids.z]
	var normal: Vector3 = (b-a).cross(c-a)
	if normal.length_squared()<1e-12: return Transform3D(Basis.IDENTITY,a)
	var x: Vector3 = (b-a).normalized()
	var z: Vector3 = normal.normalized()
	var y: Vector3 = z.cross(x).normalized()
	return Transform3D(Basis(x,y,z),a*barycentric.x+b*barycentric.y+c*barycentric.z)

func set_damage_parameters(parameters: Dictionary) -> void:
	for material in materials:
		for key in parameters: material.set_shader_parameter(key,parameters[key])
