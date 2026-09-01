class_name DevContentCatalog
extends RefCounted

const UNIT_ROOTS := ["res://scenes/friendlies", "res://scenes/enemies"]
const ITEM_ROOT := "res://resources/items"
const ABILITY_ROOT := "res://resources/abilities"

static var _unit_entries: Array[Dictionary] = []
static var _items: Array[ItemDefinition] = []
static var _abilities: Array[AbilityDefinition] = []


static func get_unit_entries() -> Array[Dictionary]:
	if _unit_entries.is_empty():
		for root in UNIT_ROOTS:
			for file_name in DirAccess.get_files_at(root):
				if not file_name.ends_with(".tscn"):
					continue
				var path := "%s/%s" % [root, file_name]
				var scene := load(path) as PackedScene
				if scene == null:
					continue
				var instance := scene.instantiate()
				if instance is TacticalCharacter:
					var unit := instance as TacticalCharacter
					_unit_entries.append({
						"path": path,
						"name": unit.definition.display_name if unit.definition != null else unit.name,
						"friendly": unit.is_friendly(),
						"texture": unit.facing_right_texture,
					})
				instance.free()
		_unit_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return str(a.name).naturalnocasecmp_to(str(b.name)) < 0
		)
	return _unit_entries.duplicate(true)


static func get_items() -> Array[ItemDefinition]:
	if _items.is_empty():
		for file_name in DirAccess.get_files_at(ITEM_ROOT):
			if file_name.ends_with(".tres"):
				var item := load("%s/%s" % [ITEM_ROOT, file_name]) as ItemDefinition
				if item != null:
					_items.append(item)
		_items.sort_custom(func(a: ItemDefinition, b: ItemDefinition) -> bool:
			return a.display_name.naturalnocasecmp_to(b.display_name) < 0
		)
	var result: Array[ItemDefinition] = []
	result.assign(_items)
	return result


static func get_abilities() -> Array[AbilityDefinition]:
	if _abilities.is_empty():
		for file_name in DirAccess.get_files_at(ABILITY_ROOT):
			if file_name.ends_with(".tres"):
				var ability := load("%s/%s" % [ABILITY_ROOT, file_name]) as AbilityDefinition
				if ability != null:
					_abilities.append(ability)
		_abilities.sort_custom(func(a: AbilityDefinition, b: AbilityDefinition) -> bool:
			return a.display_name.naturalnocasecmp_to(b.display_name) < 0
		)
	var result: Array[AbilityDefinition] = []
	result.assign(_abilities)
	return result
