extends CharacterBody2D
## A grove guardian with interruptible, telegraphed attacks.

signal defeated
signal phase_changed(phase: int)
signal presentation_cue(cue: StringName)

enum State { DORMANT, CHASE, STOMP_WARNING, CHARGE_WARNING, CHARGING, RECOVERY, TRANSFORM, DEFEATED }

const BossDefinition = preload("res://data/definitions/boss_definition.gd")
const Health = preload("res://features/combat/health.gd")
const Player = preload("res://features/player/player.gd")
const SlowStatus = preload("res://features/combat/slow_status.gd")
const Comfort = preload("res://features/presentation/comfort.gd")

const WORLD_LAYER := 1
const PLAYER_LAYER := 2
const ENEMY_LAYER := 4
const COMBAT_TARGETS := &"combat_enemies"
const IMPACT_DURATION := 0.38
const INTRO_REVEAL_SECONDS := 0.7
const RING_TINT := Color("#ffdb7e")
const WARNING_OUTLINE := Color("#91592f")
const CHARGE_TINT := Color("#ffd374")
const PHASE_TINT := Color("#ffe1a0")
const FROST_TINT := Color("#b4e7fa")
const FACE_GLOW := Color("#fffac8")
const LEAF_GLOW := Color("#dbe9aa")

@export var definition: BossDefinition

@onready var health: Health = $Health
@onready var _footprint: CircleShape2D = $Footprint.shape
@onready var _visual: Node2D = $Visual
@onready var _body: Sprite2D = $Visual/Body

var spawn_radius: float:
	get:
		var shape := $Footprint.shape as CircleShape2D
		return shape.radius

var phase := 1
var attack_state := State.DORMANT

var _target: Player
var _slow := SlowStatus.new()
var _state_time := 0.0
var _contact_cooldown := 0.0
var _prefer_stomp := true
var _charge_direction := Vector2.ZERO
var _charge_left := 0.0
var _charge_warning_length := 0.0
var _impact_time := 0.0
var _body_clock := 0.0
var _defeat_fade := 0.0
var _hit_flash: Tween
var _run_health_multiplier := 1.0
var _run_damage_multiplier := 1.0


func configure_difficulty(hp_multiplier: float, damage_multiplier: float) -> void:
	_run_health_multiplier = hp_multiplier
	_run_damage_multiplier = damage_multiplier


func _ready() -> void:
	health.configure(roundi(definition.max_health * _run_health_multiplier))
	health.changed.connect(_on_health_changed)
	health.damaged.connect(_on_damaged)
	health.depleted.connect(_on_depleted)
	set_physics_process(false)


func start(player: Player) -> void:
	if attack_state != State.DORMANT or not health.is_alive():
		return
	_target = player
	collision_layer = ENEMY_LAYER
	collision_mask = WORLD_LAYER | PLAYER_LAYER
	add_to_group(COMBAT_TARGETS)
	_body.self_modulate.a = 1.0
	_change_state(State.CHASE, definition.first_attack_delay)
	set_physics_process(true)


func effective_move_speed() -> float:
	return definition.move_speed * _phase_speed_multiplier() * _slow.multiplier


func apply_slow(ratio: float, duration: float, minimum_speed_ratio: float = 0.4) -> void:
	if not is_in_group(COMBAT_TARGETS):
		return
	_slow.apply(ratio, duration, minimum_speed_ratio)
	_update_body_tint()


func _physics_process(delta: float) -> void:
	if _slow.tick(delta):
		_update_body_tint()
	if _impact_time > 0.0:
		_impact_time = move_toward(_impact_time, 0.0, delta)
		queue_redraw()
	_contact_cooldown = move_toward(_contact_cooldown, 0.0, delta)
	if not is_instance_valid(_target) or not _target.health.is_alive():
		velocity = Vector2.ZERO
		return

	_state_time = move_toward(_state_time, 0.0, delta)
	match attack_state:
		State.CHASE:
			_chase()
		State.STOMP_WARNING:
			queue_redraw()
			if _state_time == 0.0:
				_resolve_stomp()
		State.CHARGE_WARNING:
			queue_redraw()
			if _state_time == 0.0:
				_change_state(State.CHARGING)
				presentation_cue.emit(&"boss_charge")
		State.CHARGING:
			_advance_charge(delta)
		State.RECOVERY, State.TRANSFORM:
			if attack_state == State.TRANSFORM:
				queue_redraw()
			if _state_time == 0.0:
				_resume_chase()


func _chase() -> void:
	var offset := _target.global_position - global_position
	if _state_time == 0.0:
		_choose_attack(offset)
		return
	if absf(offset.x) > 4.0:
		_body.flip_h = offset.x < 0.0
	velocity = offset.normalized() * effective_move_speed()
	move_and_slide()
	if definition.contact_damage > 0 and _contact_cooldown == 0.0:
		for index in get_slide_collision_count():
			if get_slide_collision(index).get_collider() == _target:
				_contact_cooldown = definition.contact_interval
				_damage_target(definition.contact_damage)
				break


func _choose_attack(offset: Vector2) -> void:
	var can_stomp := offset.length_squared() <= definition.stomp_radius * definition.stomp_radius
	if _prefer_stomp and can_stomp:
		_prefer_stomp = false
		_change_state(State.STOMP_WARNING, definition.stomp_windup)
		return
	_prefer_stomp = true
	_charge_direction = offset.normalized() if not offset.is_zero_approx() else Vector2.DOWN
	_charge_warning_length = _charge_terrain_limit()
	if _charge_warning_length <= 8.0:
		if can_stomp:
			_change_state(State.STOMP_WARNING, definition.stomp_windup)
		else:
			_change_state(State.CHASE, 0.3)
		return
	_charge_left = _charge_warning_length
	_change_state(State.CHARGE_WARNING, definition.charge_windup)


func _charge_terrain_limit() -> float:
	var path := PhysicsShapeQueryParameters2D.new()
	path.shape = _footprint
	path.transform = global_transform
	path.motion = _charge_direction * definition.charge_distance
	path.collision_mask = WORLD_LAYER
	var result := get_world_2d().direct_space_state.cast_motion(path)
	if result.is_empty():
		return definition.charge_distance
	return definition.charge_distance * result[0]


func _resolve_stomp() -> void:
	_impact_time = IMPACT_DURATION
	_change_state(State.RECOVERY, definition.recovery_duration)
	presentation_cue.emit(&"boss_stomp")
	var radius := definition.stomp_radius
	if global_position.distance_squared_to(_target.global_position) <= radius * radius:
		_damage_target(definition.stomp_damage)


func _advance_charge(delta: float) -> void:
	var distance := minf(_charge_left, definition.charge_speed * _slow.multiplier * delta)
	velocity = _charge_direction * definition.charge_speed * _slow.multiplier
	var collision := move_and_collide(_charge_direction * distance)
	_charge_left -= distance
	if collision != null or _charge_left <= 0.01:
		_change_state(State.RECOVERY, definition.recovery_duration)
		if collision != null and collision.get_collider() == _target:
			_damage_target(definition.charge_damage)


func _damage_target(amount: int) -> void:
	_target.receive_damage(roundi(amount * _run_damage_multiplier))


func _phase_speed_multiplier() -> float:
	return definition.phase_two_speed_multiplier if phase == 2 else 1.0


func _resume_chase() -> void:
	var cooldown := definition.attack_cooldown
	if phase == 2:
		cooldown *= definition.phase_two_cooldown_multiplier
	_change_state(State.CHASE, cooldown)


func _change_state(next: State, time: float = 0.0) -> void:
	attack_state = next
	_state_time = time
	velocity = Vector2.ZERO
	queue_redraw()


func _on_health_changed(current: int, maximum: int) -> void:
	if phase != 1 or current <= 0 or attack_state == State.DORMANT:
		return
	if float(current) > float(maximum) * definition.phase_threshold:
		return
	phase = 2
	_charge_left = 0.0
	_impact_time = 0.0
	_change_state(State.TRANSFORM, definition.phase_transform_duration)
	_update_body_tint()
	presentation_cue.emit(&"boss_phase")
	phase_changed.emit(phase)


func _on_damaged(_amount: int) -> void:
	if _hit_flash != null:
		_hit_flash.kill()
	_body.self_modulate = Color(1.16, 1.07, 1.04) if Comfort.reduced_effects else Color(1.45, 1.21, 1.12)
	_hit_flash = create_tween()
	_hit_flash.tween_property(_body, "self_modulate", Color.WHITE, 0.15)


func _on_depleted() -> void:
	if attack_state == State.DEFEATED or attack_state == State.DORMANT:
		return
	_change_state(State.DEFEATED)
	remove_from_group(COMBAT_TARGETS)
	collision_layer = 0
	collision_mask = 0
	_slow.clear()
	_update_body_tint()
	set_physics_process(false)
	set_process(false)
	var fade := create_tween()
	fade.tween_property(_visual, "scale", Vector2(1.05, 0.87), 0.11)
	fade.tween_property(_visual, "scale", Vector2(0.87, 0.77), 0.32)
	fade.parallel().tween_property(_visual, "modulate:a", 0.0, 0.32)
	if not Comfort.reduced_effects:
		fade.parallel().tween_method(_set_defeat_fade, 1.0, 0.0, 0.32)
	fade.tween_callback(_finish_defeat)


func _set_defeat_fade(amount: float) -> void:
	_defeat_fade = amount
	queue_redraw()


func _finish_defeat() -> void:
	defeated.emit()
	queue_free()


func _update_body_tint() -> void:
	var base := PHASE_TINT if phase == 2 else Color.WHITE
	_body.modulate = base.lerp(FROST_TINT, 0.68) if _slow.multiplier < 1.0 else base
	queue_redraw()


func _process(delta: float) -> void:
	if attack_state == State.DORMANT and _body_clock < INTRO_REVEAL_SECONDS and not Comfort.reduced_effects:
		queue_redraw()
	_body_clock += delta
	var stride := sin(_body_clock * 4.4)
	var moving := not velocity.is_zero_approx()
	var bounce := absf(stride) * (6.0 if moving else 2.2)
	_body.position.y = -bounce
	_body.rotation = stride * (0.04 if moving else 0.012)
	_body.scale = Vector2(1.0, 1.0 + stride * 0.025)
	match attack_state:
		State.DORMANT:
			var arrival := _intro_progress()
			_body.position.y = lerpf(-12.0, -bounce, arrival) if not Comfort.reduced_effects else 0.0
			_body.self_modulate.a = lerpf(0.55, 1.0, arrival)
		State.STOMP_WARNING:
			var windup := 1.0 - _state_time / definition.stomp_windup
			_body.position.y = -4.0 - windup * 12.0
			_body.scale = Vector2.ONE.lerp(Vector2(0.97, 1.08), windup)
		State.CHARGE_WARNING:
			var windup := 1.0 - _state_time / definition.charge_windup
			_body.position.y = 4.0 * windup
			_body.rotation = -_charge_direction.x * windup * 0.09
			_body.scale = Vector2.ONE.lerp(Vector2(1.12, 0.83), windup)
		State.CHARGING:
			_body.position.y = -7.0
			_body.rotation = _charge_direction.x * 0.15
			_body.scale = Vector2(1.1, 0.92)
		State.RECOVERY:
			var settle := _state_time / definition.recovery_duration
			_body.position.y = 4.0 * settle
			_body.scale = Vector2.ONE.lerp(Vector2(1.08, 0.91), settle)
		State.TRANSFORM:
			_body.position.y = -4.0 if Comfort.reduced_effects else -10.0 - absf(stride) * 4.0


func _draw() -> void:
	if attack_state == State.DEFEATED:
		_draw_defeat()
		return
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, 55.0, Color(0.2, 0.3, 0.24, 0.26), true, -1.0, true)
	draw_set_transform(Vector2.ZERO)
	match attack_state:
		State.DORMANT:
			_draw_intro()
		State.STOMP_WARNING:
			_draw_stomp_warning()
		State.CHARGE_WARNING:
			_draw_charge_warning()
		State.CHARGING:
			_draw_charge_trail()
		State.TRANSFORM:
			_draw_transformation()
	if phase == 2 and attack_state != State.TRANSFORM:
		for side in [-1.0, 1.0]:
			var angle := 0.0 if side > 0.0 else PI
			draw_arc(Vector2(0, -18), 84.0, angle - 0.30, angle + 0.30, 12, Color(LEAF_GLOW, 0.56), 3.0, true)
	if _impact_time > 0.0:
		var fade := _impact_time / IMPACT_DURATION
		var radius := lerpf(definition.stomp_radius, 38.0, fade)
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(RING_TINT, fade * 0.9), 6.0, true)
		if not Comfort.reduced_effects:
			draw_arc(Vector2.ZERO, radius * 0.78, 0.0, TAU, 36, Color(FACE_GLOW, fade), 2.5, true)
	if _slow.multiplier < 1.0:
		for origin in [Vector2(-47.0, -57.0), Vector2(45.0, -70.0)]:
			for spoke in range(3):
				var arm := Vector2.from_angle(spoke * PI / 3.0) * 6.5
				draw_line(origin - arm, origin + arm, FROST_TINT, 2.0, true)


func _intro_progress() -> float:
	return 1.0 if Comfort.reduced_effects else clampf(_body_clock / INTRO_REVEAL_SECONDS, 0.0, 1.0)


func _draw_intro() -> void:
	var progress := _intro_progress()
	var radius := lerpf(44.0, 68.0, progress)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 36, Color(LEAF_GLOW, 0.64), 2.0, true)
	for index in range(6):
		var spoke := Vector2.from_angle(index * TAU / 6.0)
		draw_line(spoke * (radius - 6.0), spoke * (radius + 5.0), Color(FACE_GLOW, progress * 0.88), 2.5, true)


func _draw_charge_trail() -> void:
	if Comfort.reduced_effects:
		return
	var lateral := _charge_direction.orthogonal()
	for across: float in [-27.0, 0.0, 27.0]:
		var tail := -_charge_direction * 55.0 + lateral * across
		draw_line(tail, tail - _charge_direction * 26.0, Color(CHARGE_TINT, 0.59), 3.0, true)


func _draw_defeat() -> void:
	if _defeat_fade <= 0.0:
		return
	var radius := lerpf(97.0, 48.0, _defeat_fade)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(LEAF_GLOW, _defeat_fade * 0.7), 3.0, true)
	for index in range(6):
		var spoke := Vector2.from_angle(index * TAU / 6.0)
		var center := spoke * (radius + 3.0)
		var edge := spoke.orthogonal() * 3.0
		draw_colored_polygon(PackedVector2Array([center + spoke * 5.0, center + edge, center - spoke * 5.0, center - edge]),
			Color(FACE_GLOW, _defeat_fade * 0.85))


func _draw_stomp_warning() -> void:
	var radius := definition.stomp_radius
	var progress := 1.0 - _state_time / definition.stomp_windup
	draw_circle(Vector2.ZERO, radius, Color(RING_TINT, 0.23), true, -1.0, true)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 60, WARNING_OUTLINE, 6.0, true)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 60, RING_TINT, 3.0, true)
	draw_arc(Vector2.ZERO, lerpf(radius * 0.4, radius, progress), 0.0, TAU, 48, Color(RING_TINT, 0.72), 2.0, true)
	for index in range(12):
		var radial := Vector2.from_angle(index * TAU / 12.0)
		draw_line(radial * (radius - 11.0), radial * (radius - 4.0), FACE_GLOW, 3.0, true)


func _draw_charge_warning() -> void:
	var radius := _footprint.radius
	var forward := _charge_direction
	var perpendicular := forward.orthogonal()
	var side := perpendicular * radius
	var far := forward * _charge_warning_length
	draw_colored_polygon(PackedVector2Array([side, -side, far - side, far + side]), Color(CHARGE_TINT, 0.29))
	for edge: Vector2 in [side, -side]:
		draw_line(edge, far + edge, WARNING_OUTLINE, 6.0, true)
		draw_line(edge, far + edge, CHARGE_TINT, 3.0, true)
	draw_arc(far, radius, forward.angle() - PI / 2.0, forward.angle() + PI / 2.0, 22, CHARGE_TINT, 4.0, true)
	var alpha := lerpf(0.48, 1.0, 1.0 - _state_time / definition.charge_windup)
	for index in range(1, 7):
		var middle := forward * (_charge_warning_length * index / 7.0)
		var tip := middle + forward * 11.0
		draw_line(middle - perpendicular * 8.0, tip, Color(FACE_GLOW, alpha), 3.0, true)
		draw_line(tip, middle + perpendicular * 8.0, Color(FACE_GLOW, alpha), 3.0, true)


func _draw_transformation() -> void:
	var progress := 1.0 - _state_time / definition.phase_transform_duration
	var radius := lerpf(45.0, 100.0, progress)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(RING_TINT, 0.95 - progress * 0.62), 4.0, true)
	if Comfort.reduced_effects:
		return
	for index in range(8):
		var angle := TAU * index / 8.0 + progress
		var position_on_ring := Vector2.from_angle(angle) * radius * 0.77 + Vector2(0, -28 - progress * 20.0)
		var tint := Color(LEAF_GLOW, 0.95 - progress * 0.48)
		draw_line(position_on_ring - Vector2(2, 4), position_on_ring + Vector2(2, 4), tint, 3.0, true)
