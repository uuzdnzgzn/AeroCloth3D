@tool
class_name AeroWearableDefinition
extends Resource

@export var id: StringName = &""
@export var display_name: String = ""
@export var source_scene: PackedScene
@export var mesh_path: NodePath
@export var skeleton_path: NodePath
@export var anchor_bone: StringName = &""
@export var bind_transform: Transform3D = Transform3D.IDENTITY
@export var motion_mode: StringName = &"skinned"
@export var required_bones: PackedStringArray = PackedStringArray()
@export var fit_morph: StringName = &""
@export var body_morph: StringName = &""
@export_range(0.0, 1.0) var compression: float = 0.0
@export var proxy_mesh: ArrayMesh
@export var mobility: PackedFloat32Array = PackedFloat32Array()
@export var connection_points: PackedVector3Array = PackedVector3Array()
@export var base_color: Color = Color.WHITE
@export var material_kind: StringName = &"cloth"
@export var damage_recipe: Dictionary = {}
@export var metadata: Dictionary = {}
@export var regions: Array[AeroWearableRegion] = []
@export var effects: Array[AeroLayerEffect] = []
@export var mask_resolution: int = 512

func validate() -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	if id == &"": errors.append("Definition id is empty")
	if display_name.strip_edges().is_empty(): errors.append("Definition display name is empty")
	if motion_mode not in [&"skinned", &"cloth", &"rigid"]: errors.append("Unknown motion mode")
	if not bind_transform.origin.is_finite() or not bind_transform.basis.x.is_finite() or not bind_transform.basis.y.is_finite() or not bind_transform.basis.z.is_finite() or absf(bind_transform.basis.determinant()) < 0.000001: errors.append("Bind transform must be finite and invertible")
	if not is_finite(compression) or compression < 0.0 or compression > 1.0: errors.append("Compression must be in [0, 1]")
	for value: float in mobility:
		if not is_finite(value) or value < 0.0 or value > 1.0: errors.append("Proxy mobility values must be in [0, 1]")
	for point: Vector3 in connection_points:
		if not point.is_finite(): errors.append("Connection points must be finite")
	if not is_finite(base_color.r) or not is_finite(base_color.g) or not is_finite(base_color.b) or not is_finite(base_color.a): errors.append("Base color must be finite")
	if material_kind == &"": errors.append("Material kind is empty")
	if mask_resolution < 32 or mask_resolution > 4096 or (mask_resolution & (mask_resolution - 1)) != 0: errors.append("Mask resolution must be a power of two from 32 to 4096")
	var bones: Dictionary = {}
	for bone: String in required_bones:
		if bone.is_empty() or bones.has(bone): errors.append("Required bone names must be nonempty and unique")
		bones[bone] = true
	var region_ids: Dictionary = {}
	if regions.is_empty(): errors.append("Definition needs at least one damage region")
	for region: AeroWearableRegion in regions:
		if region == null:
			errors.append("Definition contains a null region")
			continue
		for message: String in region.validate(): errors.append("Region %s: %s" % [region.id, message])
		if region_ids.has(region.id): errors.append("Region ids must be unique")
		region_ids[region.id] = true
	var effect_ids: Dictionary = {}
	for effect: AeroLayerEffect in effects:
		if effect == null:
			errors.append("Definition contains a null effect")
			continue
		for message: String in effect.validate(): errors.append("Effect %s: %s" % [effect.id, message])
		if effect_ids.has(effect.id): errors.append("Effect ids must be unique within an item")
		effect_ids[effect.id] = true
		if effect.source_item in [&"", id] and not region_ids.has(effect.source_region): errors.append("Effect source region is absent from its owner")
	return errors

static func make_example(item_id: StringName = &"sample", kind: StringName = &"skinned") -> AeroWearableDefinition:
	var definition: AeroWearableDefinition = AeroWearableDefinition.new()
	definition.id = item_id
	definition.display_name = str(item_id).capitalize()
	definition.motion_mode = kind
	var region: AeroWearableRegion = AeroWearableRegion.new()
	region.id = &"body"
	var stage_ids: Array[StringName] = [&"intact", &"scuffed", &"torn", &"loose", &"detached"]
	var thresholds: Array[float] = [0.0, 10.0, 25.0, 50.0, 80.0]
	for index: int in range(5):
		var stage: AeroDamageStage = AeroDamageStage.new()
		stage.id = stage_ids[index]
		stage.label = ["Sağlam", "Aşınmış", "Yırtılmış", "Sarkıyor", "Kopmuş"][index]
		stage.threshold = thresholds[index]
		stage.cut_strength = float(index) * 0.25
		stage.wear_strength = float(index) * 0.25
		stage.normal_strength = float(index) * 0.25
		if index >= 3: stage.broken_connections = PackedInt32Array([0])
		if index == 4:
			stage.broken_connections = PackedInt32Array([0, 1])
			stage.release_motion = true
		region.stages.append(stage)
	definition.regions.append(region)
	return definition
