@tool
extends EditorPlugin

func _enable_plugin() -> void:
	add_autoload_singleton("SnapGd", "global/snap_gd.gd")

func _disable_plugin() -> void:
	remove_autoload_singleton("SnapGd")
