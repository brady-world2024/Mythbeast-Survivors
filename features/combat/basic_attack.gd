extends Node2D

const Player = preload("res://features/player/player.gd")
const Targets = preload("res://features/combat/combat_targets.gd")

@onready var _player := get_parent() as Player

var projectile_parent: Node2D

var _cooldown_fraction := 0.0


func _physics_process(delta: float) -> void:
	if not _player.health.is_alive() or not is_instance_valid(projectile_parent):
		return
	var weapon := _player.abilities.bolt
	if weapon == null or weapon.projectile_scene == null:
		return
	# A rank change adjusts the rate of a cooldown already in progress.
	_cooldown_fraction = move_toward(_cooldown_fraction, 0.0, delta / maxf(0.05, weapon.attack_interval))
	if _cooldown_fraction > 0.0:
		return

	var origin := _player.global_position
	var target := Targets.nearest(get_tree().get_nodes_in_group(&"combat_enemies"), origin, weapon.attack_range)
	if target == null:
		return

	var projectile := weapon.projectile_scene.instantiate()
	if not projectile is Node2D or not projectile.has_method(&"launch"):
		projectile.free()
		set_physics_process(false)
		push_error("The starting weapon needs a 2D projectile scene with a launch method.")
		return
	var direction := origin.direction_to(target.global_position)
	if projectile.has_signal(&"enemy_hit"):
		projectile.connect(&"enemy_hit", _player.abilities.on_bolt_hit)
	if projectile.has_method(&"set_visual_rank"):
		projectile.call(&"set_visual_rank", _player.abilities.rank_of(&"arcane_bolt"))
	projectile_parent.add_child(projectile)
	projectile.call(&"launch", origin, direction, weapon)
	_cooldown_fraction = 1.0
	_player.play_cast()
