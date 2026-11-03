@tool
class_name AeroDamageStage
extends Resource
## A complete prepared visual state, not a sequence of incremental mutations.

@export var id: StringName = &"intact"
@export var label: String = "Sağlam"
@export var threshold: float = 0.0
@export_range(0.0, 1.0) var cut_strength: float = 0.0
@export_range(0.0, 1.0) var wear_strength: float = 0.0
@export_range(0.0, 1.0) var burn_strength: float = 0.0
@export_range(0.0, 1.0) var blood_strength: float = 0.0
@export_range(0.0, 1.0) var normal_strength: float = 0.0
@export var morph_values: Dictionary = {}
@export var broken_connections: PackedInt32Array = PackedInt32Array()
@export var mesh_variant: PackedScene
@export var material_override: Material
@export var release_motion: bool = false
@export var damage_recipe: Dictionary = {}

func validate() -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	if id == &"": errors.append("Stage id is empty")
	if not is_finite(threshold) or threshold < 0.0: errors.append("Stage threshold must be finite and nonnegative")
	if not damage_recipe.is_empty():
		if damage_recipe.get("format", "") != "aero_damage_canvas" or damage_recipe.get("version", 0) != 1 or not damage_recipe.get("operations", null) is Array: errors.append("Stage damage recipe has an invalid canvas format")
	for property: String in ["cut_strength", "wear_strength", "burn_strength", "blood_strength", "normal_strength"]:
		var value: float = get(property)
		if not is_finite(value) or value < 0.0 or value > 1.0: errors.append(property + " must be in [0, 1]")
	var seen: Dictionary = {}
	for connection: int in broken_connections:
		if connection < 0 or seen.has(connection): errors.append("Broken connection indices must be unique and nonnegative")
		seen[connection] = true
	for key: Variant in morph_values:
		var value: Variant = morph_values[key]
		if typeof(key) not in [TYPE_STRING, TYPE_STRING_NAME] or str(key).is_empty(): errors.append("Morph names must be nonempty strings")
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or absf(float(value)) > 1.0: errors.append("Morph values must be finite in [-1, 1]")
	return errors
