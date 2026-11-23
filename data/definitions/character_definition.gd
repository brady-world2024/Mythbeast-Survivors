extends Resource
## Authored identity, movement, combat, and presentation for a playable character.

const WeaponDefinition = preload("res://data/definitions/weapon_definition.gd")

@export var id: StringName
@export var visual_scene: PackedScene
@export_range(1.0, 1000.0, 1.0) var move_speed: float = 190.0
@export_range(1, 1000) var max_health: int = 100
@export_range(0.0, 5.0, 0.05) var damage_invulnerability: float = 0.45
@export var starting_weapon: WeaponDefinition
