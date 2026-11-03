extends SceneTree
const Colliders=preload("res://addons/aero_cloth_3d/core/aero_body_collision.gd")
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("run")
func expect(ok:bool,message:String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)
func run() -> void:
	var character:=Node3D.new()
	root.add_child(character)
	var skeleton:=Skeleton3D.new()
	character.add_child(skeleton)
	skeleton.add_bone("Chest")
	skeleton.set_bone_rest(0,Transform3D(Basis.IDENTITY,Vector3(0,1,0)))
	skeleton.reset_bone_poses()
	var specs:Array=[{"id":"chest","bone":"Chest","center":Vector3(0,1.25,0),"radius":.16}]
	expect(Colliders.validate(specs,skeleton).is_empty(),"Valid animated sphere")
	var samples:Array[Vector4]=Colliders.sample(specs,skeleton,character.global_transform)
	expect(samples.size()==1 and Vector3(samples[0].x,samples[0].y,samples[0].z).is_equal_approx(Vector3(0,1.25,0)),"Rest centers stay in character rest space")
	skeleton.set_bone_pose_position(0,Vector3(.3,1,0))
	skeleton.force_update_all_bone_transforms()
	samples=Colliders.sample(specs,skeleton,character.global_transform)
	expect(Vector3(samples[0].x,samples[0].y,samples[0].z).is_equal_approx(Vector3(.3,1.25,0)),"Current bone delta moves sphere")
	character.position=Vector3(2,3,4)
	samples=Colliders.sample(specs,skeleton,character.global_transform)
	expect(Vector3(samples[0].x,samples[0].y,samples[0].z).is_equal_approx(Vector3(2.3,4.25,4)),"Character world transform is applied once")
	var compressed:Array[Vector4]=Colliders.sample(specs,skeleton,character.global_transform,1)
	expect(is_equal_approx(compressed[0].w,.144),"Compression reduces chest proxy radius")
	expect(Colliders.sample(specs,skeleton,character.global_transform,NAN).is_empty(),"Nonfinite compression rejected")
	expect(not Colliders.validate(specs,null).is_empty(),"Named bone requires a skeleton")
	var invalid:Array=specs.duplicate(true)
	invalid[0]["bone"]="Missing"
	expect(not Colliders.validate(invalid,skeleton).is_empty(),"Missing bone reported")
	expect(Colliders.sample(invalid,skeleton,character.global_transform).is_empty(),"Invalid collider set does not partly publish")
	for radius in [-1,0,.001,1.1,NAN,INF,"large"]:
		invalid=specs.duplicate(true)
		invalid[0]["radius"]=radius
		expect(not Colliders.validate(invalid,skeleton).is_empty(),"Invalid radius rejected")
	invalid=specs.duplicate(true)
	invalid[0]["center"]=[0,INF,0]
	expect(not Colliders.validate(invalid,skeleton).is_empty(),"Nonfinite center rejected")
	var static_specs:Array=[{"bone":"","center":[.1,.2,.3],"radius":.1}]
	expect(Colliders.validate(static_specs).is_empty(),"JSON static sphere valid without skeleton")
	samples=Colliders.sample(static_specs,null,Transform3D(Basis.from_scale(Vector3(2,1,1)),Vector3(1,0,0)))
	expect(Vector3(samples[0].x,samples[0].y,samples[0].z).is_equal_approx(Vector3(1.2,.2,.3)) and is_equal_approx(samples[0].w,.2),"Nonuniform scale gives conservative world radius")
	expect(Colliders.default_specs(skeleton).size()==4 and Colliders.validate(Colliders.default_specs(skeleton),skeleton).is_empty(),"Four default helpers adapt to available bone names")
	expect(Colliders.validate(Colliders.default_specs(null)).is_empty(),"Default helpers also work with static mannequin")
	expect(specs[0]["center"]==Vector3(0,1.25,0) and specs[0]["radius"]==.16,"Sampling never mutates authoring specs")
	character.queue_free()
	await process_frame
	print("BODY_COLLISION_TESTS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
