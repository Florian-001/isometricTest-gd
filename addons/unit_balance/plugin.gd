@tool
extends EditorPlugin

const BalancePanel = preload("res://addons/unit_balance/panel.gd")
var panel: Control


func _enter_tree() -> void:
	panel = BalancePanel.new()
	panel.name = "UnitBalance"
	EditorInterface.get_editor_main_screen().add_child(panel)
	panel.hide()
	EditorInterface.get_resource_filesystem().filesystem_changed.connect(_resources_changed)
	resource_saved.connect(_resource_saved)


func _exit_tree() -> void:
	if is_instance_valid(panel):
		panel.store.write_recovery()
		if not panel.store.dirty_paths().is_empty():
			if panel.store.recovery_error == OK:
				push_warning("Unit Balance has unsaved drafts. They were preserved in .godot/unit_balance/recovery.cfg and will be restored when the plugin is enabled.")
			else:
				push_error("Unit Balance has unsaved drafts and recovery could not be written. Save the resources before disabling the plugin.")
		panel.queue_free()


func _has_main_screen() -> bool:
	return true


func _get_plugin_name() -> String:
	return "Unit Balance"


func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon("GridContainer", "EditorIcons")


func _make_visible(visible: bool) -> void:
	if is_instance_valid(panel):
		panel.visible = visible
		if visible:
			panel.refresh_catalog()


func _get_unsaved_status(for_scene: String) -> String:
	if for_scene.is_empty() and is_instance_valid(panel) and not panel.store.dirty_paths().is_empty():
		return "Unit Balance: %d enemy/item resources have unsaved edits. Save before closing? Draft recovery is retained until saved or explicitly reverted." % panel.store.dirty_paths().size()
	return ""


func _save_external_data() -> void:
	if is_instance_valid(panel) and not panel.store.dirty_paths().is_empty():
		panel.save_changes()


func _resources_changed() -> void:
	if is_instance_valid(panel) and panel.is_visible_in_tree():
		panel.refresh_catalog.call_deferred()


func _resource_saved(_resource: Resource) -> void:
	_resources_changed()
