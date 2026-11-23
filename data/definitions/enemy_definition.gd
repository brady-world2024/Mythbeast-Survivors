extends Resource
## Authored movement and combat stats for an enemy.

@export_range(1.0, 1000.0, 1.0) var move_speed: float = 80.0
@export_range(1, 1000) var max_health: int = 60
@export_range(1, 1000) var contact_damage: int = 8
@export_range(0.05, 10.0, 0.05) var contact_interval: float = 0.8
@export_range(1.0, 1000.0, 1.0) var contact_range: float = 40.0
