extends Resource
## Authored identity, movement and presentation for a playable character.

@export var id: StringName
@export var visual_scene: PackedScene
@export_range(1.0, 1000.0, 1.0) var move_speed: float = 190.0
