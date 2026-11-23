extends SceneTree

const PLAYER := preload("res://features/player/player.tscn")
const SLIME := preload("res://features/enemies/forest_slime.tscn")
const BACKDROP := preload("res://features/levels/whispering_grove/grove_meadow.tscn")
const Health = preload("res://features/combat/health.gd")

var _world: Node2D
var _player: CharacterBody2D
var _abilities: Node
var _capture_dir := ""
var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	if not arguments.is_empty():
		_capture_dir = arguments[0]
	_build_world()
	_check(_abilities != null, "Each player has independent ability ranks and effect state")
	if _abilities != null:
		await _check_ranks_and_passives()
		await _check_bolt_modifiers()
		await _check_aura()
	print("Abilities smoke: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _build_world(camera_position := Vector2.ZERO) -> void:
	if is_instance_valid(_world):
		_world.free()
	_world = Node2D.new()
	_world.process_mode = Node.PROCESS_MODE_PAUSABLE
	root.add_child(_world)
	if not _capture_dir.is_empty():
		_world.add_child(BACKDROP.instantiate())
		var camera := Camera2D.new()
		camera.position = camera_position
		_world.add_child(camera)
	_player = PLAYER.instantiate() as CharacterBody2D
	_world.add_child(_player)
	_abilities = _player.get_node_or_null("%Abilities")


func _check_ranks_and_passives() -> void:
	var definition := _player.get("definition") as Resource
	var base_speed := float(definition.get("move_speed"))
	var original_weapon := definition.get("starting_weapon") as Resource
	var bolt := _abilities.get("bolt") as Resource
	_check(_rank(&"arcane_bolt") == 1 and int(bolt.get("damage")) == 10, "Arcane Bolt is the only starting weapon")
	_check(_rank(&"chain_lightning") == 0 and _rank(&"flame_aura") == 0 and _rank(&"frost_touch") == 0
		and _rank(&"swift_steps") == 0 and _rank(&"iron_guard") == 0, "All five other abilities start outside the run build")
	_check(_upgrade(&"arcane_bolt"), "Arcane Bolt can gain its second rank")
	bolt = _abilities.get("bolt") as Resource
	_check(int(bolt.get("damage")) == 13 and is_equal_approx(float(bolt.get("attack_interval")), 0.7125),
		"Arcane Bolt rank two adds three damage and shortens the cooldown by five percent")
	_check(int(original_weapon.get("damage")) == 10 and is_equal_approx(float(original_weapon.get("attack_interval")), 0.75)
		and _player.find_children("BasicAttack", "Node2D").size() == 1, "Weapon tuning and its single controller remain intact")
	for rank in range(3):
		_upgrade(&"arcane_bolt")
	_check(_rank(&"arcane_bolt") == 5 and not _upgrade(&"arcane_bolt") and not _upgrade(&"unknown"),
		"Capped or unknown ranks cannot be applied")
	_check(_upgrade(&"swift_steps"), "Swift Steps is unlocked")
	_player.set("move_direction", Vector2(1.0, -1.0))
	await _ticks(5)
	_check(is_equal_approx(_player.velocity.length(), base_speed * 1.08),
		"Swift Steps raises real movement speed and preserves diagonal normalization")
	await _capture("swift-steps")
	_upgrade(&"swift_steps")
	_check(is_equal_approx(float(_player.call("effective_move_speed")), base_speed * 1.16),
		"Multiple Swift Steps ranks derive speed from the same base")
	_player.set("move_direction", Vector2.ZERO)
	_check(_upgrade(&"iron_guard"), "Iron Guard is unlocked")
	await _capture("iron-guard")
	var health := _health(_player)
	var before := health.current
	_check(bool(_player.call("receive_damage", 8)) and health.current == before - 7,
		"Iron Guard rank one rounds 8 incoming damage down to 7")
	_check(not bool(_player.call("receive_damage", 8)) and health.current == before - 7,
		"Iron Guard preserves the existing invulnerability window")
	await _ticks(29)
	_check(bool(_player.call("receive_damage", 8)) and health.current == before - 14,
		"Damage can resume after invulnerability expires")
	for rank in range(4):
		_upgrade(&"iron_guard")
	_check(int(_abilities.call("damage_after_guard", 100)) == 60
		and int(_abilities.call("damage_after_guard", 1)) == 1
		and int(_abilities.call("damage_after_guard", -5)) == 0,
		"Iron Guard respects the forty percent cap and never creates negative damage")
	var fresh_player := PLAYER.instantiate() as CharacterBody2D
	_world.add_child(fresh_player)
	_check(is_equal_approx(float(fresh_player.call("effective_move_speed")), base_speed)
		and int(fresh_player.get_node("%Abilities").call("rank_of", &"iron_guard")) == 0,
		"A fresh hero has baseline movement and no previous run defense")


func _check_bolt_modifiers() -> void:
	_build_world(Vector2(100.0, 0.0))
	_upgrade(&"arcane_bolt")
	_upgrade(&"chain_lightning")
	_upgrade(&"frost_touch")
	var primary := _spawn_slime(Vector2(120.0, 0.0))
	var second := _spawn_slime(Vector2(182.0, 34.0))
	var third := _spawn_slime(Vector2(252.0, 65.0))
	var fourth := _spawn_slime(Vector2(308.0, 94.0))
	var distant := _spawn_slime(Vector2(560.0, 80.0))
	var dead := _spawn_slime(Vector2(140.0, -29.0))
	_health(dead).damage(30)
	var controller := _player.get_node("BasicAttack")
	controller.set("projectile_parent", _world)
	await _ticks(19)
	controller.set_physics_process(false)
	_check(_health(primary).current == 17, "The real upgraded projectile deals thirteen damage once")
	_check(_health(second).current == 23 and _health(third).current == 23, "Lightning arcs to two valid nearby enemies at the configured ratio")
	_check(_health(fourth).current == 30 and _health(distant).current == 30,
		"The chain stops at its jump limit without recursing or damaging other enemies")
	_check(is_equal_approx(float(primary.call("effective_move_speed")), 64.0)
		and is_equal_approx(float(second.call("effective_move_speed")), 80.0),
		"Frost Touch slows the initial projectile victim and leaves chain victims unchanged")
	await _capture("chain-frost")
	primary.set_physics_process(true)
	await _ticks(47)
	primary.call("apply_slow", 0.2, 1.5, 0.4)
	await _ticks(55)
	_check(is_equal_approx(float(primary.call("effective_move_speed")), 64.0),
		"A second Frost Touch refreshes duration without stacking reduced speed")
	await _ticks(40)
	_check(is_equal_approx(float(primary.call("effective_move_speed")), 80.0), "Frost expiry restores the authored movement speed")
	primary.call("apply_slow", 0.99, 1.5, 0.4)
	_check(is_equal_approx(float(primary.call("effective_move_speed")), 32.0), "Frost respects the configured movement floor")


func _check_aura() -> void:
	_build_world()
	var nearby := _spawn_slime(Vector2(78.0, 0.0))
	var outside := _spawn_slime(Vector2(-140.0, 0.0))
	var dead := _spawn_slime(Vector2(65.0, -42.0))
	var dead_health := _health(dead)
	dead_health.damage(30)
	_upgrade(&"flame_aura")
	await _ticks(4)
	_check(_health(nearby).current == 26 and _health(outside).current == 30,
		"Flame Aura applies one four-damage tick only within its radius")
	_check(dead_health.current == 0, "Flame Aura ignores a defeated enemy")
	await _capture("flame-aura")
	await _ticks(27)
	_check(_health(nearby).current == 26, "Flame Aura waits for its damage interval")
	paused = true
	await _ticks(70)
	_check(_health(nearby).current == 26, "Pausing freezes Flame Aura and its timer")
	paused = false
	await _ticks(34)
	_check(_health(nearby).current == 22, "Flame Aura resumes with one tick after the interval")
	_health(_player).damage(100)
	await _ticks(67)
	_check(_health(nearby).current == 22, "Flame Aura stops after the hero dies")


func _spawn_slime(position: Vector2) -> CharacterBody2D:
	var slime := SLIME.instantiate() as CharacterBody2D
	slime.position = position
	_world.add_child(slime)
	slime.set_physics_process(false)
	return slime


func _health(actor: Node) -> Health:
	return actor.get_node("Health") as Health


func _rank(id: StringName) -> int:
	return int(_abilities.call("rank_of", id))


func _upgrade(id: StringName) -> bool:
	return bool(_abilities.call("apply_upgrade", id))


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


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
