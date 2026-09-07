class_name RunEncounterDefinition
extends Resource

@export var display_name: String = "Encounter"
@export var battle_map: BattleMapDefinition
## Elite enemies scale these four attributes; movement and speed remain authored.
@export_range(1.0, 5.0, 0.1) var enemy_multiplier: float = 1.0
## When set, only this named enemy receives the multiplier.
@export var chief_node_name: String = ""
@export var chief_display_name: String = "Goblin Chief"
