extends SceneTree
const Factory=preload("res://addons/aero_cloth_3d/core/aero_example_factory.gd")
const Rig=preload("res://addons/aero_cloth_3d/core/aero_wearable_rig.gd")
func _initialize() -> void:
	var recipe:Resource=Factory.create()
	var error:Error=ResourceSaver.save(recipe,"res://demo/ExampleOutfit.tres")
	if error!=OK:push_error(error_string(error));quit(1);return
	var node:Node3D=Rig.new()
	node.name="WearableCharacter"
	node.outfit=recipe
	var scene:=PackedScene.new()
	error=scene.pack(node)
	if error==OK:error=ResourceSaver.save(scene,"res://demo/WearableCharacter.tscn")
	node.free()
	print("AUTHORING_EXAMPLE_BUILD ",error)
	quit(0 if error==OK else 1)
