extends Node2D
## Places weighted wave enemies within the current arena and its live cap.

const EnemyActor = preload("res://features/enemies/enemy_actor.gd")
const Player = preload("res://features/player/player.gd")
const WaveDefinition = preload("res://data/definitions/wave_definition.gd")
const DifficultyDefinition = preload("res://data/definitions/difficulty_definition.gd")

signal spawned(enemy: EnemyActor)

const PLACEMENT_ATTEMPTS := 16
const LOCAL_ATTEMPTS := 12
const VIEW_SPAWN_MARGIN := 96.0
const SPAWN_COLLISION_MASK := 1 | 2 | 4 # World, Player, and Enemy.

var spawn_interval: float = 1.8
var max_active: int = 12
@export_range(40.0, 400.0, 1.0) var minimum_spawn_distance: float = 135.0
@export var spawn_seed: int = 0
var difficulty: DifficultyDefinition

var _wave: WaveDefinition
var _player: Player
var _entities: Node2D
var _spawn_bounds := Rect2()
var _time_until_spawn := 0.0
var _random := RandomNumberGenerator.new()
var _active: Array[EnemyActor] = []
var _clearance := CircleShape2D.new()
var _query := PhysicsShapeQueryParameters2D.new()


func _ready() -> void:
	_query.shape = _clearance
	_query.collision_mask = SPAWN_COLLISION_MASK
	set_physics_process(false)


func use_wave(wave: WaveDefinition) -> void:
	if wave == _wave:
		return
	_wave = wave
	if _wave == null:
		stop()
		return
	spawn_interval = _wave.spawn_interval * (difficulty.spawn_interval_multiplier if difficulty != null else 1.0)
	max_active = _wave.max_active
	_time_until_spawn = minf(_time_until_spawn, spawn_interval)


func start(player: Player, entities: Node2D, spawn_bounds: Rect2) -> void:
	_player = player
	_entities = entities
	_spawn_bounds = spawn_bounds
	_time_until_spawn = 0.0
	if spawn_seed == 0:
		_random.randomize()
	else:
		_random.seed = spawn_seed
	set_physics_process(_wave != null)


func stop() -> void:
	set_physics_process(false)


func is_spawning() -> bool:
	return is_physics_processing()


func active_count() -> int:
	for index in range(_active.size() - 1, -1, -1):
		var enemy := _active[index]
		if not is_instance_valid(enemy) or enemy.is_queued_for_deletion() or not enemy.health.is_alive():
			_active.remove_at(index)
	return _active.size()


func clear_enemies() -> void:
	for enemy in _active:
		if is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
			enemy.dismiss()
	_active.clear()


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_player) or not _player.health.is_alive() or not is_instance_valid(_entities):
		stop()
		return

	_time_until_spawn -= delta
	if _time_until_spawn > 0.0:
		return
	_time_until_spawn = maxf(0.05, spawn_interval)
	if active_count() >= max_active:
		return

	var entry := _wave.pick_entry(_random)
	if entry == null:
		return
	var position_in_world := _find_spawn_position(entry.clearance_radius)
	if not position_in_world.is_finite():
		return

	var instance := entry.enemy_scene.instantiate()
	var enemy := instance as EnemyActor
	if enemy == null:
		instance.free()
		push_error("Wave enemy scenes must use EnemyActor.")
		return
	enemy.position = _entities.to_local(position_in_world)
	enemy.target = _player
	var hp_scale := difficulty.enemy_hp_multiplier if difficulty != null else 1.0
	var speed_scale := difficulty.enemy_speed_multiplier if difficulty != null else 1.0
	var damage_scale := difficulty.enemy_damage_multiplier if difficulty != null else 1.0
	enemy.configure_spawn(_wave.health_multiplier * hp_scale, _wave.speed_multiplier * speed_scale,
		_wave.damage_multiplier * damage_scale)
	_entities.add_child(enemy)
	_active.append(enemy)
	spawned.emit(enemy)


func _find_spawn_position(clearance_radius: float) -> Vector2:
	var radius := maxf(1.0, clearance_radius)
	if _spawn_bounds.size.x <= radius * 2.0 or _spawn_bounds.size.y <= radius * 2.0:
		return Vector2.INF
	var bounds := _spawn_bounds.grow(-radius)
	var view := get_canvas_transform().affine_inverse() * get_viewport_rect()
	var nearby := bounds.intersection(view.grow(VIEW_SPAWN_MARGIN))
	var visible_footprint := view.grow(radius)
	var seek_offscreen := nearby.has_area() and not visible_footprint.encloses(nearby)
	var valid_visible_fallback := Vector2.INF
	var space := get_world_2d().direct_space_state
	var minimum_distance_squared := minimum_spawn_distance * minimum_spawn_distance
	_clearance.radius = radius

	for attempt in PLACEMENT_ATTEMPTS:
		var search := nearby if nearby.has_area() and attempt < LOCAL_ATTEMPTS else bounds
		var candidate := Vector2(
			_random.randf_range(search.position.x, search.end.x),
			_random.randf_range(search.position.y, search.end.y)
		)
		if _player.global_position.distance_squared_to(candidate) < minimum_distance_squared:
			continue
		_query.transform = Transform2D(0.0, candidate)
		if not space.intersect_shape(_query, 1).is_empty():
			continue
		if not seek_offscreen or not visible_footprint.has_point(candidate):
			return candidate
		if not valid_visible_fallback.is_finite():
			valid_visible_fallback = candidate
	return valid_visible_fallback
