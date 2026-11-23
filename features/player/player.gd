extends CharacterBody2D

const CharacterDefinition = preload("res://data/definitions/character_definition.gd")

@export var definition: CharacterDefinition

var move_direction := Vector2.ZERO

var _visual: Node


func _ready() -> void:
	if definition == null or definition.visual_scene == null:
		push_error("Player requires a character definition with a visual scene.")
		set_physics_process(false)
		return
	_visual = definition.visual_scene.instantiate()
	$VisualAnchor.add_child(_visual)


func _physics_process(_delta: float) -> void:
	var direction := move_direction.limit_length()
	velocity = direction * definition.move_speed
	move_and_slide()
	if _visual.has_method(&"set_motion"):
		var speed_ratio := get_real_velocity().length() / maxf(1.0, definition.move_speed)
		_visual.call(&"set_motion", direction, minf(1.0, speed_ratio))
