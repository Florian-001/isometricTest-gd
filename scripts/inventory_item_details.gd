class_name InventoryItemDetails
extends PanelContainer

@export_range(0, 40) var item_gap: int = 12
@export_range(0, 40) var viewport_margin: int = 12
@onready var title: Label = $Margin/Content/Title
@onready var category: Label = $Margin/Content/Category
@onready var body: Label = $Margin/Content/Body
@onready var hint: Label = $Margin/Content/Hint


func show_item(item: ItemDefinition, equipped: bool) -> void:
	title.text = item.display_name
	category.text = ItemDefinition.EquipmentSlot.keys()[item.slot].capitalize()
	var lines: Array[String] = []
	if item.slot == ItemDefinition.EquipmentSlot.WEAPON:
		category.text += " · " + ItemDefinition.WeaponType.keys()[item.weapon_type].capitalize()
		category.text += " · " + ("Two-handed" if item.is_two_handed() else "One-handed")
		lines.append("%d weapon damage" % item.weapon_damage)
		if item.weapon_range_bonus > 0.0:
			lines.append("%s Strike range (normal attacks only)" % _signed_amount(item.weapon_range_bonus))
		var granted_names: Array[String] = []
		for ability in item.get_granted_abilities():
			granted_names.append(ability.display_name)
		lines.append("Grants while equipped: %s" % ", ".join(granted_names))
		if item.status_effect != null:
			lines.append("Applies %s\n%s" % [item.status_effect.display_name, item.status_effect.get_description()])
	if item.armor > 0:
		lines.append("+%d Armor" % item.armor)
	for modifier in item.modifiers:
		if modifier == null:
			continue
		var amount := _signed_amount(modifier.value)
		if modifier.operation != StatModifierDefinition.Operation.FLAT:
			amount = _signed_amount(modifier.value * 100.0) + "%"
		if modifier.operation == StatModifierDefinition.Operation.PERCENT_MULTIPLY:
			amount += " (multiplicative)"
		lines.append("%s %s" % [amount, UnitStat.get_display_name(modifier.stat)])
	body.text = "\n\n".join(lines) if not lines.is_empty() else "No stat modifiers"
	hint.text = "Double-click or Enter to %s\nDrag to move or swap" % ("unequip" if equipped else "equip")
	reset_size()
	show()


func place_next_to(cell: Control) -> void:
	# Wrapped labels recompute their minimum height after container layout.
	reset_size()
	var rect := cell.get_global_rect()
	var bounds := get_viewport_rect().grow(-viewport_margin)
	var target := Vector2(rect.end.x + item_gap, rect.position.y)
	if target.x + size.x > bounds.end.x:
		target.x = rect.position.x - item_gap - size.x
	target.x = clampf(target.x, bounds.position.x, maxf(bounds.position.x, bounds.end.x - size.x))
	target.y = clampf(target.y, bounds.position.y, maxf(bounds.position.y, bounds.end.y - size.y))
	global_position = target


func _signed_amount(value: float) -> String:
	var number := str(roundi(value)) if is_equal_approx(value, roundf(value)) else String.num(value, 2)
	return ("+" if value >= 0.0 else "") + number
