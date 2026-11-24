extends SceneTree

const AppFixture = preload("res://tests/support/app_fixture.gd")
const GROVE := &"whispering_grove"
const NORMAL := &"normal"
const HARD := &"hard"
const HEARTWOOD := &"heartwood_vitality"
const ARCANE := &"arcane_focus"
const WINDSTEP := &"windstep_boots"

var _app: Node
var _service: RefCounted
var _path := ""
var _capture_dir := ""
var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var gate := not args.is_empty() and args[0] == "--gate"
	if not args.is_empty() and not gate:
		_capture_dir = args[0]
	_path = AppFixture.isolated_path()
	await _open_app()
	_check(_balance() == 0 and _rank(HEARTWOOD) == 0 and FileAccess.file_exists(_path), "First launch saves clean defaults")
	await _press("Play")
	_check(_screen().name == &"StageSelect" and _button("Hard").disabled
		and _button("CrystalCaverns").disabled, "Play opens stage selection with Hard and the preview stage unavailable")
	await _capture("stages-locked")
	_screen().emit_signal(&"start_requested", GROVE, HARD)
	await _settle()
	_check(_screen().name == &"StageSelect", "The app rejects a forged locked difficulty")
	await _press("StartAdventure")
	if not _check(_screen().name == &"WhisperingGrove", "Starting Normal loads the existing arena"):
		_finish()
		return
	var first_id := int(_screen().get("run_id"))
	await _win()
	_check(_balance() == 40 and bool(_service.call("can_start", GROVE, HARD)),
		"A valid Normal victory earns 40 Star Essence and unlocks Hard")
	_screen().call("_settle_rewards")
	_verify_duplicate(first_id)
	await _capture("normal-reward")
	await _press("VictoryMainMenu")
	await _press("PermanentUpgrades")
	await _capture("upgrade-shop")
	var button := _button("BuyHeartwoodVitality")
	if gate or _capture_dir.is_empty():
		button.pressed.emit()
		button.pressed.emit()
	else:
		_click(button)
	await _settle()
	_check(_balance() == 20 and _rank(HEARTWOOD) == 1, "One purchase costs 20 and repeated presses buy only one rank")
	if not gate:
		await _buy_remaining_upgrades()
	else:
		await _press("Back")
	await _start_hard()
	var player := _screen().get_node("%Player")
	var health := player.get_node("Health")
	var spawner := _screen().get_node("%WaveSpawner")
	_check(int(health.get("maximum")) == 110 and int(health.get("current")) == 110,
		"Permanent health applies at full value on the next run")
	_check(StringName(_screen().get("_difficulty").id) == HARD and
		is_equal_approx(float(spawner.get("spawn_interval")), 1.62) and int(spawner.get("max_active")) == 12,
		"Hard applies the configured interval once and preserves the population cap")
	if not gate:
		_check(
			is_equal_approx(float(player.call("effective_move_speed")), 195.7)
				and int(player.get("abilities").bolt.damage) == 11,
			"Windstep and Arcane Focus change effective starting stats"
		)
		var abilities: Node = player.get("abilities")
		abilities.call("apply_upgrade", &"swift_steps")
		abilities.call("apply_upgrade", &"arcane_bolt")
		_check(is_equal_approx(float(player.call("effective_move_speed")), 211.356)
			and int(abilities.get("bolt").damage) == 14,
			"Permanent bonuses combine once with temporary skills")
		await _check_hard_enemy(player)
	var before_loss := _balance()
	await _lose_after_threshold()
	var defeat_time := _screen().get_node("%DefeatTime") as Label
	_check(_balance() == before_loss + 5 and defeat_time.text.ends_with("00:30"),
		"A qualifying Hard loss records 30 seconds and rounds 3 times 1.5 to 5 Star Essence")
	await _capture("hard-defeat")
	var ended := _screen()
	await _press("TryAgain")
	_check(not paused and _screen() != ended and StringName(_screen().get("_difficulty").id) == HARD
		and int(_screen().get_node("%Progression").get("level")) == 1,
		"Retry preserves Hard and resets the run")
	if not gate:
		await _check_hard_victory()
		await _check_settings()
		await _check_reward_save_retry()
	await _reopen_app()
	_finish()


func _verify_duplicate(run_id: int) -> void:
	var receipt: Dictionary = _service.call("settle", run_id, true, 99, 8, 180.0)
	_check(receipt.get("status") == &"duplicate" and _balance() == 40, "Repeated settlement cannot change the stored reward")


func _buy_remaining_upgrades() -> void:
	await _ticks(30)
	await _press("BuyArcaneFocus")
	_check(_balance() == 0 and _rank(ARCANE) == 1, "Arcane Focus purchases at the authored cost")
	await _press("Back")
	await _press("Play")
	await _press("StartAdventure")
	await _win()
	await _press("VictoryMainMenu")
	await _press("PermanentUpgrades")
	await _press("BuyWindstepBoots")
	_check(_balance() == 20 and _rank(WINDSTEP) == 1, "Windstep Boots purchases at the authored cost")
	await _press("Back")


func _start_hard() -> void:
	await _press("Play")
	await _press("Hard")
	await _capture("hard-unlocked")
	await _press("StartAdventure")


func _check_hard_enemy(player: Node) -> void:
	var enemies := get_nodes_in_group(&"combat_enemies")
	for frame in range(6):
		if not enemies.is_empty():
			break
		await physics_frame
		enemies = get_nodes_in_group(&"combat_enemies")
	if not _check(not enemies.is_empty(), "Hard spawns an ordinary enemy"):
		return
	var enemy := enemies[0]
	var hp := int(enemy.get_node("Health").get("maximum"))
	var speed := float(enemy.call("effective_move_speed"))
	_check(hp == 38 and is_equal_approx(speed, 84.0), "The Hard Slime receives health and speed modifiers once")
	var hero_hp := int(player.get_node("Health").get("current"))
	enemy.call("damage_player")
	_check(int(player.get_node("Health").get("current")) == hero_hp - 9, "Hard enemy damage uses the authored multiplier")


func _check_hard_victory() -> void:
	var balance_before := _balance()
	await _win(688)
	_check(_balance() == balance_before + 60, "A Hard victory earns 60 Star Essence")
	var record: Dictionary = _service.call("record", GROVE, HARD)
	_check(int(record.get("clears", 0)) == 1, "Hard records are separate from Normal")
	await _press("VictoryStages")
	_check(_screen().name == &"StageSelect", "Results return directly to stage selection")
	await _press("Back")


func _check_settings() -> void:
	await _press("Settings")
	var music := _screen().find_child("Music", true, false) as HSlider
	var sfx := _screen().find_child("SFX", true, false) as HSlider
	music.value = 31.0
	sfx.value = 57.0
	await _press("Back")
	var settings: Dictionary = _service.call("audio_settings")
	_check(is_equal_approx(float(settings["music_volume"]), 0.31) and is_equal_approx(float(settings["sfx_volume"]), 0.57),
		"Leaving Settings flushes the changed audio values")
	var block := ProjectSettings.globalize_path(_path) + ".tmp"
	if not _check(DirAccess.make_dir_absolute(block) == OK, "The isolated test blocks a settings write"):
		return
	await _press("Settings")
	music = _screen().find_child("Music", true, false) as HSlider
	music.value = 12.0
	await _press("Back")
	var notice := _screen().get_node("%SaveNotice") as Label
	var music_bus := AudioServer.get_bus_index(&"Music")
	_check(notice.is_visible_in_tree() and is_equal_approx(AudioServer.get_bus_volume_linear(music_bus), 0.31)
		and _service.call("audio_settings") == settings, "A failed settings save reports the error and restores the committed mix")
	DirAccess.remove_absolute(block)


func _check_reward_save_retry() -> void:
	await _start_hard()
	var balance_before := _balance()
	var block := ProjectSettings.globalize_path(_path) + ".tmp"
	if not _check(DirAccess.make_dir_absolute(block) == OK, "The isolated test blocks the next save"):
		return
	await _lose_after_threshold()
	var retry := _button("RetrySave")
	var warning := _screen().get_node("%DefeatRewards").get_node("%RewardMessage") as Label
	_check(retry != null and retry.is_visible_in_tree() and _balance() == balance_before
		and warning.text.contains("Leaving discards this reward."),
		"A failed settlement offers retry, explains discarding, and leaves the balance unchanged")
	await _capture("save-retry")
	_check(DirAccess.remove_absolute(block) == OK, "The isolated save obstruction can be cleared")
	await _press("RetrySave")
	_screen().call("_settle_rewards")
	_check(_balance() == balance_before + 5, "Retry saves the original result exactly once")
	await _press("MainMenu")


func _reopen_app() -> void:
	var expected_balance := _balance()
	var expected_settings: Dictionary = _service.call("audio_settings")
	var expected_normal: Dictionary = _service.call("record", GROVE, NORMAL)
	_app.queue_free()
	paused = false
	await _settle()
	await _open_app()
	_check(_balance() == expected_balance and _rank(HEARTWOOD) == 1 and bool(_service.call("can_start", GROVE, HARD))
		and _service.call("record", GROVE, NORMAL) == expected_normal,
		"A fresh App instance reloads currency, ranks, records, and the Hard unlock")
	_check(_service.call("audio_settings") == expected_settings, "Audio settings persist independently of the run")


func _open_app() -> void:
	_app = AppFixture.instantiate(_path)
	root.add_child(_app)
	await process_frame
	_service = _app.get("service") as RefCounted


func _win(expected_boss_health := 550) -> void:
	var arena := _screen()
	var timeline := arena.get_node("%RunTimeline")
	timeline.call("advance", 180.0)
	await _ticks(4)
	timeline.call("advance", 2.4)
	await _ticks(4)
	var boss: Node = arena.get("_boss")
	if not _check(is_instance_valid(boss) and int(timeline.get("phase")) == 2
		and int(boss.get_node("Health").get("maximum")) == expected_boss_health,
		"The authored boss starts with the expected difficulty-adjusted health"):
		return
	boss.get_node("Health").call("damage", 1000)
	await _ticks(48)
	await _settle()


func _lose_after_threshold() -> void:
	var arena := _screen()
	arena.get_node("%RunTimeline").call("advance", 30.0)
	arena.get_node("%Player").get_node("Health").call("damage", 1000)
	await _settle()


func _balance() -> int:
	return int(_service.call("balance"))


func _rank(id: StringName) -> int:
	return int(_service.call("rank", id))


func _screen() -> Node:
	return _app.get_node("ScreenHost").get_child(0)


func _button(button_name: String) -> Button:
	return _screen().find_child(button_name, true, false) as Button


func _press(button_name: String) -> void:
	var button := _button(button_name)
	if button == null or button.disabled:
		_check(false, "Usable button: " + button_name)
		return
	if _capture_dir.is_empty():
		button.pressed.emit()
	else:
		var ancestor := button.get_parent()
		while ancestor != null and not ancestor is ScrollContainer:
			ancestor = ancestor.get_parent()
		if ancestor is ScrollContainer:
			ancestor.ensure_control_visible(button)
			await _settle()
		_click(button)
	await _settle()


func _click(button: Button) -> void:
	var point := button.get_global_rect().get_center()
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.global_position = point
		event.pressed = down
		root.push_input(event, true)


func _ticks(count: int) -> void:
	for tick in range(count):
		await physics_frame


func _settle() -> void:
	await process_frame
	await process_frame
	await process_frame


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
	print("Persistent progression smoke: %d checks, %d failures" % [_checks, _failures])
	_app.call(&"request_quit", 0 if _failures == 0 else 1)
