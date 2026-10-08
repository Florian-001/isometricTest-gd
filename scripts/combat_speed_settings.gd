extends Node

signal speed_changed(speed: int)

const SPEEDS := [1, 2, 3]

## Override before entering the tree to isolate settings in tests.
var settings_path := "user://settings.cfg"
var speed: int:
	get:
		return _speed

var _speed := 1
var _config := ConfigFile.new()
var _active_battle: WeakRef


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	_config = ConfigFile.new()
	var error := _config.load(settings_path)
	var saved: Variant = _config.get_value("combat", "speed", 1) if error == OK else 1
	_speed = saved if saved is int and saved in SPEEDS else 1
	_apply_speed()
	speed_changed.emit(_speed)


func set_speed(value: int) -> void:
	if value not in SPEEDS or value == _speed:
		return
	_speed = value
	_apply_speed()
	speed_changed.emit(_speed)
	_config.set_value("combat", "speed", _speed)
	var error := _config.save(settings_path)
	if error != OK:
		push_warning("Could not save combat speed (%s). The selection still applies this session." % error_string(error))


func activate_battle(battle: Node) -> void:
	_active_battle = weakref(battle)
	_apply_speed()


func deactivate_battle(battle: Node) -> void:
	if _active_battle != null and _active_battle.get_ref() == battle:
		_active_battle = null
		_apply_speed()


func _apply_speed() -> void:
	Engine.time_scale = float(_speed) if _active_battle != null and _active_battle.get_ref() != null else 1.0


func _exit_tree() -> void:
	Engine.time_scale = 1.0
