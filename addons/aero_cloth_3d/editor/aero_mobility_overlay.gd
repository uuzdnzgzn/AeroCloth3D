@tool
extends Control
var points:=PackedVector3Array()
func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
func _draw() -> void:
	for point in points:
		var color:Color=Color("ffbd69") if point.z<.01 else (Color("48dfca") if point.z<.99 else Color("7388d4"))
		draw_circle(Vector2(point.x,point.y)*size,4,color)
