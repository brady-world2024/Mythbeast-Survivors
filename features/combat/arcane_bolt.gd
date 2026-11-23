extends CharacterBody2D

signal enemy_hit(enemy: Node2D, origin: Vector2, damage: int)

const Targets = preload("res://features/combat/combat_targets.gd")
const WeaponDefinition = preload("res://data/definitions/weapon_definition.gd")

const IMPACT_DURATION := 0.18
const VISUAL_HEIGHT := Vector2(0, -30)
const VIOLET := Color("764bb1")
const LAVENDER := Color("cbb1ff")
const PALE_GOLD := Color("fff1c9")

var _remaining_lifetime := 0.0
var _damage := 0
var _impact_remaining := 0.0
var _visual_scale := 1.0


func set_visual_rank(rank: int) -> void:
	_visual_scale = 1.0 + clampi(rank - 1, 0, 4) * 0.06


func launch(origin: Vector2, direction: Vector2, weapon: WeaponDefinition) -> void:
	global_position = origin
	var aim := direction.normalized() if not direction.is_zero_approx() else Vector2.RIGHT
	velocity = aim * weapon.projectile_speed
	_damage = weapon.damage
	_remaining_lifetime = weapon.projectile_lifetime
	queue_redraw()


func _physics_process(delta: float) -> void:
	if _impact_remaining > 0.0:
		_impact_remaining = move_toward(_impact_remaining, 0.0, delta)
		queue_redraw()
		if _impact_remaining == 0.0:
			queue_free()
		return

	var motion_time := minf(delta, _remaining_lifetime)
	var collision := move_and_collide(velocity * motion_time)
	if collision != null:
		_impact(collision.get_collider() as Node)
		return
	_remaining_lifetime -= motion_time
	if _remaining_lifetime <= 0.0:
		queue_free()


func _impact(collider: Node) -> void:
	remove_from_group(&"arcane_bolts")
	collision_layer = 0
	collision_mask = 0
	velocity = Vector2.ZERO
	_impact_remaining = IMPACT_DURATION
	queue_redraw()

	var enemy := collider as Node2D
	if enemy == null or not enemy.is_in_group(&"combat_enemies"):
		return
	var health := Targets.living_health(enemy)
	if health != null:
		var hit_origin := enemy.global_position
		health.damage(_damage)
		enemy_hit.emit(enemy if is_instance_valid(enemy) else null, hit_origin, _damage)


func _draw() -> void:
	if _impact_remaining > 0.0:
		_draw_impact()
		return
	var trail := VISUAL_HEIGHT - velocity.normalized() * 24.0
	draw_line(trail, VISUAL_HEIGHT, Color(LAVENDER, 0.42), 8.0, true)
	draw_line(trail.lerp(VISUAL_HEIGHT, 0.5), VISUAL_HEIGHT, Color(VIOLET, 0.62), 3.0, true)
	draw_circle(VISUAL_HEIGHT, 15.0 * _visual_scale, Color(LAVENDER, 0.3), true, -1.0, true)
	draw_circle(VISUAL_HEIGHT, 9.0 * _visual_scale, VIOLET, true, -1.0, true)
	draw_circle(VISUAL_HEIGHT, 6.0 * _visual_scale, LAVENDER, true, -1.0, true)
	draw_circle(VISUAL_HEIGHT + Vector2(-2, -2), 3.0, PALE_GOLD, true, -1.0, true)


func _draw_impact() -> void:
	var fade := _impact_remaining / IMPACT_DURATION
	var spread := lerpf(24.0, 8.0, fade) * _visual_scale
	draw_arc(VISUAL_HEIGHT, spread, 0.0, TAU, 24, Color(LAVENDER, fade), 3.0, true)
	draw_circle(VISUAL_HEIGHT, 9.0, Color(PALE_GOLD, fade), true, -1.0, true)
	for spark in range(4):
		var direction := Vector2.from_angle(spark * TAU / 4.0 + 0.45)
		var point := VISUAL_HEIGHT + direction * spread
		draw_line(point, point + direction * 6.0, Color(PALE_GOLD, fade), 2.5, true)
