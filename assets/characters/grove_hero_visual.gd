extends Node2D
## Original hero presentation. Local origin is the center of the feet.

const IDLE_DURATION := 1.9
const IDLE_HEIGHT := 2.4
const WALK_HEIGHT := 6.0
const WALK_BLEND_SPEED := 12.0
const FACING_AXIS_MARGIN := 0.10
const SHADOW_COLOR := Color(0.12, 0.2, 0.17, 0.14)
const HIT_TINT := Color(1.0, 0.58, 0.59)
const HIT_DURATION := 0.18
const CAST_DURATION := 0.22

@export var side_texture: Texture2D
@export var back_texture: Texture2D

@onready var _body: Sprite2D = $Body
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


func set_motion(facing: Vector2, speed_ratio: float) -> void:
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
	_hit_remaining = HIT_DURATION
	_body.self_modulate = HIT_TINT


func play_cast() -> void:
	_cast_remaining = CAST_DURATION


func _process(delta: float) -> void:
	if _hit_remaining > 0.0:
		_hit_remaining = move_toward(_hit_remaining, 0.0, delta)
		_body.self_modulate = Color.WHITE.lerp(HIT_TINT, _hit_remaining / HIT_DURATION)
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
	var cast_lift := 4.0 * sin(PI * _cast_remaining / CAST_DURATION)
	_body.position = Vector2(2.1 * stride * _walk_strength, lerpf(idle_y, -WALK_HEIGHT * lift, _walk_strength) - cast_lift)
	_body.rotation = (_forward_lean + 0.065 * stride) * _walk_strength
	_body.scale = _rest_scale * Vector2(1.0 + 0.037 * landing, 1.0 - 0.043 * landing)


func _draw() -> void:
	for ring in range(5):
		var radius := Vector2(38.0 - 3.0 * ring, 11.0 - 1.3 * ring)
		draw_set_transform(Vector2(0, 1.0), 0.0, Vector2(1.0, radius.y / radius.x))
		draw_circle(Vector2.ZERO, radius.x, SHADOW_COLOR, true, -1.0, true)
