extends "res://features/enemies/enemy_actor.gd"

enum AttackStage { CHASE, WIND_UP, LUNGE, RECOVER }

const WARNING_COLOR := Color("#a94737")
const IMPACT_COLOR := Color("#ffe299")
const MINIMUM_LUNGE_DISTANCE := 55.0

var _stage := AttackStage.CHASE
var _stage_remaining := 0.0
var _lunge_cooldown := 0.0
var _contact_cooldown := 0.0
var _aim := Vector2.RIGHT
var _stride := 0.0


func _ready() -> void:
	super._ready()
	_lunge_cooldown = definition.lunge_interval


func _step_ai(delta: float) -> void:
	_lunge_cooldown = move_toward(_lunge_cooldown, 0.0, delta)
	_contact_cooldown = move_toward(_contact_cooldown, 0.0, delta)
	match _stage:
		AttackStage.CHASE:
			_follow_target()
		AttackStage.WIND_UP:
			_stage_remaining = move_toward(_stage_remaining, 0.0, delta)
			if _stage_remaining == 0.0:
				_stage = AttackStage.LUNGE
				_stage_remaining = definition.lunge_duration
			queue_redraw()
		AttackStage.LUNGE:
			_lunge(delta)
		AttackStage.RECOVER:
			_stage_remaining = move_toward(_stage_remaining, 0.0, delta)
			if _stage_remaining == 0.0:
				_stage = AttackStage.CHASE


func _follow_target() -> void:
	var offset := target.global_position - global_position
	var distance_squared := offset.length_squared()
	if (
		_lunge_cooldown == 0.0 and _contact_cooldown == 0.0
		and distance_squared >= MINIMUM_LUNGE_DISTANCE * MINIMUM_LUNGE_DISTANCE
		and distance_squared <= definition.attack_trigger_range * definition.attack_trigger_range
	):
		_aim = offset.normalized()
		_body.flip_h = _aim.x < 0.0
		velocity = Vector2.ZERO
		_lunge_cooldown = definition.lunge_interval
		_stage = AttackStage.WIND_UP
		_stage_remaining = definition.attack_windup
		queue_redraw()
		return
	chase(offset, definition.contact_range)
	if _contact_cooldown == 0.0 and global_position.distance_squared_to(target.global_position) <= definition.contact_range * definition.contact_range:
		_contact_cooldown = definition.contact_interval
		damage_player()


func _lunge(delta: float) -> void:
	var step := minf(delta, _stage_remaining)
	_stage_remaining -= step
	velocity = _aim * definition.lunge_speed
	var hit := move_and_collide(velocity * step)
	if hit == null and _stage_remaining > 0.0:
		return
	if hit != null and hit.get_collider() == target and _contact_cooldown == 0.0:
		_contact_cooldown = definition.contact_interval
		damage_player()
	velocity = Vector2.ZERO
	_stage = AttackStage.RECOVER
	_stage_remaining = definition.attack_recovery
	queue_redraw()


func _animate(delta: float) -> void:
	var moving := not velocity.is_zero_approx()
	_stride += delta * (16.0 if moving else 3.0)
	var bounce := absf(sin(_stride))
	_body.position.y = -bounce * (7.0 if moving else 2.0)
	_body.rotation = sin(_stride) * (0.065 if moving else 0.018)
	_body.scale = Vector2.ONE
	match _stage:
		AttackStage.WIND_UP:
			var crouch := 1.0 - _stage_remaining / definition.attack_windup
			_body.position.y = lerpf(0.0, 4.0, crouch)
			_body.scale = Vector2.ONE.lerp(Vector2(1.12, 0.77), crouch)
			_body.rotation = -_aim.x * crouch * 0.10
		AttackStage.LUNGE:
			_body.position.y = -8.0
			_body.scale = Vector2(1.12, 0.92)
			_body.rotation = _aim.x * 0.18
		AttackStage.RECOVER:
			var recovery := _stage_remaining / definition.attack_recovery
			_body.position.y *= 1.0 - recovery
			_body.scale = Vector2.ONE.lerp(Vector2(1.12, 0.86), recovery)
	_shadow.scale = Vector2.ONE * (1.0 - 0.07 * bounce)


func _draw() -> void:
	super._draw()
	if not health.is_alive():
		return
	if _stage == AttackStage.LUNGE and not Comfort.reduced_effects:
		var across := _aim.orthogonal() * 11.0
		for offset: Vector2 in [across, -across]:
			var tail := offset - _aim * 28.0
			draw_line(tail, tail - _aim * 20.0, Color(IMPACT_COLOR, 0.68), 2.5, true)
		return
	if _stage != AttackStage.WIND_UP:
		return
	var distance := definition.lunge_speed * definition.lunge_duration
	var across := _aim.orthogonal()
	var tip := _aim * distance
	var opacity := lerpf(0.60, 1.0, 1.0 - _stage_remaining / definition.attack_windup)
	draw_line(_aim * 10.0, tip, Color(WARNING_COLOR, opacity * 0.45), 18.0, true)
	draw_dashed_line(_aim * 14.0, tip - _aim * 5.0, Color(IMPACT_COLOR, opacity), 3.0, 9.0, true, true)
	draw_polyline(PackedVector2Array([tip - _aim * 13.0 + across * 10.0, tip, tip - _aim * 13.0 - across * 10.0]),
		Color(WARNING_COLOR, opacity), 3.0, true)
