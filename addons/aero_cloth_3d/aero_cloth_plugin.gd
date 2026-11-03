@tool
extends EditorPlugin
const Workspace=preload("res://addons/aero_cloth_3d/editor/aero_authoring_workspace.gd")
var workspace:Control

func _enter_tree() -> void:
	add_tool_menu_item("AeroCloth3D · Open Authoring", _open_lab)
	workspace=Workspace.new()
	workspace.configure(self)
	get_editor_interface().get_editor_main_screen().add_child(workspace)
	workspace.hide()

func _exit_tree() -> void:
	remove_tool_menu_item("AeroCloth3D · Open Authoring")
	if is_instance_valid(workspace):workspace.queue_free()

func _has_main_screen() -> bool:return true
func _get_plugin_name() -> String:return "AeroCloth3D"
func _make_visible(value:bool) -> void:
	if is_instance_valid(workspace):workspace.visible=value
func _get_plugin_icon() -> Texture2D:return get_editor_interface().get_base_control().get_theme_icon("MeshInstance3D","EditorIcons")

func _open_lab() -> void:
	get_editor_interface().set_main_screen_editor("AeroCloth3D")
