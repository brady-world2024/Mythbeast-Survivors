extends Resource
## One weighted enemy scene and its placement footprint.

@export var enemy_scene: PackedScene
@export_range(1, 1000) var weight: int = 1
@export_range(8.0, 100.0, 1.0) var clearance_radius: float = 24.0


func is_spawnable() -> bool:
	return enemy_scene != null and weight > 0
