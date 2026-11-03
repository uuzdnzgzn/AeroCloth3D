@tool
class_name AeroBodyCollision
extends RefCounted
## Cheap animated sphere proxies. Centers are authored in character rest space,
## not bone-local space. These are conservative helpers, not exact body contact.

static func default_specs(skeleton:Skeleton3D=null) -> Array[Dictionary]:
	var result:Array[Dictionary]=[]
	for values in [["chest","Chest",Vector3(0,1.25,0),.16],["hips","Hips",Vector3(0,.98,0),.17],["thigh_r","Thigh_R",Vector3(-.11,.65,0),.105],["thigh_l","Thigh_L",Vector3(.11,.65,0),.105]]:
		var bone:String=values[1] if skeleton and skeleton.find_bone(values[1])>=0 else ""
		result.append({"id":values[0],"bone":bone,"center":values[2],"radius":values[3]})
	return result

static func _center(value:Variant) -> Variant:
	if value is Vector3:return value if value.is_finite() else null
	if value is Array and value.size()==3:
		for component in value:
			if typeof(component) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(component)):return null
		return Vector3(value[0],value[1],value[2])
	return null

static func validate(specs:Array,skeleton:Skeleton3D=null) -> PackedStringArray:
	var errors:=PackedStringArray()
	for i in range(specs.size()):
		var spec:Variant=specs[i]
		if not spec is Dictionary:
			errors.append("Body collider %d is not a dictionary" % i)
			continue
		var bone:Variant=spec.get("bone","")
		if typeof(bone) not in [TYPE_STRING,TYPE_STRING_NAME]:errors.append("Body collider %d has invalid bone" % i)
		elif str(bone)!="" and (skeleton==null or skeleton.find_bone(bone)<0):errors.append("Body collider %d missing bone: %s" % [i,str(bone)])
		if _center(spec.get("center"))==null:errors.append("Body collider %d needs a finite rest-space center" % i)
		var radius:Variant=spec.get("radius")
		if typeof(radius) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(radius)) or float(radius)<.005 or float(radius)>1.0:errors.append("Body collider %d radius must be finite in [0.005,1]" % i)
	return errors

static func sample(specs:Array,skeleton:Skeleton3D,character_global:Transform3D,compression:float=0.0) -> Array[Vector4]:
	var result:Array[Vector4]=[]
	if not validate(specs,skeleton).is_empty() or not is_finite(compression):return result
	if not character_global.origin.is_finite() or not character_global.basis.x.is_finite() or not character_global.basis.y.is_finite() or not character_global.basis.z.is_finite() or absf(character_global.basis.determinant())<.000001:return result
	var character_to_skeleton:=Transform3D.IDENTITY
	if skeleton:
		if absf(skeleton.global_basis.determinant())<.000001:return result
		character_to_skeleton=skeleton.global_transform.affine_inverse()*character_global
	for spec in specs:
		var transform:Transform3D=character_global
		var bone:StringName=StringName(spec.get("bone",""))
		if skeleton and bone!=&"":
			var index:int=skeleton.find_bone(bone)
			var rest:Transform3D=skeleton.get_bone_global_rest(index)
			if absf(rest.basis.determinant())<.000001:return []
			transform=skeleton.global_transform*skeleton.get_bone_global_pose(index)*rest.affine_inverse()*character_to_skeleton
		var center:Vector3=transform*_center(spec["center"])
		var scale:float=maxf(transform.basis.x.length(),maxf(transform.basis.y.length(),transform.basis.z.length()))
		var radius:float=float(spec["radius"])*scale
		if str(spec.get("id",""))=="chest" or bone==&"Chest":radius*=1.0-.1*clampf(compression,0.0,1.0)
		if not center.is_finite() or not is_finite(radius):return []
		result.append(Vector4(center.x,center.y,center.z,radius))
	return result
