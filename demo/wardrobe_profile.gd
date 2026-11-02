extends RefCounted
## Authoring settings only. Loading a profile never repairs runtime item damage.

static func encode(actor: Node3D) -> Dictionary:
	var shoulder: Array = []
	var bag: Array = []
	for point in actor.shoulder.connection_points: shoulder.append([point.x,point.y,point.z])
	for point in actor.bag.connection_points: bag.append([point.x,point.y,point.z])
	return {"format":"AeroCloth3D.profile", "version":1, "shoulder_connections":shoulder,"bag_connections":bag,"cloth_weights":Array(actor.cloth.weights),"accessory_rule":actor.accessory_rule,"shoulder_covers_inner":actor.shoulder_covers_inner}

static func validate(data: Variant) -> bool:
	if not data is Dictionary or data.get("format") != "AeroCloth3D.profile" or data.get("version") != 1:
		return false
	for key in ["shoulder_connections","bag_connections"]:
		if not data.get(key) is Array or data[key].size() != (2 if key == "shoulder_connections" else 1): return false
		for point in data[key]:
			if not point is Array or point.size() != 3: return false
			for coordinate in point:
				if not (coordinate is float or coordinate is int) or not is_finite(float(coordinate)) or absf(float(coordinate)) > 0.5: return false
	if not data.get("cloth_weights") is Array or data["cloth_weights"].size() != 99: return false
	for weight in data["cloth_weights"]:
		if not (weight is float or weight is int) or not is_finite(float(weight)) or weight < 0 or weight > 1: return false
	var rule: Variant = data.get("accessory_rule")
	if not (rule is float or rule is int): return false
	return (rule == 0.0 or rule == 1.0 or rule == 2.0) and data.get("shoulder_covers_inner") is bool

static func apply(actor: Node3D, data: Dictionary) -> void:
	for i in range(2):
		var point: Array = data["shoulder_connections"][i]
		actor.shoulder.set_connection_point(i, Vector3(point[0],point[1],point[2]))
	var point: Array = data["bag_connections"][0]
	actor.bag.set_connection_point(0, Vector3(point[0],point[1],point[2]))
	actor.cloth.weights = PackedFloat32Array(data["cloth_weights"])
	actor.accessory_rule = int(data["accessory_rule"])
	actor.shoulder_covers_inner = data["shoulder_covers_inner"]
	actor.refresh_coverage()
