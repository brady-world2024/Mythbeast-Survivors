extends SceneTree

const LevelDefinition = preload("res://data/definitions/level_definition.gd")
const EnemyActor = preload("res://features/enemies/enemy_actor.gd")
const WaveDefinition = preload("res://data/definitions/wave_definition.gd")
const SpawnEntry = preload("res://data/definitions/enemy_spawn_entry.gd")
const WaveSpawner = preload("res://features/enemies/wave_spawner.gd")
const Player = preload("res://features/player/player.gd")
const PLAYER_SCENE = preload("res://features/player/player.tscn")
const LEVEL: LevelDefinition = preload("res://data/levels/whispering_grove.tres")

var _world := Node2D.new()
var _hero: Player
var _spawner: WaveSpawner
var _spawned: Array[EnemyActor] = []
var _checks: int
var _failures: int
var _death_events: int


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_definitions()
	await _check_placement()
	print("Wave data smoke: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check_definitions() -> void:
	var wave_ids: Array[StringName] = []
	for time in [0.0, 60.0, 120.0]:
		wave_ids.append(LEVEL.wave_at(time).id)
	_check(wave_ids == [&"forest_awakening", &"the_hunt_begins", &"grove_under_siege"],
		"Three distinct wave records begin at 0, 60 and 120 seconds")
	_check(LEVEL.wave_index_at(59.99) == 0 and LEVEL.wave_index_at(119.99) == 1
		and LEVEL.wave_index_at(179.99) == 2 and LEVEL.wave_at(180.0) == null,
		"Wave intervals end exclusively and stop at the survival limit")
	_check(LEVEL.environment_scene != null and LEVEL.boss_scene != null,
		"The level definition resolves its environment and Boss scenes")
	_check(LEVEL.waves[0].max_active == 12 and LEVEL.waves[1].max_active == 20
		and LEVEL.waves[2].max_active == 28 and LEVEL.waves[0].spawn_interval > LEVEL.waves[1].spawn_interval
		and LEVEL.waves[1].spawn_interval > LEVEL.waves[2].spawn_interval,
		"The authored caps and cadence increase pressure across waves")

	var expected_weights := [[1], [65, 35], [45, 35, 20]]
	for index in LEVEL.waves.size():
		var actual_weights: Array[int] = []
		for entry in LEVEL.waves[index].entries:
			if entry != null and entry.is_spawnable():
				actual_weights.append(entry.weight)
		_check(actual_weights == expected_weights[index], "Wave %d has valid weighted enemy entries" % (index + 1))

	var first := RandomNumberGenerator.new()
	var second := RandomNumberGenerator.new()
	first.seed = 733
	second.seed = 733
	var wave := LEVEL.waves[2]
	var counts := {}
	var reproducible := true
	for attempt in 600:
		var entry := wave.pick_entry(first)
		reproducible = reproducible and entry == wave.pick_entry(second)
		counts[entry.weight] = counts.get(entry.weight, 0) + 1
	_check(reproducible and counts.size() == 3, "A fixed seed reproduces the full mixed wave sequence")
	_check(counts[45] > counts[35] and counts[35] > counts[20], "Seeded samples favor entries with larger weights")

	var invalid_wave := WaveDefinition.new()
	var missing_scene := SpawnEntry.new()
	invalid_wave.entries = [null, missing_scene, wave.entries[0]]
	_check(invalid_wave.pick_entry(first) == wave.entries[0], "An invalid scene cannot consume a weighted roll")


func _check_placement() -> void:
	root.add_child(_world)
	_hero = PLAYER_SCENE.instantiate() as Player
	_hero.position = LEVEL.player_start
	_world.add_child(_hero)
	_spawner = WaveSpawner.new()
	_world.add_child(_spawner)
	_spawner.spawned.connect(_on_spawned)
	_spawner.use_wave(LEVEL.waves[2])
	_spawner.spawn_interval = 0.06
	_spawner.max_active = 4
	_spawner.spawn_seed = 37

	var obstacle := StaticBody2D.new()
	obstacle.position = Vector2(130, 40)
	obstacle.collision_layer = 1
	var obstacle_collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 60.0
	obstacle_collision.shape = shape
	obstacle.add_child(obstacle_collision)
	_world.add_child(obstacle)
	await physics_frame

	_spawner.start(_hero, _world, Rect2(-25, -25, 50, 50))
	await _ticks(20)
	_check(_spawned.is_empty() and _spawner.active_count() == 0, "Blocked placement leaves the active count unchanged")

	_spawner.start(_hero, _world, LEVEL.arena_bounds)
	await _ticks(120)
	var safely_placed := true
	var scaled_without_mutation := true
	for enemy in _spawned:
		var center := enemy.global_position
		safely_placed = (safely_placed and LEVEL.arena_bounds.grow(-24.0).has_point(center)
			and center.distance_to(_hero.global_position) >= _spawner.minimum_spawn_distance
			and center.distance_to(obstacle.global_position) > shape.radius + 23.5)
		scaled_without_mutation = (scaled_without_mutation
			and enemy.health.maximum == roundi(enemy.definition.max_health * LEVEL.waves[2].health_multiplier))
	_check(_spawned.size() == 4 and _spawner.active_count() == 4, "Mixed enemy spawning reaches its cap without overspawning")
	_check(safely_placed, "Spawned enemies avoid the player, walls, and a blocking obstacle")
	_check(scaled_without_mutation, "Wave health scaling applies to scene instances at spawn")

	if not _spawned.is_empty():
		_spawned[0].health.damage(1000)
		_check(_spawner.active_count() == 3 and _death_events == 1, "One enemy death releases exactly one spawn slot")
	_spawner.stop()
	_spawner.clear_enemies()
	await _ticks(4)
	_check(_spawner.active_count() == 0 and _death_events == 1,
		"Administrative wave cleanup clears actors without combat deaths")
	_check(not _spawner.is_spawning(), "A stopped wave does not schedule replacements")


func _on_spawned(enemy: EnemyActor) -> void:
	_spawned.append(enemy)
	enemy.set_physics_process(false)
	enemy.health.depleted.connect(func() -> void: _death_events += 1)


func _ticks(count: int) -> void:
	for tick in count:
		await physics_frame


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
