extends Resource
## Authored identity, movement, combat, and presentation for a playable character.

@export var id: StringName
@export var visual_scene: PackedScene
@export_range(1.0, 1000.0, 1.0) var move_speed: float = 190.0
@export_range(1, 1000) var max_health: int = 100
@export_range(1, 1000) var basic_attack_damage: int = 14
@export_range(1.0, 1000.0, 1.0) var basic_attack_range: float = 160.0
@export_range(0.05, 10.0, 0.05) var basic_attack_interval: float = 0.65
