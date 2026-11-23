extends Node2D
## Replenishes the combat test arena while the player is alive.

const ForestSlime = preload("res://features/enemies/forest_slime.gd")
const Player = preload("res://features/player/player.gd")
const SLIME_SCENE = preload("res://features/enemies/forest_slime.tscn")

signal spawned(enemy: ForestSlime)

const PLACEMENT_ATTEMPTS := 16
const SPAWN_CLEARANCE := 24.0
const SPAWN_COLLISION_MASK := 1 | 2 | 4 # World, Player, and Enemy.

@export_range(0.1, 30.0, 0.1) var spawn_interval := 2.0
@export_range(1, 24) var max_active := 8
@export_range(40.0, 400.0, 1.0) var minimum_spawn_distance := 135.0
@export var spawn_seed := 0

var _player: Player
var _entities: Node2D
var _spawn_bounds := Rect2()
var _time_until_spawn := 0.0
var _random := RandomNumberGenerator.new()
var _active: Array[ForestSlime] = []
var _query := PhysicsShapeQueryParameters2D.new()


func _ready() -> void:
	var clearance := CircleShape2D.new()
	clearance.radius = SPAWN_CLEARANCE
	_query.shape = clearance
	_query.collision_mask = SPAWN_COLLISION_MASK
	set_physics_process(false)


func start(player: Player, entities: Node2D, spawn_bounds: Rect2) -> void:
	_player = player
	_entities = entities
	_spawn_bounds = spawn_bounds.grow(-SPAWN_CLEARANCE)
	_time_until_spawn = 0.0
	if spawn_seed == 0:
		_random.randomize()
	else:
		_random.seed = spawn_seed
	set_physics_process(true)


func stop() -> void:
	set_physics_process(false)


func is_spawning() -> bool:
	return is_physics_processing()


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_player) or not _player.health.is_alive() or not is_instance_valid(_entities):
		stop()
		return

	_time_until_spawn -= delta
	if _time_until_spawn > 0.0:
		return
	_time_until_spawn = spawn_interval

	for index in range(_active.size() - 1, -1, -1):
		var slime := _active[index]
		if not is_instance_valid(slime) or slime.is_queued_for_deletion() or not slime.health.is_alive():
			_active.remove_at(index)
	if _active.size() >= max_active or not _spawn_bounds.has_area():
		return

	var space := get_world_2d().direct_space_state
	var minimum_distance_squared := minimum_spawn_distance * minimum_spawn_distance
	for attempt in range(PLACEMENT_ATTEMPTS):
		var candidate := Vector2(
			_random.randf_range(_spawn_bounds.position.x, _spawn_bounds.end.x),
			_random.randf_range(_spawn_bounds.position.y, _spawn_bounds.end.y)
		)
		if _player.global_position.distance_squared_to(candidate) < minimum_distance_squared:
			continue
		_query.transform = Transform2D(0.0, candidate)
		if not space.intersect_shape(_query, 1).is_empty():
			continue
		var enemy := SLIME_SCENE.instantiate() as ForestSlime
		enemy.position = _entities.to_local(candidate)
		enemy.target = _player
		_entities.add_child(enemy)
		_active.append(enemy)
		spawned.emit(enemy)
		return
