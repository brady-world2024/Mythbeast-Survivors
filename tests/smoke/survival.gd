extends SceneTree

const AppFixture = preload("res://tests/support/app_fixture.gd")

const LEVEL := "res://data/levels/whispering_grove.tres"

var _app: Node
var _arena: Node
var _hero: Node2D
var _timeline: Node
var _spawner: Node
var _progression: Node
var _capture_dir := ""
var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	var gate := not arguments.is_empty() and arguments[0] == "--gate"
	if not arguments.is_empty() and not gate:
		_capture_dir = arguments[0]
	_app = AppFixture.instantiate()
	root.add_child(_app)
	await process_frame
	_press(_button(_screen(), "Play"))
	await _settle()
	_press(_button(_screen(), "StartAdventure"))
	await _settle()
	_bind()
	if not _check(_timeline != null and ResourceLoader.exists(LEVEL), "The grove uses an authored level and a run timeline"):
		_finish()
		return
	var duration := float((_arena.get("definition") as Resource).get("survival_duration"))
	_check(duration == 180.0 and _wave() == 0 and _elapsed() < 1.0, "The three-minute level begins in wave one")
	await _check_pause()
	await _check_waves()
	await _check_win_and_retry()
	if not gate:
		_check_intro_wait()
		await _check_terminal_states()
	_finish()


func _bind() -> void:
	_arena = _screen()
	_hero = _arena.get_node_or_null("%Player") as Node2D
	_timeline = _arena.get_node_or_null("%RunTimeline")
	_spawner = _arena.get_node_or_null("%WaveSpawner")
	_progression = _arena.get_node_or_null("%Progression")


func _check_pause() -> void:
	_press(_button(_arena, "PauseButton"))
	await _settle()
	var time := _elapsed()
	await _ticks(12)
	_check(paused and _elapsed() == time, "Pause freezes the survival clock")
	_press(_button(_arena, "Resume"))
	await _ticks(5)
	_check(not paused and _elapsed() > time, "Resume restores the active-play clock")

	_arena.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	time = _elapsed()
	await _ticks(8)
	_arena.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	_check(paused and _elapsed() == time, "Background time does not count and returning requires Resume")
	_press(_button(_arena, "Resume"))
	await _settle()

	_progression.call("grant_xp", 20)
	var picker := _arena.get_node("%UpgradePicker") as Control
	await _settle()
	time = _elapsed()
	await _ticks(10)
	_check(picker.visible and paused and _elapsed() == time, "A level-up choice freezes the survival clock")
	_press(_button(picker, "Choice1"))
	await _settle()
	await _settle()
	_check(not paused and not picker.visible, "Picking an upgrade resumes the survival wave")


func _check_waves() -> void:
	_advance_to(59.0)
	_check(_wave() == 0, "Wave one lasts until the first minute")
	_advance_to(60.0)
	_check(_wave() == 1 and int(_spawner.get("max_active")) == 20, "At 60 seconds wave two applies its own cap")
	_advance_to(120.0)
	_check(_wave() == 2 and int(_spawner.get("max_active")) == 28, "At 120 seconds the final wave applies its own cap")
	await _ticks(2)
	_check(_caption("%TimerCaption").text == "02:00 / 03:00" and _caption("%WaveCaption").text == "Final Wave",
		"The HUD reports active time and the final wave")
	await _capture("final-wave")


func _check_win_and_retry() -> void:
	_spawner.call("clear_enemies")
	# Own one verified kill and leave its gem active through administrative cleanup.
	var enemies := get_nodes_in_group(&"combat_enemies")
	for tick in range(130):
		enemies = get_nodes_in_group(&"combat_enemies")
		if not enemies.is_empty():
			break
		await physics_frame
	if not enemies.is_empty():
		var regular := enemies[0] as Node2D
		regular.position = Vector2(140, 140)
		regular.get_node("Health").call("damage", 1000)
	var drops := get_nodes_in_group(&"xp_gems").size()
	var kills := int(_timeline.get("enemies_defeated"))
	_advance_to(179.5)
	_check(_phase() == 0 and _boss() == null, "The boss cannot appear before 180 active seconds")
	_advance_to(180.0)
	await _ticks(3)
	var boss := _boss()
	if not _check(_phase() == 1 and boss != null and not bool(_spawner.call("is_spawning")) and _elapsed() == 180.0,
		"At 180 seconds the director stops spawning and introduces one Boss"):
		return
	_check(not boss.is_in_group(&"combat_enemies") and int(boss.get("attack_state")) == 0
		and get_nodes_in_group(&"xp_gems").size() == drops and int(_timeline.get("enemies_defeated")) == kills,
		"The introduction Boss cannot attack and clearing the wave grants no kills or XP")
	await _capture("boss-intro")

	_timeline.call("advance", 2.4)
	await _ticks(3)
	_check(_phase() == 2 and _boss() == boss and boss.is_in_group(&"combat_enemies")
		and int(boss.get("phase")) == 1 and _caption("%WaveCaption").text == "BOSS BATTLE",
		"The same Boss enters phase one with a dedicated HUD")
	await _capture("boss-fight")

	var health := boss.get_node("Health")
	var max_hp := int(health.get("maximum"))
	health.call("damage", max_hp - 1)
	_check(int(boss.get("phase")) == 2 and _phase() == 2, "Crossing half HP begins phase two without ending the encounter")
	await _capture("boss-phase-two")
	boss.set_physics_process(false)
	var target_position := (boss as Node2D).position
	var offset := Vector2(120, 0) if target_position.x < 20.0 else Vector2(-120, 0)
	_hero.position = target_position + offset
	for tick in range(150):
		if paused:
			break
		await physics_frame
	var victory := _arena.get_node("%VictoryPanel") as Control
	var defeat := _arena.get_node("%GameOverPanel") as Control
	if not _check(_phase() == 3 and paused and victory.visible and not defeat.visible and bool(_timeline.get("boss_defeated")),
		"A real Arcane Bolt finishing blow opens Victory only"):
		return
	_check(int(_timeline.get("enemies_defeated")) == kills + 1 and _arena.get_node("%VictoryTime").text.ends_with("03:00")
		and _arena.get_node("%VictoryLevel").text.ends_with(str(_progression.get("level"))),
		"Victory shows the tracked time, exact kills and player level")
	await _capture("victory")
	var old_arena := _arena
	_press(_button(_arena, "PlayAgain"))
	await _settle()
	_bind()
	_check(not paused and not is_instance_valid(old_arena) and _phase() == 0 and _wave() == 0
		and _elapsed() < 1.0 and int(_timeline.get("enemies_defeated")) == 0 and _boss() == null
		and int(_progression.get("level")) == 1 and get_nodes_in_group(&"xp_gems").is_empty(),
		"Play Again resets the entire level, clock, boss, rewards and statistics")


func _check_terminal_states() -> void:
	for phase_to_test in [0, 1, 2]:
		if phase_to_test > 0:
			_advance_to(180.0)
			await _ticks(3)
		if phase_to_test == 2:
			_timeline.call("advance", 2.4)
			await _ticks(3)
			_boss().get_node("Health").call("damage", 1000)
		_check(_phase() == phase_to_test, "The test reaches the requested run phase")
		_hero.get_node("Health").call("damage", 1000)
		await _ticks(40)
		var defeat := _arena.get_node("%GameOverPanel") as Control
		var victory := _arena.get_node("%VictoryPanel") as Control
		_check(_phase() == 4 and paused and defeat.visible and not victory.visible
			and not bool(_timeline.get("boss_defeated")), "Game Over wins terminal state arbitration")
		if phase_to_test < 2:
			_press(_button(_arena, "TryAgain"))
			await _settle()
			_bind()
		else:
			await _capture("game-over")
			_press(_button(_arena, "MainMenu"))
			await _settle()
			_check(not paused and _screen().name == &"MainMenu", "Main Menu safely releases the ended run")


func _check_intro_wait() -> void:
	var timeline_script := load("res://features/levels/run_timeline.gd") as Script
	var timeline := timeline_script.new() as Node
	timeline.call("begin", _arena.get("definition"))
	timeline.call("advance", 180.0)
	timeline.call("advance", 10.0)
	_check(not bool(timeline.call("begin_boss")) and is_equal_approx(float(timeline.get("intro_remaining")), 2.4),
		"A blocked boss spawn cannot consume the visible introduction")
	timeline.call("mark_boss_visible")
	timeline.call("advance", 2.4)
	_check(bool(timeline.call("begin_boss")), "The boss starts after its full visible introduction")
	timeline.free()


func _advance_to(seconds: float) -> void:
	_timeline.call("advance", maxf(0.0, seconds - _elapsed()))


func _elapsed() -> float:
	return float(_timeline.get("elapsed"))


func _phase() -> int:
	return int(_timeline.get("phase"))


func _wave() -> int:
	return int(_timeline.get("wave_index"))


func _boss() -> Node:
	var boss: Variant = _arena.get("_boss")
	return boss if is_instance_valid(boss) else null


func _caption(path: NodePath) -> Label:
	return _arena.get_node("%HUD").get_node(path) as Label


func _screen() -> Node:
	return _app.get_node("ScreenHost").get_child(0)


func _button(screen: Node, name_to_find: String) -> Button:
	return screen.find_child(name_to_find, true, false) as Button


func _press(button: Button) -> void:
	if _capture_dir.is_empty():
		button.pressed.emit()
		return
	var point := button.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.global_position = point
		event.pressed = pressed
		root.push_input(event, true)


func _settle() -> void:
	await process_frame
	await process_frame


func _ticks(count: int) -> void:
	for tick in range(count):
		await physics_frame


func _capture(name_to_capture: String) -> void:
	if _capture_dir.is_empty():
		return
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	_check(frame != null and frame.save_png(_capture_dir.path_join(name_to_capture + ".png")) == OK,
		"Captured " + name_to_capture)


func _check(condition: bool, message: String) -> bool:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
	return condition


func _finish() -> void:
	paused = false
	print("Survival smoke: %d checks, %d failures" % [_checks, _failures])
	_app.call(&"request_quit", 0 if _failures == 0 else 1)
