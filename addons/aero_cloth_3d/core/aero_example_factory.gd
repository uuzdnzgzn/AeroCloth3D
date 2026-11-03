@tool
extends RefCounted
const BodyCollision = preload("res://addons/aero_cloth_3d/core/aero_body_collision.gd")
const Definition = preload("res://addons/aero_cloth_3d/resources/aero_wearable_definition.gd")
const Region = preload("res://addons/aero_cloth_3d/resources/aero_wearable_region.gd")
const Effect = preload("res://addons/aero_cloth_3d/resources/aero_layer_effect.gd")
const Outfit = preload("res://addons/aero_cloth_3d/resources/aero_outfit.gd")

static func panel(width:float,height:float,columns:int=9,rows:int=11,torn:bool=false,fully_torn:bool=false) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uv := PackedVector2Array()
	var ids := PackedInt32Array()
	for y in range(rows):
		for x in range(columns):
			var t := Vector2(float(x)/(columns-1),float(y)/(rows-1))
			var px: float = (t.x-.5)*width
			if torn and y>rows/2 and x>columns/2: px += (t.y-.5)*.15
			vertices.append(Vector3(px,-t.y*height,0))
			normals.append(Vector3.BACK)
			uv.append(t)
			var i: int = y*columns+x
			if x<columns-1 and y<rows-1:
				if torn and y>=int((rows-1)*.4) and y<int((rows-1)*.5) and (fully_torn or x!=int((columns-1)/2)): continue
				ids.append_array(PackedInt32Array([i,i+columns,i+1,i+1,i+columns,i+columns+1]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_TEX_UV]=uv
	arrays[Mesh.ARRAY_TEX_UV2]=uv
	arrays[Mesh.ARRAY_INDEX]=ids
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

static func pack_mesh(mesh:Mesh) -> PackedScene:
	var node := MeshInstance3D.new()
	node.name="Wearable"
	node.mesh=mesh
	var scene := PackedScene.new()
	scene.pack(node)
	node.free()
	return scene

static func make_item(id:StringName,label:String,mode:StringName,mesh:Mesh,color:Color,origin:Vector3,bone:StringName) -> Resource:
	var item:Resource = Definition.make_example(id,mode)
	item.display_name=label
	item.source_scene=pack_mesh(mesh)
	item.base_color=color
	item.bind_transform=Transform3D(Basis.IDENTITY,origin)
	item.anchor_bone=bone
	item.required_bones=PackedStringArray([str(bone)])
	for i in range(1,5): item.regions[0].stages[i].damage_recipe=recipe("cut",Vector2(.45,.35),.04+.035*i,17+i)
	item.regions[0].label="Ana bölge"
	item.regions[0].stages[1].label="Kesikler"
	item.regions[0].stages[2].label="Büyüyen hasar"
	item.regions[0].stages[1].cut_strength=.7
	item.regions[0].stages[2].cut_strength=.85
	item.regions[0].stages[3].cut_strength=1.0
	item.regions[0].stages[4].cut_strength=1.0
	item.connection_points=PackedVector3Array([Vector3(-.1,0,0),Vector3(.1,0,0)])
	return item

static func recipe(brush: String, uv: Vector2, radius: float, seed_value: int) -> Dictionary:
	return {"format":"aero_damage_canvas","version":1,"size":512,"operations":[{"uv":[uv.x,uv.y],"brush":brush,"radius":radius,"strength":1.0,"angle":0.35,"seed":seed_value,"erase":false}]}

static func dent_mesh(mesh: ArrayMesh) -> ArrayMesh:
	var result := ArrayMesh.new()
	result.add_blend_shape("Dent")
	result.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_NORMALIZED
	for index in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(index)
		var shape: Array = []
		shape.resize(Mesh.ARRAY_MAX)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX].duplicate()
		for i in range(vertices.size()):
			var p: Vector3 = vertices[i]
			vertices[i].z -= 0.05 * exp(-pow(p.x/0.10,2.0)-pow((p.y+0.11)/0.09,2.0))
		shape[Mesh.ARRAY_VERTEX] = vertices
		shape[Mesh.ARRAY_NORMAL] = arrays[Mesh.ARRAY_NORMAL]
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [shape])
	return result

static func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D: return node
	for child in node.get_children():
		var found: Skeleton3D = _find_skeleton(child)
		if found: return found
	return null

static func create() -> Resource:
	var outfit:Resource = Outfit.new()
	for path in ["res://demo/assets/authoring_character/character.glb","res://demo/assets/recovery_character/character.glb"]:
		if ResourceLoader.exists(path):
			outfit.character_scene=load(path)
			break
	var shirt:Resource=make_item(&"shirt","Alt kumaş",&"cloth",panel(.46,.6,33,41),Color("a84d3f"),Vector3(-.18,1.12,.20),&"Hips")
	shirt.proxy_mesh=panel(.46,.6)
	shirt.mobility=PackedFloat32Array()
	for i in range(99): shirt.mobility.append(0.0 if i<9 else 1.0)
	var upper:Resource=shirt.regions[0]
	upper.id=&"upper"
	upper.label="Üst yarı"
	upper.uv_rect=Rect2(0,0,1,.5)
	for i in range(45): upper.proxy_indices.append(i)
	var lower:Resource=upper.duplicate(true)
	lower.id=&"lower"
	lower.label="Alt yarı"
	lower.uv_rect=Rect2(0,.5,1,.5)
	lower.proxy_indices=PackedInt32Array()
	for i in range(45,99): lower.proxy_indices.append(i)
	shirt.regions.append(lower)
	var tears: Array = []
	var bridges: Array = [[40,49]]
	var seen: Dictionary = {}
	var proxy_ids: PackedInt32Array = shirt.proxy_mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	for i in range(0,proxy_ids.size(),3):
		for pair in [[proxy_ids[i],proxy_ids[i+1]],[proxy_ids[i+1],proxy_ids[i+2]],[proxy_ids[i+2],proxy_ids[i]]]:
			var edge := Vector2i(mini(pair[0],pair[1]),maxi(pair[0],pair[1]))
			if edge.x < 45 and edge.y >= 45 and edge != Vector2i(40,49) and not seen.has(edge):
				tears.append([edge.x,edge.y])
				seen[edge]=true
	shirt.metadata={"tear_edges":tears,"tear_bridge":bridges,"release_pins":[{"stage":3,"indices":[0,1,2,3]},{"stage":4,"indices":[4,5,6,7,8]}]}
	# A prepared visual variant is baked/bound before the first hit.
	var bridge_variant: PackedScene=pack_mesh(panel(.46,.6,33,41,true,false))
	var free_variant: PackedScene=pack_mesh(panel(.46,.6,33,41,true,true))
	for region in shirt.regions:
		region.stages[3].mesh_variant=bridge_variant
		region.stages[4].mesh_variant=free_variant
	for stage in lower.stages:
		for operation in stage.damage_recipe.get("operations",[]): operation["uv"][1]=.75
	var jacket:Resource=make_item(&"jacket","Üst ceket parçası",&"rigid",panel(.49,.32),Color("435d7e"),Vector3(-.18,1.13,.235),&"Hips")
	jacket.material_kind=&"cloth"
	var restrict:Resource=Effect.new()
	restrict.id=&"jacket_holds_shirt"
	restrict.source_item=&"jacket"
	restrict.target_item=&"shirt"
	restrict.target_region=&"upper"
	restrict.mobility_cap=0.0
	restrict.hides_region=true
	restrict.active_until_stage=2
	restrict.priority=10
	jacket.effects.append(restrict)
	var belt:Resource=make_item(&"harness","İkinci kısıtlayıcı",&"rigid",panel(.48,.07,5,2),Color("98724c"),Vector3(-.18,1.02,.26),&"Hips")
	var second:Resource=restrict.duplicate(true)
	second.id=&"harness_holds_shirt"
	second.source_item=&"harness"
	second.mobility_cap=.2
	second.hides_region=false
	second.priority=20
	belt.body_morph=&"ChestCompression"
	belt.fit_morph=&"FitCompression"
	belt.compression=.5
	belt.effects.append(second)
	var armor:Resource=make_item(&"armor","Omuz zırhı",&"rigid",dent_mesh(panel(.32,.23,7,5)),Color("74849a"),Vector3(-.3,1.51,.15),&"UpperArm_R")
	armor.material_kind=&"metal"
	armor.regions[0].stages[1].cut_strength=0.0
	armor.regions[0].stages[2].cut_strength=0.0
	armor.regions[0].stages[2].morph_values={"Dent":.7}
	armor.regions[0].stages[1].damage_recipe=recipe("dent",Vector2(.5,.5),.12,81)
	armor.regions[0].stages[2].damage_recipe=recipe("dent",Vector2(.5,.5),.17,82)
	armor.regions[0].stages[3].mesh_variant=pack_mesh(panel(.34,.25,7,5,true))
	armor.regions[0].stages[4].mesh_variant=armor.regions[0].stages[3].mesh_variant
	var worn := StandardMaterial3D.new()
	worn.albedo_color=Color(.55,.42,.35)
	worn.roughness=.95
	worn.metallic=.2
	armor.regions[0].stages[3].material_override=worn
	var bag:Resource=make_item(&"bag","Bağlı çanta",&"rigid",panel(.13,.16,3,3),Color("c68c5e"),Vector3(-.36,.89,.29),&"Hips")
	bag.connection_points=PackedVector3Array([Vector3.ZERO])
	for stage in bag.regions[0].stages:
		stage.broken_connections=PackedInt32Array([0]) if stage.threshold>=50 else PackedInt32Array()
	bag.metadata={"attach_item":"shirt","triangle":Vector3i(33,42,34),"barycentric":Vector3(.3,.3,.4)}
	for item in [shirt,jacket,belt,armor,bag]:
		if outfit.character_scene==null:
			item.required_bones=PackedStringArray()
			item.anchor_bone=&""
		outfit.items.append(item)
	outfit.timeline.assign([{"time":1.0,"item_id":"jacket","region_id":"body","uv":[.4,.4],"amount":12.0,"type":"slash","seed":1},{"time":2.0,"item_id":"jacket","region_id":"body","uv":[.4,.4],"amount":18.0,"type":"slash","seed":2},{"time":3.0,"item_id":"jacket","region_id":"body","uv":[.4,.4],"amount":25.0,"type":"slash","seed":3},{"time":4.0,"item_id":"jacket","region_id":"body","uv":[.4,.4],"amount":30.0,"type":"slash","seed":4}])
	outfit.metadata={"format":"AeroCloth3D.outfit","version":1,"example":true,"body_colliders":[]}
	if outfit.character_scene!=null:
		var probe: Node = outfit.character_scene.instantiate()
		outfit.metadata["body_colliders"] = BodyCollision.default_specs(_find_skeleton(probe))
		probe.free()
	return outfit
