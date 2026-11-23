extends SceneTree

const PROGRESSION_PATH := "res://features/progression/progression.gd"
const GEM_PATH := "res://features/progression/xp_gem.tscn"
const ABILITY_IDS := [&"arcane_bolt", &"chain_lightning", &"flame_aura", &"frost_touch", &"swift_steps", &"iron_guard"]

var _app: Node
var _arena: Node
var _hero: Node2D
var _progression: Node
var _abilities: Node
var _picker: Control
var _spawner: Node
var _capture_dir := ""
var _checks := 0
var _failures := 0


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
	_press(_button(_screen(), "Play"))
	await _settle()
	_bind_run()
	var has_progression := _check(_progression != null, "The playable grove owns run progression")
	var has_picker := _check(_picker != null and _abilities != null, "The grove has a picker and runtime abilities")
	if not (has_progression and has_picker):
		_finish()
		return
	_check(_level() == 1 and _xp() == 0 and _rank(&"arcane_bolt") == 1, "A new run starts at level 1 with Arcane Bolt")
	await _check_rewards(gate)
	if not _check(paused and _picker.visible, "Crossing the first threshold opens the upgrade picker"):
		_finish()
		return
	await _check_choice()
	if not gate:
		_check_level_bounds()
		await _check_queue()
		_check_rolls()
		await _check_empty_selection()
		if _capture_dir.is_empty():
			await _check_reward_cap()
	await _check_restart()
	_finish()


func _bind_run() -> void:
	_arena = _screen()
	_hero = _arena.get_node_or_null("%Player") as Node2D
	_progression = _arena.get_node_or_null("%Progression")
	_picker = _arena.get_node_or_null("%UpgradePicker") as Control
	_abilities = _hero.get_node_or_null("%Abilities")
	_spawner = _arena.get_node_or_null("%SlimeSpawner")


func _check_rewards(gate: bool) -> void:
	_spawner.call("stop")
	for enemy in get_nodes_in_group(&"combat_enemies"):
		enemy.queue_free()
	await _settle()
	for index in range(4):
		var enemy := await _spawn_enemy(index + 31)
		if enemy == null:
			_check(false, "The arena spawns a real Forest Slime")
			return
		var health := enemy.get_node("Health")
		var xp_before := _xp()
		for tick in range(200):
			if not get_nodes_in_group(&"xp_gems").is_empty():
				break
			await physics_frame
		var gems := get_nodes_in_group(&"xp_gems")
		if gems.size() != 1 or not is_instance_valid(health) or int(health.get("current")) != 0 or int(gems[0].get("xp_value")) != 5:
			_check(false, "Arcane Bolt defeats a slime and drops one five-XP gem")
			return
		if index == 0 and not gate:
			health.call("damage", 100)
			_check(get_nodes_in_group(&"xp_gems").size() == 1 and _xp() == xp_before, "Death drops XP once and waits for collection")
			await _capture("xp-gem")
		Input.action_press(&"move_right")
		for tick in range(38):
			if get_nodes_in_group(&"xp_gems").is_empty():
				break
			await physics_frame
		Input.action_release(&"move_right")
		await _settle()
		if not get_nodes_in_group(&"xp_gems").is_empty() or _xp() != (xp_before + 5) % 20:
			_check(false, "Moving to the gem collects exactly five XP")
			return
		if not paused:
			_hero.position = Vector2(0, 25)
		if index == 0 and not gate:
			await _ticks(10)
			var hud := _arena.get_node("%HUD")
			var bar := hud.get_node("%XP") as ProgressBar
			_check(is_equal_approx(bar.value, 5.0) and is_equal_approx(bar.max_value, 20.0), "The HUD shows 5 of 20 XP")
			await _capture("xp-progress")
	_check(true, "Four real Arcane Bolt kills each produce a five-XP pickup")


func _spawn_enemy(spawn_seed: int) -> Node2D:
	_spawner.set("spawn_seed", spawn_seed)
	_spawner.call("start", _hero, _hero.get_parent(), Rect2(-205, -145, 410, 507))
	for tick in range(10):
		var enemies := get_nodes_in_group(&"combat_enemies")
		if not enemies.is_empty():
			_spawner.call("stop")
			var enemy := enemies[0] as Node2D
			enemy.set_physics_process(false)
			enemy.global_position = _hero.global_position + Vector2(122.0, 0.0)
			return enemy
		await physics_frame
	return null


func _check_choice() -> void:
	var ids := _offered()
	_check(paused and _level() == 2 and _pending() == 1 and ids.size() == 3
		and ids[0] != ids[1] and ids[0] != ids[2] and ids[1] != ids[2],
		"Four kills open a paused level 2 picker with three distinct choices")
	if ids.is_empty():
		return
	var hud := _arena.get_node("%HUD")
	var level_label := hud.get_node("%LevelCaption") as Label
	_check(level_label.text.ends_with("2"), "The HUD shows level 2 before choosing")
	var position := _hero.position
	Input.action_press(&"move_left")
	await _ticks(8)
	Input.action_release(&"move_left")
	_check(_hero.position == position and paused, "The upgrade picker freezes movement")
	_arena.call("_select_upgrade", &"not_offered")
	_check(_pending() == 1 and paused, "An invalid selection does not spend an upgrade")
	await _capture("level-up")
	var chosen: StringName = ids[0]
	var previous_rank := _rank(chosen)
	var option := _button(_picker, "Choice1")
	_press(option)
	if _capture_dir.is_empty():
		_press(option)
	await _settle()
	await _settle()
	_check(_rank(chosen) == previous_rank + 1 and _pending() == 0 and not paused and not _picker.visible,
		"One choice adds exactly one rank and resumes play")


func _check_level_bounds() -> void:
	var progression_script := load(PROGRESSION_PATH) as Script
	var sample := progression_script.new() as Node
	sample.set("max_level", 3)
	sample.call("grant_xp", -1)
	_check(int(sample.get("current_xp")) == 0 and int(sample.get("level")) == 1, "Negative XP is ignored")
	sample.call("grant_xp", 9223372036854775807)
	_check(int(sample.get("level")) == 3 and int(sample.get("required_xp")) == 0
		and int(sample.get("pending_upgrades")) == 2, "Very large XP safely reaches the configured cap")
	sample.free()


func _check_queue() -> void:
	_progression.call("grant_xp", 61)
	_check(_level() == 4 and _xp() == 5 and _pending() == 2 and paused,
		"Large rewards advance multiple levels and preserve excess XP")
	var gem := _add_gem_at(_hero.global_position)
	var collected: Array[int] = []
	gem.connect("collected", func(amount: int) -> void: collected.append(amount))
	await _ticks(8)
	_check(collected.is_empty() and is_instance_valid(gem), "XP collection stops while the picker is open")
	gem.queue_free()
	await _capture("next-level")
	_press(_button(_picker, "Choice1"))
	await _settle()
	await _settle()
	_check(_pending() == 1 and paused and _picker.visible, "Pending upgrades appear one at a time")
	_press(_button(_picker, "Choice1"))
	await _settle()
	await _settle()
	_check(_pending() == 0 and not paused, "The world resumes only after the last pending choice")


func _check_rolls() -> void:
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 7
	b.seed = 7
	var options_a: Array = _abilities.call("roll_choices", a, 3)
	var options_b: Array = _abilities.call("roll_choices", b, 3)
	_check(options_a == options_b and options_a.size() == 3, "The same seed reproduces the same upgrade choices")
	for id in ABILITY_IDS:
		if id == &"arcane_bolt":
			continue
		while bool(_abilities.call("apply_upgrade", id)):
			pass
	var last_options: Array = _abilities.call("roll_choices", a, 3)
	_check(last_options.size() == 1 and last_options[0].get("id") == &"arcane_bolt", "Maxed skills are excluded and a smaller pool is supported")
	while bool(_abilities.call("apply_upgrade", &"arcane_bolt")):
		pass
	_check(_rank(&"arcane_bolt") == 5 and not bool(_abilities.call("apply_upgrade", &"invalid")),
		"Ability ranks cap at five and invalid abilities are rejected")


func _check_empty_selection() -> void:
	_progression.call("grant_xp", 100)
	await _settle()
	_check(_pending() == 0 and not paused and not _picker.visible, "No eligible choices consumes the queue without a soft lock")


func _check_reward_cap() -> void:
	_hero.position = Vector2(0, 25)
	_hero.get_node("BasicAttack").set_physics_process(false)
	for index in range(50):
		var enemy := await _spawn_enemy(index + 201)
		if enemy == null:
			_check(false, "Slimes remain spawnable during the pickup cap test")
			return
		enemy.position = Vector2(0, 210)
		enemy.get_node("Health").call("damage", 1000)
	var gems := get_nodes_in_group(&"xp_gems")
	var total_xp := 0
	for gem in gems:
		total_xp += int(gem.get("xp_value"))
	_check(gems.size() == 48 and total_xp == 250, "Excess enemy rewards merge without losing XP or exceeding the pickup cap")


func _check_restart() -> void:
	var old_arena := _arena
	var old_gem := _add_gem_at(_hero.global_position + Vector2(-160.0, 0.0))
	var health := _hero.get_node("Health")
	health.call("damage", 1000)
	await _settle()
	_check(paused and _button(_arena, "TryAgain").is_visible_in_tree() and not _picker.visible, "Game Over remains independent of the upgrade modal")
	_press(_button(_arena, "TryAgain"))
	await _settle()
	_bind_run()
	var bonus_ranks := 0
	for id in ABILITY_IDS:
		if id != &"arcane_bolt":
			bonus_ranks += _rank(id)
	_check(not paused and not is_instance_valid(old_arena) and not is_instance_valid(old_gem)
		and _level() == 1 and _xp() == 0 and _pending() == 0 and _rank(&"arcane_bolt") == 1 and bonus_ranks == 0,
		"Try Again discards the old gems, levels, pending choices and ability ranks")


func _add_gem_at(world_position: Vector2) -> Node2D:
	var scene := load(GEM_PATH) as PackedScene
	var gem := scene.instantiate() as Node2D
	var rewards := _arena.get_node("%Rewards") as Node2D
	gem.position = rewards.to_local(world_position)
	gem.call("setup", _hero, 5)
	rewards.add_child(gem)
	return gem


func _offered() -> Array:
	return _arena.get("_offered_ids")


func _level() -> int:
	return int(_progression.get("level"))


func _xp() -> int:
	return int(_progression.get("current_xp"))


func _pending() -> int:
	return int(_progression.get("pending_upgrades"))


func _rank(id: StringName) -> int:
	return int(_abilities.call("rank_of", id))


func _screen() -> Node:
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


func _settle() -> void:
	await process_frame
	await process_frame


func _ticks(count: int) -> void:
	for tick in range(count):
		await physics_frame


func _capture(capture_name: String) -> void:
	if _capture_dir.is_empty():
		return
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	_check(frame != null and frame.save_png(_capture_dir.path_join(capture_name + ".png")) == OK, "Captured " + capture_name)


func _check(condition: bool, message: String) -> bool:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
	return condition


func _finish() -> void:
	paused = false
	print("Progression smoke: %d checks, %d failures" % [_checks, _failures])
	_app.call(&"request_quit", 0 if _failures == 0 else 1)
