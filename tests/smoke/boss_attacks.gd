extends SceneTree

const Boss = preload("res://features/bosses/ancient_grove_beast.gd")
const BossScene = preload("res://features/bosses/ancient_grove_beast.tscn")
const Player = preload("res://features/player/player.gd")
const PlayerScene = preload("res://features/player/player.tscn")
const MeadowScene = preload("res://features/levels/whispering_grove/grove_meadow.tscn")

var _world: Node2D
var _boss: Boss
var _player: Player
var _passed := 0
var _failed := 0
var _capture_dir := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	if not arguments.is_empty() and DisplayServer.get_name() != "headless":
		_capture_dir = arguments[0]
	await _test_intro_and_stomp()
	await _test_charge()
	await _test_phase_and_death()
	await _test_ability_compatibility()
	print("Boss attacks smoke: %d checks, %d failures" % [_passed + _failed, _failed])
	quit(0 if _failed == 0 else 1)


func _test_intro_and_stomp() -> void:
	_build_world(Vector2.ZERO, Vector2(92, 0))
	await _ticks(90)
	_check(_boss.attack_state == Boss.State.DORMANT and _boss.collision_layer == 0
		and not _boss.is_in_group(&"combat_enemies") and _player.health.current == 100,
		"During introduction the visible boss cannot attack or be targeted")
	_boss.start(_player)
	_check(_boss.phase == 1 and _boss.health.current == 550 and _boss.is_in_group(&"combat_enemies"),
		"Starting combat activates a full-health boss in phase one")
	var warned := await _until(Boss.State.STOMP_WARNING)
	_check(warned and _player.health.current == 100, "Stomp displays a warning before applying damage")
	await _capture("grove-stomp-warning")
	var position_before_pause := _boss.global_position
	paused = true
	await _ticks(55)
	_check(_boss.attack_state == Boss.State.STOMP_WARNING and _boss.global_position == position_before_pause
		and _player.health.current == 100, "Tree pause freezes the stomp warning without damage")
	paused = false
	var resolved := await _until(Boss.State.RECOVERY)
	_check(resolved and _player.health.current == 82, "An in-range stomp resolves once for 18 damage")
	await _ticks(12)
	_check(_player.health.current == 82, "Stomp recovery cannot damage the player again")

	_build_world(Vector2.ZERO, Vector2(92, 0))
	_boss.start(_player)
	await _until(Boss.State.STOMP_WARNING)
	_player.global_position = Vector2(-140, 130)
	resolved = await _until(Boss.State.RECOVERY)
	_check(resolved and _player.health.current == 100, "A player outside the marked circle avoids the stomp")


func _test_charge() -> void:
	_build_world(Vector2(-65, 0), Vector2(160, 0))
	_add_right_wall()
	_boss.start(_player)
	var warned := await _until(Boss.State.CHARGE_WARNING)
	_check(warned and _player.health.current == 100, "Charge shows a locked lane before rushing")
	await _capture("forest-charge-warning")
	var start := _boss.global_position
	_player.global_position = Vector2(158, 125)
	var charging := await _until(Boss.State.CHARGING)
	_check(charging and _boss.global_position.is_equal_approx(start),
		"The boss remains stationary until the charge warning finishes")
	var resolved := await _until(Boss.State.RECOVERY)
	_check(resolved and absf(_boss.global_position.y - start.y) < 0.25 and _player.health.current == 100,
		"Moving off the lane avoids the charge without causing retargeting")
	_check(_boss.global_position.x > start.x + 100.0 and _boss.global_position.x <= 211.0 - _boss.spawn_radius + 0.1,
		"A terrain-limited charge stops inside the arena")

	_build_world(Vector2(-65, 0), Vector2(160, 0))
	_boss.start(_player)
	await _until(Boss.State.CHARGE_WARNING)
	resolved = await _until(Boss.State.RECOVERY)
	_check(resolved and _player.health.current == 85, "A charge collision deals damage exactly once")
	await _ticks(12)
	_check(_player.health.current == 85, "Charge recovery does not reapply collision damage")

	_build_world(Vector2(170.0, 0.0), Vector2(193.0, 76.0))
	_add_right_wall()
	_boss.definition = _boss.definition.duplicate()
	_boss.definition.first_attack_delay = 0.04
	_boss.set("_prefer_stomp", false)
	_boss.start(_player)
	warned = await _until(Boss.State.STOMP_WARNING, 30)
	_check(warned, "A blocked charge changes to the in-range stomp instead of running into a wall")


func _test_phase_and_death() -> void:
	_build_world(Vector2.ZERO, Vector2(92, 0))
	var phases: Array[int] = []
	var defeats: Array[int] = []
	_boss.phase_changed.connect(func(phase: int) -> void: phases.append(phase))
	_boss.defeated.connect(func() -> void: defeats.append(1))
	_boss.start(_player)
	await _until(Boss.State.STOMP_WARNING)
	_boss.health.damage(274)
	_check(_boss.phase == 1 and phases.is_empty(), "Boss stays in phase one above half health")
	_boss.health.damage(1)
	_check(_boss.phase == 2 and phases == [2] and _boss.attack_state == Boss.State.TRANSFORM,
		"The exact half-health hit interrupts an attack and transforms once")
	await _capture("guardian-transformation")
	_boss.health.heal(10)
	_boss.health.damage(12)
	_check(phases == [2] and _boss.effective_move_speed() > _boss.definition.move_speed,
		"Crossing half health again does not repeat the phase or reset its speed")
	await _ticks(52)
	_check(_boss.attack_state == Boss.State.CHASE and _player.health.current == 100,
		"The canceled stomp cannot deal damage after the transformation")
	_boss.health.damage(1000)
	_boss.health.damage(1000)
	_check(_boss.attack_state == Boss.State.DEFEATED and not _boss.is_in_group(&"combat_enemies")
		and _boss.collision_layer == 0 and defeats.is_empty(),
		"Lethal damage immediately disables combat before the defeat animation")
	await _ticks(32)
	_check(defeats == [1] and not is_instance_valid(_boss) and _player.health.current == 100,
		"Boss defeat emits once after its animation and frees the actor")


func _test_ability_compatibility() -> void:
	_build_world(Vector2.ZERO, Vector2(94, 0))
	_player.abilities.apply_upgrade(&"frost_touch")
	var attack := _player.get_node("BasicAttack")
	attack.set("projectile_parent", _world)
	attack.set_physics_process(true)
	_boss.start(_player)
	await _ticks(25)
	_check(_boss.health.current == 540, "Arcane Bolt selects and damages the boss using shared combat")
	_check(is_equal_approx(_boss.effective_move_speed(), 44.0), "Frost Touch slows the boss through the existing status")
	attack.set_physics_process(false)
	_player.abilities.apply_upgrade(&"flame_aura")
	await _ticks(3)
	_check(_boss.health.current <= 536, "Flame Aura applies its area damage to the boss")
	_player.abilities.apply_upgrade(&"iron_guard")
	await _until(Boss.State.STOMP_WARNING)
	var resolved := await _until(Boss.State.RECOVERY)
	_check(resolved and _player.health.current == 83, "Iron Guard reduces damage from a boss stomp")


func _build_world(boss_position: Vector2, player_position: Vector2) -> void:
	if is_instance_valid(_world):
		_world.free()
	_world = Node2D.new()
	root.add_child(_world)
	if not _capture_dir.is_empty():
		_world.add_child(MeadowScene.instantiate())
		_world.add_child(Camera2D.new())
	_player = PlayerScene.instantiate() as Player
	_player.position = player_position
	_world.add_child(_player)
	_player.get_node("BasicAttack").set_physics_process(false)
	_boss = BossScene.instantiate() as Boss
	_boss.position = boss_position
	_world.add_child(_boss)


func _add_right_wall() -> void:
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	wall.position = Vector2(221, 0)
	var shape := RectangleShape2D.new()
	shape.size = Vector2(20, 600)
	var collider := CollisionShape2D.new()
	collider.shape = shape
	wall.add_child(collider)
	_world.add_child(wall)


func _until(state: Boss.State, limit: int = 240) -> bool:
	for index in range(limit):
		if not is_instance_valid(_boss):
			return false
		if _boss.attack_state == state:
			return true
		await physics_frame
	return false


func _ticks(count: int) -> void:
	for index in range(count):
		await physics_frame


func _capture(name: String) -> void:
	if _capture_dir.is_empty():
		return
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and image.save_png(_capture_dir.path_join(name + ".png")) == OK, "Captured " + name)


func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		printerr("Boss attacks check failed: " + label)
