extends CharacterBody2D

const EnemyDefinition = preload("res://data/definitions/enemy_definition.gd")
const Health = preload("res://features/combat/health.gd")
const Player = preload("res://features/player/player.gd")

@export var definition: EnemyDefinition

@onready var health: Health = $Health
@onready var _visual: Node2D = $Visual
@onready var _body: Sprite2D = $Visual/Body
@onready var _shadow: Sprite2D = $Visual/Shadow

var target: Player

var _contact_cooldown := 0.0
var _bounce_phase := 0.0
var _hop_strength := 0.0


func _ready() -> void:
	health.configure(definition.max_health)
	health.depleted.connect(_on_depleted)


func _physics_process(delta: float) -> void:
	_contact_cooldown = move_toward(_contact_cooldown, 0.0, delta)
	if not is_instance_valid(target) or not target.health.is_alive():
		velocity = Vector2.ZERO
		return

	velocity = global_position.direction_to(target.global_position) * definition.move_speed
	move_and_slide()

	var contact_range_squared := definition.contact_range * definition.contact_range
	if (
		_contact_cooldown <= 0.0
		and global_position.distance_squared_to(target.global_position) <= contact_range_squared
	):
		_contact_cooldown = definition.contact_interval
		target.health.damage(definition.contact_damage)


func _process(delta: float) -> void:
	var speed_ratio := 0.0
	if not velocity.is_zero_approx():
		speed_ratio = minf(get_real_velocity().length() / definition.move_speed, 1.0)
	_hop_strength = move_toward(_hop_strength, speed_ratio, 8.0 * delta)
	_bounce_phase = fposmod(_bounce_phase + delta * lerpf(0.8, 2.2, _hop_strength), 1.0)
	var lift := sin(PI * _bounce_phase)
	var squash := 0.07 - 0.14 * lift
	_body.position.y = -lift * lerpf(2.0, 8.0, _hop_strength)
	_body.scale = Vector2(1.0 + squash, 1.0 - squash)
	_shadow.scale = Vector2.ONE * (1.0 - 0.12 * lift * _hop_strength)


func _on_depleted() -> void:
	remove_from_group(&"combat_enemies")
	set_physics_process(false)
	set_process(false)
	velocity = Vector2.ZERO
	collision_layer = 0
	collision_mask = 0

	var fade := create_tween()
	fade.tween_property(_body, "position:y", 0.0, 0.07)
	fade.parallel().tween_property(_body, "scale", Vector2(1.23, 0.62), 0.07)
	fade.tween_property(_visual, "modulate:a", 0.0, 0.15)
	fade.parallel().tween_property(_body, "scale", Vector2(0.8, 0.16), 0.15)
	fade.tween_callback(queue_free)
