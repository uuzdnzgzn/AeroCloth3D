@tool
class_name AeroWearableRegion
extends Resource

@export var id: StringName = &"body"
@export var label: String = "Ana bölge"
@export var uv_rect: Rect2 = Rect2(0.0, 0.0, 1.0, 1.0)
@export var proxy_indices: PackedInt32Array = PackedInt32Array()
@export_range(0.0, 1.0) var base_mobility: float = 1.0
@export var stages: Array[AeroDamageStage] = []
@export var damage_multiplier: Dictionary = {}
@export var bounds: AABB = AABB()

func validate() -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	if id == &"": errors.append("Region id is empty")
	if not uv_rect.position.is_finite() or not uv_rect.size.is_finite() or uv_rect.size.x <= 0.0 or uv_rect.size.y <= 0.0 or uv_rect.position.x < 0.0 or uv_rect.position.y < 0.0 or uv_rect.end.x > 1.0 or uv_rect.end.y > 1.0: errors.append("Region UV rectangle must lie within [0, 1]")
	if not is_finite(base_mobility) or base_mobility < 0.0 or base_mobility > 1.0: errors.append("Base mobility must be in [0, 1]")
	if not bounds.position.is_finite() or not bounds.size.is_finite() or bounds.size.x < 0.0 or bounds.size.y < 0.0 or bounds.size.z < 0.0: errors.append("Region bounds must be finite with nonnegative size")
	var seen_indices: Dictionary = {}
	for index: int in proxy_indices:
		if index < 0 or seen_indices.has(index): errors.append("Proxy indices must be unique and nonnegative")
		seen_indices[index] = true
	if stages.is_empty(): errors.append("Region needs an intact stage")
	var previous: float = -1.0
	var stage_ids: Dictionary = {}
	for index: int in range(stages.size()):
		var stage: AeroDamageStage = stages[index]
		if stage == null:
			errors.append("Region contains a null damage stage")
			continue
		for message: String in stage.validate(): errors.append("Stage %d: %s" % [index, message])
		if index == 0 and stage.threshold != 0.0: errors.append("Intact stage threshold must be zero")
		if stage.threshold <= previous: errors.append("Stage thresholds must increase strictly")
		if stage_ids.has(stage.id): errors.append("Stage ids must be unique")
		stage_ids[stage.id] = true
		previous = stage.threshold
	for key: Variant in damage_multiplier:
		var value: Variant = damage_multiplier[key]
		if typeof(key) not in [TYPE_STRING, TYPE_STRING_NAME] or str(key).is_empty(): errors.append("Damage types must be nonempty strings")
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) < 0.0: errors.append("Damage multipliers must be finite and nonnegative")
	return errors
