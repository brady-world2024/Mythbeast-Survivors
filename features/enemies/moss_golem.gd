extends "res://features/enemies/enemy_actor.gd"

enum AttackStage { CHASE, WIND_UP, RECOVER }

const WARNING_COLOR := Color("#a94737")
const IMPACT_COLOR := Color("#ffdf8f")
const IMPACT_SECONDS := 0.23

var _stage := AttackStage.CHASE
var _stage_remaining := 0.0
var _slam_cooldown := 0.0
var _impact_remaining := 0.0
var _stride := 0.0


func _step_ai(delta: float) -> void:
	_slam_cooldown = move_toward(_slam_cooldown, 0.0, delta)
	if _impact_remaining > 0.0:
		_impact_remaining = move_toward(_impact_remaining, 0.0, delta)
		queue_redraw()
	match _stage:
		AttackStage.CHASE:
			_approach()
		AttackStage.WIND_UP:
			_stage_remaining = move_toward(_stage_remaining, 0.0, delta)
			if _stage_remaining == 0.0:
				_resolve_slam()
			queue_redraw()
		AttackStage.RECOVER:
			_stage_remaining = move_toward(_stage_remaining, 0.0, delta)
			if _stage_remaining == 0.0:
				_stage = AttackStage.CHASE


func _approach() -> void:
	var offset := target.global_position - global_position
	var attack_distance := definition.attack_trigger_range
	if _slam_cooldown == 0.0 and offset.length_squared() <= attack_distance * attack_distance:
		velocity = Vector2.ZERO
		_stage = AttackStage.WIND_UP
		_stage_remaining = definition.attack_windup
		_slam_cooldown = definition.contact_interval
		queue_redraw()
		return
	chase(offset, definition.contact_range)


func _resolve_slam() -> void:
	_stage = AttackStage.RECOVER
	_stage_remaining = definition.attack_recovery
	_impact_remaining = IMPACT_SECONDS
	var radius := definition.slam_radius
	if global_position.distance_squared_to(target.global_position) <= radius * radius:
		damage_player()


func _animate(delta: float) -> void:
	_stride += delta * (2.1 if velocity.is_zero_approx() else 7.0)
	var step := sin(_stride)
	_body.position.y = -absf(step) * 3.3
	_body.rotation = step * (0.018 if velocity.is_zero_approx() else 0.05)
	_body.scale = Vector2.ONE
	if _stage == AttackStage.WIND_UP:
		var lift := 1.0 - _stage_remaining / definition.attack_windup
		_body.position.y = -4.0 - lift * 12.0
		_body.scale = Vector2(0.95, 1.07)
	elif _impact_remaining > 0.0:
		_body.scale = Vector2.ONE.lerp(Vector2(1.13, 0.88), _impact_remaining / IMPACT_SECONDS)


func _draw() -> void:
	super._draw()
	if not health.is_alive():
		return
	var radius := definition.slam_radius
	if _stage == AttackStage.WIND_UP:
		var progress := 1.0 - _stage_remaining / definition.attack_windup
		draw_circle(Vector2.ZERO, radius, Color(WARNING_COLOR, 0.12))
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, Color(WARNING_COLOR, 0.8), 3.0, true)
		draw_arc(Vector2.ZERO, radius - 6.0, -PI / 2.0, -PI / 2.0 + TAU * progress, 32, IMPACT_COLOR, 4.0, true)
	elif _impact_remaining > 0.0:
		var fade := _impact_remaining / IMPACT_SECONDS
		var impact_radius := lerpf(radius, radius * 0.32, fade)
		draw_arc(Vector2.ZERO, impact_radius, 0.0, TAU, 32, Color(IMPACT_COLOR, fade), 4.0, true)
		for index in range(7):
			var direction := Vector2.from_angle(index * TAU / 7.0)
			draw_line(direction * impact_radius, direction * (impact_radius + 9.0), Color(IMPACT_COLOR, fade), 2.0, true)
