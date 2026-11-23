extends SceneTree

const SLIME_SCENE := "res://features/enemies/forest_slime.tscn"

var _app: Node
var _arena: Node2D
var _hero: CharacterBody2D
var _slime: CharacterBody2D
var _checks := 0
var _failures := 0
var _capture_dir := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	var gate := not arguments.is_empty() and arguments[0] == "--gate"
	if not gate and not arguments.is_empty():
		_capture_dir = arguments[0]
	var app_scene := load(str(ProjectSettings.get_setting("application/run/main_scene"))) as PackedScene
	if app_scene == null:
		push_error("The configured main scene did not load")
		quit(1)
		return
	_app = app_scene.instantiate()
	root.add_child(_app)
	await process_frame
	_arena = await _enter_grove()
	if _arena != null:
		_hero = _arena.find_child("Player", true, false) as CharacterBody2D
		_slime = _arena.find_child("ForestSlime", true, false) as CharacterBody2D
	var has_combat := _hero != null and _slime != null
	if has_combat:
		has_combat = _hero.has_node("Health") and _hero.has_node("BasicAttack") and _slime.has_node("Health")
	if not _check(has_combat, "Whispering Grove starts with a combat-ready hero and Forest Slime"):
		_finish()
		return

	await _check_pursuit(gate)
	await _check_attacks(gate)
	await _check_contact(gate)
	await _check_defeat(gate)
	_finish()


func _active_screen() -> Node:
	var host := _app.get_node("ScreenHost")
	return host.get_child(0) if host.get_child_count() > 0 else null


func _enter_grove() -> Node2D:
	var menu := _active_screen()
	if menu == null:
		return null
	var play := menu.find_child("Play", true, false) as Button
	if play == null:
		return null
	play.pressed.emit()
	await process_frame
	await process_frame
	return _active_screen() as Node2D


func _check_pursuit(gate: bool) -> void:
	var initial_range := _slime.global_position.distance_to(_hero.global_position)
	var health := _slime.get_node("Health")
	var initial_health := int(health.get("current"))
	await _ticks(14)
	_check(_slime.global_position.distance_to(_hero.global_position) < initial_range - 10.0, "Forest Slime pursues the hero")
	if not gate:
		_check(int(health.get("current")) == initial_health, "The hero does not hit a distant enemy")


func _check_attacks(gate: bool) -> void:
	var hero_definition := _hero.get("definition") as Resource
	var strike_damage := int(hero_definition.get("basic_attack_damage"))
	var far_health := _slime.get_node("Health")
	var far_start := int(far_health.get("current"))
	_slime.set_physics_process(false)
	_slime.global_position = _hero.global_position + Vector2(120, 0)

	var slime_scene := load(SLIME_SCENE) as PackedScene
	var nearby := slime_scene.instantiate() as CharacterBody2D
	nearby.position = _hero.position + Vector2(-72, 0)
	_slime.get_parent().add_child(nearby)
	nearby.set_physics_process(false)
	var near_health := nearby.get_node("Health")
	var near_start := int(near_health.get("current"))

	await _ticks(2)
	_check(
		int(near_health.get("current")) == near_start - strike_damage
		and int(far_health.get("current")) == far_start,
		"The first auto-attack hits only the closest living enemy"
	)
	await _ticks(10)
	_check(int(near_health.get("current")) == near_start - strike_damage, "The attack cannot fire during its cooldown")
	await _ticks(32)
	if not gate:
		_check(int(near_health.get("current")) == near_start - strike_damage * 2, "A living target is hit again after the interval")

	near_health.call(&"damage", near_health.get("current"))
	_check(not bool(near_health.call(&"is_alive")), "Lethal damage marks an enemy dead immediately")
	await _ticks(41)
	_check(int(far_health.get("current")) == far_start - strike_damage, "Auto-attacks skip the dead enemy and retarget")
	await _capture("grove-pulse")
	_check(not is_instance_valid(nearby), "A defeated slime is removed from the arena")


func _check_contact(gate: bool) -> void:
	var health := _hero.get_node("Health")
	var health_start := int(health.get("current"))
	_slime.global_position = _hero.global_position + Vector2(34, 0)
	_slime.set_physics_process(true)
	await _ticks(5)
	var after_contact := int(health.get("current"))
	var hud := _arena.find_child("HUD", true, false)
	var label := hud.get_node("%HealthCaption") as Label
	var bar := hud.get_node("%Health") as ProgressBar
	_check(
		after_contact < health_start and is_equal_approx(bar.value, after_contact)
		and label.text.ends_with("%d / %d" % [after_contact, int(health.get("maximum"))]),
		"Enemy contact reduces hero health and updates the HUD"
	)
	if not gate:
		await _ticks(12)
		_check(int(health.get("current")) == after_contact, "Contact damage has a cooldown")


func _check_defeat(gate: bool) -> void:
	var health := _hero.get_node("Health")
	health.call(&"damage", int(health.get("current")) + 100)
	var title := _arena.find_child("PauseHeading", true, false) as Label
	var resume := _arena.find_child("Resume", true, false) as Button
	var back := _arena.find_child("BackToMenu", true, false) as Button
	_check(
		paused and title.text == "Defeat" and not resume.visible and back.is_visible_in_tree(),
		"Zero hero health opens Defeat and stops the run"
	)
	if not gate:
		_check(int(health.get("current")) == 0, "Lethal damage clamps health to zero")
		resume.pressed.emit()
		_check(paused, "A defeated hero cannot resume the encounter")
	await _capture("defeat")
	back.pressed.emit()
	await process_frame
	await process_frame
	var menu := _active_screen()
	_check(not paused and menu != null and menu.name == &"MainMenu", "Defeat returns to the menu and clears pause")
	if not gate:
		var next_arena := await _enter_grove()
		_check(_is_fresh_encounter(next_arena), "Entering again starts a fresh hero and Forest Slime")


func _is_fresh_encounter(arena: Node2D) -> bool:
	if arena == null:
		return false
	var player := arena.find_child("Player", true, false)
	var slime := arena.find_child("ForestSlime", true, false)
	if player == null or slime == null:
		return false
	var actors: Array[Node] = [player, slime]
	for actor in actors:
		var health := actor.get_node_or_null("Health")
		if health == null or not bool(health.call(&"is_alive")) or health.get("current") != health.get("maximum"):
			return false
	return true


func _ticks(count: int) -> void:
	for index in count:
		await physics_frame


func _capture(name: String) -> void:
	if _capture_dir.is_empty():
		return
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	_check(frame != null and frame.save_png(_capture_dir.path_join(name + ".png")) == OK, "Captured " + name)


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
