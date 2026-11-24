extends Resource
## Enemy pressure and composition for a half-open interval of active play.

const SpawnEntry = preload("res://data/definitions/enemy_spawn_entry.gd")

@export var id: StringName
@export var display_name: String
@export_range(0.0, 900.0, 0.1) var start_time: float = 0.0
@export_range(1.0, 900.0, 0.1) var end_time: float = 60.0
@export_range(0.1, 30.0, 0.1) var spawn_interval: float = 1.8
@export_range(1, 48) var max_active: int = 12
@export var entries: Array[SpawnEntry] = []
@export_range(0.25, 3.0, 0.01) var health_multiplier: float = 1.0
@export_range(0.25, 2.0, 0.01) var speed_multiplier: float = 1.0
@export_range(0.25, 3.0, 0.01) var damage_multiplier: float = 1.0


func pick_entry(random: RandomNumberGenerator) -> SpawnEntry:
	var total_weight := 0
	for entry in entries:
		if entry != null and entry.is_spawnable():
			total_weight += entry.weight
	if total_weight <= 0:
		return null
	var roll := random.randi_range(1, total_weight)
	for entry in entries:
		if entry != null and entry.is_spawnable():
			roll -= entry.weight
			if roll <= 0:
				return entry
	return null
