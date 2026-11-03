@tool
class_name AeroLayerEffect
extends Resource

@export var id: StringName = &""
@export var source_item: StringName = &""
@export var source_region: StringName = &"body"
@export var target_item: StringName = &""
@export var target_region: StringName = &"body"
@export_range(0.0, 1.0) var mobility_cap: float = 1.0
@export var priority: int = 0
@export var hides_region: bool = false
@export var active_until_stage: int = 3

func validate() -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	if id == &"": errors.append("Layer effect id is empty")
	if source_region == &"" or target_item == &"" or target_region == &"": errors.append("Layer effect needs source region, target item and target region")
	if not is_finite(mobility_cap) or mobility_cap < 0.0 or mobility_cap > 1.0: errors.append("Mobility cap must be in [0, 1]")
	if active_until_stage < 0: errors.append("Active-until stage must be nonnegative")
	return errors
