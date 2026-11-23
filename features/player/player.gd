extends CharacterBody2D

const CharacterDefinition = preload("res://data/definitions/character_definition.gd")
const Health = preload("res://features/combat/health.gd")

@export var definition: CharacterDefinition

@onready var health: Health = $Health

var move_direction := Vector2.ZERO

var _visual: Node
var _invulnerability_remaining := 0.0


func _ready() -> void:
	if definition == null or definition.visual_scene == null:
		push_error("Player requires a character definition with a visual scene.")
		set_physics_process(false)
		return
	health.configure(definition.max_health)
	_visual = definition.visual_scene.instantiate()
	$VisualAnchor.add_child(_visual)
	health.damaged.connect(_on_damaged)
	health.depleted.connect(_on_depleted)


func receive_damage(amount: int) -> bool:
	if amount <= 0 or not health.is_alive() or _invulnerability_remaining > 0.0:
		return false
	_invulnerability_remaining = definition.damage_invulnerability
	health.damage(amount)
	return true


func play_cast() -> void:
	if is_instance_valid(_visual) and _visual.has_method(&"play_cast"):
		_visual.call(&"play_cast")


func _physics_process(delta: float) -> void:
	if not health.is_alive():
		return
	_invulnerability_remaining = move_toward(_invulnerability_remaining, 0.0, delta)
	var direction := move_direction.limit_length()
	velocity = direction * definition.move_speed
	move_and_slide()
	if _visual.has_method(&"set_motion"):
		var speed_ratio := get_real_velocity().length() / maxf(1.0, definition.move_speed)
		_visual.call(&"set_motion", direction, minf(1.0, speed_ratio))


func _on_damaged(_amount: int) -> void:
	if _visual.has_method(&"play_hit"):
		_visual.call(&"play_hit")


func _on_depleted() -> void:
	move_direction = Vector2.ZERO
	velocity = Vector2.ZERO
