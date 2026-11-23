extends Node2D

const Player = preload("res://features/player/player.gd")
const Health = preload("res://features/combat/health.gd")

@onready var _player := get_parent() as Player

var projectile_parent: Node2D

var _cooldown_remaining := 0.0


func _physics_process(delta: float) -> void:
	_cooldown_remaining = move_toward(_cooldown_remaining, 0.0, delta)
	if _cooldown_remaining > 0.0 or not _player.health.is_alive() or not is_instance_valid(projectile_parent):
		return
	var weapon := _player.definition.starting_weapon
	if weapon == null or weapon.projectile_scene == null:
		return

	var target := _nearest_enemy(weapon.attack_range)
	if target == null:
		return

	var projectile := weapon.projectile_scene.instantiate()
	if not projectile is Node2D or not projectile.has_method(&"launch"):
		projectile.free()
		set_physics_process(false)
		push_error("The starting weapon needs a 2D projectile scene with a launch method.")
		return
	var origin := _player.global_position
	var direction := origin.direction_to(target.global_position)
	projectile_parent.add_child(projectile)
	projectile.call(&"launch", origin, direction, weapon)
	_cooldown_remaining = weapon.attack_interval
	_player.play_cast()


func _nearest_enemy(attack_range: float) -> Node2D:
	var nearest: Node2D
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
			nearest = enemy
			nearest_distance_squared = distance_squared
	return nearest
