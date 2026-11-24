extends SceneTree

const HEALTH := preload("res://features/combat/health.gd")
const SLIME_SCENE := "res://features/enemies/forest_slime.tscn"
const BOLT_SCENE := "res://features/combat/arcane_bolt.tscn"

var _app: Node
var _arena: Node2D
var _hero: CharacterBody2D
var _spawner: Node
var _effects: Node2D
var _checks := 0
var _failures := 0
var _capture_dir := ""
var _spawns := 0
var _safe_spawns := true


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	var gate := not arguments.is_empty() and arguments[0] == "--gate"
	if not gate and not arguments.is_empty():
		_capture_dir = arguments[0]
	var app_scene := load(str(ProjectSettings.get_setting("application/run/main_scene"))) as PackedScene
	_app = app_scene.instantiate()
	root.add_child(_app)
	await process_frame
	_press(_button(_active_screen(), "Play"))
	await _settle()
	_bind_arena()
	var has_bolt := _check(ResourceLoader.exists(BOLT_SCENE), "Arcane Bolt has a projectile scene")
	var has_spawner := _check(_spawner != null, "The grove has an encounter spawner")
	var has_retry := _check(_button(_arena, "TryAgain") != null, "Game Over supports a direct retry")
	var has_receiver := _check(_hero.has_method(&"receive_damage"), "The hero receives damage through a shared invulnerability window")
	if not (has_bolt and has_spawner and has_retry and has_receiver):
		_finish()
		return

	await _check_weapon(gate)
	if not gate:
		await _check_health()
		await _check_lifetime()
		await _check_spawn_cap()
	await _check_game_over_and_retry(gate)
	_finish()


func _bind_arena() -> void:
	_arena = _active_screen() as Node2D
	_hero = _arena.get_node("%Player") as CharacterBody2D
	_spawner = _arena.get_node_or_null("%WaveSpawner")
	_effects = _arena.get_node_or_null("%Effects") as Node2D


func _active_screen() -> Node:
	return _app.get_node("ScreenHost").get_child(0)


func _button(screen: Node, button_name: String) -> Button:
	return screen.find_child(button_name, true, false) as Button


func _press(button: Button) -> void:
	if _capture_dir.is_empty():
		button.pressed.emit()
		return
	var position := button.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = position
		click.global_position = position
		click.pressed = pressed
		root.push_input(click, true)


func _check_weapon(gate: bool) -> void:
	await _clear_field()
	# The opening spawn may have triggered a shot before the fixture took over.
	await _ticks(ceili(float(_weapon_definition().get("attack_interval")) * Engine.physics_ticks_per_second) + 1)
	var weapon := _hero.get_node("BasicAttack")
	weapon.set_physics_process(false)
	var chaser := _enemy_at(Vector2(0, 280), true)
	var initial_y := chaser.global_position.y
	await _ticks(12)
	_check(chaser.global_position.y < initial_y - 8.0, "Forest Slime pursues the hero")
	if not gate:
		chaser.set_physics_process(false)
		chaser.global_position = _hero.global_position + Vector2(0, 260)
		weapon.set_physics_process(true)
		await _ticks(5)
		_check(_bolts().is_empty(), "The weapon ignores targets outside range")
		weapon.set_physics_process(false)
	chaser.queue_free()
	await _settle()

	var near_enemy := _enemy_at(Vector2(126, 0))
	var far_enemy := _enemy_at(Vector2(-168, 0))
	var near_health := near_enemy.get_node("Health")
	var far_health := far_enemy.get_node("Health")
	var near_start := int(near_health.get("current"))
	var far_start := int(far_health.get("current"))
	var damage := int(_weapon_definition().get("damage"))
	var damage_events: Array[int] = []
	near_health.connect("damaged", func(amount: int) -> void: damage_events.append(amount))
	weapon.set_physics_process(true)
	var bolt := await _wait_for_bolt()
	if not _check(bolt != null and int(near_health.get("current")) == near_start, "The bolt flies before dealing damage"):
		return
	var fired_at := bolt.global_position
	await _ticks(2)
	_check(is_instance_valid(bolt) and bolt.global_position.x > fired_at.x, "The shot travels toward the nearer enemy")
	await _ticks(4)
	await _capture("arcane-bolt")

	if not gate and is_instance_valid(bolt) and _bolts().has(bolt):
		_press(_button(_arena, "PauseButton"))
		var paused_at := bolt.global_position
		await _ticks(8)
		_check(paused and bolt.global_position == paused_at, "Pause freezes a bolt in flight")
		_press(_button(_arena, "Resume"))

	for tick in range(20):
		if not _bolts().has(bolt):
			break
		await physics_frame
	_check(
		int(near_health.get("current")) == near_start - damage
		and int(far_health.get("current")) == far_start
		and damage_events == [damage] and _bolts().is_empty(),
		"One impact hits only the nearest enemy exactly once and consumes the bolt"
	)
	if not gate:
		await _capture("slime-hit")
		await _ticks(13)
		_check(not is_instance_valid(bolt) and damage_events == [damage], "Impact releases the projectile without dealing damage again")
		_check(_bolts().is_empty(), "Cooldown prevents an early second shot")
		var deaths: Array[int] = []
		near_health.connect("depleted", func() -> void: deaths.append(1))
		near_health.call("damage", near_start)
		near_health.call("damage", 100)
		_check(deaths.size() == 1 and not _enemies().has(near_enemy), "A defeated slime leaves targeting and emits death once")
		await _ticks(56)
		_check(int(far_health.get("current")) == far_start - damage, "The weapon retargets a surviving enemy after cooldown")
		_check(not is_instance_valid(near_enemy), "A defeated slime is released after its animation")


func _check_health() -> void:
	await _clear_field()
	var sample := HEALTH.new()
	sample.configure(30)
	sample.damage(-5)
	_check(sample.current == 30, "Nonpositive damage has no effect")
	sample.damage(5)
	sample.call("heal", 10)
	_check(sample.current == 30, "Healing caps at maximum health")
	sample.damage(50)
	sample.call("heal", 20)
	_check(sample.current == 0, "Health clamps at zero and healing does not revive")
	sample.free()

	_hero.get_node("BasicAttack").set_physics_process(false)
	var hero_health := _hero.get_node("Health")
	var starting_hp := int(hero_health.get("current"))
	var left := _enemy_at(Vector2(-37, 0), true)
	var right := _enemy_at(Vector2(37, 0), true)
	await _ticks(4)
	var current_hp := int(hero_health.get("current"))
	var hud := _arena.get_node("%HUD")
	var bar := hud.get_node("%Health") as ProgressBar
	var label := hud.get_node("%HealthCaption") as Label
	_check(current_hp == starting_hp - 8, "Two simultaneous slime contacts apply only one hit")
	_check(is_instance_valid(bar) and int(bar.value) == current_hp and label.text.ends_with("%d / %d" % [
		current_hp, int(hero_health.get("maximum"))
	]), "The HUD reflects damage immediately")
	_check(not bool(_hero.call("receive_damage", 8)), "A second hit is ignored within the invulnerability window")
	left.queue_free()
	right.queue_free()
	await _ticks(29)
	_check(bool(_hero.call("receive_damage", 8)), "The hero can take damage after the invulnerability window")
	var contact := _enemy_at(Vector2(38, 0), true)
	await _ticks(29)
	var blocked_contact := int(hero_health.get("current"))
	await _ticks(12)
	_check(int(hero_health.get("current")) == blocked_contact, "A slime waits for its own contact cooldown")
	await _ticks(20)
	_check(int(hero_health.get("current")) == blocked_contact - 8, "A slime hits again after its contact cooldown")
	contact.queue_free()
	await _settle()


func _check_lifetime() -> void:
	await _clear_field()
	var projectile_scene := load(BOLT_SCENE) as PackedScene
	var definition := _weapon_definition().duplicate()
	definition.set("projectile_speed", 100.0)
	definition.set("projectile_lifetime", 0.25)
	var former_target := _enemy_at(Vector2(120, 0))
	var empty_bolt := projectile_scene.instantiate() as Node2D
	_effects.add_child(empty_bolt)
	empty_bolt.call("launch", _hero.global_position, Vector2.RIGHT, definition)
	former_target.queue_free()
	await _ticks(5)
	_check(is_instance_valid(empty_bolt) and _bolts().has(empty_bolt), "A shot survives removal of its intended target")
	await _ticks(17)
	_check(not is_instance_valid(empty_bolt), "A missed bolt expires and frees its node")

	var wall_bolt := projectile_scene.instantiate() as Node2D
	_effects.add_child(wall_bolt)
	wall_bolt.call("launch", Vector2(194, 25), Vector2.RIGHT, _weapon_definition())
	await _ticks(5)
	_check(not _bolts().has(wall_bolt), "The arena boundary stops a projectile")
	await _ticks(13)
	_check(not is_instance_valid(wall_bolt), "A projectile hitting the wall is released")


func _check_spawn_cap() -> void:
	await _clear_field()
	_hero.get_node("BasicAttack").set_physics_process(false)
	_spawns = 0
	_safe_spawns = true
	_spawner.set("max_active", 8)
	_spawner.connect("spawned", _record_spawn)
	_begin_spawns(0.10, 11)
	await _ticks(75)
	_check(_spawns == 8 and _enemies().size() == 8, "Spawner reaches eight live enemies and stays at the cap")
	_check(_safe_spawns, "Spawn centers stay inside the bounds, clear of existing actors and away from the hero")
	_spawner.disconnect("spawned", _record_spawn)
	await _clear_field()


func _record_spawn(enemy: Node2D) -> void:
	_spawns += 1
	var position := enemy.global_position
	_safe_spawns = (
		_safe_spawns and _spawn_bounds().grow(-19).has_point(position)
		and position.distance_to(_hero.global_position) >= float(_spawner.get("minimum_spawn_distance"))
	)
	for other in _enemies():
		if other != enemy and (other as Node2D).global_position.distance_to(position) < 37.9:
			_safe_spawns = false
	enemy.set_physics_process(false)


func _check_game_over_and_retry(gate: bool) -> void:
	await _clear_field()
	# Progression has its own integration suite. Keep this case on baseline combat.
	_arena.get_node("%Progression").set("max_level", 1)
	var health := _hero.get_node("Health")
	health.call("configure", int(health.get("maximum")))
	_hero.get_node("BasicAttack").set_physics_process(true)
	_begin_spawns(0.14 if gate or not _capture_dir.is_empty() else 2.0, 21)
	var deaths: Array[int] = []
	health.connect("depleted", func() -> void: deaths.append(1))
	var tick_limit := 960 if gate or not _capture_dir.is_empty() else 7200
	for tick in range(tick_limit):
		if paused:
			break
		await physics_frame
	var retry := _button(_arena, "TryAgain")
	var heading := _arena.find_child("GameOverHeading", true, false) as Label
	var reached_game_over := (
		paused and int(health.get("current")) == 0 and deaths.size() == 1
		and retry.is_visible_in_tree() and heading.text == "Game Over"
		and not bool(_spawner.call("is_spawning"))
	)
	if not _check(reached_game_over, "Enemy contact defeats the player, stops spawning and opens Game Over"):
		return
	var old_arena := _arena
	var old_hero := _hero
	var old_effects := _effects
	var old_spawner := _spawner
	if not gate:
		var frozen_hero := _hero.global_position
		var enemy := _enemies().front() as Node2D
		var frozen_enemy := enemy.global_position
		_hero.set("move_direction", Vector2.RIGHT)
		_hero.call("receive_damage", 100)
		_button(_arena, "Resume").pressed.emit()
		await _ticks(10)
		_check(
			paused and _hero.global_position == frozen_hero and enemy.global_position == frozen_enemy
			and int(health.get("current")) == 0 and deaths.size() == 1,
			"Defeat prevents movement, enemy AI, duplicate death and Resume"
		)
	await _capture("game-over")
	_press(retry)
	if _capture_dir.is_empty():
		_press(retry)
	await _settle()
	_bind_arena()
	var new_health := _hero.get_node("Health")
	_check(
		not paused and not is_instance_valid(old_arena) and not is_instance_valid(old_hero)
		and not is_instance_valid(old_effects) and not is_instance_valid(old_spawner)
		and int(new_health.get("current")) == int(new_health.get("maximum"))
		and _effects.get_child_count() == 0 and bool(_spawner.call("is_spawning"))
		and _app.get_node("ScreenHost").get_child_count() == 1,
		"Try Again replaces the entire run with one fresh, full-health arena"
	)
	await _capture("retry")
	if not gate:
		await _ticks(6)
		_check(_enemies().size() == 1, "A fresh run starts exactly one spawner")
		_hero.call("receive_damage", 100)
		await _settle()
		_press(_button(_arena, "MainMenu"))
		await _settle()
		_check(not paused and _active_screen().name == &"MainMenu", "Game Over Main Menu leaves the run")


func _begin_spawns(interval: float, spawn_seed: int) -> void:
	_spawner.set("spawn_interval", interval)
	_spawner.set("spawn_seed", spawn_seed)
	_spawner.call("start", _hero, _hero.get_parent(), _spawn_bounds())


func _spawn_bounds() -> Rect2:
	var bounds := _arena.get_node("World/ArenaBounds")
	var west := bounds.get_node("West") as Node2D
	var east := bounds.get_node("East") as Node2D
	var north := bounds.get_node("North") as Node2D
	var south := bounds.get_node("South") as Node2D
	return Rect2(west.global_position.x, north.global_position.y,
		east.global_position.x - west.global_position.x, south.global_position.y - north.global_position.y)


func _enemy_at(offset: Vector2, chasing := false) -> CharacterBody2D:
	var scene := load(SLIME_SCENE) as PackedScene
	var enemy := scene.instantiate() as CharacterBody2D
	enemy.position = _hero.position + offset
	enemy.set("target", _hero)
	_hero.get_parent().add_child(enemy)
	enemy.set_physics_process(chasing)
	return enemy


func _clear_field() -> void:
	_spawner.call("stop")
	for enemy in _enemies():
		enemy.queue_free()
	for effect in _effects.get_children():
		effect.queue_free()
	await _settle()


func _enemies() -> Array[Node]:
	return get_nodes_in_group(&"combat_enemies")


func _bolts() -> Array[Node]:
	return get_nodes_in_group(&"arcane_bolts")


func _weapon_definition() -> Resource:
	var character := _hero.get("definition") as Resource
	return character.get("starting_weapon") as Resource


func _wait_for_bolt() -> Node2D:
	for tick in range(12):
		if not _bolts().is_empty():
			return _bolts().front() as Node2D
		await physics_frame
	return null


func _settle() -> void:
	await process_frame
	await process_frame


func _ticks(count: int) -> void:
	for index in range(count):
		await physics_frame


func _capture(capture_name: String) -> void:
	if _capture_dir.is_empty():
		return
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and image.save_png(_capture_dir.path_join(capture_name + ".png")) == OK,
		"Captured " + capture_name)


func _check(condition: bool, message: String) -> bool:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
	return condition


func _finish() -> void:
	paused = false
	print("Combat smoke: %d checks, %d failures" % [_checks, _failures])
	_app.call(&"request_quit", 0 if _failures == 0 else 1)
