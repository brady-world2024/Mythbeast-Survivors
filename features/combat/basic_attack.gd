extends Node2D

const Player = preload("res://features/player/player.gd")
const Health = preload("res://features/combat/health.gd")

const PULSE_DURATION := 0.22
const LAVENDER := Color("cbb1ff")
const GOLD := Color("ffe4a8")

@onready var _player := get_parent() as Player

var _cooldown_remaining := 0.0
var _pulse_remaining := 0.0
var _pulse_origin := Vector2.ZERO
var _pulse_impact := Vector2.ZERO


func _ready() -> void:
	z_index = 2


func _physics_process(delta: float) -> void:
	if _pulse_remaining > 0.0:
		_pulse_remaining = maxf(0.0, _pulse_remaining - delta)
		queue_redraw()

	_cooldown_remaining = maxf(0.0, _cooldown_remaining - delta)
	if _cooldown_remaining > 0.0 or _player.definition == null or not _player.health.is_alive():
		return

	var target := _nearest_enemy_health(_player.definition.basic_attack_range)
	if target == null:
		return

	var enemy := target.get_parent() as Node2D
	_pulse_origin = _player.global_position + Vector2(0, -52)
	_pulse_impact = enemy.global_position + Vector2(0, -22)
	_pulse_remaining = PULSE_DURATION
	_cooldown_remaining = _player.definition.basic_attack_interval
	target.damage(_player.definition.basic_attack_damage)
	queue_redraw()


func _nearest_enemy_health(attack_range: float) -> Health:
	var nearest: Health
	var nearest_distance_squared := attack_range * attack_range
	for candidate in get_tree().get_nodes_in_group(&"combat_enemies"):
		var enemy := candidate as Node2D
		if enemy == null or enemy.is_queued_for_deletion():
			continue
		var health := enemy.get_node_or_null(^"Health") as Health
		if health == null or not health.is_alive():
			continue
		var distance_squared := _player.global_position.distance_squared_to(enemy.global_position)
		if distance_squared <= nearest_distance_squared:
			nearest = health
			nearest_distance_squared = distance_squared
	return nearest


func _draw() -> void:
	if _pulse_remaining <= 0.0:
		return

	var fade := _pulse_remaining / PULSE_DURATION
	var progress := 1.0 - fade
	var origin := to_local(_pulse_origin)
	var impact := to_local(_pulse_impact)
	var control := origin.lerp(impact, 0.5) + Vector2(0, -27)
	var trail := PackedVector2Array()
	for index in range(9):
		var t := index / 8.0
		trail.append(origin.lerp(control, t).lerp(control.lerp(impact, t), t))

	draw_polyline(trail, Color(LAVENDER, fade * 0.32), 10.0, true)
	draw_polyline(trail, Color(LAVENDER, fade), 4.0, true)
	draw_polyline(trail, Color(GOLD, fade), 1.5, true)
	draw_arc(impact, 8.0 + progress * 18.0, -1.8, 3.2, 20, Color(LAVENDER, fade), 2.0, true)
	draw_circle(impact, 5.0 + progress * 8.0, Color(GOLD, fade * 0.7), true, -1.0, true)
	for index in range(3):
		var outward := Vector2.from_angle(index * TAU / 3.0 - 0.65)
		var spark := impact + outward * (12.0 + progress * 24.0)
		draw_line(spark, spark + outward * (3.0 + fade * 5.0), Color(GOLD, fade), 2.0, true)
