extends SceneTree
const Factory = preload("res://addons/aero_cloth_3d/core/aero_example_factory.gd")
const Definition = preload("res://addons/aero_cloth_3d/resources/aero_wearable_definition.gd")
const Outfit = preload("res://addons/aero_cloth_3d/resources/aero_outfit.gd")
const Effect = preload("res://addons/aero_cloth_3d/resources/aero_layer_effect.gd")
const Rig = preload("res://addons/aero_cloth_3d/core/aero_wearable_rig.gd")
var checks: int = 0
var failures: Array[String] = []
var rigs: Array[Node3D] = []
func _initialize() -> void: call_deferred("run")
func expect(condition: bool, message: String) -> void:
	checks+=1
	if not condition:
		failures.append(message)
		push_error(message)
func rig_for(outfit: Resource) -> Node3D:
	var rig: Node3D=Rig.new()
	rig.manual_simulation=true
	root.add_child(rig)
	rigs.append(rig)
	expect(rig.load_outfit(outfit).is_empty(),"Contact fixture loads without adapter errors")
	return rig
func panel_mesh(with_uv: bool=true) -> ArrayMesh:
	var arrays: Array=Factory.panel(.8,.8,3,3).surface_get_arrays(0)
	if with_uv:
		var uv2:=PackedVector2Array()
		for uv in arrays[Mesh.ARRAY_TEX_UV]: uv2.append(Vector2(.2+.5*uv.x,.1+.5*uv.y))
		arrays[Mesh.ARRAY_TEX_UV2]=uv2
	else:
		arrays[Mesh.ARRAY_TEX_UV]=null
		arrays[Mesh.ARRAY_TEX_UV2]=null
	var mesh:=ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh
func item(id: StringName, mesh: Mesh, position: Vector3) -> Resource:
	var definition: Resource=Definition.make_example(id,&"rigid")
	definition.source_scene=Factory.pack_mesh(mesh)
	definition.bind_transform=Transform3D(Basis.IDENTITY,position)
	definition.connection_points=PackedVector3Array([Vector3.ZERO])
	definition.mask_resolution=64
	return definition
func packed(node: Node) -> PackedScene:
	var scene:=PackedScene.new()
	scene.pack(node)
	node.free()
	return scene
func skeleton_node() -> Skeleton3D:
	var skeleton:=Skeleton3D.new()
	skeleton.name="Skeleton3D"
	skeleton.add_bone("Root")
	skeleton.add_bone("Hand")
	skeleton.set_bone_parent(1,0)
	skeleton.set_bone_rest(1,Transform3D(Basis.IDENTITY,Vector3(0,1,0)))
	return skeleton
func skinned_fixture() -> Dictionary:
	var character:=Node3D.new()
	var skeleton: Skeleton3D=skeleton_node()
	character.add_child(skeleton)
	skeleton.owner=character
	var player:=AnimationPlayer.new()
	character.add_child(player)
	player.owner=character
	var library:=AnimationLibrary.new()
	var animation:=Animation.new()
	animation.length=1.0
	var track: int=animation.add_track(Animation.TYPE_ROTATION_3D)
	animation.track_set_path(track,NodePath("Skeleton3D:Hand"))
	animation.rotation_track_insert_key(track,0.0,Quaternion.IDENTITY)
	animation.rotation_track_insert_key(track,1.0,Quaternion(Vector3.BACK,.9))
	library.add_animation("Swing",animation)
	player.add_animation_library("",library)
	var recipe: Resource=Outfit.new()
	recipe.character_scene=packed(character)
	var source:=Node3D.new()
	var source_skeleton: Skeleton3D=skeleton_node()
	source.add_child(source_skeleton)
	source_skeleton.owner=source
	var arrays: Array=[]
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3(-.3,1,0),Vector3(.3,1,0),Vector3(0,1.6,0)])
	arrays[Mesh.ARRAY_NORMAL]=PackedVector3Array([Vector3.BACK,Vector3.BACK,Vector3.BACK])
	arrays[Mesh.ARRAY_TEX_UV]=PackedVector2Array([Vector2(0,0),Vector2(1,0),Vector2(.5,1)])
	arrays[Mesh.ARRAY_TEX_UV2]=PackedVector2Array([Vector2(.1,.2),Vector2(.7,.2),Vector2(.4,.8)])
	arrays[Mesh.ARRAY_BONES]=PackedInt32Array([0,0,0,0,0,0,0,0,0,0,0,0])
	arrays[Mesh.ARRAY_WEIGHTS]=PackedFloat32Array([1,0,0,0,1,0,0,0,1,0,0,0])
	var mesh:=ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var visual:=MeshInstance3D.new()
	visual.name="Garment"
	visual.mesh=mesh
	visual.skin=Skin.new()
	visual.skin.add_named_bind(&"Hand",Transform3D(Basis.IDENTITY,Vector3(0,-1,0)))
	visual.skeleton=NodePath("../Skeleton3D")
	source.add_child(visual)
	visual.owner=source
	var definition: Resource=Definition.make_example(&"skin",&"skinned")
	definition.source_scene=packed(source)
	definition.mesh_path=NodePath("Garment")
	definition.required_bones=PackedStringArray(["Hand"])
	definition.mask_resolution=64
	recipe.items.append(definition)
	return {"recipe":recipe,"rest_centroid":Vector3(0,1.2,0)}
func run() -> void:
	var recipe: Resource=Outfit.new()
	var unrelated: Resource=item(&"unrelated",panel_mesh(),Vector3(2,0,.12))
	var inner: Resource=item(&"inner",panel_mesh(),Vector3.ZERO)
	var outer: Resource=item(&"outer",panel_mesh(),Vector3(0,0,.08))
	var cover: Resource=Effect.new()
	cover.id=&"cover"
	cover.target_item=&"inner"
	cover.hides_region=true
	cover.active_until_stage=3
	outer.effects.append(cover)
	outer.regions[0].stages[2].cut_strength=1.0
	outer.damage_recipe=Factory.recipe("cut",Vector2(.45,.35),.2,18)
	recipe.items.assign([unrelated,inner,outer])
	var rig: Node3D=rig_for(recipe)
	var contact:=Vector3(0,-.4,0)
	var direction:=Vector3(0,0,-1)
	var resolved: Dictionary=rig.resolve_hit(contact,direction)
	expect(resolved.get("resolved",false) and resolved["item_id"]==&"outer","World contact chooses the outer intersecting layer, not the first registered item")
	expect(resolved["uv"].is_equal_approx(Vector2(.45,.35)),"World contact resolves actual UV2 damage coordinates")
	expect(not rig.slots[&"inner"]["visual"].visible,"Covered inner fixture has no submitted geometry before the hole test")
	var result: Dictionary=rig.apply_hit({"position":contact,"direction":direction,"amount":1.0,"hit_id":"world-1","seed":17})
	expect(result["accepted"] and result["item_id"]==&"outer","Game caller can apply damage with only a world contact and direction")
	var before: Dictionary=rig.controller.export_state()
	expect(not rig.apply_hit({"position":contact,"direction":direction,"amount":1.0,"hit_id":"world-1"})["accepted"] and rig.controller.export_state()==before,"Duplicate world hit id leaves all item states unchanged")
	expect(not rig.apply_hit({"position":Vector3(9,9,9),"direction":direction,"amount":1,"hit_id":"miss"})["accepted"] and rig.controller.export_state()==before,"World miss is rejected without damaging a global fallback item")
	expect(not rig.apply_hit({"position":contact,"direction":Vector3.ZERO,"amount":1})["accepted"],"Zero attack direction is rejected")
	expect(not rig.apply_hit({"position":Vector3(NAN,0,0),"direction":direction,"amount":1})["accepted"],"Nonfinite world contact is rejected")
	rig.controller.set_preview_stage(&"outer",&"body",2)
	resolved=rig.resolve_hit(contact,direction)
	expect(resolved.get("resolved",false) and resolved["item_id"]==&"inner","CPU damage alpha lets an attack through the outer hole to its covered inner layer")
	rig.controller.unequip(&"inner")
	expect(not rig.resolve_hit(contact,direction).get("resolved",false),"Unequipped inner layer cannot receive a hole-through attack")
	rig.controller.equip(&"inner")
	resolved=rig.resolve_hit(contact,Vector3(1,.5,-1),&"inner")
	expect(resolved.get("resolved",false) and is_equal_approx(resolved["angle"],atan2(-.5,1.0)),"World attack direction projects into the actual UV frame")
	result=rig.apply_hit({"item_id":"inner","position":contact,"direction":Vector3(1,.5,-1),"amount":2,"hit_id":"angled"})
	var stamp: Dictionary=rig.controller.get_item_state(&"inner")["regions"][&"body"]["stamps"].back()
	expect(result["accepted"] and is_equal_approx(stamp["angle"],atan2(-.5,1.0)),"Derived UV angle reaches normalized gameplay stamps")
	expect(is_equal_approx(rig.slots[&"inner"]["canvas"].operations.back()["angle"],stamp["angle"]),"Damage canvas replays the attack angle instead of discarding it")
	before=rig.controller.export_state()
	expect(not rig.apply_hit({"item_id":"inner","uv":Vector2(.45,.35),"amount":2,"angle":INF})["accepted"] and rig.controller.export_state()==before,"Nonfinite explicit angle fails the normal controller transaction")
	result=rig.apply_hit({"item_id":"inner","uv":Vector2(.3,.3),"amount":80,"hit_id":"explicit","angle":.7,"impulse":Vector3(2,0,0)})
	expect(result["accepted"] and result["item_id"]==&"inner","Explicit item plus UV remains a supported direct game call")
	expect(rig.slots[&"inner"]["last_impulse"]==Vector3(2,0,0) and rig.slots[&"inner"]["preview_velocity"].x>1.0,"New rigid release uses the provided combat impulse")
	var saved: Dictionary=JSON.parse_string(JSON.stringify(rig.save_runtime_state()))
	expect(rig.load_runtime_state(saved) and is_equal_approx(rig.controller.get_item_state(&"inner")["regions"][&"body"]["stamps"].back()["angle"],.7),"Attack angle survives runtime JSON save and load")
	var missing_recipe: Resource=Outfit.new()
	missing_recipe.items.append(item(&"no_uv",panel_mesh(false),Vector3.ZERO))
	var missing: Node3D=rig_for(missing_recipe)
	expect(missing.resolve_hit(contact,direction).get("reason","")=="missing_uv","Missing source UV data produces an explicit rejection")
	var skinned: Dictionary=skinned_fixture()
	var skin_rig: Node3D=rig_for(skinned["recipe"])
	skin_rig.play_animation("Swing")
	skin_rig.step(.5)
	var skeleton: Skeleton3D=skin_rig.skeleton
	var visual: MeshInstance3D=skin_rig.slots[&"skin"]["visual"]
	var centroid: Vector3=skeleton.global_transform*skeleton.get_bone_global_pose(1)*visual.skin.get_bind_pose(0)*skinned["rest_centroid"]
	expect(centroid.distance_to(skinned["rest_centroid"])>.02,"Skin fixture actually changes pose under AnimationPlayer")
	resolved=skin_rig.resolve_hit(centroid,direction,&"skin")
	expect(resolved.get("resolved",false) and resolved["uv"].is_equal_approx(Vector2(.4,.4)),"Animated skinned vertices resolve through named Skin binds and current bone poses")
	result=skin_rig.apply_hit({"position":centroid,"direction":direction,"amount":12,"hit_id":"animated"})
	expect(result["accepted"] and result["stage"]==1,"World-position game damage works on an animated imported-style skinned wearable")
	var real: Node3D=rig_for(Factory.create())
	real.controller.unequip(&"jacket")
	real.controller.unequip(&"harness")
	real.step(1.0/60.0)
	var surface: Node3D=real.slots[&"shirt"]["surface"]
	var tri: int=100
	var p0: Vector3=surface.points[surface.triangles[tri*3]]
	var p1: Vector3=surface.points[surface.triangles[tri*3+1]]
	var p2: Vector3=surface.points[surface.triangles[tri*3+2]]
	var center: Vector3=(p0+p1+p2)/3.0
	var normal: Vector3=(p1-p0).cross(p2-p0).normalized()
	resolved=real.resolve_hit(center,-normal,&"shirt")
	expect(resolved.get("resolved",false) and resolved["item_id"]==&"shirt","Moving dense-cloth contact is resolved from authoritative CPU proxy triangles")
	result=real.apply_hit({"item_id":"shirt","position":center,"direction":-normal,"amount":12,"hit_id":"cloth-contact"})
	expect(result["accepted"] and result["region_id"]==&"lower","CPU cloth hit UV chooses the correct local damage region")
	var regions: PackedVector4Array=real.slots[&"shirt"]["materials"][0].get_shader_parameter("damage_region_rects")
	expect(is_equal_approx(regions[0].y,.5),"Shader region ownership follows the same sorted-id boundary policy as gameplay")
	var camera:=Camera3D.new()
	root.add_child(camera)
	camera.position=Vector3(0,-.4,3)
	camera.look_at(contact)
	var picked: Dictionary=rig.pick(camera,camera.unproject_position(contact),&"outer")
	expect(picked.is_empty(),"Editor pick shares gameplay cut-alpha rejection")
	camera.queue_free()
	for node in rigs: node.queue_free()
	await process_frame
	print("GAME_HIT_ADAPTER_TESTS: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
