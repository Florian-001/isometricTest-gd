class_name RunSaveStore
extends RefCounted

var path: String = "user://run/active.json"
var error_message: String = ""
var recovered_backup: bool = false

func exists() -> bool:
	return FileAccess.file_exists(path) or FileAccess.file_exists(path + ".bak")

func load_run() -> RunState:
	error_message = ""
	recovered_backup = false
	var state := _read(path)
	if state != null:
		return state
	state = _read(path + ".bak")
	if state != null:
		recovered_backup = true
		error_message = "The latest save was unreadable. Recovered the previous checkpoint."
	elif exists():
		error_message = "This run save could not be read. It has been kept; start a new run to replace it."
	return state

func save_run(state: RunState) -> bool:
	error_message = ""
	var absolute := ProjectSettings.globalize_path(path)
	if DirAccess.make_dir_recursive_absolute(absolute.get_base_dir()) != OK:
		return _fail("Could not create the run save folder.")
	var text := JSON.stringify(state.to_data())
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return _fail("Could not write the run checkpoint.")
	file.store_string(text)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK or _read(path + ".tmp") == null:
		return _fail("The run checkpoint could not be verified.")
	# Rotate only a readable checkpoint, preserving a good backup after recovery.
	if FileAccess.file_exists(path):
		if _read(path) != null:
			if DirAccess.copy_absolute(absolute, absolute + ".bak") != OK:
				return _fail("Could not retain the previous run checkpoint.")
	# Godot's rename replaces the destination on supported desktop platforms.
	if DirAccess.rename_absolute(absolute + ".tmp", absolute) != OK:
		return _fail("Could not replace the run checkpoint. Previous progress is intact.")
	return true

func _read(candidate: String) -> RunState:
	if not FileAccess.file_exists(candidate):
		return null
	var file := FileAccess.open(candidate, FileAccess.READ)
	if file == null or file.get_length() > 2000000:
		return null
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return null
	var parsed: Variant = parser.data
	if not parsed is Dictionary:
		return null
	return RunState.from_data(parsed)

func _fail(message: String) -> bool:
	error_message = message
	return false
