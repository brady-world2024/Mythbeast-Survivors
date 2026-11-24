extends SceneTree

const EnemyActor = preload("res://features/enemies/enemy_actor.gd")
const Player = preload("res://features/player/player.gd")
const PLAYER_SCENE := preload("res://features/player/player.tscn")
const SLIME := preload("res://features/enemies/forest_slime.tscn")
const FANGLING := preload("res://features/enemies/swift_fangling.tscn")
const GOLEM := preload("res://features/enemies/moss_golem.tscn")
const MEADOW := preload("res://features/levels/whispering_grove/grove_meadow.tscn")
const FANGLING_WINDUP := 1
const FANGLING_RECOVERY := 3
const GOLEM_WINDUP := 1
const GOLEM_RECOVERY := 2

var _world := Node2D.new()
var _player: Player
var _checks := 0
var _failures := 0
var _capture_dir := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	if not arguments.is_empty():
		_capture_dir = arguments[0]
	_world.process_mode = Node.PROCESS_MODE_PAUSABLE
	root.add_child(_world)
	_world.add_child(MEADOW.instantiate())
	_world.add_child(Camera2D.new())
	_player = PLAYER_SCENE.instantiate() as Player
	_world.add_child(_player)
	_player.get_node("BasicAttack").set_physics_process(false)
	await _check_configs_and_chase()
	await _check_lunge()
	await _check_slam()
	await _check_shared_abilities()
	print("Enemy AI smoke: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check_configs_and_chase() -> void:
	var slime := _spawn(SLIME, Vector2(-162.0, 0.0))
	var fangling := _spawn(FANGLING, Vector2(160.0, 0.0))
	var golem := _spawn(GOLEM, Vector2(0.0, 180.0))
	_check(
		[slime.definition.xp_reward, fangling.definition.xp_reward, golem.definition.xp_reward] == [5, 7, 15]
		and [slime.health.maximum, fangling.health.maximum, golem.health.maximum] == [30, 20, 90],
		"The three enemy scenes use their authored XP and health",
	)
	await _ticks(12)
	_check(fangling.get_real_velocity().length() > slime.get_real_velocity().length()
		and slime.get_real_velocity().length() > golem.get_real_velocity().length(),
		"The Fangling, Slime, and Golem chase at distinct speeds")
	await _capture("ordinary-enemies")
	await _clear()
	var scaled := GOLEM.instantiate() as EnemyActor
	scaled.configure_spawn(1.25, 1.10, 1.05)
	_world.add_child(scaled)
	_check(scaled.health.maximum == 113 and is_equal_approx(scaled.effective_move_speed(), 55.0)
		and scaled.definition.max_health == 90, "Wave tuning remains local to one actor")
	var deaths: Array[int] = []
	scaled.health.depleted.connect(func() -> void: deaths.append(1))
	scaled.dismiss()
	await _ticks(2)
	_check(deaths.is_empty() and not is_instance_valid(scaled), "Administrative cleanup never emits a kill")


func _check_lunge() -> void:
	await _clear()
	var fangling := _spawn(FANGLING, Vector2(-100.0, 0.0))
	# Enable the first ready lunge without waiting through its spawn cooldown.
	fangling.set("_lunge_cooldown", 0.0)
	await _ticks(6)
	_check(fangling.get("_stage") == FANGLING_WINDUP and _player.health.current == 100,
		"The locked lunge shows a safe wind-up before damage")
	var windup := float(fangling.get("_stage_remaining"))
	paused = true
	await _ticks(11)
	_check(is_equal_approx(windup, float(fangling.get("_stage_remaining"))),
		"Pause freezes the Fangling wind-up")
	paused = false
	await _capture("fangling-warning")
	_player.position = Vector2(0.0, -85.0)
	for frame in range(64):
		if fangling.get("_stage") == FANGLING_RECOVERY:
			break
		await physics_frame
	_check(fangling.position.x > 0.0 and is_zero_approx(fangling.position.y)
		and _player.health.current == 100, "A sidestep avoids the fixed-direction lunge")
	await _clear()
	fangling = _spawn(FANGLING, Vector2(-94.0, 0.0))
	fangling.set("_lunge_cooldown", 0.0)
	await _ticks(69)
	_check(_player.health.current == 94 and float(fangling.get("_lunge_cooldown")) > 0.0,
		"A lunge hit deals six damage once and respects cooldown")


func _check_slam() -> void:
	await _clear()
	_player.health.heal(100)
	var golem := _spawn(GOLEM, Vector2(-65.0, 0.0))
	await _ticks(9)
	_check(golem.get("_stage") == GOLEM_WINDUP and _player.health.current == 100,
		"The slam announces a ground area without contact damage")
	await _capture("golem-warning")
	_player.position.y = -150.0
	for frame in range(50):
		if golem.get("_stage") == GOLEM_RECOVERY:
			break
		await physics_frame
	_check(_player.health.current == 100, "Leaving the slam radius avoids damage")
	await _clear()
	_player.abilities.apply_upgrade(&"iron_guard")
	golem = _spawn(GOLEM, Vector2(-60.0, 0.0))
	await _ticks(64)
	_check(_player.health.current == 87, "The slam uses Iron Guard and applies damage once")
	var deaths: Array[int] = []
	golem.health.depleted.connect(func() -> void: deaths.append(1))
	golem.health.damage(1000)
	golem.health.damage(1000)
	_check(not golem.is_in_group(&"combat_enemies") and deaths.size() == 1,
		"Death clears the target group immediately and emits once")
	await _ticks(120)
	_check(not is_instance_valid(golem) and _player.health.current == 87, "A dead Golem cannot attack")


func _check_shared_abilities() -> void:
	await _clear()
	var fangling := _spawn(FANGLING, Vector2(66.0, 0.0), false)
	var golem := _spawn(GOLEM, Vector2(113.0, -42.0), false)
	var slime := _spawn(SLIME, Vector2(20.0, 78.0), false)
	_player.abilities.apply_upgrade(&"chain_lightning")
	_player.abilities.apply_upgrade(&"frost_touch")
	_player.get_node("BasicAttack").set("projectile_parent", _world)
	_player.get_node("BasicAttack").set_physics_process(true)
	await _ticks(20)
	_player.get_node("BasicAttack").set_physics_process(false)
	_check(fangling.health.current == 10 and golem.health.current == 84 and slime.health.current == 24,
		"Arcane Bolt and Chain Lightning hit each of the three enemy types")
	fangling.health.heal(fangling.health.maximum)
	_player.abilities.on_bolt_hit(golem, golem.position, 10)
	_player.abilities.on_bolt_hit(slime, slime.position, 10)
	_check(is_equal_approx(fangling.effective_move_speed(), 112.0)
		and is_equal_approx(golem.effective_move_speed(), 40.0)
		and is_equal_approx(slime.effective_move_speed(), 64.0), "Frost Touch applies the shared slow to all enemies")
	await _clear()
	fangling = _spawn(FANGLING, Vector2(63.0, 0.0), false)
	golem = _spawn(GOLEM, Vector2(-65.0, 0.0), false)
	slime = _spawn(SLIME, Vector2(5.0, 66.0), false)
	_player.abilities.apply_upgrade(&"flame_aura")
	await _ticks(7)
	_check(fangling.health.current == 16 and golem.health.current == 86 and slime.health.current == 26,
		"Flame Aura applies one shared pulse across all three enemy types")


func _spawn(scene: PackedScene, position: Vector2, active := true) -> EnemyActor:
	var enemy := scene.instantiate() as EnemyActor
	enemy.position = position
	enemy.target = _player
	_world.add_child(enemy)
	enemy.set_physics_process(active)
	return enemy


func _clear() -> void:
	for candidate in get_nodes_in_group(&"combat_enemies"):
		(candidate as EnemyActor).dismiss()
	_player.position = Vector2.ZERO
	await _ticks(4)


func _ticks(count: int) -> void:
	for frame in range(count):
		await physics_frame


func _capture(capture_name: String) -> void:
	if _capture_dir.is_empty():
		return
	await RenderingServer.frame_post_draw
	var screenshot := root.get_texture().get_image()
	_check(screenshot != null and screenshot.save_png(_capture_dir.path_join(capture_name + ".png")) == OK,
		"Saved capture " + capture_name)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
