extends Node2D
## Original hero presentation. Local origin is the center of the feet.

const Comfort = preload("res://features/presentation/comfort.gd")

const IDLE_DURATION := 1.9
const IDLE_HEIGHT := 2.4
const WALK_HEIGHT := 6.0
const WALK_BLEND_SPEED := 12.0
const FACING_AXIS_MARGIN := 0.10
const HIT_TINT := Color(1.0, 0.58, 0.59)
const CAST_TINT := Color("#fff3ca")
const HIT_DURATION := 0.18
const CAST_DURATION := 0.22

@export var side_texture: Texture2D
@export var back_texture: Texture2D

@onready var _body: Sprite2D = $Body
@onready var _expression: Sprite2D = $Body/Expression
@onready var _shadow: Sprite2D = $Shadow
@onready var _front_texture: Texture2D = _body.texture
@onready var _rest_scale: Vector2 = _body.scale

var _idle_phase := 0.0
var _stride_phase := 0.0
var _speed_ratio := 0.0
var _walk_strength := 0.0
var _forward_lean := 0.0
var _facing_side := false
var _hit_remaining := 0.0
var _cast_remaining := 0.0
var _settled := false


func set_motion(facing: Vector2, speed_ratio: float) -> void:
	if _settled:
		return
	_speed_ratio = clampf(speed_ratio, 0.0, 1.0)
	if facing.is_zero_approx():
		return
	var unit := facing.normalized()
	var axis_difference := absf(unit.x) - absf(unit.y)
	if absf(axis_difference) > FACING_AXIS_MARGIN:
		_facing_side = axis_difference > 0.0
	if _facing_side:
		_body.texture = side_texture
		_body.flip_h = facing.x < 0.0
		_forward_lean = signf(facing.x) * 0.05
	else:
		_body.texture = back_texture if facing.y < 0.0 else _front_texture
		_body.flip_h = false
		_forward_lean = 0.0


func play_hit() -> void:
	if _settled:
		return
	_hit_remaining = HIT_DURATION


func play_cast() -> void:
	if not _settled:
		_cast_remaining = CAST_DURATION


func play_defeat() -> void:
	if _settled:
		return
	var pose := _begin_outcome(0)
	var duration := 0.16 if Comfort.reduced_effects else 0.32
	pose.tween_property(_body, "position", Vector2(-11, 9), duration)
	pose.parallel().tween_property(_body, "rotation", -0.54, duration)
	pose.parallel().tween_property(_body, "scale", _rest_scale * Vector2(1.08, 0.77), duration)
	pose.parallel().tween_property(_body, "modulate", Color("#c8bfc6"), duration)


func play_victory() -> void:
	if _settled:
		return
	var pose := _begin_outcome(1)
	if not Comfort.reduced_effects:
		pose.tween_property(_body, "position", Vector2(0, -13), 0.2)
		pose.parallel().tween_property(_body, "scale", _rest_scale * Vector2(0.96, 1.07), 0.2)
	pose.tween_property(_body, "position", Vector2(0, -2), 0.18)
	pose.parallel().tween_property(_body, "scale", _rest_scale * Vector2(1.025, 0.99), 0.18)
	pose.parallel().tween_property(_body, "rotation", 0.035, 0.18)


func _begin_outcome(expression: int) -> Tween:
	_settled = true
	set_process(false)
	_body.texture = _front_texture
	_body.flip_h = false
	_body.modulate = Color.WHITE
	_expression.frame = expression
	_expression.show()
	_shadow.scale = Vector2.ONE
	return create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	_hit_remaining = move_toward(_hit_remaining, 0.0, delta)
	_cast_remaining = move_toward(_cast_remaining, 0.0, delta)
	_idle_phase = fposmod(_idle_phase + TAU * delta / IDLE_DURATION, TAU)
	_walk_strength = move_toward(_walk_strength, _speed_ratio, delta * WALK_BLEND_SPEED)
	if _walk_strength > 0.0:
		var stride_rate := lerpf(1.3, 2.6, _walk_strength)
		_stride_phase = fposmod(_stride_phase + TAU * delta * stride_rate, TAU)
	else:
		_stride_phase = 0.0

	var stride := sin(_stride_phase)
	var lift := absf(stride)
	var idle_y := -IDLE_HEIGHT * (0.5 - 0.5 * cos(_idle_phase))
	var landing := (1.0 - lift) * _walk_strength
	var cast_strength := sin(PI * _cast_remaining / CAST_DURATION)
	var cast_lift := (2.0 if Comfort.reduced_effects else 5.0) * cast_strength
	var hit_strength := _hit_remaining / HIT_DURATION * (0.4 if Comfort.reduced_effects else 1.0)
	var idle_stretch := sin(_idle_phase) * (1.0 - _walk_strength) * 0.012
	var lift_y := lerpf(idle_y, -WALK_HEIGHT * lift, _walk_strength) - cast_lift + 2.0 * hit_strength
	_body.position = Vector2(2.1 * stride * _walk_strength, lift_y)
	_body.rotation = (_forward_lean + 0.065 * stride) * _walk_strength + _forward_lean * cast_strength
	_body.scale = _rest_scale * Vector2(1.0 + 0.037 * landing - idle_stretch, 1.0 - 0.043 * landing + idle_stretch + 0.045 * cast_strength)
	_body.modulate = Color.WHITE.lerp(CAST_TINT, cast_strength).lerp(HIT_TINT, hit_strength)
	_shadow.scale = Vector2.ONE * (1.0 - 0.09 * lift * _walk_strength)
