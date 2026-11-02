extends SceneTree

const Actor = preload("res://demo/scenario_character.gd")
const Profile = preload("res://demo/wardrobe_profile.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var actor := Actor.new()
	root.add_child(actor)
	await physics_frame
	var authored: Dictionary = Profile.encode(actor)
	check(Profile.validate(authored), "Generated profile is valid")
	var decoded: Variant = JSON.parse_string(JSON.stringify(authored))
	check(Profile.validate(decoded), "JSON roundtrip is valid")
	actor.shoulder.apply_hit()
	actor.shoulder.set_connection_point(0, Vector3(0.2,0.2,0.2))
	actor.shoulder_covers_inner = false
	actor.cloth.weights[15] = 0.0
	Profile.apply(actor, decoded)
	check(actor.shoulder.get_active_connection_count() == 1, "Loading authoring settings preserves damage")
	check(actor.shoulder.connection_points[0].is_equal_approx(Vector3(-0.11,0.09,0.035)), "Connection restored")
	check(actor.shoulder_covers_inner and actor.under_shoulder.visible, "Rule restored but damage keeps region open")
	check(actor.cloth.weights[15] == authored["cloth_weights"][15], "Paint settings restored")
	check(not Profile.validate(null), "Null rejected")
	check(not Profile.validate({}), "Unknown schema rejected")
	var invalid: Dictionary = authored.duplicate(true)
	invalid["shoulder_connections"][0][0] = "instruction text"
	check(not Profile.validate(invalid), "Nonnumeric coordinate rejected")
	invalid = authored.duplicate(true)
	invalid["cloth_weights"].pop_back()
	check(not Profile.validate(invalid), "Wrong topology weight count rejected")
	invalid = authored.duplicate(true)
	invalid["cloth_weights"][0] = 2
	check(not Profile.validate(invalid), "Out of range weights rejected")
	invalid = authored.duplicate(true)
	invalid["shoulder_covers_inner"] = "true"
	check(not Profile.validate(invalid), "Invalid coverage type rejected")
	actor.queue_free()
	await process_frame
	print("PROFILE_TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
