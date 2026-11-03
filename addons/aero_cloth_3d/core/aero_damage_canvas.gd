@tool
class_name AeroDamageCanvas
extends RefCounted
## CPU-authoritative UV damage masks. R=cut, G=wear, B=burn, A=blood.
## Stamp a batch, then call flush() once. Textures retain their identity, including
## after clear/import/resize. GPU textures are never read back into authoring state.
## Radii are normalized UV units; footprints clip at the image border (no wrapping).

const MAX_SIZE: int = 4096
const MAX_OPERATIONS: int = 4096
const RECIPE_VERSION: int = 1
const BRUSHES: Array[StringName] = [&"cut", &"wear", &"burn", &"blood", &"dent", &"smooth", &"grow", &"shrink"]
const FILTER_BRUSHES: Array[StringName] = [&"smooth", &"grow", &"shrink"]

var size: int = 0
var image: Image
var texture: ImageTexture
var height_image: Image
var height_texture: ImageTexture
var normal_image: Image
var normal_texture: ImageTexture
var operations: Array[Dictionary] = []
var dirty: bool = false
var flush_count: int = 0
## Set before initialize() on a worker-owned canvas. CPU Image authoring remains
## available, while all ImageTexture creation/publication is disabled.
var cpu_only: bool = false
## Runtime/preview opt-in: derive normals from the uploaded height map in the
## fragment shader. Explicit normal-map baking still computes the CPU image.
var gpu_normal_preview: bool = false:
	set(value):
		if gpu_normal_preview == value:
			return
		gpu_normal_preview = value
		if image != null and not value:
			dirty = true
var _dent_image: Image
var _normal_dirty_rect: Rect2i = Rect2i()


func initialize(requested_size: int = 512) -> void:
	# Invalid allocation requests preserve existing data and texture references.
	if requested_size < 1 or requested_size > MAX_SIZE:
		return
	size = requested_size
	image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	height_image = Image.create(size, size, false, Image.FORMAT_RF)
	height_image.fill(Color(0.0, 0.0, 0.0, 1.0))
	_dent_image = Image.create(size, size, false, Image.FORMAT_RF)
	_dent_image.fill(Color(0.0, 0.0, 0.0, 1.0))
	normal_image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	normal_image.fill(Color(0.5, 0.5, 1.0, 1.0))
	operations.clear()
	_normal_dirty_rect = Rect2i()
	dirty = false
	if cpu_only:
		return
	if texture == null:
		texture = ImageTexture.create_from_image(image)
		height_texture = ImageTexture.create_from_image(height_image)
		normal_texture = ImageTexture.create_from_image(normal_image)
	else:
		texture.set_image(image)
		height_texture.set_image(height_image)
		normal_texture.set_image(normal_image)


func clear() -> void:
	if image == null:
		return
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	height_image.fill(Color(0.0, 0.0, 0.0, 1.0))
	_dent_image.fill(Color(0.0, 0.0, 0.0, 1.0))
	normal_image.fill(Color(0.5, 0.5, 1.0, 1.0))
	operations.clear()
	_normal_dirty_rect = Rect2i()
	dirty = true


func stamp(uv: Vector2, brush: StringName, radius: float, strength: float, angle: float = 0.0, seed: int = 0, erase: bool = false) -> bool:
	if image == null or operations.size() >= MAX_OPERATIONS:
		return false
	var operation: Dictionary = _validate_operation({"uv": [uv.x, uv.y], "brush": String(brush), "radius": radius, "strength": strength, "angle": angle, "seed": seed, "erase": erase})
	if operation.is_empty():
		return false
	_apply_operation(operation)
	operations.append(operation)
	return true


func flush() -> void:
	if not dirty or image == null or cpu_only:
		return
	if not gpu_normal_preview:
		_rebuild_normals()
	texture.update(image)
	height_texture.update(height_image)
	if not gpu_normal_preview:
		normal_texture.update(normal_image)
	dirty = false
	flush_count += 1


func export_cpu_result() -> Dictionary:
	## Transfer these independent CPU Images after a worker completes. The sender
	## must not mutate them again. Operations are copied; textures never cross here.
	if image == null:
		return {}
	return {"size": size, "image": image, "height_image": height_image, "dent_image": _dent_image, "operations": operations.duplicate(true)}


func publish_cpu_result(result: Dictionary) -> bool:
	## Main-thread publication of a completed internal worker result. Structural
	## validation is atomic and bounded by recipe length, with no full pixel scan,
	## replay or GPU readback on this latency-sensitive path.
	if not Thread.is_main_thread() or cpu_only or image == null or texture == null or height_texture == null or normal_texture == null:
		return false
	if result.has("size") and not _integer_in_range(result["size"], size, size):
		return false
	for key: String in ["image", "height_image", "dent_image"]:
		var candidate: Variant = result.get(key)
		if not candidate is Image or candidate.is_empty() or candidate.get_width() != size or candidate.get_height() != size or candidate.has_mipmaps():
			return false
		if candidate.get_format() != (Image.FORMAT_RGBA8 if key == "image" else Image.FORMAT_RF):
			return false
	var source_operations: Variant = result.get("operations")
	if not source_operations is Array or source_operations.size() > MAX_OPERATIONS:
		return false
	var validated: Array[Dictionary] = []
	for entry: Variant in source_operations:
		if not entry is Dictionary:
			return false
		var operation: Dictionary = _validate_operation(entry)
		if operation.is_empty():
			return false
		validated.append(operation)
	# Existing ImageTexture objects stay bound to every material after publication.
	image = result["image"]
	height_image = result["height_image"]
	_dent_image = result["dent_image"]
	operations.assign(validated)
	_normal_dirty_rect = Rect2i(0, 0, size, size)
	dirty = true
	flush()
	return true


func get_coverage(uv: Vector2) -> Color:
	if image == null or not uv.is_finite() or uv.x < 0.0 or uv.y < 0.0 or uv.x > 1.0 or uv.y > 1.0:
		return Color(0.0, 0.0, 0.0, 0.0)
	return image.get_pixel(clampi(int(uv.x * size), 0, size - 1), clampi(int(uv.y * size), 0, size - 1))


func export_recipe() -> Dictionary:
	return {"format": "aero_damage_canvas", "version": RECIPE_VERSION, "size": size, "operations": operations.duplicate(true)}


func import_recipe(recipe: Dictionary) -> bool:
	# Validate the complete recipe before replacing any live image/texture/state.
	if recipe.get("format", "") != "aero_damage_canvas" or not _integer_in_range(recipe.get("version"), RECIPE_VERSION, RECIPE_VERSION):
		return false
	if not _integer_in_range(recipe.get("size"), 1, MAX_SIZE):
		return false
	var source_operations: Variant = recipe.get("operations")
	if not source_operations is Array or source_operations.size() > MAX_OPERATIONS:
		return false
	var validated: Array[Dictionary] = []
	for entry: Variant in source_operations:
		if not entry is Dictionary:
			return false
		var operation: Dictionary = _validate_operation(entry)
		if operation.is_empty():
			return false
		validated.append(operation)
	initialize(int(recipe["size"]))
	for operation: Dictionary in validated:
		_apply_operation(operation)
		operations.append(operation)
	# Empty imports still need to upload a cleared texture after a later flush.
	dirty = true
	return true


func bake_map(kind: StringName) -> Image:
	if image == null:
		return null
	if kind == &"mask":
		return image.duplicate()
	if kind == &"normal":
		_rebuild_normals()
		return normal_image.duplicate()
	if kind not in [&"alpha", &"roughness", &"albedo", &"height"]:
		return null
	var result: Image = Image.create(size, size, false, Image.FORMAT_RGBA8 if kind == &"albedo" else Image.FORMAT_L8)
	for y: int in range(size):
		for x: int in range(size):
			var mask: Color = image.get_pixel(x, y)
			var value: float = 0.0
			if kind == &"alpha":
				value = 1.0 - mask.r
			elif kind == &"roughness":
				value = clampf(0.85 + mask.g * 0.15 + mask.b * 0.1 - mask.a * 0.32, 0.0, 1.0)
			elif kind == &"height":
				# Signed relief maps to [0,1], with neutral height at 0.5.
				value = clampf(0.5 + height_image.get_pixel(x, y).r * 10.0, 0.0, 1.0)
			else:
				# Neutral-material preview, not a bake of a mesh's source albedo.
				var color: Color = Color(0.5, 0.5, 0.5).lerp(Color(0.65, 0.64, 0.60), mask.g)
				color = color.lerp(Color(0.035, 0.022, 0.014), mask.b)
				color = color.lerp(Color(0.19, 0.008, 0.012), mask.a)
				color.a = 1.0 - mask.r
				result.set_pixel(x, y, color)
				continue
			result.set_pixel(x, y, Color(value, value, value, 1.0))
	return result


func save_maps(directory: String) -> Error:
	if image == null or directory.strip_edges().is_empty():
		return ERR_INVALID_PARAMETER
	var error: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	if error != OK:
		return error
	for kind: StringName in [&"alpha", &"normal", &"mask", &"roughness", &"albedo", &"height"]:
		error = bake_map(kind).save_png(directory.path_join(String(kind) + ".png"))
		if error != OK:
			return error
	var file: FileAccess = FileAccess.open(directory.path_join("recipe.json"), FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(export_recipe(), "\t"))
	return file.get_error()


func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


func _integer_in_range(value: Variant, minimum: int, maximum: int) -> bool:
	return _number(value) and float(value) >= minimum and float(value) <= maximum and float(value) == floorf(float(value))


func _validate_operation(entry: Dictionary) -> Dictionary:
	var uv: Variant = entry.get("uv")
	if not uv is Array or uv.size() != 2 or not _number(uv[0]) or not _number(uv[1]):
		return {}
	if float(uv[0]) < 0.0 or float(uv[0]) > 1.0 or float(uv[1]) < 0.0 or float(uv[1]) > 1.0:
		return {}
	var brush: Variant = entry.get("brush")
	if (not brush is String and not brush is StringName) or StringName(brush) not in BRUSHES:
		return {}
	if not _number(entry.get("radius")) or float(entry["radius"]) <= 0.0 or float(entry["radius"]) > 1.0:
		return {}
	if not _number(entry.get("strength")) or float(entry["strength"]) <= 0.0 or float(entry["strength"]) > 1.0:
		return {}
	if not _number(entry.get("angle", 0.0)) or not _integer_in_range(entry.get("seed", 0), -2147483647, 2147483647) or not entry.get("erase", false) is bool:
		return {}
	# Filters already express a complete operation; an eraser has no unambiguous
	# inverse for averaging/dilation/erosion, so reject that combination atomically.
	if StringName(brush) in FILTER_BRUSHES and bool(entry.get("erase", false)):
		return {}
	return {"uv": [float(uv[0]), float(uv[1])], "brush": String(brush), "radius": float(entry["radius"]), "strength": float(entry["strength"]), "angle": wrapf(float(entry.get("angle", 0.0)), -PI, PI), "seed": int(entry.get("seed", 0)), "erase": bool(entry.get("erase", false))}


func _noise(x: int, y: int, seed: int) -> float:
	var hash_value: int = ((x * 73856093) ^ (y * 19349663) ^ (seed * 83492791)) & 0x7fffffff
	hash_value = ((hash_value >> 13) ^ hash_value) * 1274126177 & 0x7fffffff
	return float(hash_value) / 2147483647.0


func _apply_operation(operation: Dictionary) -> void:
	var uv: Vector2 = Vector2(operation["uv"][0], operation["uv"][1])
	var radius: float = operation["radius"]
	var brush: StringName = StringName(operation["brush"])
	var strength: float = operation["strength"]
	var angle: float = operation["angle"]
	var seed: int = operation["seed"]
	var erase: bool = operation["erase"]
	var first: Vector2i = Vector2i(maxi(0, int(floorf((uv.x - radius) * size))), maxi(0, int(floorf((uv.y - radius) * size))))
	var last: Vector2i = Vector2i(mini(size, int(ceilf((uv.x + radius) * size))), mini(size, int(ceilf((uv.y + radius) * size))))
	var area: Rect2i = Rect2i(first, last - first)
	if brush in FILTER_BRUSHES:
		_apply_filter(uv, brush, radius, strength, area)
		return
	var cosine: float = cos(angle)
	var sine: float = sin(angle)
	for y: int in range(first.y, last.y):
		for x: int in range(first.x, last.x):
			var delta: Vector2 = (Vector2(x + 0.5, y + 0.5) / float(size) - uv) / radius
			var q: Vector2 = Vector2(cosine * delta.x + sine * delta.y, -sine * delta.x + cosine * delta.y)
			var distance: float = q.length()
			var influence: float = 0.0
			if brush == &"cut":
				var width: float = 0.12 + _noise(int(floorf(q.x * 23.0)), 7, seed) * 0.065
				influence = smoothstep(0.0, 0.22, 1.0 - Vector2(q.x, q.y / width).length())
			elif brush == &"wear":
				influence = smoothstep(0.0, 0.8, 1.0 - distance) * (0.4 + _noise(x, y, seed) * 0.6)
			elif brush == &"burn":
				influence = smoothstep(0.0, 0.65, 1.0 - distance) * (0.8 + _noise(x / 3, y / 3, seed) * 0.2)
			elif brush == &"blood":
				influence = smoothstep(0.0, 0.6, 1.0 - distance) * (0.85 + _noise(x / 2, y / 2, seed) * 0.15)
			else:
				influence = pow(maxf(0.0, 1.0 - distance * distance), 2.0)
			var amount: float = clampf(influence * strength, 0.0, 1.0)
			if amount <= 0.0:
				continue
			var mask: Color = image.get_pixel(x, y)
			if brush == &"dent":
				var old_height: float = _dent_image.get_pixel(x, y).r
				var relief: float = old_height * (1.0 - amount) if erase else minf(old_height, -0.025 * amount)
				_dent_image.set_pixel(x, y, Color(relief, 0.0, 0.0, 1.0))
			else:
				var channel: int = 0 if brush == &"cut" else (1 if brush == &"wear" else (2 if brush == &"burn" else 3))
				mask[channel] = mask[channel] * (1.0 - amount) if erase else 1.0 - (1.0 - mask[channel]) * (1.0 - amount)
				image.set_pixel(x, y, mask)
				# Read quantized RGBA8 values so recipes and derived maps agree exactly.
				mask = image.get_pixel(x, y)
			var height: float = _dent_image.get_pixel(x, y).r - mask.r * 0.008 - mask.g * 0.003 - mask.b * 0.001 + mask.a * 0.0008
			height_image.set_pixel(x, y, Color(height, 0.0, 0.0, 1.0))
	_normal_dirty_rect = area if not _normal_dirty_rect.has_area() else _normal_dirty_rect.merge(area)
	dirty = true


func _apply_filter(uv: Vector2, brush: StringName, radius: float, strength: float, area: Rect2i) -> void:
	# Each operation samples a fixed CPU snapshot, never its own partially written
	# output. Copy once per operation, then visit only the clipped brush footprint.
	var source: Image = image.duplicate()
	var source_dent: Image = _dent_image.duplicate()
	for y: int in range(area.position.y, area.end.y):
		for x: int in range(area.position.x, area.end.x):
			var distance: float = (Vector2(x + 0.5, y + 0.5) / float(size) - uv).length() / radius
			if distance >= 1.0:
				continue
			var amount: float = strength * smoothstep(0.0, 0.25, 1.0 - distance)
			var original: Color = source.get_pixel(x, y)
			var original_dent: float = source_dent.get_pixel(x, y).r
			var filtered: Color = Color(0.0, 0.0, 0.0, 0.0)
			var filtered_dent: float = 0.0
			if brush == &"shrink":
				filtered = Color(1.0, 1.0, 1.0, 1.0)
				filtered_dent = -1.0
			for offset_y: int in range(-1, 2):
				for offset_x: int in range(-1, 2):
					var sample_x: int = clampi(x + offset_x, 0, size - 1)
					var sample_y: int = clampi(y + offset_y, 0, size - 1)
					var sample: Color = source.get_pixel(sample_x, sample_y)
					var sample_dent: float = source_dent.get_pixel(sample_x, sample_y).r
					if brush == &"smooth":
						filtered += sample / 9.0
						filtered_dent += sample_dent / 9.0
					elif brush == &"grow":
						for channel: int in range(4): filtered[channel] = maxf(filtered[channel], sample[channel])
						# A deeper dent is more damage, so dilation uses minimum height.
						filtered_dent = minf(filtered_dent, sample_dent)
					else:
						for channel: int in range(4): filtered[channel] = minf(filtered[channel], sample[channel])
						filtered_dent = maxf(filtered_dent, sample_dent)
			image.set_pixel(x, y, original.lerp(filtered, amount))
			_dent_image.set_pixel(x, y, Color(lerpf(original_dent, filtered_dent, amount), 0.0, 0.0, 1.0))
			var mask: Color = image.get_pixel(x, y)
			var height: float = _dent_image.get_pixel(x, y).r - mask.r * 0.008 - mask.g * 0.003 - mask.b * 0.001 + mask.a * 0.0008
			height_image.set_pixel(x, y, Color(height, 0.0, 0.0, 1.0))
	_normal_dirty_rect = area if not _normal_dirty_rect.has_area() else _normal_dirty_rect.merge(area)
	dirty = true


func _rebuild_normals() -> void:
	if not _normal_dirty_rect.has_area():
		return
	var region: Rect2i = _normal_dirty_rect.grow(2).intersection(Rect2i(0, 0, size, size))
	for y: int in range(region.position.y, region.end.y):
		for x: int in range(region.position.x, region.end.x):
			var slope_x: float = (height_image.get_pixel(mini(x + 1, size - 1), y).r - height_image.get_pixel(maxi(x - 1, 0), y).r) * float(size) * 0.5
			var slope_y: float = (height_image.get_pixel(x, mini(y + 1, size - 1)).r - height_image.get_pixel(x, maxi(y - 1, 0)).r) * float(size) * 0.5
			var normal: Vector3 = Vector3(-slope_x, -slope_y, 1.0).normalized()
			normal_image.set_pixel(x, y, Color(normal.x * 0.5 + 0.5, normal.y * 0.5 + 0.5, normal.z * 0.5 + 0.5, 1.0))
	_normal_dirty_rect = Rect2i()
