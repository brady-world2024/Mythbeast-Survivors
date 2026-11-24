extends CharacterBody2D
## Shared health, movement, status, and cleanup for ordinary enemies.

const EnemyDefinition = preload("res://data/definitions/enemy_definition.gd")
const Health = preload("res://features/combat/health.gd")
const Player = preload("res://features/player/player.gd")
const SlowStatus = preload("res://features/combat/slow_status.gd")

const HIT_TINT := Color(1.75, 1.35, 1.48)
const HIT_FLASH_SECONDS := 0.14

@export var definition: EnemyDefinition

@onready var health: Health = $Health
@onready var _visual: Node2D = $Visual
@onready var _body: Sprite2D = $Visual/Body
@onready var _shadow: Sprite2D = $Visual/Shadow

var target: Player

var _health_scale := 1.0
var _speed_scale := 1.0
var _damage_scale := 1.0
var _hit_flash: Tween
var _slow := SlowStatus.new()


func configure_spawn(health_multiplier: float, speed_multiplier: float, damage_multiplier: float) -> void:
	_health_scale = maxf(0.01, health_multiplier)
	_speed_scale = maxf(0.01, speed_multiplier)
	_damage_scale = maxf(0.0, damage_multiplier)


func _ready() -> void:
	health.configure(roundi(definition.max_health * _health_scale))
	health.damaged.connect(_on_damaged)
	health.depleted.connect(_on_depleted)


func _physics_process(delta: float) -> void:
	if _slow.tick(delta):
		_update_slow_visual()
	if not valid_target():
		velocity = Vector2.ZERO
		return
	_step_ai(delta)


func _step_ai(_delta: float) -> void:
	pass


func _process(delta: float) -> void:
	_animate(delta)


func _animate(_delta: float) -> void:
	pass


func valid_target() -> bool:
	return (
		is_instance_valid(target) and not target.is_queued_for_deletion()
		and is_instance_valid(target.health) and target.health.is_alive()
	)


func chase(offset: Vector2, stop_distance: float) -> void:
	if absf(offset.x) > 3.0:
		_body.flip_h = offset.x < 0.0
	if offset.length_squared() > stop_distance * stop_distance:
		velocity = offset.normalized() * effective_move_speed()
		move_and_slide()
	else:
		velocity = Vector2.ZERO


func damage_player() -> bool:
	if not valid_target() or not health.is_alive():
		return false
	return target.receive_damage(roundi(definition.contact_damage * _damage_scale))


func effective_move_speed() -> float:
	return definition.move_speed * _speed_scale * _slow.multiplier


func apply_slow(ratio: float, duration: float, minimum_speed_ratio: float = 0.4) -> void:
	if health.is_alive():
		_slow.apply(ratio, duration, minimum_speed_ratio)
		_update_slow_visual()


func _update_slow_visual() -> void:
	_body.modulate = Color("a9e7ff") if _slow.multiplier < 1.0 else Color.WHITE
	queue_redraw()


func _draw() -> void:
	if _slow.multiplier >= 1.0:
		return
	for point: Vector2 in [Vector2(-21.0, -39.0), Vector2(20.0, -45.0)]:
		for spoke in range(3):
			var arm := Vector2.from_angle(spoke * PI / 3.0) * 5.0
			draw_line(point - arm, point + arm, Color("c4f6ff"), 2.0, true)


func _on_damaged(_amount: int) -> void:
	if _hit_flash != null:
		_hit_flash.kill()
	_body.self_modulate = HIT_TINT
	_hit_flash = create_tween()
	_hit_flash.tween_property(_body, "self_modulate", Color.WHITE, HIT_FLASH_SECONDS)


func _on_depleted() -> void:
	_disable_combat()
	var sway := create_tween()
	sway.tween_property(_body, "position:y", 0.0, 0.07)
	sway.parallel().tween_property(_body, "scale", Vector2(1.23, 0.62), 0.07)
	sway.tween_property(_visual, "modulate:a", 0.0, 0.15)
	sway.parallel().tween_property(_body, "scale", Vector2(0.8, 0.16), 0.15)
	sway.tween_callback(queue_free)


func dismiss() -> void:
	_disable_combat()
	queue_free()


func _disable_combat() -> void:
	_slow.clear()
	_update_slow_visual()
	if is_in_group(&"combat_enemies"):
		remove_from_group(&"combat_enemies")
	set_physics_process(false)
	set_process(false)
	velocity = Vector2.ZERO
	collision_layer = 0
	collision_mask = 0
	target = null
