@tool
class_name EnemyAIProfile
extends Resource

@export_category("Identity")
@export var display_name: String = "General AI"

@export_category("Decision Making")
## How strongly the unit avoids forecast damage and hostile effects.
## 0 ignores danger, 1 is balanced, and 2 is cautious.
@export_range(0.0, 2.0, 0.05) var risk_aversion: float = 1.0
