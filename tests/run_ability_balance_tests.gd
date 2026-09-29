extends SceneTree

const Store = preload("res://addons/ability_balance/draft_store.gd")
const Columns = preload("res://addons/ability_balance/columns.gd")
const Catalog = preload("res://addons/ability_balance/catalog.gd")
const AbilityPanel = preload("res://addons/ability_balance/panel.gd")
const ROOT := "res://.godot/ability_balance_tests"
var failures: Array[String] = []
var checks := 0


func _init() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT)
	var catalog := Catalog.new()
	catalog.scan()
	check(catalog.active.size() >= 24 and catalog.passives.size() >= 4, "Discovers active and passive definitions")
	check(not catalog.references.get("res://abilities/nonexistent.tres", []).size(), "Missing reference is empty")
	check(not catalog.references.get("res://resources/abilities/strike.tres", []).is_empty(), "Finds class or unit ability references")
	var ability := AbilityDefinition.new()
	ability.display_name = "Fixture"
	ability.effect = AbilityDefinition.PrimaryEffect.DAMAGE
	ability.ability_type = AbilityDefinition.AbilityType.MELEE
	ability.image = load("res://assets/passive_icons/flight.svg")
	ability.status_effect = load("res://resources/statuses/burning.tres")
	var knockback := KnockbackEffectDefinition.new()
	ability.effects.append(knockback)
	var path := ROOT + "/active.tres"
	ResourceSaver.save(ability, path)
	var uid := ResourceLoader.get_resource_uid(path)
	var passive := PassiveAbilityDefinition.new()
	passive.passive_id = &"fixture"
	passive.display_name = "Fixture passive"
	passive.effects.append(NearbyAlliesWeaponDamagePassiveEffect.new())
	var passive_path := ROOT + "/passive.tres"
	ResourceSaver.save(passive, passive_path)
	var shared_path := ROOT + "/shared.tres"
	ResourceSaver.save(HealEffectDefinition.new(), shared_path)
	var shared_owner := AbilityDefinition.new()
	shared_owner.display_name = "Shared owner"
	shared_owner.effects.append(load(shared_path))
	var owner_path := ROOT + "/owner.tres"
	ResourceSaver.save(shared_owner, owner_path)
	var store := Store.new()
	store.recovery_path = ROOT + "/recovery.cfg"
	for fixture in [path, passive_path, owner_path]:
		store.add_resource(fixture)
	check(store.states.has(shared_path), "External effects are separate drafts")
	store.set_effect_field(path, 0, "distance", 7)
	check(load(path).effects[0].distance == 2, "Embedded draft does not mutate cached effect")
	check(store.draft(path).effects[0].distance == 7, "Embedded draft applies changes")
	store.history.undo()
	check(not store.is_dirty(path), "Undo restores nested baseline")
	store.history.redo()
	store.set_effect_field(owner_path, 0, "amount", 42)
	check(store.is_dirty(shared_path) and not store.is_dirty(owner_path), "Shared edit belongs to external resource")
	check(store.draft(owner_path).effects[0].amount == 42 and load(shared_path).amount == 10, "Owner previews shared draft without mutating original")
	store.set_field(path, "area_of_effect", 4)
	check(store.states[path].area_of_effect == 5, "Area setter normalizes even spans")
	store.set_field(path, "scaling_stat", DamageCalculator.ScalingSource.WEAPON)
	check(store.states[path].scaling_stat == DamageCalculator.ScalingSource.WEAPON, "Melee damage supports Weapon scaling")
	store.set_field(path, "ability_type", AbilityDefinition.AbilityType.MAGIC)
	check(store.states[path].scaling_stat == DamageCalculator.ScalingSource.NONE, "Magic normalizes incompatible Weapon scaling")
	var restored := Store.new()
	restored.recovery_path = store.recovery_path
	check(restored.restore_recovery() == 2, "Recovery restores both owner and shared effect drafts")
	check(restored.draft(path).effects[0].distance == 7 and restored.draft(shared_path).amount == 42, "Recovery preserves nested values")
	var result := store.save_all()
	check(result.failed.is_empty() and result.conflicts.is_empty() and result.saved.size() == 2, "Saves valid dirty resources")
	check(ResourceLoader.get_resource_uid(path) == uid, "Save preserves resource identity (editor suite checks authored UIDs)")
	check(load(path).effects[0].distance == 7 and load(shared_path).amount == 42, "Save refreshes cached resources")
	check(load(owner_path).effects[0] == load(shared_path), "External reference identity survives save")
	check(load(path).status_effect.resource_path == "res://resources/statuses/burning.tres" and load(path).image != null, "Status and texture references survive")
	store.history.undo()
	check(store.is_dirty(path), "Undo after save becomes dirty")
	store.reload_paths([path])
	store.set_field(path, "innate_damage", 25)
	var external: AbilityDefinition = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	external.projectile_speed = 777
	ResourceSaver.save(external, path)
	result = store.save_all()
	check(path in result.conflicts and store.is_dirty(path), "Disk conflicts preserve draft")
	result = store.save_all([path])
	check(path in result.saved and load(path).projectile_speed == 777 and load(path).innate_damage == 25, "Overwrite preserves fields not edited by this draft")
	store.set_effect_field(passive_path, 0, "damage_per_ally", 0)
	result = store.save_all()
	check(not result.failed.is_empty() and store.is_dirty(passive_path), "Invalid passive effect blocks saving")
	store.reload_paths([passive_path])
	store.set_field(path, "hit_targeting", AbilityDefinition.HitTargeting.SELECT_PER_HIT)
	store.set_field(path, "caster_centered", true)
	check(not store.validation(path).is_empty(), "Targeting validation uses runtime rules")
	check(not store.save_all().failed.is_empty(), "Invalid targeting blocks saving")
	store.reload_paths([path])
	var panel := AbilityPanel.new()
	panel.catalog_root = ROOT
	panel.persist_preferences = false
	panel.store.recovery_path = ""
	root.add_child(panel)
	await process_frame
	check(panel.grid.rows.size() >= 2, "Active table contains only ability definitions")
	check(panel.store.dirty_paths().is_empty(), "Opening panel leaves all resources clean")
	panel.set_visible_columns("active", ["display_name", "on_kill_status"])
	panel.grid.select_cell(panel.grid.row_index_for(path), 1)
	check(panel.grid.copy_text() == "", "Empty resource references copy as empty paths")
	check(panel.paste_text(panel.grid.copy_text()), "Empty resource copy/paste round-trips")
	panel.set_visible_columns("active", ["display_name", "innate_damage", "hit_count"])
	panel.grid.select_cell(panel.grid.row_index_for(path), 1)
	check(not panel.paste_text("12\tbad"), "Invalid rectangle is rejected")
	check(panel.store.dirty_paths().is_empty(), "Invalid paste is atomic")
	check(panel.paste_text("12\t3"), "Valid rectangle is accepted")
	check(panel.store.states[path].innate_damage == 12 and panel.store.states[path].hit_count == 3, "Paste updates selected fields")
	panel.store.history.undo()
	check(panel.store.dirty_paths().is_empty(), "Entire paste is a single undo action")
	panel.search.text = "no matching ability"
	panel._refresh()
	check(not panel.paste_text("55"), "Filtered-out active row cannot redirect paste to another resource")
	panel.search.text = ""
	panel._refresh()
	panel._show_column_picker()
	await process_frame
	var picker = panel.get_children().filter(func(child): return child is AcceptDialog)[0]
	check(picker.checkboxes.has("hit_count") and not picker.checkboxes.has("combat_rating"), "Shared picker uses supplied ability columns")
	picker.toggle_column("hit_count", false)
	check(not panel.grid.columns.any(func(column): return column.key == "hit_count"), "Column toggle updates grid")
	picker.hide()
	panel.tabs.current_tab = 1
	panel.grid.select_cell(0, 0)
	await process_frame
	check(panel.grid.rows.size() == 1 and panel.details.get_child_count() > 5, "Passive tab shows effects and details")
	check(panel.column_visibility.passives == Columns.PASSIVE_DEFAULTS, "Tab columns are independent")
	var target_column := Columns.property_column(AbilityDefinition.new(), "target_flags")
	check(Columns.parse(target_column, "Friend | Enemy").value == 3, "Target masks parse labels")
	check(Columns.parse(target_column, "32").has("error"), "Target masks reject unknown bits")
	var range_column := Columns.property_column(AbilityDefinition.new(), "range")
	check(Columns.parse(range_column, "NaN").has("error") and Columns.parse(range_column, "-1").has("error"), "Rejects nonfinite and negative ranges")
	panel.free()
	await process_frame
	await _extended_checks(store, path, passive_path, owner_path, shared_path)
	store.history.clear_history()
	restored.history.clear_history()
	print("ABILITY_BALANCE_TESTS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _extended_checks(store, path: String, passive_path: String, owner_path: String, shared_path: String) -> void:
	# Every currently supported nested type round-trips without touching originals.
	for script_path in Columns.ACTIVE_EFFECTS + Columns.PASSIVE_EFFECTS:
		var effect: Resource = load(script_path).new()
		var snapshot: Dictionary = Store.encode(effect)
		var copy: Resource = store.decode(snapshot)
		check(copy != effect and Store.capture(copy) == Store.capture(effect), "Effect snapshot round-trip " + script_path.get_file())
	var settings := Columns.property_column(AbilityDefinition.new(), "status_effect")
	check(Columns.parse(settings, "res://resources/abilities/strike.tres").has("error"), "Status picker rejects wrong resource type")
	check(Columns.parse(settings, "").value == null, "Status picker supports None")
	var healing := AbilityDefinition.new()
	healing.effect = AbilityDefinition.PrimaryEffect.HEAL
	check(Columns.parse(Columns.property_column(healing, "scaling_stat"), "Weapon").has("error"), "Heal cannot choose Weapon scaling")
	store.set_field(owner_path, "display_name", "Unsaved owner")
	store.set_effect_field(owner_path, 0, "amount", 53)
	var external: Resource = ResourceLoader.load(shared_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	external.amount = 99
	ResourceSaver.save(external, shared_path)
	var result: Dictionary = store.save_all()
	check(shared_path in result.conflicts and owner_path not in result.saved, "Shared effect conflict blocks dependent owner save")
	check(store.is_dirty(owner_path) and store.is_dirty(shared_path), "Blocked owner and effect remain dirty")
	store.reload_paths([owner_path, shared_path])
	store.set_field(path, "innate_damage", 73)
	var cached: Resource = load(path)
	cached.innate_damage = 81
	check(path in store.conflicts(), "Unsaved Inspector changes trigger conflicts")
	store.reload_paths([path])
	# Preserve custom types and native resources embedded in their unknown fields.
	var script_file := ROOT + "/custom_effect.gd"
	var file := FileAccess.open(script_file, FileAccess.WRITE)
	file.store_string("@tool\nextends AbilityEffectDefinition\n@export var custom_weight := 19\n@export var curve: Curve\n@export var custom_data := {}\n")
	file.close()
	var custom: Resource = load(script_file).new()
	custom.custom_data = {"$ref": "literal custom data", "array": [1, 2, 3]}
	custom.curve = Curve.new()
	custom.curve.add_point(Vector2(0.0, 0.2))
	custom.curve.add_point(Vector2(1.0, 0.8))
	var effects: Array = store.states[path].effects.duplicate(true)
	effects.append(Store.encode(custom))
	store.set_field(path, "effects", effects)
	result = store.save_all()
	check(path in result.saved, "Saves unknown custom effect without discarding it")
	var reloaded: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	check(reloaded.effects[1].custom_weight == 19 and reloaded.effects[1].curve.point_count == 2, "Custom properties and embedded native resource survive save")
	check(is_equal_approx(reloaded.effects[1].curve.get_point_position(1).y, 0.8), "Native curve contents survive snapshot")
	check(reloaded.effects[1].custom_data == custom.custom_data, "Custom dictionary keys cannot collide with resource snapshot tags")
	var panel := AbilityPanel.new()
	panel.catalog_root = ROOT
	panel.persist_preferences = true
	panel.preferences_path = ROOT + "/preferences.cfg"
	panel.store.recovery_path = ""
	root.add_child(panel)
	await process_frame
	panel._move_effect(path, 1, -1)
	check(panel.store.draft(path).effects[0].get_script().resource_path == script_file, "Effect reordering preserves custom type")
	panel.store.history.undo()
	check(not panel.store.is_dirty(path), "Effect reorder is undoable")
	panel.set_visible_columns("active", ["display_name", "range"])
	panel.set_visible_columns("passives", ["display_name", "passive_id"])
	panel.tabs.current_tab = 0
	panel.grid.select_cell(panel.grid.row_index_for(path), 1)
	panel.set_visible_columns("active", ["display_name"])
	check(panel.grid.active_key == "display_name" and path in panel.grid.selected, "Hiding active column keeps row selection")
	panel.free()
	await process_frame
	var reopened := AbilityPanel.new()
	reopened.catalog_root = ROOT
	reopened.preferences_path = ROOT + "/preferences.cfg"
	reopened.store.recovery_path = ""
	root.add_child(reopened)
	await process_frame
	check(reopened.column_visibility.active == ["display_name"] and reopened.column_visibility.passives == ["display_name", "passive_id"], "Independent tab columns persist across reopening")
	reopened.free()
	await process_frame
	var missing_path := ROOT + "/removed.tres"
	ResourceSaver.save(AbilityDefinition.new(), missing_path)
	store.add_resource(missing_path)
	store.set_field(missing_path, "display_name", "Removed")
	DirAccess.remove_absolute(missing_path)
	var overwrite_missing: Array[String] = [missing_path]
	result = store.save_all(overwrite_missing)
	check(not result.failed.is_empty() and store.is_dirty(missing_path), "Missing file save failure retains draft")
	var missing_recovery = Store.new()
	missing_recovery.recovery_path = store.recovery_path
	missing_recovery.restore_recovery()
	check(missing_recovery.is_dirty(missing_path), "Recovery retains drafts whose source file was removed")
	store.reload_paths([missing_path])
	store.set_field(passive_path, "description", "First line\nSecond line")
	store.write_recovery()
	var recovery = Store.new()
	recovery.recovery_path = store.recovery_path
	recovery.restore_recovery()
	check(recovery.states[passive_path].description == "First line\nSecond line", "Recovery preserves multiline text")
	store.reload_paths([passive_path])
	check(store.dirty_paths().is_empty(), "Revert clears remaining drafts")
