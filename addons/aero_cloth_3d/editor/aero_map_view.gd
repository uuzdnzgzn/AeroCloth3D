@tool
extends Control
signal stroke_started
signal stroke_point(uv:Vector2)
signal stroke_finished
var texture:Texture2D
var drawing:=false
var view_kind:=0
var mobility_overlay:Control
func _ready() -> void:
	custom_minimum_size=Vector2(230,230)
	mouse_filter=Control.MOUSE_FILTER_STOP
	var shader:=Shader.new()
	shader.code="shader_type canvas_item; uniform int view_kind=0; void fragment(){vec4 c=texture(TEXTURE,UV);vec3 out_color=c.rgb;if(view_kind==1){out_color=vec3(1.0-c.r);}if(view_kind==3){out_color=vec3(clamp(.85+c.g*.15+c.b*.1-c.a*.32,0.0,1.0));}if(view_kind==4){out_color=mix(vec3(.5),vec3(.65,.64,.6),c.g);out_color=mix(out_color,vec3(.035,.022,.014),c.b);out_color=mix(out_color,vec3(.19,.008,.012),c.a);}if(view_kind==5){out_color=vec3(clamp(.5+c.r*10.0,0.0,1.0));}COLOR=vec4(out_color,1.0);}"
	var mat:=ShaderMaterial.new()
	mat.shader=shader
	material=mat
	mobility_overlay=preload("res://addons/aero_cloth_3d/editor/aero_mobility_overlay.gd").new()
	add_child(mobility_overlay)
func set_view_kind(value:int) -> void:
	view_kind=value
	if material:material.set_shader_parameter("view_kind",value)
	queue_redraw()
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("101928"))
	if texture: draw_texture_rect(texture,Rect2(Vector2.ZERO,size),false)
	draw_rect(Rect2(Vector2.ZERO,size),Color("4cdbc5"),false,1)
func _gui_input(event:InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		drawing=event.pressed
		if drawing:
			stroke_started.emit()
			stroke_point.emit((event.position/size).clamp(Vector2.ZERO,Vector2.ONE))
		else: stroke_finished.emit()
	elif event is InputEventMouseMotion and drawing: stroke_point.emit((event.position/size).clamp(Vector2.ZERO,Vector2.ONE))
