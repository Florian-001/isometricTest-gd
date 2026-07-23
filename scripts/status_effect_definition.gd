@tool
class_name StatusEffectDefinition
extends Resource

@export_category("Status")
## Stable identifier used to refresh an existing status instead of stacking another copy.
@export var status_id: StringName = &"new_status"
@export var display_name: String = "New Status"
@export_range(1, 99, 1, "or_greater") var duration_turns: int = 1

@export_category("Presentation")
@export var icon: Texture2D
@export var color: Color = Color.WHITE

@export_category("Stat Modifiers")
@export var modifiers: Array[StatModifierDefinition] = []
