extends Resource
## Content and timing for one survival level. Run state stays in the arena.

const WaveDefinition = preload("res://data/definitions/wave_definition.gd")

@export var id: StringName
@export var display_name: String
@export var environment_scene: PackedScene
@export var arena_bounds := Rect2(-205, -145, 410, 507)
@export var player_start := Vector2(0, 25)
@export_range(1.0, 900.0, 0.1) var survival_duration: float = 180.0
@export var waves: Array[WaveDefinition] = []
@export var boss_scene: PackedScene
@export_range(0.0, 10.0, 0.1) var boss_intro_duration: float = 2.4
@export_range(40.0, 400.0, 1.0) var minimum_spawn_distance: float = 135.0


func wave_index_at(elapsed: float) -> int:
	if elapsed < 0.0 or elapsed >= survival_duration:
		return -1
	for index in waves.size():
		var wave := waves[index]
		if wave != null and elapsed >= wave.start_time and elapsed < wave.end_time:
			return index
	return -1


func wave_at(elapsed: float) -> WaveDefinition:
	var index := wave_index_at(elapsed)
	return waves[index] if index >= 0 else null
