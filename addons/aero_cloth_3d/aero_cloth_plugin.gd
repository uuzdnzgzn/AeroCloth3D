@tool
extends EditorPlugin

func _enter_tree() -> void:
	add_tool_menu_item("AeroCloth3D · Open Character Lab", _open_lab)

func _exit_tree() -> void:
	remove_tool_menu_item("AeroCloth3D · Open Character Lab")

func _open_lab() -> void:
	get_editor_interface().open_scene_from_path("res://demo/CharacterWardrobe.tscn")
	get_editor_interface().play_custom_scene("res://demo/CharacterWardrobe.tscn")
