class_name AeroClothLayerState
extends RefCounted
## Conservative authored region coverage. Only fully safe cover suppresses a region.
## Hiding removes its draw submission; it does NOT compact skin vertices or free memory.
## Collision proxies are deliberately not visibility children and stay independent.

signal changed

var _regions: Dictionary = {}
var _covers: Dictionary = {}
var _visibility: Dictionary = {}


func set_region(id: StringName, node: Node3D, base_visible: bool = true) -> void:
	_regions[id] = {"node": node, "base_visible": base_visible}
	recompute()


func set_region_enabled(id: StringName, enabled: bool) -> void:
	if _regions.has(id):
		_regions[id]["base_visible"] = enabled
		recompute()


func set_cover(id: StringName, region_ids: Array[StringName], fully_covering: bool) -> void:
	_covers[id] = {"regions": region_ids.duplicate(), "fully_covering": fully_covering}
	recompute()


func remove_cover(id: StringName) -> void:
	_covers.erase(id)
	recompute()


func recompute() -> void:
	for id: StringName in _regions:
		var region: Dictionary = _regions[id]
		var should_draw: bool = bool(region["base_visible"])
		for cover_id: StringName in _covers:
			var cover: Dictionary = _covers[cover_id]
			if bool(cover["fully_covering"]) and id in cover["regions"]:
				should_draw = false
				break
		_visibility[id] = should_draw
		var node: Node3D = region["node"] as Node3D
		if is_instance_valid(node):
			node.visible = should_draw
	changed.emit()


func is_region_visible(id: StringName) -> bool:
	return bool(_visibility.get(id, false))


func get_region_count() -> int:
	return _regions.size()


func get_hidden_region_count() -> int:
	var count: int = 0
	for visible_value: bool in _visibility.values():
		if not visible_value:
			count += 1
	return count
