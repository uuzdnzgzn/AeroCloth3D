@tool
extends Control
## Editor authoring client; preview and exported gameplay use AeroWearableRig.
const Rig = preload("res://addons/aero_cloth_3d/core/aero_wearable_rig.gd")
const Factory = preload("res://addons/aero_cloth_3d/core/aero_example_factory.gd")
const Definition = preload("res://addons/aero_cloth_3d/resources/aero_wearable_definition.gd")
const Canvas = preload("res://addons/aero_cloth_3d/core/aero_damage_canvas.gd")
const MapView = preload("res://addons/aero_cloth_3d/editor/aero_map_view.gd")
const Surface = preload("res://addons/aero_cloth_3d/core/aero_proxy_surface_3d.gd")
const TEAL:=Color("48dfca")
var editor_plugin:EditorPlugin
var outfit:Resource
var rig:Node3D
var viewport:SubViewport
var camera:Camera3D
var selected_id:StringName=&"shirt"
var selected_region:=0
var selected_stage:=0
var selected_tab:=1
var item_list:ItemList
var region_list:OptionButton
var stage_list:ItemList
var tools:VBoxContainer
var map_view:Control
var status:Label
var detail:Label
var slider:HSlider
var event_list:ItemList
var timeline_controls:HBoxContainer
var local_history:=UndoRedo.new()
var canvas:RefCounted
var brush:=&"cut"
var radius:=.08
var strength:=.95
var angle:=0.0
var erase:=false
var paint_mode:=true
var painting:=false
var paint_before:Dictionary={}
var stage_map:=false
var paint_target:Resource
var mobility_paint:=false
var mobility_value:=0.0
var paint_weights_before:=PackedFloat32Array()
var map_preview_kind:=0
var hit_type:=&"slash"
var show_collision:=false
var collision_debug:Node3D
var selection_gizmo:Node3D
var selection_box:MeshInstance3D
var selection_mesh:MeshInstance3D
var painting_3d:=false
var playing:=false
var preview_time:=0.0
var tick:=0
var event_cursor:=0
var accumulator:=0.0
var updating:=false
var orbit:=Vector2(-.4,.13)
var distance:=3.25
var focus:=Vector3(0,.98,0)
var dirty:=false
var last_hit:Dictionary={"uv":Vector2(.5,.5)}
var _built:=false
var _capture:=false
var _capture_frames:=0

func _ready() -> void:
	if _built:return
	_built=true
	_build_ui()
	_build_world()
	load_recipe(Factory.create())
	for argument in OS.get_cmdline_user_args():
		if argument=="--authoring-capture":
			_capture=true
			_capture_frames=80

func configure(plugin:EditorPlugin) -> void: editor_plugin=plugin

func _style(color:Color,border:Color=Color("2b3b50")) -> StyleBoxFlat:
	var result:=StyleBoxFlat.new()
	result.bg_color=color
	result.border_color=border
	result.set_border_width_all(1)
	result.set_corner_radius_all(5)
	result.content_margin_left=10
	result.content_margin_right=10
	result.content_margin_top=7
	result.content_margin_bottom=7
	return result

func _label(parent:Node,text_value:String,font_size:int=14,color:Color=Color("d8e3f0")) -> Label:
	var label:=Label.new()
	label.text=text_value
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color)
	parent.add_child(label)
	return label

func _text(parent:Node,text_value:String) -> Label:
	var result:Label=_label(parent,text_value,12,Color("91a2bc"))
	result.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	return result

func _button(parent:Node,text_value:String,callback:Callable) -> Button:
	var button:=Button.new()
	button.text=text_value
	button.custom_minimum_size.y=34
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _build_ui() -> void:
	var theme_value:=Theme.new()
	theme_value.default_font_size=13
	theme_value.set_color("font_color","Label",Color("d8e3f0"))
	theme_value.set_stylebox("normal","Button",_style(Color("1b293b")))
	theme_value.set_stylebox("hover","Button",_style(Color("204146"),TEAL))
	theme_value.set_stylebox("pressed","Button",_style(Color("163d3b"),TEAL))
	theme_value.set_stylebox("selected","ItemList",_style(Color("16443e"),TEAL))
	theme_value.set_stylebox("selected_focus","ItemList",_style(Color("16443e"),TEAL))
	theme_value.set_color("font_selected_color","ItemList",TEAL)
	theme=theme_value
	var bg:=ColorRect.new()
	bg.color=Color("0b1320")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin:=MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,12)
	add_child(margin)
	var stack:=VBoxContainer.new()
	stack.add_theme_constant_override("separation",9)
	margin.add_child(stack)
	var bar:=HBoxContainer.new()
	stack.add_child(bar)
	var title:Label=_label(bar,"AERO / CLOTH · Hazırlama",23,TEAL)
	title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_button(bar,"Örnek",func()->void:load_recipe(Factory.create()))
	_button(bar,"Aç",func()->void:_dialog("open"))
	_button(bar,"Kaydet",save_recipe)
	_button(bar,"Farklı kaydet",func()->void:_dialog("save"))
	_button(bar,"Geri al",_undo)
	_button(bar,"Yinele",_redo)
	var main:=HBoxContainer.new()
	main.size_flags_vertical=Control.SIZE_EXPAND_FILL
	stack.add_child(main)
	var left:=VBoxContainer.new()
	left.custom_minimum_size.x=215
	main.add_child(left)
	_label(left,"GİYİLEN PARÇALAR",12,TEAL)
	item_list=ItemList.new()
	item_list.custom_minimum_size.y=180
	item_list.size_flags_vertical=Control.SIZE_EXPAND_FILL
	item_list.item_selected.connect(func(index:int)->void:select_item(outfit.items[index].id))
	left.add_child(item_list)
	_button(left,"Giysi GLB / sahne ekle",func()->void:_dialog("item"))
	_button(left,"Karakter GLB seç",func()->void:_dialog("character"))
	_button(left,"Blender metadata içe aktar",func()->void:_dialog("metadata"))
	_label(left,"HASAR BÖLGESİ",12,TEAL)
	region_list=OptionButton.new()
	region_list.item_selected.connect(func(index:int)->void:
		selected_region=index
		selected_stage=0
		_refresh_stage_list()
		_build_tools()
	)
	left.add_child(region_list)
	_label(left,"DÜZENLENEN AŞAMA",12,TEAL)
	stage_list=ItemList.new()
	stage_list.custom_minimum_size.y=150
	stage_list.item_selected.connect(_choose_stage)
	left.add_child(stage_list)
	_button(left,"Aşama ekle",_add_stage)
	_button(left,"Seçili aşamayı kaldır",_remove_stage)
	var center:=VBoxContainer.new()
	center.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	main.add_child(center)
	var preview_bar:=HBoxContainer.new()
	center.add_child(preview_bar)
	_button(preview_bar,"Karaktere odakla",func()->void:focus=Vector3(0,.98,0);distance=3.25;_update_camera())
	_button(preview_bar,"Seçili parçaya odakla",func()->void:
		if rig.slots.has(selected_id): focus=rig.slots[selected_id]["visual"].global_position;distance=1.2;_update_camera()
	)
	_button(preview_bar,"Doğrula",validate_recipe)
	_button(preview_bar,"Oyun sahnesi üret",func()->void:_dialog("game_scene"))
	var preview:=SubViewportContainer.new()
	preview.stretch=true
	preview.custom_minimum_size=Vector2(350,300)
	preview.size_flags_vertical=Control.SIZE_EXPAND_FILL
	preview.gui_input.connect(_preview_input)
	center.add_child(preview)
	viewport=SubViewport.new()
	viewport.own_world_3d=true
	viewport.handle_input_locally=false
	preview.add_child(viewport)
	detail=_text(center,"Sağ sürükle: kamera · Tekerlek: yaklaş · Sol tuş: boya veya darbe")
	timeline_controls=HBoxContainer.new()
	center.add_child(timeline_controls)
	_button(timeline_controls,"▶ Oynat",func()->void:playing=true)
	_button(timeline_controls,"Ⅱ Duraklat",func()->void:playing=false)
	_button(timeline_controls,"↺ Baştan",func()->void:seek_time(0))
	_button(timeline_controls,"+ Olay",add_timeline_event)
	slider=HSlider.new()
	slider.max_value=8
	slider.step=1.0/60
	slider.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(value:float)->void:
		if not updating: seek_time(value)
	)
	center.add_child(slider)
	event_list=ItemList.new()
	event_list.custom_minimum_size.y=62
	center.add_child(event_list)
	event_list.item_selected.connect(func(_index:int)->void:
		if selected_tab==4:_build_tools()
	)
	var right:=VBoxContainer.new()
	right.custom_minimum_size.x=315
	main.add_child(right)
	var tabs:=OptionButton.new()
	for tab in ["Hazırlama","Haritalar","Aşamalar","Katmanlar","Test / kayıt","Çarpışma"]: tabs.add_item(tab)
	tabs.selected=1
	tabs.item_selected.connect(func(index:int)->void:selected_tab=index;_build_tools())
	right.add_child(tabs)
	var scroll:=ScrollContainer.new()
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	right.add_child(scroll)
	tools=VBoxContainer.new()
	tools.custom_minimum_size.x=295
	tools.add_theme_constant_override("separation",8)
	scroll.add_child(tools)
	status=_text(stack,"Hazırlama kaynağı yükleniyor…")
	status.custom_minimum_size.y=32

func _build_world() -> void:
	var world:=Node3D.new()
	viewport.add_child(world)
	var environment:=WorldEnvironment.new()
	var settings:=Environment.new()
	settings.background_mode=Environment.BG_COLOR
	settings.background_color=Color("101c2b")
	settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color=Color("bdcce0")
	settings.ambient_light_energy=.55
	environment.environment=settings
	world.add_child(environment)
	var key:=DirectionalLight3D.new()
	key.rotation_degrees=Vector3(-35,-25,0)
	key.light_energy=1.2
	world.add_child(key)
	var floor_node:=MeshInstance3D.new()
	var floor_mesh:=BoxMesh.new()
	floor_mesh.size=Vector3(20,.08,20)
	floor_node.mesh=floor_mesh
	floor_node.position.y=-.05
	var floor_material:=StandardMaterial3D.new()
	floor_material.albedo_color=Color("1a2b40")
	floor_node.material_override=floor_material
	world.add_child(floor_node)
	var floor_body:=StaticBody3D.new()
	var shape:=CollisionShape3D.new()
	var box:=BoxShape3D.new()
	box.size=floor_mesh.size
	shape.shape=box
	floor_body.add_child(shape)
	floor_body.position=floor_node.position
	world.add_child(floor_body)
	rig=Rig.new()
	rig.manual_simulation=true
	rig.simulation_running=false
	world.add_child(rig)
	camera=Camera3D.new()
	camera.fov=35
	world.add_child(camera)
	_update_camera()

func load_recipe(recipe:Resource) -> void:
	if not recipe is AeroOutfit:
		status.text="Bu dosya AeroOutfit hazırlama kaynağı değil."
		return
	playing=false
	local_history.clear_history()
	outfit=recipe
	selected_id=outfit.items[0].id if not outfit.items.is_empty() else &""
	selected_region=0
	selected_stage=0
	_reload_rig()
	dirty=false
	status.text="Kaynak yüklendi. Önizleme oyun hasarından ayrı tutulur."

func _reload_rig() -> void:
	playing=false
	preview_time=0
	tick=0
	event_cursor=0
	var problems:PackedStringArray=rig.load_outfit(outfit)
	item_list.clear()
	for item in outfit.items:
		item_list.add_item(item.display_name)
		if item.id==selected_id: item_list.select(item_list.item_count-1)
	_refresh_regions()
	if selected_stage>0 and _region() and rig.controller.has_method("set_preview_stage"):
		rig.controller.set_preview_stage(selected_id,_region().id,selected_stage)
	_build_tools()
	_refresh_timeline()
	_refresh_animations()
	if not problems.is_empty(): status.text="Doğrulama: "+" · ".join(problems)

func _item() -> Resource:
	if outfit:
		for item in outfit.items:
			if item.id==selected_id:return item
	return null

func _region() -> Resource:
	var item:Resource=_item()
	return item.regions[mini(selected_region,item.regions.size()-1)] if item and not item.regions.is_empty() else null

func select_item(id:StringName) -> void:
	selected_id=id
	if outfit:
		for i in range(outfit.items.size()):
			if outfit.items[i].id==id:item_list.select(i)
	selected_region=0
	selected_stage=0
	_refresh_regions()
	_build_tools()

func _refresh_regions() -> void:
	region_list.clear()
	var item:Resource=_item()
	if item:
		for region in item.regions: region_list.add_item(region.label+" / "+str(region.id))
		if not item.regions.is_empty(): region_list.select(mini(selected_region,item.regions.size()-1))
	_refresh_stage_list()

func _refresh_stage_list() -> void:
	stage_list.clear()
	var region:Resource=_region()
	if region:
		for stage in region.stages: stage_list.add_item("%s · %.0f" % [stage.label,stage.threshold])
		selected_stage=clampi(selected_stage,0,region.stages.size()-1)
		stage_list.select(selected_stage)

func _choose_stage(index:int) -> void:
	selected_stage=index
	playing=false
	var region:Resource=_region()
	if region and rig.controller.has_method("set_preview_stage"):
		rig.controller.set_preview_stage(selected_id,region.id,index)
	_build_tools()
	_refresh_detail()

func _clear_tools() -> void:
	for child in tools.get_children():
		tools.remove_child(child)
		child.queue_free()

func _build_tools() -> void:
	_clear_tools()
	var item:Resource=_item()
	if not item:
		_text(tools,"Giysi ekleyin veya örneği yükleyin.")
		return
	_label(tools,item.display_name,21,TEAL)
	var equipped:=CheckButton.new()
	equipped.text="Giyili · hasar korunur"
	equipped.button_pressed=rig.controller.get_item_state(selected_id).get("equipped",false)
	equipped.toggled.connect(func(value:bool)->void:
		if value:rig.controller.equip(selected_id)
		else:rig.controller.unequip(selected_id)
		_refresh_detail()
	)
	tools.add_child(equipped)
	match selected_tab:
		0:_prepare_tools(item)
		1:_map_tools(item)
		2:_stage_tools(item)
		3:_layer_tools(item)
		4:_test_tools(item)
		5:_collision_tools()
	_refresh_detail()

func _spin(parent:Node,label_value:String,value:float,min_value:float,max_value:float,step:float,callback:Callable) -> SpinBox:
	var row:=HBoxContainer.new()
	parent.add_child(row)
	var label:Label=_label(row,label_value,12)
	label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var spin:=SpinBox.new()
	spin.min_value=min_value
	spin.max_value=max_value
	spin.step=step
	spin.value=value
	spin.value_changed.connect(callback)
	row.add_child(spin)
	return spin

func _prepare_tools(item:Resource) -> void:
	_text(tools,"İskelet, mesh ve kaynak alanları Godot Inspector üzerinden de düzenlenebilir.")
	_button(tools,"Giysi kaynağını Inspector’da aç",func()->void:
		if editor_plugin:editor_plugin.get_editor_interface().inspect_object(item)
	)
	var name_edit:=LineEdit.new()
	name_edit.text=item.display_name
	name_edit.text_submitted.connect(func(value:String)->void:_commit_value("Giysi adı",item,"display_name",item.display_name,value))
	tools.add_child(name_edit)
	var mode:=OptionButton.new()
	for name_value in ["skinned","cloth","rigid"]:mode.add_item(name_value)
	mode.select([&"skinned",&"cloth",&"rigid"].find(item.motion_mode))
	mode.item_selected.connect(func(index:int)->void:_commit_value("Hareket tipi",item,"motion_mode",item.motion_mode,[&"skinned",&"cloth",&"rigid"][index]))
	tools.add_child(mode)
	var bone:=OptionButton.new()
	bone.add_item("Kemik seçilmedi")
	if rig.skeleton:
		for i in range(rig.skeleton.get_bone_count()):
			var name_value:String=rig.skeleton.get_bone_name(i)
			bone.add_item(name_value)
			if name_value==str(item.anchor_bone):bone.select(i+1)
	bone.item_selected.connect(func(index:int)->void:_commit_value("Kemik bağlantısı",item,"anchor_bone",item.anchor_bone,StringName(bone.get_item_text(index)) if index>0 else &""))
	tools.add_child(bone)
	if item.source_scene:
		var imported:Node=item.source_scene.instantiate()
		var paths:Array[NodePath]=[]
		var meshes: Array[MeshInstance3D]=rig.meshes(imported)
		if not meshes.is_empty():
			var selector:=OptionButton.new()
			for mesh in meshes:
				var path:NodePath=imported.get_path_to(mesh)
				paths.append(path)
				selector.add_item(str(path))
				if path==item.mesh_path:selector.select(paths.size()-1)
			selector.item_selected.connect(func(index:int)->void:_commit_value("Kaynak mesh seçimi",item,"mesh_path",item.mesh_path,paths[index]))
			_label(tools,"Giysi mesh’i",12,TEAL)
			tools.add_child(selector)
			var proxy_selector:=OptionButton.new()
			proxy_selector.add_item("Proxy mesh seç / değiştir")
			for mesh in meshes:proxy_selector.add_item(str(imported.get_path_to(mesh)))
			var source_meshes:Array[Mesh]=[]
			for mesh in meshes:source_meshes.append(mesh.mesh)
			proxy_selector.item_selected.connect(func(index:int)->void:
				if index==0:return
				var source_mesh:Mesh=source_meshes[index-1]
				if source_mesh is ArrayMesh:_commit_value("Fizik proxy mesh",item,"proxy_mesh",item.proxy_mesh,source_mesh)
				else:status.text="Proxy için ArrayMesh içeren GLB mesh seçin."
			)
			tools.add_child(proxy_selector)
		imported.free()
	for axis in range(3):
		_spin(tools,"Konum "+["X","Y","Z"][axis],item.bind_transform.origin[axis],-5,5,.01,func(value:float)->void:
			var transform:Transform3D=item.bind_transform
			transform.origin[axis]=value
			_commit_value("Giysi konumu",item,"bind_transform",item.bind_transform,transform)
		)
	for index in range(item.connection_points.size()):
		_label(tools,"Bağlantı %d" % (index+1),12,TEAL)
		for axis in range(3):
			_spin(tools,["X","Y","Z"][axis],item.connection_points[index][axis],-.8,.8,.01,func(value:float)->void:
				var points:PackedVector3Array=item.connection_points.duplicate()
				points[index][axis]=value
				_commit_value("Bağlantı yerleştir",item,"connection_points",item.connection_points,points)
			)
	_spin(tools,"Sıkıştırma",item.compression,0,1,.05,func(value:float)->void:_commit_value("Morph sürücüsü",item,"compression",item.compression,value))
	_text(tools,"Skinned giysi aynı rest iskeletine hazırlanmış olmalı. Otomatik ağırlık önerisi Blender eklentisinde kopya üzerinde yapılır.")

func _map_tools(item:Resource) -> void:
	var scope:=CheckButton.new()
	scope.text="Seçili aşamaya özel harita"
	scope.button_pressed=stage_map
	scope.toggled.connect(func(value:bool)->void:stage_map=value;_build_tools())
	tools.add_child(scope)
	canvas=Canvas.new()
	canvas.initialize(item.mask_resolution)
	var target:Resource=_map_target()
	if target and not target.damage_recipe.is_empty():canvas.import_recipe(target.damage_recipe)
	canvas.flush()
	if item.proxy_mesh:
		var paint_selector:=OptionButton.new()
		for label_value in ["Hasar haritası","Hareket: sabit (0)","Hareket: kısmi (0.5)","Hareket: serbest (1)"]:paint_selector.add_item(label_value)
		paint_selector.selected=0 if not mobility_paint else int(mobility_value*2)+1
		paint_selector.item_selected.connect(func(index:int)->void:mobility_paint=index>0;mobility_value=float(index-1)*.5;_refresh_map_preview())
		tools.add_child(paint_selector)
	var brush_choice:=OptionButton.new()
	for name_value in Canvas.BRUSHES:brush_choice.add_item(str(name_value))
	brush_choice.select(Canvas.BRUSHES.find(brush))
	brush_choice.item_selected.connect(func(index:int)->void:
		brush=Canvas.BRUSHES[index]
		if brush in Canvas.FILTER_BRUSHES:erase=false
		call_deferred("_build_tools")
	)
	tools.add_child(brush_choice)
	_spin(tools,"Yarıçap / UV",radius,.005,.5,.005,func(value:float)->void:radius=value)
	_spin(tools,"Güç",strength,0,1,.05,func(value:float)->void:strength=value)
	_spin(tools,"Açı / derece",rad_to_deg(angle),-180,180,5,func(value:float)->void:angle=deg_to_rad(value))
	var erase_toggle:=CheckButton.new()
	erase_toggle.text="Silgi"
	erase_toggle.button_pressed=erase
	erase_toggle.disabled=brush in Canvas.FILTER_BRUSHES
	erase_toggle.toggled.connect(func(value:bool)->void:erase=value)
	tools.add_child(erase_toggle)
	var paint_toggle:=CheckButton.new()
	paint_toggle.text="3D önizlemede boya"
	paint_toggle.button_pressed=paint_mode
	paint_toggle.toggled.connect(func(value:bool)->void:paint_mode=value)
	tools.add_child(paint_toggle)
	var map_choice:=OptionButton.new()
	for name_value in ["Maske RGB","Alpha","Normal","Roughness","Albedo önizlemesi","Yükseklik"]:map_choice.add_item(name_value)
	map_choice.selected=map_preview_kind
	map_choice.item_selected.connect(func(index:int)->void:map_preview_kind=index;_refresh_map_preview())
	tools.add_child(map_choice)
	map_view=MapView.new()
	map_view.texture=canvas.texture
	map_view.stroke_started.connect(_stroke_begin)
	map_view.stroke_point.connect(_stroke_at)
	map_view.stroke_finished.connect(_stroke_end)
	tools.add_child(map_view)
	_refresh_map_preview()
	_text(tools,"UV görünümü: R kesik · G aşınma · B yanık. Normal/alpha/roughness haritaları Dışa aktar ile üretilir. Aşama 0 sağlam görünür; testi aşama seçimiyle yap.")
	if item.proxy_mesh:_text(tools,"Hareket noktaları: turuncu sabit · turkuaz kısmi · mavi serbest. Bunlar temel boya; üst katman etkileri ayrıca uygulanır.")
	_button(tools,"Haritaları PNG / tarif olarak dışa aktar",func()->void:_dialog("maps"))
	_button(tools,"Haritayı temizle",func()->void:
		var map_target:Resource=_map_target()
		if map_target:_commit_value("Haritayı temizle",map_target,"damage_recipe",map_target.damage_recipe,{})
	)

func _map_target() -> Resource:
	return _region().stages[selected_stage] if stage_map and _region() else _item()

func _refresh_map_preview() -> void:
	if not is_instance_valid(map_view) or canvas==null:return
	map_view.texture=canvas.normal_texture if map_preview_kind==2 else (canvas.height_texture if map_preview_kind==5 else canvas.texture)
	map_view.set_view_kind(map_preview_kind)
	if is_instance_valid(map_view.mobility_overlay):
		var points:=PackedVector3Array()
		var item:Resource=_item()
		if mobility_paint and item and item.proxy_mesh:
			var uv:PackedVector2Array=_proxy_uvs(item)
			for i in range(uv.size()):points.append(Vector3(uv[i].x,uv[i].y,item.mobility[i] if i<item.mobility.size() else 1.0))
		map_view.mobility_overlay.points=points
		map_view.mobility_overlay.queue_redraw()

func _proxy_uvs(item:Resource) -> PackedVector2Array:
	var arrays:Array=item.proxy_mesh.surface_get_arrays(0)
	if arrays[Mesh.ARRAY_TEX_UV2]!=null and not arrays[Mesh.ARRAY_TEX_UV2].is_empty():return arrays[Mesh.ARRAY_TEX_UV2]
	return arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV]!=null else PackedVector2Array()

func _stage_tools(_item_value:Resource) -> void:
	var region:Resource=_region()
	if region==null:return
	var stage:Resource=region.stages[selected_stage]
	var label_edit:=LineEdit.new()
	label_edit.text=stage.label
	label_edit.text_submitted.connect(func(value:String)->void:_commit_value("Aşama adı",stage,"label",stage.label,value))
	tools.add_child(label_edit)
	_spin(tools,"Hasar eşiği",stage.threshold,0,10000,1,func(value:float)->void:_commit_value("Aşama eşiği",stage,"threshold",stage.threshold,value))
	for pair in [["cut_strength","Alpha kesik"],["normal_strength","Normal detayı"],["wear_strength","Aşınma"],["burn_strength","Yanık"],["blood_strength","Kan"]]:
		_spin(tools,pair[1],stage.get(pair[0]),0,1,.05,func(value:float)->void:_commit_value("Materyal aşaması",stage,pair[0],stage.get(pair[0]),value))
	var broken:=LineEdit.new()
	broken.placeholder_text="Kopan bağlantılar: 0,1"
	broken.text=",".join(Array(stage.broken_connections).map(func(index:int)->String:return str(index)))
	broken.text_submitted.connect(func(value:String)->void:
		var ids:=PackedInt32Array()
		for part in value.split(",",false):
			if part.strip_edges().is_valid_int():ids.append(part.to_int())
		_commit_value("Kopma bağlantıları",stage,"broken_connections",stage.broken_connections,ids)
	)
	tools.add_child(broken)
	var release:=CheckButton.new()
	release.text="Bölge hareketini serbest bırak"
	release.button_pressed=stage.release_motion
	release.toggled.connect(func(value:bool)->void:_commit_value("Serbestleşme",stage,"release_motion",stage.release_motion,value))
	tools.add_child(release)
	_button(tools,"Hazırlanmış model varyantını seç",func()->void:_dialog("variant"))
	_text(tools,"Model / morph ve diğer kaynak alanları Inspector’da da düzenlenir. Varyantlar ilk hazırlamada bağlanır; darbe sırasında yüklenmez.")
	_button(tools,"Aşamayı Inspector’da aç",func()->void:
		if editor_plugin:editor_plugin.get_editor_interface().inspect_object(stage)
	)

func _layer_tools(item:Resource) -> void:
	var region:Resource=_region()
	if region:
		var effect:Dictionary=rig.controller.get_region_effects(selected_id,region.id)
		_text(tools,"Etkin hareket: %.2f · çizim: %s\nEtkileyenler: %s" % [effect.get("mobility",1),effect.get("visible",true),str(effect.get("sources",[]))])
		_spin(tools,"Temel serbestlik",region.base_mobility,0,1,.05,func(value:float)->void:_commit_value("Temel hareket",region,"base_mobility",region.base_mobility,value))
		for field in ["x","y","width","height"]:
			var rect:Rect2=region.uv_rect
			var value:float={"x":rect.position.x,"y":rect.position.y,"width":rect.size.x,"height":rect.size.y}[field]
			_spin(tools,"Bölge UV "+field,value,0,1,.05,func(new_value:float)->void:
				var next:Rect2=region.uv_rect
				match field:
					"x":next.position.x=new_value
					"y":next.position.y=new_value
					"width":next.size.x=new_value
					"height":next.size.y=new_value
				_commit_value("Bölge sınırı",region,"uv_rect",region.uv_rect,next)
			)
	for effect in item.effects:
		_label(tools,str(effect.id),12,TEAL)
		_text(tools,"%s/%s → %s/%s" % [effect.source_item,effect.source_region,effect.target_item,effect.target_region])
		var source_selector:=OptionButton.new()
		for i in range(item.regions.size()):
			source_selector.add_item(item.regions[i].label)
			if item.regions[i].id==effect.source_region:source_selector.select(i)
		source_selector.item_selected.connect(func(index:int)->void:_commit_value("Kaynak bölge",effect,"source_region",effect.source_region,item.regions[index].id))
		tools.add_child(source_selector)
		var target_selector:=OptionButton.new()
		var targets:Array=[]
		for candidate in outfit.items:
			if candidate.id==item.id:continue
			targets.append(candidate)
			target_selector.add_item(candidate.display_name)
			if candidate.id==effect.target_item:target_selector.select(targets.size()-1)
		target_selector.item_selected.connect(func(index:int)->void:
			var replacement:Resource=effect.duplicate(true)
			replacement.target_item=targets[index].id
			replacement.target_region=targets[index].regions[0].id
			var after:Array=item.effects.duplicate()
			after[item.effects.find(effect)]=replacement
			_commit_value("Hedef giysi",item,"effects",item.effects.duplicate(),after)
		)
		tools.add_child(target_selector)
		for target in targets:
			if target.id!=effect.target_item:continue
			var region_selector:=OptionButton.new()
			for i in range(target.regions.size()):
				region_selector.add_item(target.regions[i].label)
				if target.regions[i].id==effect.target_region:region_selector.select(i)
			region_selector.item_selected.connect(func(index:int)->void:_commit_value("Hedef bölge",effect,"target_region",effect.target_region,target.regions[index].id))
			tools.add_child(region_selector)
		_spin(tools,"Hareket sınırı",effect.mobility_cap,0,1,.05,func(value:float)->void:_commit_value("Üst katman etkisi",effect,"mobility_cap",effect.mobility_cap,value))
		_spin(tools,"Son etkin aşama",effect.active_until_stage,0,20,1,func(value:float)->void:_commit_value("Etki koşulu",effect,"active_until_stage",effect.active_until_stage,int(value)))
		var hides:=CheckButton.new()
		hides.text="Hedef bölgeyi örter"
		hides.button_pressed=effect.hides_region
		hides.toggled.connect(func(value:bool)->void:_commit_value("Örtme kuralı",effect,"hides_region",effect.hides_region,value))
		tools.add_child(hides)
		_button(tools,"Bu ilişkiyi kaldır",func()->void:
			var after:Array=item.effects.duplicate()
			after.erase(effect)
			_commit_value("Katman ilişkisi kaldır",item,"effects",item.effects.duplicate(),after)
		)
	_button(tools,"Yeni bölge ekle",_add_region)
	if region and item.proxy_mesh:
		_button(tools,"UV bölgesini proxy noktalarına eşle",func()->void:
			var arrays:Array=item.proxy_mesh.surface_get_arrays(0)
			var uv:PackedVector2Array=_proxy_uvs(item)
			var indices:=PackedInt32Array()
			for i in range(uv.size()):
				if region.uv_rect.grow(.00001).has_point(uv[i]):indices.append(i)
			_commit_value("Bölge proxy eşlemesi",region,"proxy_indices",region.proxy_indices,indices)
		)
	_button(tools,"Yeni üst → alt ilişki",_add_effect)
	_button(tools,"İlişkileri Inspector’da aç",func()->void:
		if editor_plugin:editor_plugin.get_editor_interface().inspect_object(item)
	)
	_text(tools,"Örtme ve hareket bağımsızdır. Aynı bölgeyi tutan ikinci giysi varsa ilk kopma tam serbestlik sağlamaz.")

func _test_tools(_item_value:Resource) -> void:
	paint_mode=false
	var attack:=OptionButton.new()
	var attack_types:Array[StringName]=[&"slash",&"blunt",&"pierce",&"burn",&"wear",&"blood"]
	for label_value in ["Kesici","Ezici","Delici","Yanık","Aşınma","Kan"]:attack.add_item(label_value)
	attack.select(attack_types.find(hit_type))
	attack.item_selected.connect(func(index:int)->void:hit_type=attack_types[index])
	tools.add_child(attack)
	_text(tools,"3D görünümde sol tık, gerçek darbe API’sini çağırır. Aşama seçimi yalnız hazırlama önizlemesidir.")
	_button(tools,"Seçili bölgeye darbe · 15",func()->void:hit_selected(15))
	_button(tools,"Güçlü darbe · 60",func()->void:hit_selected(60))
	_button(tools,"Eşya hasarını sıfırla",func()->void:rig.controller.reset_damage(selected_id);_refresh_detail())
	_button(tools,"Oyun hasarını kaydet",func()->void:_dialog("state_save"))
	_button(tools,"Oyun hasarını yükle",func()->void:_dialog("state_load"))
	_button(tools,"Seçili zaman olayı kaldır",_remove_event)
	var selected:PackedInt32Array=event_list.get_selected_items()
	if not selected.is_empty() and selected[0]<outfit.timeline.size():
		var index:int=selected[0]
		_spin(tools,"Olay zamanı / sn",outfit.timeline[index].get("time",0),0,30,.1,func(value:float)->void:_edit_event(index,"time",value))
		_spin(tools,"Olay hasarı",outfit.timeline[index].get("amount",15),0,10000,1,func(value:float)->void:_edit_event(index,"amount",value))
	_button(tools,"Eski demo JSON içe aktar",func()->void:_dialog("legacy"))
	_text(tools,"Oyun apply_hit ile konum/yön/tür/şiddet gönderir. stage_changed ve attachment_broken sinyalleri sonucu bildirir. Model değişimi ve bağlantı kopması aynı controller’dan yönetilir.")

func _collision_tools() -> void:
	_text(tools,"Kumaş proxy’si kemikleri izleyen ucuz beden küreleriyle temas eder. Bu, tam beden veya kumaş-kumaş çarpışması garantisi değildir.")
	var toggle:=CheckButton.new()
	toggle.text="Beden çarpışma temsillerini göster"
	toggle.button_pressed=show_collision
	toggle.toggled.connect(func(value:bool)->void:show_collision=value;_refresh_collision_debug())
	tools.add_child(toggle)
	var specs:Array=outfit.metadata.get("body_colliders",[])
	for index in range(specs.size()):
		var spec:Dictionary=specs[index]
		_label(tools,str(spec.get("bone",""))+" · "+str(index+1),12,TEAL)
		var raw:Variant=spec.get("center",Vector3.ZERO)
		var center:Vector3=raw if raw is Vector3 else Vector3(raw[0],raw[1],raw[2])
		for axis in range(3):
			_spin(tools,["X","Y","Z"][axis],center[axis],-5,5,.01,func(value:float)->void:
				var metadata:Dictionary=outfit.metadata.duplicate(true)
				var point:Vector3=center
				point[axis]=value
				metadata["body_colliders"][index]["center"]=point
				_commit_value("Beden çarpışma noktası",outfit,"metadata",outfit.metadata.duplicate(true),metadata)
			)
		_spin(tools,"Yarıçap",float(spec.get("radius",.1)),.005,1,.005,func(value:float)->void:
			var metadata:Dictionary=outfit.metadata.duplicate(true)
			metadata["body_colliders"][index]["radius"]=value
			_commit_value("Beden çarpışma yarıçapı",outfit,"metadata",outfit.metadata.duplicate(true),metadata)
		)
	_button(tools,"Varsayılan beden temsillerini kur",func()->void:
		var helper=load("res://addons/aero_cloth_3d/core/aero_body_collision.gd")
		var metadata:Dictionary=outfit.metadata.duplicate(true)
		metadata["body_colliders"]=helper.default_specs(rig.skeleton)
		_commit_value("Beden çarpışma hazırlığı",outfit,"metadata",outfit.metadata.duplicate(true),metadata)
	)

func _refresh_collision_debug() -> void:
	if is_instance_valid(collision_debug):collision_debug.queue_free();collision_debug=null
	if not show_collision or not outfit:return
	var helper=load("res://addons/aero_cloth_3d/core/aero_body_collision.gd")
	if helper==null:return
	collision_debug=Node3D.new()
	rig.get_parent().add_child(collision_debug)
	var specs:Array=outfit.metadata.get("body_colliders",[])
	var spheres:Array=helper.sample(specs,rig.skeleton,rig.global_transform)
	for sphere:Vector4 in spheres:
		var marker:=MeshInstance3D.new()
		var shape:=SphereMesh.new()
		shape.radius=sphere.w
		shape.height=sphere.w*2
		shape.radial_segments=12
		shape.rings=6
		marker.mesh=shape
		var mat:=StandardMaterial3D.new()
		mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color=Color(.2,.9,.8,.25)
		mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		marker.material_override=mat
		collision_debug.add_child(marker)
		marker.global_position=Vector3(sphere.x,sphere.y,sphere.z)

func _stroke_begin() -> void:
	if not _item():return
	painting=true
	paint_target=_map_target()
	paint_before=paint_target.damage_recipe.duplicate(true)
	paint_weights_before=_item().mobility.duplicate()
	if canvas==null:
		canvas=Canvas.new()
		canvas.initialize(_item().mask_resolution)
		if not paint_before.is_empty():canvas.import_recipe(paint_before);canvas.flush()

func _stroke_at(uv:Vector2) -> void:
	if not painting or canvas==null:return
	if mobility_paint and _item().proxy_mesh:
		var item:Resource=_item()
		var arrays:Array=item.proxy_mesh.surface_get_arrays(0)
		var uvs:PackedVector2Array=_proxy_uvs(item)
		var weights:PackedFloat32Array=item.mobility.duplicate()
		if weights.size()!=uvs.size():weights.resize(uvs.size());weights.fill(1)
		for i in range(uvs.size()):
			if uvs[i].distance_to(uv)<=radius:weights[i]=mobility_value
		item.mobility=weights
		if rig.slots[selected_id]["surface"]:rig.slots[selected_id]["surface"].base_mobility=weights.duplicate()
		rig._sync_state(selected_id)
		_refresh_map_preview()
		status.text="Temel hareket boyası %.1f; üst katman etkileri ayrıca hesaplanır." % mobility_value
		return
	if not canvas.stamp(uv,brush,radius,strength,angle,canvas.operations.size(),erase and brush not in Canvas.FILTER_BRUSHES):
		status.text="Fırça ayarları geçersiz veya tarif işlem sınırına ulaşıldı."
		return
	canvas.flush()
	paint_target.damage_recipe=canvas.export_recipe()
	rig._sync_state(selected_id)
	_refresh_map_preview()
	status.text="Harita taslağı boyanıyor · aşama %d ile görünüşü dene" % selected_stage

func _stroke_end() -> void:
	if not painting:return
	painting=false
	if mobility_paint:
		var weights:PackedFloat32Array=_item().mobility.duplicate()
		_item().mobility=paint_weights_before
		_commit_value("Temel hareket fırçası",_item(),"mobility",paint_weights_before,weights)
	else:
		var after:Dictionary=paint_target.damage_recipe.duplicate(true)
		paint_target.damage_recipe=paint_before
		_commit_value("Hasar haritası fırçası",paint_target,"damage_recipe",paint_before,after)

func _commit_value(title:String,target:Resource,property:String,before:Variant,after:Variant) -> void:
	if editor_plugin:
		var history:EditorUndoRedoManager=editor_plugin.get_undo_redo()
		history.create_action(title,UndoRedo.MERGE_DISABLE,outfit)
		history.add_do_method(self,"_apply_author_value",target,property,after)
		history.add_undo_method(self,"_apply_author_value",target,property,before)
		history.commit_action()
	else:
		local_history.create_action(title)
		local_history.add_do_method(_apply_author_value.bind(target,property,after))
		local_history.add_undo_method(_apply_author_value.bind(target,property,before))
		local_history.commit_action()

func _apply_author_value(target:Resource,property:String,value:Variant) -> void:
	if target.get(property) is Array and value is Array:
		target.get(property).assign(value)
	else:target.set(property,value)
	target.emit_changed()
	dirty=true
	if property=="damage_recipe":
		rig._sync_state(selected_id)
		if selected_tab==1:call_deferred("_build_tools")
	elif target==outfit and property=="timeline":_refresh_timeline()
	else:call_deferred("_reload_rig")

func _undo() -> void:
	if editor_plugin:
		var history:UndoRedo=editor_plugin.get_undo_redo().get_history_undo_redo(editor_plugin.get_undo_redo().get_object_history_id(outfit))
		if history and history.has_undo():history.undo()
	elif local_history.has_undo():local_history.undo()

func _redo() -> void:
	if editor_plugin:
		var history:UndoRedo=editor_plugin.get_undo_redo().get_history_undo_redo(editor_plugin.get_undo_redo().get_object_history_id(outfit))
		if history and history.has_redo():history.redo()
	elif local_history.has_redo():local_history.redo()

func _add_stage() -> void:
	var region:Resource=_region()
	if region==null:return
	var after:Array=region.stages.duplicate()
	var stage:Resource=region.stages[-1].duplicate(true)
	stage.id=StringName("stage_"+str(region.stages.size()))
	stage.label="Yeni aşama"
	stage.threshold+=25
	after.append(stage)
	_commit_value("Aşama ekle",region,"stages",region.stages.duplicate(),after)

func _remove_stage() -> void:
	var region:Resource=_region()
	if region==null or selected_stage==0:return
	var after:Array=region.stages.duplicate()
	after.remove_at(selected_stage)
	selected_stage=maxi(0,selected_stage-1)
	_commit_value("Aşama kaldır",region,"stages",region.stages.duplicate(),after)

func _add_region() -> void:
	var item:Resource=_item()
	if item.regions.size()>=4:
		status.text="Bu sürüm mesh başına 4 bölgenin bütün görünürlük durumlarını önceden hazırlar. Daha fazla bölgeyi ayrı hazırlama parçasına ayırın."
		return
	var next:Resource=item.regions[0].duplicate(true)
	next.id=StringName("region_"+str(item.regions.size()))
	next.label="Yeni bölge"
	next.proxy_indices=PackedInt32Array()
	var after:Array=item.regions.duplicate()
	after.append(next)
	_commit_value("Bölge ekle",item,"regions",item.regions.duplicate(),after)

func _add_effect() -> void:
	var item:Resource=_item()
	var Effect=load("res://addons/aero_cloth_3d/resources/aero_layer_effect.gd")
	var effect:Resource=Effect.new()
	effect.id=StringName("effect_"+str(item.effects.size()))
	effect.source_item=item.id
	effect.source_region=_region().id
	for candidate in outfit.items:
		if candidate.id!=item.id:
			effect.target_item=candidate.id
			effect.target_region=candidate.regions[0].id
			break
	effect.active_until_stage=2
	var after:Array=item.effects.duplicate()
	after.append(effect)
	_commit_value("Katman ilişkisi ekle",item,"effects",item.effects.duplicate(),after)

func hit_selected(amount:float) -> Dictionary:
	var region:Resource=_region()
	if not region:return {}
	var event:Dictionary={"hit_id":"editor_"+str(Time.get_ticks_usec()),"item_id":selected_id,"region_id":region.id,"uv":last_hit.get("uv",region.uv_rect.get_center()),"position":last_hit.get("position",Vector3.ZERO),"direction":last_hit.get("direction",Vector3.FORWARD),"type":hit_type,"amount":amount,"seed":tick}
	event["angle"]=last_hit.get("angle",angle)
	var result:Dictionary=rig.apply_hit(event)
	_refresh_detail()
	return result

func add_timeline_event() -> void:
	if not _region():return
	var after:Array=outfit.timeline.duplicate(true)
	var uv:Vector2=last_hit.get("uv",_region().uv_rect.get_center())
	after.append({"time":preview_time,"item_id":str(selected_id),"region_id":str(_region().id),"uv":[uv.x,uv.y],"amount":15.0,"type":str(hit_type),"angle":last_hit.get("angle",angle),"seed":after.size()})
	_commit_value("Zaman çizgisi darbesi",outfit,"timeline",outfit.timeline.duplicate(true),after)

func _remove_event() -> void:
	var selected:PackedInt32Array=event_list.get_selected_items()
	if selected.is_empty():return
	var after:Array=outfit.timeline.duplicate(true)
	after.remove_at(selected[0])
	_commit_value("Zaman olayı kaldır",outfit,"timeline",outfit.timeline.duplicate(true),after)

func _refresh_timeline() -> void:
	event_list.clear()
	if not outfit:return
	for event in outfit.timeline:event_list.add_item("%.2fs · %s/%s · %s %.0f" % [event.get("time",0),event.get("item_id",""),event.get("region_id",""),event.get("type","slash"),event.get("amount",0)])

func _edit_event(index:int,key:String,value:Variant) -> void:
	var after:Array=outfit.timeline.duplicate(true)
	after[index][key]=value
	_commit_value("Zaman olayı düzenle",outfit,"timeline",outfit.timeline.duplicate(true),after)

func _refresh_animations() -> void:
	for child in timeline_controls.get_children():
		if child is OptionButton:timeline_controls.remove_child(child);child.queue_free()
	if not rig.animation:return
	var selector:=OptionButton.new()
	var names:Array[String]=[]
	for name_value in rig.animation.get_animation_list():
		if name_value!="RESET":names.append(name_value);selector.add_item(name_value)
	selector.item_selected.connect(func(index:int)->void:rig.play_animation(names[index]);seek_time(0))
	timeline_controls.add_child(selector)

func seek_time(value:float) -> void:
	playing=false
	rig.reset_preview()
	tick=0
	preview_time=0
	event_cursor=0
	var target:int=mini(1800,maxi(0,int(round(value*60))))
	for i in range(target):_advance()
	_refresh_detail()

func _advance() -> void:
	tick+=1
	preview_time=float(tick)/60
	var events:Array=outfit.timeline.duplicate(true)
	events.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return float(a.get("time",0))<float(b.get("time",0)))
	while event_cursor<events.size() and float(events[event_cursor].get("time",0))<=preview_time+.00001:
		var hit:Dictionary=events[event_cursor].duplicate(true)
		hit["hit_id"]="timeline_"+str(event_cursor)
		rig.apply_hit(hit)
		event_cursor+=1
	rig.step(1.0/60)

func _refresh_detail() -> void:
	if not rig or not _region():return
	var state:Dictionary=rig.controller.get_item_state(selected_id)
	var region:Dictionary=state.get("regions",{}).get(_region().id,{})
	var effects:Dictionary=rig.controller.get_region_effects(selected_id,_region().id)
	detail.text="%.2fs · %s/%s · önizleme aşaması %s · hasar %.1f · hareket %.2f · %s" % [preview_time,selected_id,_region().id,region.get("stage",0),region.get("damage",0),effects.get("mobility",1),"görünür" if effects.get("visible",true) else "örtülü"]
	updating=true
	slider.value=preview_time
	updating=false
	_refresh_selection()

func _refresh_selection() -> void:
	if not rig.slots.has(selected_id):return
	var slot:Dictionary=rig.slots[selected_id]
	var visual:MeshInstance3D=slot["visual"]
	if selection_mesh!=visual or not is_instance_valid(selection_gizmo):
		if is_instance_valid(selection_gizmo):selection_gizmo.queue_free()
		selection_mesh=visual
		selection_gizmo=Node3D.new()
		visual.add_child(selection_gizmo)
		var lines:=ImmediateMesh.new()
		var mat:=StandardMaterial3D.new()
		mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color=TEAL
		var corners:Array[Vector3]=[Vector3(-.5,-.5,-.5),Vector3(.5,-.5,-.5),Vector3(.5,-.5,.5),Vector3(-.5,-.5,.5),Vector3(-.5,.5,-.5),Vector3(.5,.5,-.5),Vector3(.5,.5,.5),Vector3(-.5,.5,.5)]
		lines.surface_begin(Mesh.PRIMITIVE_LINES,mat)
		for pair in [Vector2i(0,1),Vector2i(1,2),Vector2i(2,3),Vector2i(3,0),Vector2i(4,5),Vector2i(5,6),Vector2i(6,7),Vector2i(7,4),Vector2i(0,4),Vector2i(1,5),Vector2i(2,6),Vector2i(3,7)]:
			lines.surface_add_vertex(corners[pair.x])
			lines.surface_add_vertex(corners[pair.y])
		lines.surface_end()
		selection_box=MeshInstance3D.new()
		selection_box.mesh=lines
		selection_gizmo.add_child(selection_box)
		if slot["piece"]:
			for point in slot["piece"].connection_points:
				var marker:=MeshInstance3D.new()
				var sphere:=SphereMesh.new()
				sphere.radius=.012
				sphere.height=.024
				sphere.radial_segments=8
				sphere.rings=4
				marker.mesh=sphere
				marker.material_override=mat.duplicate()
				marker.material_override.no_depth_test=true
				selection_gizmo.add_child(marker)
				marker.position=visual.to_local(slot["piece"].get_visual_root().global_transform*point)
	var box:AABB=visual.custom_aabb if slot["surface"] else visual.mesh.get_aabb()
	selection_box.position=box.get_center()
	selection_box.scale=box.size.max(Vector3(.005,.005,.005))*1.025
	if slot["piece"]:
		for i in range(1,selection_gizmo.get_child_count()):
			selection_gizmo.get_child(i).material_override.albedo_color=Color("ff6b70") if slot["piece"].broken_connections[i-1] else TEAL

func _process(delta:float) -> void:
	if playing and outfit:
		accumulator=minf(accumulator+delta,.15)
		while accumulator>=1.0/60:
			_advance()
			accumulator-=1.0/60
		if preview_time>=slider.max_value:playing=false
		_refresh_detail()
		if show_collision:_refresh_collision_debug()
	if _capture:
		_capture_frames-=1
		if _capture_frames==40:
			selected_id=&"jacket"
			select_item(selected_id)
			seek_time(3.25)
			selected_stage=3
			stage_map=true
			map_preview_kind=1
			_refresh_stage_list()
			_build_tools()
		if _capture_frames==0:call_deferred("_save_capture")

func _save_capture() -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/authoring-workspace.png")
	print("AUTHORING_CAPTURE_OK")
	get_tree().quit()

func _update_camera() -> void:
	if not camera:return
	camera.position=focus+Vector3(sin(orbit.x)*cos(orbit.y),sin(orbit.y),cos(orbit.x)*cos(orbit.y))*distance
	camera.look_at(focus)

func _preview_input(event:InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			distance=clampf(distance*(.9 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.1),.4,9)
			_update_camera()
		elif event.button_index==MOUSE_BUTTON_LEFT:
			if event.pressed:
				last_hit=rig.pick(camera,event.position,selected_id)
				if last_hit.is_empty():status.text="Seçili parçanın yüzeyine tıklayın.";return
				if paint_mode and selected_tab==1:_stroke_begin();_stroke_at(last_hit["uv"]);painting_3d=true
				else:hit_selected(15)
			elif painting_3d:_stroke_end();painting_3d=false
	elif event is InputEventMouseMotion:
		if event.button_mask&MOUSE_BUTTON_MASK_RIGHT:
			orbit+=Vector2(-event.relative.x,event.relative.y)*.006
			orbit.y=clampf(orbit.y,-.2,1.1)
			_update_camera()
		elif painting_3d:
			var hit:Dictionary=rig.pick(camera,event.position,selected_id)
			if not hit.is_empty():_stroke_at(hit["uv"])

func validate_recipe() -> PackedStringArray:
	var errors:PackedStringArray=outfit.validate()
	errors.append_array(rig.errors)
	status.text="Hazırlama doğrulaması başarılı." if errors.is_empty() else " · ".join(errors)
	return errors

func save_recipe() -> void:
	if outfit.resource_path.is_empty():_dialog("save");return
	_save_recipe_at(outfit.resource_path)

func _save_recipe_at(path:String) -> void:
	if not validate_recipe().is_empty():return
	var error:Error=ResourceSaver.save(outfit,path)
	if error==OK:outfit.take_over_path(path);dirty=false
	status.text="Kaydedildi: "+path if error==OK else "Kaydetme hatası: "+error_string(error)
	if editor_plugin:editor_plugin.get_editor_interface().get_resource_filesystem().scan()

func _dialog(kind:String) -> void:
	var dialog:=FileDialog.new()
	dialog.access=FileDialog.ACCESS_RESOURCES
	dialog.file_mode=FileDialog.FILE_MODE_OPEN_FILE
	dialog.filters=PackedStringArray(["*.tres,*.res ; Godot kaynakları"])
	match kind:
		"save":dialog.file_mode=FileDialog.FILE_MODE_SAVE_FILE;dialog.current_file="Outfit.tres"
		"item","character","variant":dialog.filters=PackedStringArray(["*.glb,*.gltf,*.tscn,*.scn ; 3D sahne"])
		"metadata","legacy","state_load":dialog.filters=PackedStringArray(["*.json ; JSON"])
		"state_save":dialog.file_mode=FileDialog.FILE_MODE_SAVE_FILE;dialog.filters=PackedStringArray(["*.json ; JSON"]);dialog.current_file="inventory-damage.json"
		"maps":dialog.file_mode=FileDialog.FILE_MODE_OPEN_DIR
		"game_scene":dialog.file_mode=FileDialog.FILE_MODE_SAVE_FILE;dialog.filters=PackedStringArray(["*.tscn ; Oyun sahnesi"]);dialog.current_file="WearableCharacter.tscn"
	dialog.file_selected.connect(_file_selected.bind(kind))
	dialog.dir_selected.connect(_file_selected.bind(kind))
	dialog.visibility_changed.connect(func()->void:
		if not dialog.visible:dialog.queue_free()
	)
	add_child(dialog)
	dialog.popup_centered(Vector2i(850,550))

func _file_selected(path:String,kind:String) -> void:
	match kind:
		"open":load_recipe(load(path))
		"save":_save_recipe_at(path)
		"character":_commit_value("Karakter sahnesi",outfit,"character_scene",outfit.character_scene,load(path))
		"item":
			var item:Resource=Definition.make_example(StringName("item_"+str(outfit.items.size())),&"skinned")
			item.source_scene=load(path)
			item.display_name=path.get_file().get_basename()
			var after:Array=outfit.items.duplicate()
			after.append(item)
			selected_id=item.id
			_commit_value("Giysi ekle",outfit,"items",outfit.items.duplicate(),after)
		"variant":
			var stage:Resource=_region().stages[selected_stage]
			_commit_value("Hazır model varyantı",stage,"mesh_variant",stage.mesh_variant,load(path))
		"maps":
			if canvas:status.text="Harita dışa aktarımı: "+error_string(canvas.save_maps(path))
		"state_save":
			var file:=FileAccess.open(path,FileAccess.WRITE)
			if file:file.store_string(JSON.stringify(rig.save_runtime_state(),"\t"));status.text="Eşya hasarı ve fizik durumu kaydedildi."
		"state_load":
			var data:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
			var accepted:bool=false
			if data is Dictionary:accepted=rig.load_runtime_state(data) if data.has("controller") else rig.controller.import_state(data)
			status.text="Hasar geri yüklendi." if accepted else "Hasar kaydı uyumsuz; durum değiştirilmedi."
		"game_scene":export_game_scene(path)
		"metadata":
			var importer=load("res://addons/aero_cloth_3d/core/aero_blender_import.gd")
			var result:Dictionary=importer.import_file(path)
			if result.get("outfit")!=null:
				if outfit and outfit.metadata.get("blender_metadata","")==path:
					var merged:Dictionary=importer.merge(outfit,result["outfit"])
					if merged.get("outfit")!=null and merged.get("errors",[]).is_empty():load_recipe(merged["outfit"])
					else:status.text="Yeniden import engellendi; eski hazırlık korundu: "+" · ".join(merged.get("errors",[]));return
				else:load_recipe(result["outfit"])
			status.text=" · ".join(result.get("errors",[]))+" · ".join(result.get("warnings",[]))
		"legacy":_import_legacy(path)

func _import_legacy(path:String) -> void:
	var data:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or data.get("format")!="AeroCloth3D.profile":status.text="Eski demo profili değil.";return
	var item:Resource=_item()
	if item==null:return
	if data.get("cloth_weights") is Array and item.proxy_mesh:
		var count:int=item.proxy_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
		if data["cloth_weights"].size()!=count:status.text="Eski boyama nokta sayısı proxy ile eşleşmiyor; uygulanmadı.";return
		for weight in data["cloth_weights"]:
			if not (weight is float or weight is int) or not is_finite(float(weight)) or weight<0 or weight>1:
				status.text="Eski boyamada geçersiz değer; hazırlama değiştirilmedi."
				return
		_commit_value("Eski temel boyama",item,"mobility",item.mobility,PackedFloat32Array(data["cloth_weights"]))
	status.text="Eski boyama aktarıldı. Demo omuz/çanta indeksleri genel varlığa otomatik eşlenmedi; bağlantıları kontrol edin."

func export_game_scene(path:String) -> Error:
	if not validate_recipe().is_empty():return ERR_INVALID_DATA
	var node:Node3D=Rig.new()
	node.name="WearableCharacter"
	node.outfit=outfit
	var packed:=PackedScene.new()
	var error:Error=packed.pack(node)
	if error==OK:error=ResourceSaver.save(packed,path)
	node.free()
	status.text="Oyun sahnesi oluşturuldu. WearableCharacter.controller.apply_hit(...) ile bağlayın: "+path if error==OK else error_string(error)
	return error

func _exit_tree() -> void:
	local_history.clear_history()
	local_history.free()
