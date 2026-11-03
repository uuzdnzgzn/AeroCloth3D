class_name AeroWearableController
extends Node
## Runtime state never mutates authoring Resources or directly changes scene nodes.

signal damage_applied(result: Dictionary)
signal stage_changed(item: StringName, region: StringName, old_stage: int, new_stage: int)
signal attachment_broken(item: StringName, region: StringName, index: int)
signal piece_detached(item: StringName, region: StringName)
signal state_changed(item: StringName)

var validation_errors: PackedStringArray = PackedStringArray()
var validation_warnings: PackedStringArray = PackedStringArray()
var _definitions: Dictionary = {}
var _items: Dictionary = {}
var _effects: Dictionary = {}
var _seen_hits: Dictionary = {}
var _transaction_active: bool = false
var _pending: Array[Dictionary] = []

func register_item(definition: AeroWearableDefinition, instance_id: StringName = &"") -> bool:
	validation_errors.clear()
	validation_warnings.clear()
	if _transaction_active or definition == null:
		validation_errors.append("Registration needs a definition and no active transaction")
		return false
	validation_errors = definition.validate()
	var key: StringName = definition.id if instance_id == &"" else instance_id
	if _items.has(key): validation_errors.append("Item instance id is already registered")
	if not validation_errors.is_empty(): return false
	var candidates: Dictionary = _definitions.duplicate()
	candidates[key] = definition
	_validate_effect_graph(candidates)
	if not validation_errors.is_empty(): return false
	_definitions[key] = definition
	_items[key] = _fresh_item(key, definition, false)
	_recompute_morphs(key)
	_recompute_effects()
	for warning: String in validation_warnings: push_warning(warning)
	state_changed.emit(key)
	return true

func equip(id: StringName) -> bool:
	return _set_equipped(id, true)

func unequip(id: StringName) -> bool:
	return _set_equipped(id, false)

func _set_equipped(id: StringName, value: bool) -> bool:
	if not _items.has(id): return false
	if _transaction_active:
		_pending.append({"op":"equip", "id":id, "value":value})
		return true
	if bool(_items[id]["equipped"]) == value: return true
	_items[id]["equipped"] = value
	_recompute_effects()
	_transaction_active = true
	state_changed.emit(id)
	_drain_pending()
	_transaction_active = false
	return true

func apply_hit(hit: Dictionary) -> Dictionary:
	if _transaction_active:
		_pending.append({"op":"hit", "hit":hit.duplicate(true)})
		return {"accepted":false, "queued":true, "reason":"queued"}
	_transaction_active = true
	var result: Dictionary = _apply_hit_internal(hit)
	_notify_damage(result)
	_drain_pending()
	_transaction_active = false
	return result.duplicate(true)

func _drain_pending() -> void:
	# Iterative queue: signal listeners see a committed state; nested hits wait.
	while not _pending.is_empty():
		var request: Dictionary = _pending.pop_front()
		match request["op"]:
			"hit": _notify_damage(_apply_hit_internal(request["hit"]))
			"equip":
				var id: StringName = request["id"]
				if _items.has(id) and _items[id]["equipped"] != request["value"]:
					_items[id]["equipped"] = request["value"]
					_recompute_effects()
					state_changed.emit(id)
			"reset": _reset_internal(request["id"])

func _reject(reason: String) -> Dictionary:
	return {"accepted":false, "queued":false, "reason":reason}

func _apply_hit_internal(input: Dictionary) -> Dictionary:
	var parsed: Dictionary = _normalize_hit(input)
	if not parsed.get("valid", false): return _reject(parsed.get("reason", "invalid_hit"))
	var hit: Dictionary = parsed["hit"]
	var id: StringName = hit["item_id"]
	if not _items.has(id): return _reject("unknown_item")
	if not bool(_items[id]["equipped"]): return _reject("unequipped")
	var hit_id: String = hit["hit_id"]
	if not hit_id.is_empty() and _seen_hits.has(hit_id): return _reject("duplicate_hit")
	var region: AeroWearableRegion = _find_hit_region(_definitions[id], hit)
	if region == null: return _reject("unknown_or_unmatched_region")
	hit["region_id"] = region.id
	if not bool(hit["has_uv"]): hit["uv"] = region.uv_rect.get_center()
	hit["has_uv"] = true
	var added_damage: float = float(hit["amount"]) * float(region.damage_multiplier.get(hit["type"], 1.0))
	var state: Dictionary = _items[id]["regions"][region.id]
	var total: float = float(state["damage"]) + added_damage
	if not is_finite(total): return _reject("damage_overflow")
	var old_stage: int = state["stage"]
	var old_broken: Array = state["broken_connections"].duplicate()
	var old_detached: bool = state["detached"]
	state["damage"] = total
	state["stage"] = _stage_for_damage(region, total)
	state["stamps"].append(hit.duplicate(true))
	_apply_prepared_stage(region, state)
	if not hit_id.is_empty(): _seen_hits[hit_id] = id
	_recompute_morphs(id)
	_recompute_effects()
	var newly_broken: Array[int] = []
	for connection: int in state["broken_connections"]:
		if connection not in old_broken: newly_broken.append(connection)
	return {"accepted":true,"queued":false,"reason":"applied","item_id":id,"region_id":region.id,"hit_id":hit_id,"uv":hit["uv"],"damage":total,"applied_amount":added_damage,"old_stage":old_stage,"stage":state["stage"],"stage_id":state["stage_id"],"broken_connections":state["broken_connections"].duplicate(),"newly_broken":newly_broken,"detached":state["detached"],"newly_detached":not old_detached and bool(state["detached"])}

func _notify_damage(result: Dictionary) -> void:
	if not result.get("accepted", false): return
	var id: StringName = result["item_id"]
	var region_id: StringName = result["region_id"]
	damage_applied.emit(result.duplicate(true))
	if result["old_stage"] != result["stage"]: stage_changed.emit(id, region_id, result["old_stage"], result["stage"])
	for index: int in result["newly_broken"]: attachment_broken.emit(id, region_id, index)
	if result["newly_detached"]: piece_detached.emit(id, region_id)
	state_changed.emit(id)

func _number(value: Variant) -> bool:
	return typeof(value) in [TYPE_FLOAT, TYPE_INT]

func _normalize_hit(input: Dictionary) -> Dictionary:
	for key: String in ["item_id", "region_id", "hit_id", "type"]:
		if input.has(key) and typeof(input[key]) not in [TYPE_STRING, TYPE_STRING_NAME]: return {"valid":false,"reason":"invalid_" + key}
	if str(input.get("item_id", "")).is_empty(): return {"valid":false,"reason":"missing_item"}
	var amount: Variant = input.get("amount", 0.0)
	if not _number(amount) or not is_finite(float(amount)) or float(amount) < 0.0: return {"valid":false,"reason":"invalid_amount"}
	var uv: Vector2 = Vector2.ZERO
	if input.has("uv"):
		var candidate: Variant = input["uv"]
		if candidate is Vector2: uv = candidate
		elif candidate is Array and candidate.size() == 2 and _number(candidate[0]) and _number(candidate[1]): uv = Vector2(float(candidate[0]), float(candidate[1]))
		else: return {"valid":false,"reason":"invalid_uv"}
		if not uv.is_finite() or uv.x < 0.0 or uv.y < 0.0 or uv.x > 1.0 or uv.y > 1.0: return {"valid":false,"reason":"invalid_uv"}
	var normalized: Dictionary = {"item_id":StringName(input["item_id"]),"region_id":StringName(input.get("region_id", "")),"hit_id":str(input.get("hit_id", "")),"type":str(input.get("type", "cut")),"amount":float(amount),"uv":uv,"has_uv":input.has("uv")}
	for key: String in ["position", "direction", "impulse"]:
		var value: Variant = input.get(key, Vector3.ZERO)
		var vector: Vector3 = Vector3.ZERO
		if value is Vector3: vector = value
		elif value is Array and value.size() == 3 and _number(value[0]) and _number(value[1]) and _number(value[2]): vector = Vector3(float(value[0]), float(value[1]), float(value[2]))
		else: return {"valid":false,"reason":"invalid_" + key}
		if not vector.is_finite(): return {"valid":false,"reason":"invalid_" + key}
		normalized[key] = vector
	var seed_value: Variant = input.get("seed", 0)
	if not _number(seed_value) or not is_finite(float(seed_value)) or float(seed_value) != floorf(float(seed_value)) or absf(float(seed_value)) > 9007199254740991.0: return {"valid":false,"reason":"invalid_seed"}
	normalized["seed"] = int(seed_value)
	var angle: Variant = input.get("angle", 0.0)
	if not _number(angle) or not is_finite(float(angle)): return {"valid":false,"reason":"invalid_angle"}
	normalized["angle"] = float(angle)
	return {"valid":true,"hit":normalized}

func _find_hit_region(definition: AeroWearableDefinition, hit: Dictionary) -> AeroWearableRegion:
	var region_id: StringName = hit["region_id"]
	if region_id != &"":
		for region: AeroWearableRegion in definition.regions:
			if region.id == region_id: return region
		return null
	if not hit["has_uv"]: return definition.regions[0] if definition.regions.size() == 1 else null
	var candidates: Array[AeroWearableRegion] = []
	var uv: Vector2 = hit["uv"]
	for region: AeroWearableRegion in definition.regions:
		if uv.x >= region.uv_rect.position.x and uv.y >= region.uv_rect.position.y and uv.x <= region.uv_rect.end.x and uv.y <= region.uv_rect.end.y: candidates.append(region)
	candidates.sort_custom(func(a: AeroWearableRegion, b: AeroWearableRegion) -> bool: return str(a.id) < str(b.id))
	return candidates[0] if not candidates.is_empty() else null

func _stage_for_damage(region: AeroWearableRegion, damage: float) -> int:
	var selected: int = 0
	for index: int in range(region.stages.size()):
		if damage >= region.stages[index].threshold: selected = index
	return selected

func _fresh_item(id: StringName, definition: AeroWearableDefinition, equipped: bool) -> Dictionary:
	var regions: Dictionary = {}
	for region: AeroWearableRegion in definition.regions:
		var state: Dictionary = {"damage":0.0,"stage":0,"stamps":[],"broken_connections":[],"detached":false}
		_apply_prepared_stage(region, state)
		regions[region.id] = state
	return {"instance_id":id,"definition":definition.id,"definition_id":definition.id,"equipped":equipped,"regions":regions,"prepared_morphs":{}}

func _apply_prepared_stage(region: AeroWearableRegion, state: Dictionary) -> void:
	var stage: AeroDamageStage = region.stages[int(state["stage"])]
	state["stage_id"] = stage.id
	for property: String in ["cut_strength", "wear_strength", "burn_strength", "blood_strength", "normal_strength"]: state[property] = stage.get(property)
	state["morph_values"] = stage.morph_values.duplicate(true)
	state["mesh_variant"] = stage.mesh_variant.resource_path if stage.mesh_variant != null else ""
	state["material_override"] = stage.material_override.resource_path if stage.material_override != null else ""
	var broken: Array = state["broken_connections"]
	for index: int in range(int(state["stage"]) + 1):
		for connection: int in region.stages[index].broken_connections:
			if connection not in broken: broken.append(connection)
		state["detached"] = bool(state["detached"]) or region.stages[index].release_motion
	broken.sort()

func _recompute_morphs(id: StringName) -> void:
	var prepared: Dictionary = {}
	var region_ids: Array = _items[id]["regions"].keys()
	region_ids.sort()
	for region_id: Variant in region_ids:
		var morphs: Dictionary = _items[id]["regions"][region_id]["morph_values"]
		for channel: Variant in morphs:
			if not prepared.has(channel) or absf(float(morphs[channel])) > absf(float(prepared[channel])): prepared[channel] = morphs[channel]
	_items[id]["prepared_morphs"] = prepared

func _resolve_reference(reference: StringName, owner: StringName, definitions: Dictionary) -> StringName:
	var own_definition: AeroWearableDefinition = definitions[owner]
	if reference == &"" or reference == own_definition.id: return owner
	if definitions.has(reference): return reference
	var matches: Array[StringName] = []
	for id: StringName in definitions:
		if definitions[id].id == reference: matches.append(id)
	return matches[0] if matches.size() == 1 else reference

func _all_authored_effects(definitions: Dictionary) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for owner: StringName in definitions:
		var definition: AeroWearableDefinition = definitions[owner]
		for effect: AeroLayerEffect in definition.effects:
			if effect != null: results.append({"owner":owner,"resource":effect,"source":_resolve_reference(effect.source_item, owner, definitions),"target":_resolve_reference(effect.target_item, owner, definitions)})
	results.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["owner"]) + "/" + str(a["resource"].id) < str(b["owner"]) + "/" + str(b["resource"].id))
	return results

func _validate_effect_graph(definitions: Dictionary) -> void:
	var graph: Dictionary = {}
	var priority_targets: Dictionary = {}
	for record: Dictionary in _all_authored_effects(definitions):
		var effect: AeroLayerEffect = record["resource"]
		var source: StringName = record["source"]
		var target: StringName = record["target"]
		for endpoint: Array in [[source, effect.source_region], [target, effect.target_region]]:
			if definitions.has(endpoint[0]):
				var found: bool = false
				for region: AeroWearableRegion in definitions[endpoint[0]].regions:
					if region.id == endpoint[1]: found = true
				if not found: validation_errors.append("Effect references missing region: %s/%s" % endpoint)
		var source_key: String = str(source) + "/" + str(effect.source_region)
		var target_key: String = str(target) + "/" + str(effect.target_region)
		if not graph.has(source_key): graph[source_key] = []
		graph[source_key].append(target_key)
		var priority_key: String = target_key + "/" + str(effect.priority)
		if priority_targets.has(priority_key):
			var earlier: AeroLayerEffect = priority_targets[priority_key]
			if earlier.mobility_cap != effect.mobility_cap or earlier.hides_region != effect.hides_region: validation_warnings.append("Conflicting effects share priority %d for %s; minimum mobility and OR coverage apply" % [effect.priority, target_key])
		else: priority_targets[priority_key] = effect
	var marks: Dictionary = {}
	for node_key: String in graph:
		if _graph_has_cycle(node_key, graph, marks):
			validation_errors.append("Layer effect graph contains a source-to-target cycle")
			break

func _graph_has_cycle(key: String, graph: Dictionary, marks: Dictionary) -> bool:
	if marks.get(key, 0) == 1: return true
	if marks.get(key, 0) == 2: return false
	marks[key] = 1
	for next: String in graph.get(key, []):
		if _graph_has_cycle(next, graph, marks): return true
	marks[key] = 2
	return false

func _recompute_effects() -> void:
	_effects.clear()
	for id: StringName in _items:
		var definition: AeroWearableDefinition = _definitions[id]
		var regions: Dictionary = {}
		for region: AeroWearableRegion in definition.regions: regions[region.id] = {"mobility":region.base_mobility,"visible":bool(_items[id]["equipped"]),"sources":[]}
		_effects[id] = regions
	for record: Dictionary in _all_authored_effects(_definitions):
		var effect: AeroLayerEffect = record["resource"]
		var source: StringName = record["source"]
		var target: StringName = record["target"]
		if not _items.has(source) or not _items.has(target) or not _items[source]["equipped"]: continue
		if not _items[source]["regions"].has(effect.source_region) or not _effects[target].has(effect.target_region): continue
		var source_state: Dictionary = _items[source]["regions"][effect.source_region]
		if int(source_state["stage"]) > effect.active_until_stage or bool(source_state["detached"]): continue
		var target_state: Dictionary = _effects[target][effect.target_region]
		target_state["mobility"] = minf(float(target_state["mobility"]), effect.mobility_cap)
		target_state["visible"] = bool(target_state["visible"]) and not effect.hides_region
		target_state["sources"].append({"id":effect.id,"source_item":source,"source_region":effect.source_region,"priority":effect.priority,"mobility_cap":effect.mobility_cap,"hides_region":effect.hides_region})
	for id: StringName in _effects:
		for region_id: StringName in _effects[id]:
			_effects[id][region_id]["sources"].sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				if a["priority"] != b["priority"]: return a["priority"] > b["priority"]
				return str(a["source_item"]) + "/" + str(a["id"]) < str(b["source_item"]) + "/" + str(b["id"])
			)

func get_item_state(id: StringName) -> Dictionary:
	return _items[id].duplicate(true) if _items.has(id) else {}

func set_preview_stage(id: StringName, region_id: StringName, index: int) -> bool:
	## Authoring/debug override. Preserves stamps and every other region; permits repair.
	## Gameplay must use apply_hit so damage and transition notifications stay causal.
	if _transaction_active or not _definitions.has(id): return false
	var definition: AeroWearableDefinition = _definitions[id]
	var region: AeroWearableRegion = null
	for candidate: AeroWearableRegion in definition.regions:
		if candidate.id == region_id: region = candidate
	if region == null or index < 0 or index >= region.stages.size(): return false
	var state: Dictionary = _items[id]["regions"][region_id]
	state["damage"] = region.stages[index].threshold
	state["stage"] = index
	state["broken_connections"] = []
	state["detached"] = false
	_apply_prepared_stage(region, state)
	_recompute_morphs(id)
	_recompute_effects()
	_transaction_active = true
	state_changed.emit(id)
	_drain_pending()
	_transaction_active = false
	return true

func get_region_effects(id: StringName, region: StringName) -> Dictionary:
	return _effects[id][region].duplicate(true) if _effects.has(id) and _effects[id].has(region) else {}

func export_state() -> Dictionary:
	return {"version":1,"items":_json_encode(_items),"seen_hits":_json_encode(_seen_hits)}

func snapshot() -> Dictionary:
	return export_state()

func restore(data: Dictionary) -> bool:
	return import_state(data)

func _json_encode(value: Variant) -> Variant:
	if value is Vector2: return [value.x, value.y]
	if value is Vector3: return [value.x, value.y, value.z]
	if typeof(value) == TYPE_STRING_NAME: return str(value)
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value: result[str(key)] = _json_encode(value[key])
		return result
	if value is Array or value is PackedInt32Array or value is PackedStringArray:
		var result: Array = []
		for entry: Variant in value: result.append(_json_encode(entry))
		return result
	return value

func import_state(data: Dictionary) -> bool:
	if _transaction_active or data.get("version", 0) != 1 or not data.get("items", null) is Dictionary or not data.get("seen_hits", {}) is Dictionary: return false
	var imported: Dictionary = data["items"]
	if imported.size() != _items.size(): return false
	var candidate_items: Dictionary = {}
	var candidate_seen: Dictionary = {}
	for raw_id: Variant in imported:
		if typeof(raw_id) not in [TYPE_STRING, TYPE_STRING_NAME]: return false
		var id: StringName = StringName(raw_id)
		if not _definitions.has(id) or not imported[raw_id] is Dictionary: return false
		var saved: Dictionary = imported[raw_id]
		var definition: AeroWearableDefinition = _definitions[id]
		if str(saved.get("definition_id", "")) != str(definition.id) or typeof(saved.get("equipped", null)) != TYPE_BOOL or not saved.get("regions", null) is Dictionary: return false
		if saved["regions"].size() != definition.regions.size(): return false
		var fresh: Dictionary = _fresh_item(id, definition, saved["equipped"])
		for region: AeroWearableRegion in definition.regions:
			if not saved["regions"].has(str(region.id)) or not saved["regions"][str(region.id)] is Dictionary: return false
			var entry: Dictionary = saved["regions"][str(region.id)]
			var damage: Variant = entry.get("damage", null)
			if not _number(damage) or not is_finite(float(damage)) or float(damage) < 0.0 or not entry.get("stamps", null) is Array: return false
			var state: Dictionary = fresh["regions"][region.id]
			state["damage"] = float(damage)
			state["stage"] = _stage_for_damage(region, float(damage))
			if entry.has("stage") and entry["stage"] != state["stage"]: return false
			_apply_prepared_stage(region, state)
			for stamp: Variant in entry["stamps"]:
				if not stamp is Dictionary: return false
				var normalized: Dictionary = _normalize_hit(stamp)
				if not normalized.get("valid", false): return false
				var hit: Dictionary = normalized["hit"]
				if hit["item_id"] != id or hit["region_id"] != region.id: return false
				var hit_id: String = hit["hit_id"]
				if not hit_id.is_empty():
					if candidate_seen.has(hit_id): return false
					candidate_seen[hit_id] = id
				state["stamps"].append(hit)
		candidate_items[id] = fresh
	for raw_hit_id: Variant in data.get("seen_hits", {}):
		var item_id: Variant = data["seen_hits"][raw_hit_id]
		if typeof(raw_hit_id) not in [TYPE_STRING, TYPE_STRING_NAME] or str(raw_hit_id).is_empty() or typeof(item_id) not in [TYPE_STRING, TYPE_STRING_NAME] or not candidate_items.has(StringName(item_id)): return false
		if candidate_seen.has(str(raw_hit_id)) and candidate_seen[str(raw_hit_id)] != StringName(item_id): return false
		candidate_seen[str(raw_hit_id)] = StringName(item_id)
	# Atomic commit. Derived fields always come from authoring, not save caches.
	_items = candidate_items
	_seen_hits = candidate_seen
	for id: StringName in _items: _recompute_morphs(id)
	_recompute_effects()
	_transaction_active = true
	var ids: Array = _items.keys()
	ids.sort()
	for id: StringName in ids: state_changed.emit(id)
	_drain_pending()
	_transaction_active = false
	return true

func reset_damage(id: StringName = &"") -> bool:
	if id != &"" and not _items.has(id): return false
	if _transaction_active:
		_pending.append({"op":"reset","id":id})
		return true
	_transaction_active = true
	_reset_internal(id)
	_drain_pending()
	_transaction_active = false
	return true

func _reset_internal(id: StringName) -> void:
	var ids: Array = _items.keys() if id == &"" else [id]
	ids.sort()
	for item_id: StringName in ids:
		_items[item_id] = _fresh_item(item_id, _definitions[item_id], _items[item_id]["equipped"])
		_recompute_morphs(item_id)
	for hit_id: String in _seen_hits.keys():
		if _seen_hits[hit_id] in ids: _seen_hits.erase(hit_id)
	_recompute_effects()
	for item_id: StringName in ids: state_changed.emit(item_id)
