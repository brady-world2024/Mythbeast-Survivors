extends "res://features/enemies/enemy_actor.gd"

var _contact_cooldown := 0.0
var _bounce_phase := 0.0
var _hop_strength := 0.0


func _step_ai(delta: float) -> void:
	_contact_cooldown = move_toward(_contact_cooldown, 0.0, delta)
	var distance_squared := definition.contact_range * definition.contact_range
	chase(target.global_position - global_position, definition.contact_range)
	if _contact_cooldown <= 0.0 and global_position.distance_squared_to(target.global_position) <= distance_squared:
		_contact_cooldown = definition.contact_interval
		damage_player()


func _animate(delta: float) -> void:
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
