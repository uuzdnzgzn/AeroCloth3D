@tool
class_name AeroOutfit
extends Resource
## Immutable authoring recipe. Runtime inventory damage is saved separately.
@export var character_scene: PackedScene
@export var items: Array[AeroWearableDefinition] = []
@export var timeline: Array[Dictionary] = []
@export var metadata: Dictionary = {}

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	var ids: Dictionary = {}
	for item in items:
		if item == null:
			errors.append("Empty wearable")
			continue
		if ids.has(item.id): errors.append("Duplicate item: " + str(item.id))
		ids[item.id] = true
		errors.append_array(item.validate())
		if item.source_scene == null: errors.append("No source scene: " + str(item.id))
	for item in items:
		if item == null: continue
		for effect in item.effects:
			if effect != null and not ids.has(effect.target_item): errors.append("Missing target: " + str(effect.target_item))
	for event in timeline:
		if not ids.has(StringName(event.get("item_id",""))): errors.append("Timeline target is absent")
		if not is_finite(float(event.get("time",-1))) or float(event.get("time",-1))<0: errors.append("Invalid timeline time")
	return errors
