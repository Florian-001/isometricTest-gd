@tool
class_name EnemyDefinition
extends CharacterDefinition

@export_category("Enemy AI")
## Default AI used by every unit that references this enemy archetype.
@export var ai_profile: EnemyAIProfile


func _init() -> void:
	faction = Faction.ENEMY
