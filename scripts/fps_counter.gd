extends Label

const UPDATE_INTERVAL := 0.5

var _elapsed := 0.0


func _ready() -> void:
	_update_counter()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < UPDATE_INTERVAL:
		return
	_elapsed = 0.0
	_update_counter()


func _update_counter() -> void:
	text = "FPS: %d" % Engine.get_frames_per_second()
