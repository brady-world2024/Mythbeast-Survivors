extends Resource
## Authored run modifiers and a clear prerequisite.

@export var id: StringName
@export var display_name: String
@export var requires_stage: StringName
@export var requires_difficulty: StringName
@export var lock_reason: String

@export_range(0.1, 10.0, 0.01) var enemy_hp_multiplier := 1.0
@export_range(0.1, 10.0, 0.01) var enemy_damage_multiplier := 1.0
@export_range(0.1, 10.0, 0.01) var enemy_speed_multiplier := 1.0
@export_range(0.1, 10.0, 0.01) var spawn_interval_multiplier := 1.0
@export_range(0.1, 10.0, 0.01) var boss_hp_multiplier := 1.0
@export_range(0.1, 10.0, 0.01) var boss_damage_multiplier := 1.0
@export_range(0.1, 10.0, 0.01) var reward_multiplier := 1.0
