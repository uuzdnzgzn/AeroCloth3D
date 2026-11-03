extends SceneTree
const Canvas = preload("res://addons/aero_cloth_3d/core/aero_damage_canvas.gd")
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error(description)

func channel_coverage(canvas: RefCounted, channel: int) -> int:
	var covered: int = 0
	for y: int in range(canvas.size):
		for x: int in range(canvas.size):
			if canvas.image.get_pixel(x, y)[channel] > 0.1: covered += 1
	return covered

func worker_cpu_result() -> Dictionary:
	var worker_canvas: RefCounted = Canvas.new()
	worker_canvas.cpu_only = true
	worker_canvas.gpu_normal_preview = true
	worker_canvas.initialize(32)
	worker_canvas.stamp(Vector2(0.5, 0.5), &"cut", 0.3, 1.0, 0.0, 42)
	worker_canvas.stamp(Vector2(0.4, 0.5), &"dent", 0.2, 0.7)
	worker_canvas.flush() # Defensive no-op: even an accidental worker flush is safe.
	var result: Dictionary = worker_canvas.export_cpu_result()
	result["no_textures"] = worker_canvas.texture == null and worker_canvas.height_texture == null and worker_canvas.normal_texture == null
	result["worker_thread"] = not Thread.is_main_thread()
	return result

func run() -> void:
	var canvas = Canvas.new()
	canvas.initialize(64)
	var ids: Array[int] = [canvas.texture.get_instance_id(), canvas.height_texture.get_instance_id(), canvas.normal_texture.get_instance_id()]
	expect(canvas.image.get_format() == Image.FORMAT_RGBA8 and canvas.image.get_width() == 64, "Mask uses requested RGBA8 resolution")
	expect(canvas.get_coverage(Vector2(0.5, 0.5)) == Color(0, 0, 0, 0), "All four damage channels start at zero, including blood alpha")
	var flat: Color = canvas.normal_image.get_pixel(20, 20)
	expect(absf(flat.r - 0.5) < 0.005 and absf(flat.g - 0.5) < 0.005 and flat.b == 1.0, "Neutral normal map faces out of the surface")
	canvas.flush()
	expect(canvas.flush_count == 0, "Clean flush does not upload textures")
	expect(canvas.stamp(Vector2(0.5, 0.5), &"cut", 0.35, 1.0, 0.0, 42), "Valid procedural cut is accepted")
	expect(canvas.dirty and canvas.flush_count == 0, "Stamp changes CPU state without an automatic texture upload")
	var cut: Color = canvas.get_coverage(Vector2(0.5, 0.5))
	expect(cut.r > 0.95 and cut.g == 0.0 and cut.b == 0.0 and cut.a == 0.0, "Cut modifies only red mask channel")
	expect(canvas.get_coverage(Vector2(0.72, 0.5)).r > 0.8 and canvas.get_coverage(Vector2(0.5, 0.72)).r == 0.0, "Cut produces an elongated stroke instead of a circular hole")
	canvas.stamp(Vector2(0.2, 0.2), &"wear", 0.13, 1.0, 0.0, 8)
	canvas.stamp(Vector2(0.8, 0.2), &"burn", 0.13, 1.0, 0.0, 9)
	canvas.stamp(Vector2(0.8, 0.8), &"blood", 0.13, 1.0, 0.0, 10)
	canvas.flush()
	expect(canvas.flush_count == 1 and not canvas.dirty, "A complete stamp batch flushes once")
	canvas.flush()
	expect(canvas.flush_count == 1, "Repeated clean flush remains a no-op")
	expect(canvas.get_coverage(Vector2(0.2, 0.2)).g > 0.2 and canvas.get_coverage(Vector2(0.8, 0.2)).b > 0.7 and canvas.get_coverage(Vector2(0.8, 0.8)).a > 0.7, "Wear, burn and blood use their distinct channels")
	var recipe: Dictionary = canvas.export_recipe()
	var restored = Canvas.new()
	expect(restored.import_recipe(JSON.parse_string(JSON.stringify(recipe))), "Serializable JSON recipe imports successfully")
	restored.flush()
	expect(restored.image.get_data() == canvas.image.get_data(), "Seeded recipe replay reproduces exact mask pixels")
	expect(restored.height_image.get_data() == canvas.height_image.get_data(), "Seeded recipe replay reproduces exact relief pixels")
	expect(restored.normal_image.get_data() == canvas.normal_image.get_data(), "Seeded recipe replay reproduces exact normal pixels")
	var previous_bytes: PackedByteArray = canvas.image.get_data()
	var bad: Dictionary = recipe.duplicate(true)
	bad["operations"].append({"uv": [0.5, 0.5], "brush": "unknown", "radius": 0.1, "strength": 1.0})
	expect(not canvas.import_recipe(bad) and canvas.image.get_data() == previous_bytes and canvas.operations.size() == 4, "Invalid final operation rejects the whole import atomically")
	bad = recipe.duplicate(true)
	bad["size"] = 4097
	expect(not canvas.import_recipe(bad) and canvas.size == 64, "Oversized recipe cannot allocate or replace live data")
	canvas.initialize(4097)
	expect(canvas.size == 64 and canvas.image.get_data() == previous_bytes, "Invalid initialization also preserves existing maps")
	for invalid: Dictionary in [{"uv": Vector2(NAN, 0.5)}, {"uv": Vector2(-0.1, 0.5)}, {"radius": 0.0}, {"radius": INF}, {"strength": NAN}, {"strength": 1.1}, {"angle": INF}, {"brush": &"invalid"}]:
		expect(not canvas.stamp(invalid.get("uv", Vector2(0.5, 0.5)), invalid.get("brush", &"cut"), invalid.get("radius", 0.1), invalid.get("strength", 1.0), invalid.get("angle", 0.0)), "Nonfinite/out-of-range authoring operation is safely rejected: " + str(invalid))
	expect(canvas.image.get_data() == previous_bytes, "Rejected stamps never modify pixels")
	canvas.stamp(Vector2(0.5, 0.5), &"burn", 0.1, 1.0)
	var before_erase: Dictionary = canvas.export_recipe()
	canvas.stamp(Vector2(0.5, 0.5), &"cut", 0.35, 1.0, 0.0, 42, true)
	var erased: Color = canvas.get_coverage(Vector2(0.5, 0.5))
	expect(erased.r < 0.05 and erased.b > 0.7, "Selected-channel eraser restores cut opacity and preserves overlapping burn")
	expect(canvas.import_recipe(before_erase) and canvas.get_coverage(Vector2(0.5, 0.5)).r > 0.95, "Recipe Undo restores the erased cut")
	canvas.clear()
	canvas.stamp(Vector2(0.5, 0.5), &"dent", 0.25, 1.0)
	canvas.flush()
	expect(canvas.get_coverage(Vector2(0.5, 0.5)) == Color(0, 0, 0, 0) and canvas.height_image.get_pixel(32, 32).r < -0.02, "Dent affects relief without misusing a semantic mask channel")
	expect(canvas.normal_image.get_pixel(40, 32).r < 0.49, "Height gradients produce a non-flat tangent normal")
	canvas.clear()
	canvas.stamp(Vector2(0, 0), &"wear", 0.3, 1.0)
	expect(canvas.get_coverage(Vector2(0.01, 0.01)).g > 0.1 and canvas.get_coverage(Vector2(0.99, 0.99)).g == 0.0, "Border stamps clip safely without texture wrapping")
	canvas.clear()
	canvas.stamp(Vector2(0.5, 0.5), &"cut", 0.3, 1.0)
	var alpha: Image = canvas.bake_map(&"alpha")
	expect(alpha.get_pixel(32, 32).r < 0.05 and alpha.get_pixel(0, 0).r > 0.99, "Baked alpha correctly inverts the red cut mask")
	expect(canvas.bake_map(&"normal") != null and canvas.bake_map(&"height") != null and canvas.bake_map(&"roughness") != null and canvas.bake_map(&"albedo") != null and canvas.bake_map(&"unknown") == null, "Supported generated map types bake from CPU state")
	var output: String = "user://damage-canvas-export"
	expect(canvas.save_maps(output) == OK, "Map export writes required maps and recipe")
	for filename: String in ["mask.png", "alpha.png", "normal.png", "roughness.png", "recipe.json"]:
		expect(FileAccess.file_exists(output.path_join(filename)), "Export includes " + filename)
	canvas.initialize(32)
	expect(ids == [canvas.texture.get_instance_id(), canvas.height_texture.get_instance_id(), canvas.normal_texture.get_instance_id()], "Resize, clear and history replay preserve all GPU texture identities")
	canvas.clear()
	canvas.flush()
	expect(canvas.operations.is_empty() and canvas.get_coverage(Vector2.ZERO) == Color(0, 0, 0, 0), "Clear removes operations and damage")
	# Morphological tools act independently on all semantic channels and use one
	# source snapshot per operation, making replay independent of scan order.
	canvas.initialize(64)
	for brush_name: StringName in [&"cut", &"wear", &"burn", &"blood"]:
		canvas.stamp(Vector2(0.5, 0.5), brush_name, 0.22, 1.0, 0.0, 73)
	var coverage_before: Array[int] = []
	for channel: int in range(4): coverage_before.append(channel_coverage(canvas, channel))
	expect(canvas.stamp(Vector2(0.5, 0.5), &"grow", 0.45, 1.0), "Grow is a validated authoring brush")
	var coverage_grown: Array[int] = []
	for channel: int in range(4):
		coverage_grown.append(channel_coverage(canvas, channel))
		expect(coverage_grown[channel] > coverage_before[channel], "Grow increases coverage of semantic channel " + str(channel))
	expect(canvas.stamp(Vector2(0.5, 0.5), &"shrink", 0.45, 1.0), "Shrink is a validated authoring brush")
	for channel: int in range(4): expect(channel_coverage(canvas, channel) < coverage_grown[channel], "Shrink decreases coverage of semantic channel " + str(channel))
	canvas.stamp(Vector2(0.5, 0.5), &"dent", 0.22, 1.0)
	expect(canvas.stamp(Vector2(0.5, 0.5), &"smooth", 0.45, 0.75), "Smooth filters mask and independent dent relief")
	var filtered_recipe: Dictionary = canvas.export_recipe()
	var filtered_replay: RefCounted = Canvas.new()
	expect(filtered_replay.import_recipe(JSON.parse_string(JSON.stringify(filtered_recipe))), "Filter operations roundtrip as validated JSON recipes")
	canvas.flush()
	filtered_replay.flush()
	expect(filtered_replay.image.get_data() == canvas.image.get_data() and filtered_replay.height_image.get_data() == canvas.height_image.get_data() and filtered_replay.normal_image.get_data() == canvas.normal_image.get_data(), "Smooth/grow/shrink replay reproduces all mask, height and normal pixels exactly")
	var before_rejected_filter: PackedByteArray = canvas.image.get_data()
	expect(not canvas.stamp(Vector2(0.5, 0.5), &"smooth", 0.3, 1.0, 0.0, 0, true) and canvas.image.get_data() == before_rejected_filter, "Undefined filter eraser combinations reject without changing data")
	canvas.clear()
	canvas.stamp(Vector2(0, 0), &"smooth", 0.3, 1.0)
	canvas.stamp(Vector2(0, 0), &"grow", 0.3, 1.0)
	canvas.stamp(Vector2(0, 0), &"shrink", 0.3, 1.0)
	var flushes_before: int = canvas.flush_count
	canvas.flush()
	expect(canvas.flush_count == flushes_before + 1 and canvas.get_coverage(Vector2.ZERO) == Color(0,0,0,0), "Flat border filters remain finite and share one explicit batch upload")
	flat = canvas.normal_image.get_pixel(0, 0)
	expect(is_finite(flat.r) and is_finite(flat.g) and flat.b > 0.99 and absf(flat.r - 0.5) < 0.005, "Flat smoothing with clamped image edges preserves a neutral finite normal")
	canvas.clear()
	canvas.gpu_normal_preview = true
	canvas.stamp(Vector2(0.5, 0.5), &"dent", 0.3, 1.0)
	canvas.flush()
	flat = canvas.normal_image.get_pixel(40, 32)
	expect(absf(flat.r - 0.5) < 0.005 and flat.b > 0.99, "GPU normal preview skips CPU normal regeneration during flush")
	expect(canvas.height_image.get_pixel(32, 32).r < -0.02 and not canvas.dirty, "GPU preview retains authoritative RF relief and completes the requested batch flush")
	var baked_gpu_normal: Image = canvas.bake_map(&"normal")
	expect(baked_gpu_normal.get_pixel(40, 32).r < 0.49, "Explicit normal export builds deferred CPU normals even in GPU preview mode")
	canvas.gpu_normal_preview = false
	canvas.flush()
	expect(canvas.normal_image.get_data() == baked_gpu_normal.get_data() and not canvas.dirty, "Returning to CPU normal preview retains the baked normal image and completes its upload")
	var worker: Thread = Thread.new()
	expect(worker.start(worker_cpu_result) == OK, "Independent CPU-only canvas starts on a real worker thread")
	var cpu_result: Dictionary = worker.wait_to_finish()
	expect(cpu_result.get("worker_thread", false) and cpu_result.get("no_textures", false), "Worker-owned authoring produces CPU Images without any ImageTexture allocation")
	canvas.initialize(32)
	canvas.gpu_normal_preview = true
	var texture_ids: Array[int] = [canvas.texture.get_instance_id(), canvas.height_texture.get_instance_id(), canvas.normal_texture.get_instance_id()]
	expect(canvas.publish_cpu_result(cpu_result), "Completed worker result publishes on the main thread")
	expect(canvas.image.get_data() == cpu_result["image"].get_data() and canvas.height_image.get_data() == cpu_result["height_image"].get_data() and canvas.operations == cpu_result["operations"], "Publication preserves exact worker mask, relief and recipe data")
	expect(texture_ids == [canvas.texture.get_instance_id(), canvas.height_texture.get_instance_id(), canvas.normal_texture.get_instance_id()] and not canvas.dirty, "Publication retains all bound texture identities and completes one manual flush")
	var published_bytes: PackedByteArray = canvas.image.get_data()
	var invalid_result: Dictionary = cpu_result.duplicate()
	invalid_result["image"] = Image.create(32, 32, false, Image.FORMAT_RGB8)
	expect(not canvas.publish_cpu_result(invalid_result) and canvas.image.get_data() == published_bytes, "Wrong worker image format rejects atomically")
	invalid_result = cpu_result.duplicate()
	invalid_result["height_image"] = Image.create(33, 32, false, Image.FORMAT_RF)
	expect(not canvas.publish_cpu_result(invalid_result) and canvas.image.get_data() == published_bytes, "Wrong worker image dimensions reject atomically")
	invalid_result = cpu_result.duplicate(true)
	invalid_result["operations"].append({"brush": "invalid"})
	expect(not canvas.publish_cpu_result(invalid_result) and canvas.image.get_data() == published_bytes and canvas.operations.size() == 2, "Invalid final worker operation cannot partially publish state")
	print("DAMAGE_CANVAS_TESTS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
