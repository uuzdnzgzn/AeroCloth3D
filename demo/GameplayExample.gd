extends Node3D
## Example combat adapter. This scene has no EditorPlugin/UI-authoring dependency.
const Rig=preload("res://addons/aero_cloth_3d/core/aero_wearable_rig.gd")
@export var outfit:Resource
var wearer:Node3D
var selection:OptionButton
var message:Label
var counter:=0
func _ready() -> void:
	var light:=DirectionalLight3D.new()
	light.rotation_degrees=Vector3(-35,-25,0)
	add_child(light)
	var environment:=WorldEnvironment.new()
	var env:=Environment.new()
	env.background_mode=Environment.BG_COLOR
	env.background_color=Color("101c2b")
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_energy=.5
	environment.environment=env
	add_child(environment)
	var camera:=Camera3D.new()
	add_child(camera)
	camera.position=Vector3(-1.4,1.5,3.2)
	camera.look_at(Vector3(0,1,0))
	var floor_body:=StaticBody3D.new()
	var shape:=CollisionShape3D.new()
	var box:=BoxShape3D.new()
	box.size=Vector3(20,.1,20)
	shape.shape=box
	floor_body.add_child(shape)
	floor_body.position.y=-.05
	add_child(floor_body)
	var floor_visual:=MeshInstance3D.new()
	var floor_mesh:=BoxMesh.new()
	floor_mesh.size=box.size
	floor_visual.mesh=floor_mesh
	floor_body.add_child(floor_visual)
	wearer=Rig.new()
	add_child(wearer)
	if outfit==null:outfit=load("res://demo/ExampleOutfit.tres")
	var errors:PackedStringArray=wearer.load_outfit(outfit)
	wearer.play_animation("Walk")
	var canvas:=CanvasLayer.new()
	add_child(canvas)
	var panel:=VBoxContainer.new()
	panel.position=Vector2(20,20)
	panel.custom_minimum_size.x=420
	canvas.add_child(panel)
	var title:=Label.new()
	title.text="AeroCloth · oyun entegrasyonu örneği"
	panel.add_child(title)
	selection=OptionButton.new()
	for item in outfit.items:selection.add_item(item.display_name)
	panel.add_child(selection)
	for pair in [["Dünya temasından darbe · 22",_hit],["Hasarı sıfırla",func()->void:wearer.reset_preview()]]:
		var button:=Button.new()
		button.text=pair[0]
		button.pressed.connect(pair[1])
		panel.add_child(button)
	message=Label.new()
	message.text="Hazırlama arayüzü yüklenmedi. Darbeler runtime API ile gider." if errors.is_empty() else " · ".join(errors)
	panel.add_child(message)
	wearer.controller.stage_changed.connect(func(item_id:StringName,region_id:StringName,_old:int,next:int)->void:message.text="Sinyal: %s/%s → aşama %d"%[item_id,region_id,next])
func _hit() -> void:
	var id:StringName=outfit.items[selection.selected].id
	var slot:Dictionary=wearer.slots[id]
	var point:Vector3=slot["visual"].global_transform*slot["visual"].mesh.get_aabb().get_center()
	if slot["surface"]:point=slot["surface"].points[slot["surface"].points.size()/2]
	counter+=1
	var result:Dictionary=wearer.apply_hit({"hit_id":"combat_"+str(counter),"item_id":id,"position":point,"direction":Vector3(0,0,-1),"type":"slash","amount":22.0,"impulse":Vector3(.1,.05,.2)})
	if not result.get("accepted",false):message.text="Temas uygulanmadı: "+str(result.get("reason",""))
