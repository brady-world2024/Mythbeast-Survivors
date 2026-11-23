extends Resource
## Authored attributes for a projectile weapon.

@export var id: StringName
@export var projectile_scene: PackedScene
@export_range(1, 1000) var damage: int = 10
@export_range(0.05, 10.0, 0.05) var attack_interval: float = 0.75
@export_range(1.0, 1000.0, 1.0) var attack_range: float = 220.0
@export_range(1.0, 2000.0, 1.0) var projectile_speed: float = 450.0
@export_range(0.05, 5.0, 0.05) var projectile_lifetime: float = 1.5
