extends Resource
## Authored tuning for a two-phase grove guardian.

@export var id: StringName = &"ancient_grove_beast"
@export var display_name := "Ancient Grove Beast"

@export_group("Movement and Health")
@export_range(1, 10000) var max_health := 550
@export_range(1.0, 300.0) var move_speed := 55.0
@export_range(0, 100) var contact_damage := 0
@export_range(0.1, 10.0) var contact_interval := 1.6

@export_group("Grove Stomp")
@export_range(1, 100) var stomp_damage := 18
@export_range(48.0, 200.0) var stomp_radius := 111.0
@export_range(0.2, 4.0) var stomp_windup := 0.8

@export_group("Forest Charge")
@export_range(1, 100) var charge_damage := 15
@export_range(0.2, 4.0) var charge_windup := 0.78
@export_range(40.0, 450.0) var charge_distance := 260.0
@export_range(80.0, 700.0) var charge_speed := 350.0

@export_group("Attack Cadence")
@export_range(0.1, 10.0) var first_attack_delay := 1.3
@export_range(0.1, 10.0) var attack_cooldown := 2.0
@export_range(0.1, 3.0) var recovery_duration := 0.52
@export_range(0.1, 0.9, 0.01) var phase_threshold := 0.5
@export_range(0.1, 3.0) var phase_transform_duration := 0.75
@export_range(1.0, 2.0, 0.01) var phase_two_speed_multiplier := 1.18
@export_range(0.25, 1.0, 0.01) var phase_two_cooldown_multiplier := 0.72
