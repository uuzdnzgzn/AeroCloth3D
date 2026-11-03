extends SceneTree
const Proxy = preload("res://addons/aero_cloth_3d/core/aero_proxy_surface_3d.gd")
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func make_mesh(vertices: PackedVector3Array, ids: PackedInt32Array, uvs: PackedVector2Array = PackedVector2Array()) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = ids
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	normals.fill(Vector3(0,0,1))
	arrays[Mesh.ARRAY_NORMAL] = normals
	if not uvs.is_empty():
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_TEX_UV2] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

func _run() -> void:
	var root3d := Node3D.new()
	root.add_child(root3d)
	var visual := MeshInstance3D.new()
	root3d.add_child(visual)
	visual.position = Vector3(2,1,3)
	var vertices := PackedVector3Array([Vector3(-.4,0,0),Vector3(-.3,-.6,0),Vector3(.5,0,0),Vector3(.4,-.7,0)])
	var ids := PackedInt32Array([0,1,2,2,1,3])
	var uvs := PackedVector2Array([Vector2(.1,.1),Vector2(.2,.9),Vector2(.8,.1),Vector2(.9,.8)])
	var proxy_mesh: ArrayMesh = make_mesh(vertices,ids,uvs)
	var detail_vertices: PackedVector3Array = vertices.duplicate()
	for i in range(detail_vertices.size()): detail_vertices[i].z += .04
	var original: ArrayMesh = make_mesh(detail_vertices,ids,uvs)
	visual.mesh = original
	var base_material := StandardMaterial3D.new()
	base_material.albedo_color = Color("346bc8")
	visual.material_override = base_material
	var surface := Proxy.new()
	root3d.add_child(surface)
	surface.running = false
	check(surface.configure(visual,proxy_mesh),"Arbitrary non-grid triangle proxy configures")
	check(surface.points.size()==4 and surface.triangles.size()==6,"Proxy topology retained")
	check(visual.mesh != original and original.surface_get_arrays(0)[Mesh.ARRAY_CUSTOM0] == null,"Source mesh remains unmodified")
	check(visual.material_override==null and surface.materials.size()==1,"Bound material renders despite original global override")
	var bound_arrays: Array = visual.mesh.surface_get_arrays(0)
	check(bound_arrays[Mesh.ARRAY_TEX_UV] == uvs and bound_arrays[Mesh.ARRAY_TEX_UV2] == uvs,"UV0 and UV2 preserved")
	var binding: Dictionary = surface.bind_vertex(Vector3(0,-.1,.04))
	check(absf(binding["offset"]-.04)<.0001,"Signed normal offset retained")
	var tri: Vector3i = binding["indices"]
	var bary: Vector3 = binding["barycentric"]
	var reconstructed: Vector3 = vertices[tri.x]*bary.x+vertices[tri.y]*bary.y+vertices[tri.z]*bary.z+Vector3(0,0,binding["offset"])
	check(reconstructed.distance_to(Vector3(0,-.1,.04))<.0001,"Triangle binding reconstructs an interior vertex")
	var outside := Vector3(.8,.1,.06)
	var outside_binding: Dictionary = surface.bind_vertex(outside)
	var outside_tri: Vector3i = outside_binding["indices"]
	var outside_bary: Vector3 = outside_binding["barycentric"]
	var outside_result: Vector3 = vertices[outside_tri.x]*outside_bary.x+vertices[outside_tri.y]*outside_bary.y+vertices[outside_tri.z]*outside_bary.z+Vector3(0,0,outside_binding["offset"])
	check(outside_result.distance_to(outside)<.0001,"Proxy binding does not shrink visual vertices outside its boundary")
	var old_base: PackedFloat32Array = surface.base_mobility.duplicate()
	surface.set_region_constraint(PackedInt32Array([0,1]),.4)
	surface.set_region_constraint(PackedInt32Array([1,2]),0.0)
	surface.step(1.0/60)
	check(is_equal_approx(surface.effective_mobility[0],.4) and surface.effective_mobility[1]==0 and surface.effective_mobility[2]==0,"Overlapping constraints choose most restrictive cap")
	check(surface.base_mobility==old_base,"Constraints do not mutate base authoring weights")
	surface.set_constraint_sources({"other":{"indices":PackedInt32Array([1,2]),"cap":0.0},"first":{"indices":PackedInt32Array([0,1]),"cap":.4}})
	surface.step(1.0/60)
	check(surface.effective_mobility[1]==0,"Source ordering cannot release remaining constraint")
	surface.clear_constraints()
	var before_release: Vector3 = surface.points[1]
	surface.step(1.0/60)
	check(surface.effective_mobility[1]>0 and surface.effective_mobility[1]<1,"Release ramps instead of snapping to full mobility")
	check(surface.points[1].distance_to(before_release)<.1,"Release pose remains continuous")
	for i in range(12): surface.step(1.0/60)
	check(surface.effective_mobility[1]==1,"Release reaches authored mobility")
	var mesh_id: int = visual.mesh.get_instance_id()
	var texture_id: int = surface.proxy_texture.get_instance_id()
	for i in range(10): surface.step(1.0/60)
	check(visual.mesh.get_instance_id()==mesh_id and surface.mesh_build_count==1,"No mesh rebuild during simulation")
	check(surface.proxy_texture.get_instance_id()==texture_id,"Texture allocation remains stable")
	check(visual.custom_aabb.has_point(visual.to_local(surface.points[3])),"Deformed bounds track CPU proxy")
	var sample: Transform3D = surface.get_surface_sample(0,Vector3(.2,.3,.5))
	var sample_expected: Vector3 = surface.points[0]*.2+surface.points[1]*.3+surface.points[2]*.5
	check(sample.origin.distance_to(sample_expected)<.0001 and absf(sample.basis.determinant()-1)<.001,"Surface socket uses barycentric position and orthonormal frame")
	var targets: PackedVector3Array = surface.points.duplicate()
	for i in range(targets.size()): targets[i] += Vector3(0,.2,0)
	check(surface.set_targets(targets),"External animation targets accepted")
	surface.set_region_constraint(PackedInt32Array([0,1,2,3]),0)
	surface.step(1.0/60)
	check(surface.points[0].is_equal_approx(targets[0]) and surface.points[3].is_equal_approx(targets[3]),"Pinned proxy follows current targets")
	surface.break_edge(0,1)
	check(surface.broken_edges.has(Vector2i(0,1)),"Prepared edge can be released")
	var before_snapshot: Dictionary = surface.snapshot()
	surface.base_mobility[0] = 0
	surface.release_region(PackedInt32Array([0]))
	check(surface.base_mobility[0]==0 and surface.released_indices.has(0),"Damage release does not mutate authored mobility")
	surface.points[0] += Vector3(.2,.3,.1)
	check(surface.restore(before_snapshot) and surface.points[0].is_equal_approx(before_snapshot["points"][0]),"Snapshot restores live proxy pose")
	surface.reset_simulation()
	check(surface.broken_edges.is_empty() and surface.released_indices.is_empty(),"Explicit simulation reset repairs prepared tears")
	surface.set_damage_parameters({"cut_strength":.5})
	check(surface.materials[0].get_shader_parameter("cut_strength")==.5,"Damage uniforms reach bound material")
	surface.restore_source()
	check(visual.mesh==original and visual.material_override==base_material,"Source mesh and material can be restored")
	check(surface.configure(visual,proxy_mesh) and surface.points.size()==4,"Rebinding resets transient arrays")
	surface.restore_source()
	var invalid: ArrayMesh = make_mesh(PackedVector3Array([Vector3.ZERO,Vector3.ZERO,Vector3.ZERO]),PackedInt32Array([0,1,2]))
	check(not surface.configure(visual,invalid),"Degenerate proxy rejected")
	var skeleton := Skeleton3D.new()
	root3d.add_child(skeleton)
	skeleton.global_transform = visual.global_transform
	skeleton.add_bone("Chest")
	skeleton.set_bone_rest(0,Transform3D.IDENTITY)
	var skin := Skin.new()
	skin.add_bind(0,Transform3D.IDENTITY)
	visual.skin = skin
	var skin_arrays: Array = proxy_mesh.surface_get_arrays(0).duplicate(true)
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	for _i in range(4):
		bones.append_array(PackedInt32Array([0,0,0,0]))
		weights.append_array(PackedFloat32Array([1,0,0,0]))
	skin_arrays[Mesh.ARRAY_BONES] = bones
	skin_arrays[Mesh.ARRAY_WEIGHTS] = weights
	var skinned_proxy := ArrayMesh.new()
	skinned_proxy.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,skin_arrays)
	check(surface.configure(visual,skinned_proxy,skeleton),"Weighted proxy configures with shared character skeleton")
	surface.set_region_constraint(PackedInt32Array([0,1,2,3]),0)
	skeleton.set_bone_pose_position(0,Vector3(0,.2,0))
	surface.step(1.0/60)
	check(surface.points[0].distance_to(skeleton.global_transform*(vertices[0]+Vector3(0,.2,0)))<.0001,"Pinned CPU points follow skeletal pose exactly once")
	surface.restore_source()
	visual.skin = null
	if DisplayServer.get_name() != "headless":
		# A real renderer compiles CUSTOM0/CUSTOM1 shader inputs and samples float data.
		var view := SubViewport.new()
		view.size = Vector2i(256,256)
		view.own_world_3d = true
		view.transparent_bg = true
		view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(view)
		root3d.reparent(view)
		visual.position = Vector3.ZERO
		check(surface.configure(visual,proxy_mesh),"Graphical proxy binds")
		var camera := Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 1.6
		view.add_child(camera)
		camera.position = Vector3(0,-.3,2)
		camera.look_at(Vector3(0,-.3,0))
		await process_frame
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var image: Image = view.get_texture().get_image()
		var count := 0
		for y in range(256):
			for x in range(256):
				if image.get_pixel(x,y).a>.5: count += 1
		check(count>10000,"Real GPU binding renders the non-grid surface")
		var centroid_before := 0.0
		for y in range(256):
			for x in range(256):
				if image.get_pixel(x,y).a>.5: centroid_before += x
		centroid_before /= maxf(count,1)
		for i in range(surface.points.size()): surface.points[i] += Vector3(.15,0,0)
		surface.upload()
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var moved: Image = view.get_texture().get_image()
		var centroid_after := 0.0
		var moved_count := 0
		for y in range(256):
			for x in range(256):
				if moved.get_pixel(x,y).a>.5:
					centroid_after += x
					moved_count += 1
		centroid_after /= maxf(moved_count,1)
		print("GPU_PROXY_SHIFT ",centroid_before," -> ",centroid_after," pixels=",count,"/",moved_count)
		moved.save_png("res://artifacts/proxy-surface-moved.png")
		check(absf((centroid_after-centroid_before)-24.0)<1.0,"GPU pixels follow updated CPU texture positions")
		image.save_png("res://artifacts/proxy-surface-render.png")
		view.queue_free()
	else:
		root3d.queue_free()
	await process_frame
	print("PROXY_SURFACE_TESTS: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
