extends Resource
## Authored movement, combat, and reward stats for an enemy.

@export var id: StringName
@export var display_name: String
@export_range(1.0, 1000.0, 1.0) var move_speed: float = 80.0
@export_range(1, 1000) var max_health: int = 30
@export_range(1, 1000) var contact_damage: int = 8
@export_range(0.05, 10.0, 0.05) var contact_interval: float = 1.0
@export_range(1.0, 1000.0, 1.0) var contact_range: float = 40.0
@export_range(0, 10000) var xp_reward: int = 0

@export_group("Special Attack")
@export_range(0.1, 10.0, 0.05) var attack_windup: float = 0.55
@export_range(0.05, 10.0, 0.05) var attack_recovery: float = 0.42
@export_range(1.0, 600.0, 1.0) var attack_trigger_range: float = 145.0
@export_range(1.0, 300.0, 1.0) var slam_radius: float = 87.0
@export_range(0.1, 20.0, 0.05) var lunge_interval: float = 3.5
@export_range(1.0, 1000.0, 1.0) var lunge_speed: float = 375.0
@export_range(0.05, 3.0, 0.01) var lunge_duration: float = 0.36
