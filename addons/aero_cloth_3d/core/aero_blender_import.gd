@tool
class_name AeroBlenderImport
extends RefCounted
## Blender source indices are not assumed to survive glTF seam splitting.
const Outfit = preload("res://addons/aero_cloth_3d/resources/aero_outfit.gd")
const Definition = preload("res://addons/aero_cloth_3d/resources/aero_wearable_definition.gd")
const Region = preload("res://addons/aero_cloth_3d/resources/aero_wearable_region.gd")

static func import_file(path: String) -> Dictionary:
	var errors := PackedStringArray()
	var warnings := PackedStringArray()
	if not FileAccess.file_exists(path): return _result(null,PackedStringArray(["Metadata file not found"]),warnings)
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK: return _result(null,PackedStringArray(["Invalid metadata JSON"]),warnings)
	var data: Variant = parser.data
	if not data is Dictionary or data.get("schema") != "AeroCloth3D.blender" or data.get("version") != 1:
		return _result(null,PackedStringArray(["Unsupported Blender metadata schema/version"]),warnings)
	var filename: Variant = data.get("source_glb")
	if not filename is String or filename.is_empty() or filename != filename.get_file() or filename.contains(":") or filename.contains("\\") or filename.get_extension().to_lower() != "glb":
		return _result(null,PackedStringArray(["source_glb must name a local companion GLB beside metadata"]),warnings)
	var glb_path: String = path.get_base_dir().path_join(filename)
	if not FileAccess.file_exists(glb_path): return _result(null,PackedStringArray(["Companion GLB is missing: "+glb_path]),warnings)
	if data.has("glb_sha256"):
		if not data["glb_sha256"] is String or data["glb_sha256"].length()!=64 or FileAccess.get_sha256(glb_path)!=data["glb_sha256"]:
			return _result(null,PackedStringArray(["Companion GLB hash mismatch; export GLB and metadata together"]),warnings)
	if not data.get("objects") is Array or data["objects"].is_empty(): return _result(null,PackedStringArray(["Metadata has no objects"]),warnings)
	var objects: Dictionary = {}
	for value in data["objects"]:
		if not value is Dictionary:
			errors.append("Object record must be a dictionary")
			continue
		var record: Dictionary = value
		if not record.get("id") is String or record["id"].strip_edges().is_empty() or objects.has(record["id"]):
			errors.append("Object IDs must be nonempty and unique")
			continue
		if not record.get("name") is String or not record.get("type") is String or not record.get("role") is String:
			errors.append("Object needs name, type and role: "+record["id"])
			continue
		objects[record["id"]] = record
		if record["role"] in ["garment","rigid","proxy"] and record["type"]!="MESH": errors.append("Wearable/proxy role requires a mesh: "+record["id"])
		if record["type"]=="MESH":
			if not record.get("topology_fingerprint") is String or record["topology_fingerprint"].is_empty(): errors.append("Missing topology fingerprint: "+record["id"])
			if not _integer(record.get("vertex_count")) or int(record.get("vertex_count",0))<1: errors.append("Invalid source vertex count: "+record["id"])
			if not record.get("damage_uv",{}) is Dictionary: errors.append("Invalid damage UV report: "+record["id"])
			if not record.get("shape_keys",[]) is Array: errors.append("Invalid shape key list: "+record["id"])
			if not record.get("regions",[]) is Array: errors.append("Regions must be an array: "+record["id"])
			else:
				var region_ids: Dictionary = {}
				for rv in record.get("regions",[]):
					if not rv is Dictionary or not rv.get("id") is String or rv.get("id","").is_empty() or region_ids.has(rv.get("id")) or not rv.get("weights") is Array:
						errors.append("Invalid/duplicate source region: "+record["id"])
						continue
					region_ids[rv["id"]] = true
					for weight in rv["weights"]:
						if not weight is Array or weight.size()!=2 or not _integer(weight[0]) or int(weight[0])<0 or int(weight[0])>=int(record.get("vertex_count",0)) or not _number(weight[1]) or float(weight[1])<0 or float(weight[1])>1:
							errors.append("Invalid source region weights: "+record["id"])
	if not errors.is_empty(): return _result(null,errors,warnings)
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var status: Error = document.append_from_file(glb_path,state)
	if status != OK: return _result(null,PackedStringArray(["Could not read companion GLB: "+str(status)]),warnings)
	var scene: Node = document.generate_scene(state)
	if scene == null: return _result(null,PackedStringArray(["Companion GLB produced no scene"]),warnings)
	var scene_ids: Dictionary = {}
	_collect_ids(scene,scene_ids,errors)
	var source := PackedScene.new()
	_own(scene,scene)
	if source.pack(scene)!=OK:
		scene.free()
		return _result(null,PackedStringArray(["Could not pack imported GLB"]),warnings)
	var outfit: AeroOutfit = Outfit.new()
	outfit.metadata = {"format":"AeroCloth3D.outfit","version":1,"blender_metadata":path,"source_glb":glb_path,"source_glb_sha256":FileAccess.get_sha256(glb_path),"source_objects":data["objects"].duplicate(true)}
	var strip_meshes: Array[Node] = []
	for identity in objects:
		var record: Dictionary = objects[identity]
		if record["role"] not in ["garment","rigid","proxy"]: continue
		if not scene_ids.has(identity):
			errors.append("GLB is missing stable object ID: "+identity)
			continue
		var mesh: MeshInstance3D = _mesh(scene_ids[identity])
		if mesh == null or mesh.mesh == null:
			errors.append("Stable object has no imported mesh: "+identity)
			continue
		strip_meshes.append(mesh)
		if record["role"]=="proxy": continue
		var definition: AeroWearableDefinition = Definition.make_example(StringName(identity),&"rigid" if record["role"]=="rigid" else &"skinned")
		definition.display_name = record["name"]
		definition.source_scene = source
		definition.mesh_path = scene.get_path_to(mesh)
		definition.bind_transform = _transform(mesh,scene)
		var skeleton: Skeleton3D = mesh.get_node_or_null(mesh.skeleton) as Skeleton3D
		if skeleton:
			definition.skeleton_path = scene.get_path_to(skeleton)
			if mesh.skin:
				for i in range(mesh.skin.get_bind_count()):
					var bone: StringName = mesh.skin.get_bind_name(i)
					var index: int = mesh.skin.get_bind_bone(i)
					if bone==&"" and index>=0 and index<skeleton.get_bone_count(): bone = skeleton.get_bone_name(index)
					if bone!=&"" and not str(bone) in definition.required_bones: definition.required_bones.append(str(bone))
		definition.metadata = {"blender_object_id":identity,"blender_topology_fingerprint":record["topology_fingerprint"],"topology_fingerprint":record["topology_fingerprint"],"imported_mesh_fingerprint":_mesh_fingerprint(mesh.mesh),"source_vertex_count":record["vertex_count"],"damage_uv_report":record.get("damage_uv",{}).duplicate(true),"mapping_rebuild_required":not record.get("regions",[]).is_empty(),"source_regions":record.get("regions",[]).duplicate(true)}
		var armature: Dictionary=objects.get(record.get("armature_id",""),{})
		definition.metadata["rig_fingerprint"]=JSON.stringify(armature.get("bones",[]),"",true,true).sha256_text()
		if record.get("damage_uv",{}).get("status")!="valid": warnings.append(definition.display_name+": damage UV2 requires validation/repair before local painting")
		if not record.get("regions",[]).is_empty():
			var example_stages: Array[AeroDamageStage] = definition.regions[0].stages
			definition.regions.clear()
			for rr in record["regions"]:
				var region: AeroWearableRegion = Region.new()
				region.id = StringName(rr["id"])
				region.label = rr["id"]
				for stage in example_stages: region.stages.append(stage.duplicate(true))
				definition.regions.append(region)
			warnings.append(definition.display_name+": source region weights retained; rebake proxy mapping after GLB vertex splitting")
		var shape_keys: Array = record.get("shape_keys",[])
		if "FitCompression" in shape_keys: definition.fit_morph = &"FitCompression"
		if "ChestCompression" in shape_keys: definition.body_morph = &"ChestCompression"
		for cid in objects:
			var link: Dictionary = objects[cid].get("connection",{})
			if link.get("item_id")!=identity: continue
			if not scene_ids.has(cid):
				warnings.append("Missing connection node: "+cid)
				continue
			definition.connection_points.append(definition.bind_transform.affine_inverse()*_transform(scene_ids[cid],scene).origin)
			var bone: StringName = StringName(link.get("bone",""))
			if definition.anchor_bone==&"": definition.anchor_bone=bone
			elif bone!=&"" and bone!=definition.anchor_bone: warnings.append(definition.display_name+": connections use different bones; choose a shared anchor explicitly")
		var matches: Array[MeshInstance3D] = []
		for pid in objects:
			if objects[pid]["role"]!="proxy" or not scene_ids.has(pid): continue
			var extras: Dictionary = scene_ids[pid].get_meta("extras",{})
			if str(objects[pid].get("proxy_for",extras.get("ac_proxy_for","")))==identity:
				var proxy: MeshInstance3D = _mesh(scene_ids[pid])
				if proxy: matches.append(proxy)
		if matches.size()==1:
			var proxy: MeshInstance3D = matches[0]
			var relation: Transform3D = definition.bind_transform.affine_inverse()*_transform(proxy,scene)
			if relation.is_equal_approx(Transform3D.IDENTITY) and proxy.mesh is ArrayMesh and proxy.mesh.get_surface_count()==1:
				definition.proxy_mesh=proxy.mesh.duplicate(true)
				definition.motion_mode=&"cloth"
				definition.mobility.resize(definition.proxy_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size())
				definition.mobility.fill(0.0)
				definition.metadata["proxy_object_id"]=_identity(proxy)
				warnings.append(definition.display_name+": proxy imported; paint mobility and rebake visual/region bindings")
			else: warnings.append(definition.display_name+": proxy transform/surfaces require preparation in garment coordinates")
		elif matches.size()>1: errors.append(definition.display_name+": multiple explicit proxies; select one before import")
		outfit.items.append(definition)
	for mesh in strip_meshes:
		if is_instance_valid(mesh) and mesh.get_parent():
			mesh.get_parent().remove_child(mesh)
			mesh.free()
	_own(scene,scene)
	var character := PackedScene.new()
	if character.pack(scene)!=OK: errors.append("Could not pack character without garment/proxy duplicates")
	else: outfit.character_scene=character
	scene.free()
	if outfit.items.is_empty(): warnings.append("No separate garment/rigid objects exported. Combined body_outfit remains the character; add separate garments in the editor.")
	errors.append_array(outfit.validate())
	return _result(outfit if errors.is_empty() else null,errors,warnings)

static func merge(existing: Resource, incoming: Resource) -> Dictionary:
	var errors := PackedStringArray()
	var warnings := PackedStringArray()
	var invalidated := PackedStringArray()
	if not existing is AeroOutfit or not incoming is AeroOutfit: return {"outfit":null,"errors":PackedStringArray(["Both recipes must be AeroOutfit resources"]),"warnings":warnings,"invalidated":invalidated}
	var result: AeroOutfit = incoming.duplicate(true)
	var old_items: Dictionary = {}
	for item in existing.items: old_items[item.id]=item
	var new_ids: Dictionary = {}
	for i in range(result.items.size()):
		var next: AeroWearableDefinition=result.items[i]
		new_ids[next.id]=true
		if not old_items.has(next.id): continue
		var old: AeroWearableDefinition=old_items[next.id]
		var old_fingerprint: String=str(old.metadata.get("topology_fingerprint",""))
		var next_fingerprint: String=str(next.metadata.get("topology_fingerprint",""))
		var imported_changed: bool=str(old.metadata.get("imported_mesh_fingerprint",""))!=str(next.metadata.get("imported_mesh_fingerprint",""))
		var rig_changed: bool=str(old.metadata.get("rig_fingerprint",""))!=str(next.metadata.get("rig_fingerprint",""))
		if old_fingerprint.is_empty() or next_fingerprint.is_empty() or old_fingerprint!=next_fingerprint or imported_changed or rig_changed:
			invalidated.append(str(next.id))
			errors.append("Topology/rig changed or unverified for "+str(next.id)+"; rebake before preserving authored damage/links")
			continue
		var preserved: AeroWearableDefinition=old.duplicate(true)
		preserved.source_scene=next.source_scene
		preserved.mesh_path=next.mesh_path
		preserved.skeleton_path=next.skeleton_path
		preserved.required_bones=next.required_bones.duplicate()
		preserved.metadata.merge(next.metadata.duplicate(true),true)
		result.items[i]=preserved
	for id in old_items:
		if not new_ids.has(id): warnings.append("Removed source item: "+str(id))
	result.timeline.clear()
	for event in existing.timeline:
		if new_ids.has(StringName(event.get("item_id",""))): result.timeline.append(event.duplicate(true))
		else: warnings.append("Timeline event targets absent item and was not copied")
	errors.append_array(result.validate())
	return {"outfit":result if errors.is_empty() else null,"errors":errors,"warnings":warnings,"invalidated":invalidated}

static func _result(outfit: Resource, errors: PackedStringArray, warnings: PackedStringArray) -> Dictionary:
	return {"outfit":outfit,"errors":errors,"warnings":warnings}
static func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))
static func _integer(value: Variant) -> bool:
	return _number(value) and float(value)==floorf(float(value))
static func _identity(node: Node) -> String:
	var direct: Variant=node.get_meta("ac_id","")
	if not str(direct).is_empty(): return str(direct)
	var extras: Variant=node.get_meta("extras",{})
	return str(extras.get("ac_id","")) if extras is Dictionary else ""
static func _collect_ids(node: Node, ids: Dictionary, errors: PackedStringArray) -> void:
	var id: String=_identity(node)
	if not id.is_empty():
		if ids.has(id): errors.append("Duplicate ac_id inside GLB: "+id)
		else: ids[id]=node
	for child in node.get_children(): _collect_ids(child,ids,errors)
static func _mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D: return node
	for child in node.get_children():
		var found: MeshInstance3D=_mesh(child)
		if found: return found
	return null
static func _transform(node: Node, root: Node) -> Transform3D:
	var result:=Transform3D.IDENTITY
	var cursor: Node=node
	while cursor and cursor!=root:
		if cursor is Node3D: result=cursor.transform*result
		cursor=cursor.get_parent()
	return result
static func _own(node: Node, root: Node) -> void:
	if node!=root: node.owner=root
	for child in node.get_children(): _own(child,root)
static func _mesh_fingerprint(mesh: Mesh) -> String:
	var context:=HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	for i in range(mesh.get_surface_count()):
		var arrays: Array=mesh.surface_get_arrays(i)
		context.update(var_to_bytes(arrays[Mesh.ARRAY_VERTEX]))
		context.update(var_to_bytes(arrays[Mesh.ARRAY_INDEX]))
		context.update(var_to_bytes(arrays[Mesh.ARRAY_TEX_UV]))
	return context.finish().hex_encode()
