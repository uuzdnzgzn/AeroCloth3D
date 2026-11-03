extends SceneTree
const Importer = preload("res://addons/aero_cloth_3d/core/aero_blender_import.gd")
const SOURCE := "res://demo/assets/authoring_character/character.aerocloth.json"
var checks := 0
var failures := 0
var directory := "/tmp/aero-import-tests"

func _initialize() -> void: call_deferred("_run")
func check(ok: bool,message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func write_metadata(data: Variant,name: String="fixture.aerocloth.json") -> String:
	var path: String=directory.path_join(name)
	var file:=FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	return path
func count_kind(node: Node,kind: String) -> int:
	var count:=1 if node.is_class(kind) else 0
	for child in node.get_children(): count += count_kind(child,kind)
	return count

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	var source: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
	DirAccess.copy_absolute(ProjectSettings.globalize_path(SOURCE.get_base_dir().path_join(source["source_glb"])),directory.path_join(source["source_glb"]))
	var actual: Dictionary=Importer.import_file(SOURCE)
	check(actual["outfit"]!=null and actual["errors"].is_empty(),"Actual Blender companion imports without errors")
	var actual_outfit: AeroOutfit=actual["outfit"]
	check(actual_outfit.items.is_empty() and not actual["warnings"].is_empty(),"Combined body_outfit is retained as character instead of pretending it is separate wardrobe")
	var character: Node=actual_outfit.character_scene.instantiate()
	check(count_kind(character,"Skeleton3D")==1 and count_kind(character,"MeshInstance3D")>0,"Actual character retains skinned body and rig")
	character.free()
	var garment: Dictionary=source.duplicate(true)
	var identity: String=""
	for record in garment["objects"]:
		if record["type"]=="MESH":
			record["role"]="garment"
			record["name"]="Renamed garment label"
			identity=record["id"]
	var result: Dictionary=Importer.import_file(write_metadata(garment))
	check(result["outfit"]!=null and result["errors"].is_empty(),"Separate garment role imports using actual GLB extras")
	var outfit: AeroOutfit=result["outfit"]
	check(outfit.items.size()==1 and str(outfit.items[0].id)==identity,"Stable exported object UUID is item identity")
	var definition: AeroWearableDefinition=outfit.items[0]
	check(definition.display_name=="Renamed garment label" and not definition.mesh_path.is_empty(),"Display name changes do not affect stable mesh selection")
	var garment_scene: Node=definition.source_scene.instantiate()
	check(garment_scene.get_node_or_null(definition.mesh_path) is MeshInstance3D,"Imported mesh path resolves without name guessing")
	garment_scene.free()
	check(definition.required_bones.size()>0 and not definition.skeleton_path.is_empty(),"Skin bone requirements imported")
	check(definition.connection_points.size()==2 and definition.anchor_bone==&"Chest","Connection empties map to local points and bone")
	check(definition.regions.size()==3 and definition.regions[0].proxy_indices.is_empty(),"Source region groups become definitions without unsafe source-index reuse")
	check(definition.metadata["mapping_rebuild_required"] and definition.metadata["source_regions"].size()==3,"Unverified region mapping is explicitly marked for rebake")
	check(definition.fit_morph==&"FitCompression" and definition.body_morph==&"ChestCompression","Prepared morph channel names retained")
	check(not str(definition.metadata["topology_fingerprint"]).is_empty(),"Source topology fingerprint preserved")
	character=outfit.character_scene.instantiate()
	check(count_kind(character,"MeshInstance3D")==0 and count_kind(character,"Skeleton3D")==1,"Character scene excludes garment duplicates but retains rig")
	character.free()
	check(outfit.validate().is_empty(),"Imported outfit resource validates")
	var saved: Error=ResourceSaver.save(outfit,directory.path_join("imported.tres"))
	check(saved==OK,"Imported in-memory GLB scene and wardrobe save to a standalone resource")
	var reloaded: AeroOutfit=ResourceLoader.load(directory.path_join("imported.tres"),"",ResourceLoader.CACHE_MODE_IGNORE) as AeroOutfit
	check(reloaded!=null and reloaded.items.size()==1 and reloaded.items[0].id==definition.id,"Saved import reloads with stable identity")
	check(Importer.import_file("/tmp/no-such-aero-metadata.json")["outfit"]==null,"Missing metadata rejected")
	check(Importer.import_file(write_metadata({}))["outfit"]==null,"Unknown schema rejected")
	var broken: Dictionary=source.duplicate(true)
	broken["source_glb"]="https://example.invalid/model.glb"
	check(Importer.import_file(write_metadata(broken))["outfit"]==null,"Remote companion rejected")
	broken=source.duplicate(true)
	broken["source_glb"]="../character.glb"
	check(Importer.import_file(write_metadata(broken))["outfit"]==null,"Parent-path companion rejected")
	broken=source.duplicate(true)
	broken["source_glb"]="missing.glb"
	check(Importer.import_file(write_metadata(broken))["outfit"]==null,"Missing GLB rejected")
	broken=source.duplicate(true)
	broken["glb_sha256"]="0".repeat(64)
	check(Importer.import_file(write_metadata(broken))["outfit"]==null,"Mismatched GLB/JSON hash rejected")
	broken=source.duplicate(true)
	broken["objects"][1]["id"]=broken["objects"][0]["id"]
	check(Importer.import_file(write_metadata(broken))["outfit"]==null,"Duplicate object IDs rejected")
	broken=source.duplicate(true)
	for record in broken["objects"]:
		if record["type"]=="MESH": record.erase("topology_fingerprint")
	check(Importer.import_file(write_metadata(broken))["outfit"]==null,"Missing topology identity rejected")
	broken=garment.duplicate(true)
	for record in broken["objects"]:
		if record["type"]=="MESH": record["id"]="not-present-in-glb"
	check(Importer.import_file(write_metadata(broken))["outfit"]==null,"Missing stable ID inside GLB blocks import")
	broken=source.duplicate(true)
	for record in broken["objects"]:
		if record["type"]=="MESH": record["regions"][0]["weights"]=[[999999,1.0]]
	check(Importer.import_file(write_metadata(broken))["outfit"]==null,"Out-of-range source weights rejected")
	# Reimport authoring merge is resource-copy based and never silently reuses
	# bindings when topology changes.
	var authored: AeroOutfit=outfit.duplicate(true)
	authored.items[0].regions[0].stages[1].threshold=13.0
	authored.items[0].damage_recipe={"authored_brush":"cut"}
	authored.items[0].compression=.42
	authored.timeline.append({"time":.4,"item_id":identity,"type":"hit"})
	var incoming: AeroOutfit=outfit.duplicate(true)
	incoming.items[0].display_name="New label from export"
	var merged: Dictionary=Importer.merge(authored,incoming)
	check(merged["outfit"]!=null and merged["errors"].is_empty(),"Unchanged topology merges")
	var merged_item: AeroWearableDefinition=merged["outfit"].items[0]
	check(merged_item.regions[0].stages[1].threshold==13.0 and merged_item.damage_recipe["authored_brush"]=="cut","Reimport preserves authored stages and map recipe")
	check(is_equal_approx(merged_item.compression,.42) and merged["outfit"].timeline.size()==1,"Reimport preserves fit settings and timeline")
	check(incoming.items[0].regions[0].stages[1].threshold==10.0,"Reimport does not mutate incoming resources")
	incoming.items[0].metadata["topology_fingerprint"]="changed"
	merged=Importer.merge(authored,incoming)
	check(merged["outfit"]==null and merged["invalidated"].size()==1 and not merged["errors"].is_empty(),"Topology change invalidates mappings and blocks silent authored-state reuse")
	check(authored.items[0].regions[0].stages[1].threshold==13.0,"Failed merge leaves original authoring intact")
	incoming=outfit.duplicate(true)
	incoming.items[0].metadata["imported_mesh_fingerprint"]="exporter changed glTF split ordering"
	check(Importer.merge(authored,incoming)["outfit"]==null,"Changed imported vertex layout invalidates bindings even when Blender fingerprint is unchanged")
	incoming=outfit.duplicate(true)
	incoming.items[0].metadata["rig_fingerprint"]="rest pose changed"
	check(Importer.merge(authored,incoming)["outfit"]==null,"Changed rig/rest pose requires preparation review")
	print("BLENDER_IMPORT_TESTS: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
