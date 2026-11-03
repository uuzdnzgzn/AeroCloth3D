extends SceneTree

const Definition = preload("res://addons/aero_cloth_3d/resources/aero_wearable_definition.gd")
const Region = preload("res://addons/aero_cloth_3d/resources/aero_wearable_region.gd")
const Stage = preload("res://addons/aero_cloth_3d/resources/aero_damage_stage.gd")
const Effect = preload("res://addons/aero_cloth_3d/resources/aero_layer_effect.gd")
const Controller = preload("res://addons/aero_cloth_3d/core/aero_wearable_controller.gd")

var checks: int = 0
var failures: Array[String] = []
var controllers: Array[Node] = []

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error(description)

func controller() -> AeroWearableController:
	var node: AeroWearableController = Controller.new()
	root.add_child(node)
	controllers.append(node)
	return node

func example(id: StringName) -> AeroWearableDefinition:
	return Definition.make_example(id, &"cloth")

func add_effect(definition: AeroWearableDefinition, id: StringName, target: StringName, cap: float, hidden: bool, priority: int = 0) -> AeroLayerEffect:
	var effect: AeroLayerEffect = Effect.new()
	effect.id = id
	effect.source_region = &"body"
	effect.target_item = target
	effect.target_region = &"body"
	effect.mobility_cap = cap
	effect.hides_region = hidden
	effect.priority = priority
	effect.active_until_stage = 2
	definition.effects.append(effect)
	return effect

func hit(item: StringName, region_id: StringName, amount: float, id: String = "") -> Dictionary:
	return {"item_id":item,"region_id":region_id,"amount":amount,"hit_id":id,"type":"cut","seed":42,"position":Vector3(1,2,3),"direction":Vector3(0,-1,0),"impulse":Vector3(0,1,0)}

func run() -> void:
	var authored: AeroWearableDefinition = example(&"shirt")
	expect(authored.validate().is_empty(), "Five-stage example is a valid standalone authoring Resource")
	authored.damage_recipe = {"seed":7,"operations":[{"shape":"scratch","uv":[0.3,0.4]}]}
	authored.metadata = {"source_fingerprint":"fixture","blender":"4.3.2"}
	authored.fit_morph = &"Fit"
	authored.body_morph = &"Compress"
	authored.compression = 0.4
	authored.mobility = PackedFloat32Array([0.0, 0.5, 1.0])
	authored.connection_points = PackedVector3Array([Vector3(0,0.1,0),Vector3(0.2,0.1,0)])
	authored.regions[0].stages[2].morph_values = {"tear":0.6}
	var save_path: String = "user://wearable-controller-roundtrip.tres"
	expect(ResourceSaver.save(authored, save_path) == OK, "Complete authoring definition saves as a .tres Resource")
	var loaded: AeroWearableDefinition = ResourceLoader.load(save_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	expect(loaded != null and loaded.validate().is_empty(), "Authoring Resource reloads with typed nested regions and stages")
	expect(loaded.regions[0].stages[2].morph_values["tear"] == 0.6 and loaded.damage_recipe == authored.damage_recipe and loaded.metadata == authored.metadata, "Resource roundtrip preserves prepared morphs, canvas recipe and source metadata")
	expect(loaded.mobility == authored.mobility and loaded.connection_points == authored.connection_points and loaded.fit_morph == &"Fit", "Resource roundtrip preserves proxy weights, connections and fit channel")
	var invalid: AeroWearableDefinition = example(&"invalid")
	invalid.regions[0].stages[1].threshold = 0.0
	expect(not invalid.validate().is_empty(), "Nonincreasing damage thresholds are rejected")
	invalid = example(&"invalid")
	invalid.regions[0].base_mobility = NAN
	expect(not invalid.validate().is_empty(), "Nonfinite mobility is rejected")
	invalid = example(&"invalid")
	invalid.regions[0].stages[2].cut_strength = 1.1
	expect(not invalid.validate().is_empty(), "Visual strengths outside their normalized range are rejected")
	invalid = example(&"invalid")
	invalid.regions.append(null)
	var c: AeroWearableController = controller()
	expect(not c.register_item(invalid), "Invalid nested Resources cannot partially register an item")
	expect(c.export_state()["items"].is_empty(), "Failed registration leaves runtime inventory untouched")
	var upper: AeroWearableRegion = authored.regions[0]
	upper.id = &"upper"
	upper.uv_rect = Rect2(0,0,1,0.5)
	upper.damage_multiplier = {"fire":2.0}
	var lower: AeroWearableRegion = Region.new()
	lower.id = &"lower"
	lower.uv_rect = Rect2(0,0.5,1,0.5)
	lower.stages.assign(example(&"unused").regions[0].stages)
	authored.regions.append(lower)
	expect(c.register_item(authored), "Valid multi-region definition registers")
	expect(not c.get_item_state(&"shirt")["equipped"], "Registration creates an unequipped inventory item")
	expect(not c.apply_hit(hit(&"shirt",&"upper",12))["accepted"], "Unequipped inventory ignores combat damage")
	expect(c.equip(&"shirt"), "Registered item can be equipped")
	var signals: Dictionary = {"damage":0,"stages":0,"broken":0,"detached":0,"state":0,"coherent":true}
	c.damage_applied.connect(func(result: Dictionary) -> void:
		signals["damage"] += 1
		var state: Dictionary = c.get_item_state(result["item_id"])["regions"][result["region_id"]]
		signals["coherent"] = signals["coherent"] and state["stage"] == result["stage"] and state["damage"] == result["damage"]
	)
	c.stage_changed.connect(func(_item: StringName,_region: StringName,_old: int,_new: int) -> void: signals["stages"] += 1)
	c.attachment_broken.connect(func(_item: StringName,_region: StringName,_index: int) -> void: signals["broken"] += 1)
	c.piece_detached.connect(func(_item: StringName,_region: StringName) -> void: signals["detached"] += 1)
	c.state_changed.connect(func(_item: StringName) -> void: signals["state"] += 1)
	var result: Dictionary = c.apply_hit(hit(&"shirt",&"upper",12,"local-1"))
	expect(result["accepted"] and result["stage"] == 1, "Regional hit accumulates damage and selects its prepared stage")
	expect(c.get_item_state(&"shirt")["regions"][&"lower"]["damage"] == 0.0, "Damage remains local to the selected region")
	expect(not c.apply_hit(hit(&"shirt",&"lower",90,"local-1"))["accepted"], "Same hit id cannot damage another region twice")
	expect(c.get_item_state(&"shirt")["regions"][&"upper"]["stamps"].size() == 1, "Duplicate attack creates no extra damage stamp")
	var uv_hit: Dictionary = {"item_id":&"shirt","uv":Vector2(0.4,0.8),"amount":10,"hit_id":"uv-lower"}
	result = c.apply_hit(uv_hit)
	expect(result["region_id"] == &"lower" and result["stage"] == 1, "UV fallback selects the containing local region")
	var fire_hit: Dictionary = hit(&"shirt",&"lower",3,"fire-1")
	fire_hit["type"] = "fire"
	c.apply_hit(fire_hit)
	fire_hit = hit(&"shirt",&"upper",3,"fire-2")
	fire_hit["type"] = "fire"
	result = c.apply_hit(fire_hit)
	expect(result["applied_amount"] == 6.0, "Authored per-region damage-type multiplier applies")
	var bad_hits: Array[Dictionary] = [hit(&"shirt",&"upper",-1),hit(&"shirt",&"upper",INF),{"item_id":"shirt","amount":1,"uv":Vector2(NAN,0)},{"item_id":"shirt","amount":1,"position":Vector3(INF,0,0)},{"item_id":"shirt","amount":1,"seed":0.5}]
	var before_invalid: Dictionary = c.export_state()
	for invalid_hit: Dictionary in bad_hits: expect(not c.apply_hit(invalid_hit)["accepted"], "Invalid combat numeric input is rejected")
	expect(c.export_state() == before_invalid, "Rejected hits do not mutate damage, stamps or dedupe state")
	result = c.apply_hit(hit(&"shirt",&"upper",100,"skip-to-final"))
	var final_state: Dictionary = c.get_item_state(&"shirt")["regions"][&"upper"]
	expect(result["old_stage"] == 1 and result["stage"] == 4, "Large damage skips directly to final prepared state")
	expect(final_state["broken_connections"] == [0,1] and final_state["detached"], "Stage skip unions authored broken connections and releases motion")
	expect(final_state["cut_strength"] == 1.0 and final_state["wear_strength"] == 1.0, "Visual strengths derive from final stage without cumulative amplification")
	expect(signals["broken"] == 2 and signals["detached"] == 1 and signals["coherent"], "Connection transitions fire once against an already coherent final state")
	c.apply_hit(hit(&"shirt",&"upper",1,"already-final"))
	expect(signals["broken"] == 2 and signals["detached"] == 1, "Further damage cannot repeat physical break transitions")
	c.unequip(&"shirt")
	c.equip(&"shirt")
	expect(c.get_item_state(&"shirt")["regions"][&"upper"]["stage"] == 4, "Unequip and re-equip preserve owned regional damage")
	var detached_copy: Dictionary = c.get_item_state(&"shirt")
	detached_copy["regions"][&"upper"]["damage"] = 0
	detached_copy["regions"][&"upper"]["stamps"].clear()
	expect(c.get_item_state(&"shirt")["regions"][&"upper"]["damage"] > 100 and not c.get_item_state(&"shirt")["regions"][&"upper"]["stamps"].is_empty(), "Public runtime snapshots do not alias internal nested state")
	expect(authored.regions[0].stages[4].cut_strength == 1.0 and authored.regions[0].stages[2].morph_values == {"tear":0.6}, "Combat does not mutate shared authoring Resources")
	var exported: Dictionary = c.export_state()
	var text_value: String = JSON.stringify(exported)
	var decoded: Variant = JSON.parse_string(text_value)
	expect(decoded is Dictionary and decoded["items"]["shirt"]["regions"]["upper"]["stamps"][0]["uv"] is Array, "Export is actual JSON with vector stamps encoded as numeric arrays")
	var transitions_before: Array = [signals["damage"],signals["stages"],signals["broken"],signals["detached"]]
	var states_before: int = signals["state"]
	expect(c.import_state(decoded), "JSON-decoded runtime state imports successfully")
	expect([signals["damage"],signals["stages"],signals["broken"],signals["detached"]] == transitions_before and signals["state"] == states_before + 1, "Loading emits only state_changed and no damage, break or detach transitions")
	expect(c.export_state() == exported, "JSON roundtrip restores the complete runtime state deterministically")
	expect(not c.apply_hit(hit(&"shirt",&"upper",2,"local-1"))["accepted"], "Hit dedupe survives JSON load")
	var corrupt: Dictionary = exported.duplicate(true)
	corrupt["items"]["shirt"]["regions"]["lower"]["damage"] = -1
	expect(not c.import_state(corrupt) and c.export_state() == exported, "Malformed load is rejected atomically without partial changes")
	c.reset_damage(&"shirt")
	expect(c.get_item_state(&"shirt")["regions"][&"upper"]["damage"] == 0.0 and c.get_item_state(&"shirt")["equipped"], "Explicit damage reset repairs region while preserving equipment ownership")
	expect(c.apply_hit(hit(&"shirt",&"upper",25,"local-1"))["accepted"], "Explicit reset clears that item's previous hit identities")
	expect(c.get_item_state(&"shirt")["prepared_morphs"] == {"tear":0.6}, "Prepared morph channels rebuild from the current stage")
	# Reentrant signals queue hits until every outer transition has been observed.
	var reentrant: AeroWearableController = controller()
	reentrant.register_item(example(&"reentrant"))
	reentrant.equip(&"reentrant")
	var observed: Array[int] = []
	var nested_result: Dictionary = {}
	reentrant.damage_applied.connect(func(event: Dictionary) -> void:
		if event["hit_id"] == "outer": nested_result.merge(reentrant.apply_hit(hit(&"reentrant",&"body",80,"nested")))
	)
	reentrant.stage_changed.connect(func(_item: StringName,_region: StringName,_old: int,new_stage: int) -> void:
		observed.append(new_stage)
		expect(reentrant.get_item_state(&"reentrant")["regions"][&"body"]["stage"] == new_stage, "Reentrant stage notification observes its own committed transaction")
	)
	reentrant.apply_hit(hit(&"reentrant",&"body",10,"outer"))
	expect(nested_result.get("queued",false) and observed == [1,4], "Nested hit waits for the outer transaction then applies in order")
	# Multiple garments impose min caps and OR coverage; removal rebuilds from base.
	var base: AeroWearableDefinition = example(&"base")
	base.regions[0].base_mobility = 0.9
	var jacket: AeroWearableDefinition = example(&"jacket")
	var harness: AeroWearableDefinition = example(&"harness")
	add_effect(jacket,&"cover",&"base",0.0,true,1)
	add_effect(harness,&"tight",&"base",0.2,false,2)
	var layers: AeroWearableController = controller()
	for definition: AeroWearableDefinition in [base,jacket,harness]:
		expect(layers.register_item(definition) and layers.equip(definition.id), "Layered wardrobe item registers and equips")
	var effect_state: Dictionary = layers.get_region_effects(&"base",&"body")
	expect(effect_state["mobility"] == 0.0 and not effect_state["visible"] and effect_state["sources"].size() == 2, "Two independent overrides apply minimum cap and OR coverage")
	layers.unequip(&"jacket")
	effect_state = layers.get_region_effects(&"base",&"body")
	expect(is_equal_approx(effect_state["mobility"],0.2) and effect_state["visible"], "Removing cover reveals lower region while remaining harness retains its cap")
	layers.unequip(&"harness")
	expect(is_equal_approx(layers.get_region_effects(&"base",&"body")["mobility"],0.9), "Removing every override restores authored base mobility without ratcheting")
	layers.equip(&"jacket")
	var signal_effect_visible: Array[bool] = []
	layers.stage_changed.connect(func(_item: StringName,_region: StringName,_old: int,_new: int) -> void: signal_effect_visible.append(layers.get_region_effects(&"base",&"body")["visible"]))
	layers.apply_hit(hit(&"jacket",&"body",50,"jacket-break"))
	expect(layers.get_region_effects(&"base",&"body")["visible"] and signal_effect_visible == [true], "Breaking source past authored active stage releases layer effect before notifications")
	layers.reset_damage(&"jacket")
	expect(not layers.get_region_effects(&"base",&"body")["visible"], "Repair recomputes source coverage from intact authored stage")
	var reverse: AeroWearableController = controller()
	for definition: AeroWearableDefinition in [harness,jacket,base]:
		reverse.register_item(definition)
		reverse.equip(definition.id)
	layers.equip(&"harness")
	expect(reverse.get_region_effects(&"base",&"body") == layers.get_region_effects(&"base",&"body"), "Layer composition is independent of registration and equip order")
	var cycle_a: AeroWearableDefinition = example(&"a")
	var cycle_b: AeroWearableDefinition = example(&"b")
	add_effect(cycle_a,&"a_to_b",&"b",0.5,false)
	add_effect(cycle_b,&"b_to_a",&"a",0.5,false)
	var cyclic: AeroWearableController = controller()
	expect(cyclic.register_item(cycle_a), "A forward reference can precede its target registration")
	expect(not cyclic.register_item(cycle_b) and cyclic.get_item_state(&"b").is_empty(), "Completing a source-to-target cycle is rejected atomically")
	var ambiguous: AeroWearableDefinition = example(&"ambiguous")
	add_effect(ambiguous,&"one",&"base",0.3,true,5)
	add_effect(ambiguous,&"two",&"base",0.6,false,5)
	expect(layers.register_item(ambiguous) and not layers.validation_warnings.is_empty(), "Conflicting effects with duplicate priority report a visible authoring warning")
	var custom: AeroWearableController = controller()
	expect(custom.register_item(base,&"base-instance") and custom.equip(&"base-instance"), "Custom runtime instance ids are separate from shared definition ids")
	for item: Node in controllers: item.queue_free()
	await process_frame
	print("WEARABLE_CONTROLLER_TESTS: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
