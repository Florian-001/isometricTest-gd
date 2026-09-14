@tool
extends RefCounted

const Columns = preload("res://addons/unit_balance/columns.gd")
const TABLES := ["enemies", "items"]
const DEFAULT_GROUPS := ["Identity", "Results", "Item"]


static func definitions(table: String) -> Array:
	return Columns.enemies() if table == "enemies" else Columns.items()


static func defaults(table: String) -> Array:
	return definitions(table).filter(func(column): return column.group in DEFAULT_GROUPS).map(func(column): return column.key)


## Preserve authored order and the fixed name column, and discard obsolete keys.
static func normalize(table: String, keys: Array) -> Array:
	return definitions(table).filter(func(column): return column.key == "display_name" or column.key in keys).map(func(column): return column.key)


static func read_preferences(config: ConfigFile) -> Dictionary:
	var result := {}
	for table in TABLES:
		var keys: Variant = config.get_value("table", table + "_columns", false)
		if keys is Array:
			result[table] = normalize(table, keys)
		elif config.has_section_key("table", "groups"):
			var groups: Variant = config.get_value("table", "groups")
			if not groups is Array:
				groups = DEFAULT_GROUPS
			# Identity was always visible in the group-only editor, including CR.
			result[table] = definitions(table).filter(func(column): return column.group == "Identity" or column.group in groups).map(func(column): return column.key)
		else:
			result[table] = defaults(table)
	return result


static func write_preferences(config: ConfigFile, visibility: Dictionary) -> void:
	for table in TABLES:
		config.set_value("table", table + "_columns", normalize(table, visibility[table]))
