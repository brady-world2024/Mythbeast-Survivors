extends SceneTree

const ARENA := preload("res://features/levels/whispering_grove/whispering_grove.tscn")

var _arena: Node2D
var _player: CharacterBody2D
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
	_arena = ARENA.instantiate() as Node2D
	root.add_child(_arena)
	_arena.get_node("%WaveSpawner").call("stop")
	for enemy in get_nodes_in_group(&"combat_enemies"):
		enemy.queue_free()
	_player = _arena.find_child("Player", true, false) as CharacterBody2D
	await _ticks(3)
	await _check_keyboard()
	await _check_touch(gate)
	if not gate:
		await _check_facing()
	await _check_bounds(gate)
	print("Movement smoke: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check_keyboard() -> void:
	var start := _player.position
	_key(KEY_D, true)
	await _ticks(10)
	var straight_speed := _player.get_real_velocity().length()
	_check(_player.position.x > start.x + 12.0, "D moves the hero right")
	_key(KEY_W, true)
	await _ticks(5)
	_check(
		_player.get_real_velocity().y < -20.0
		and is_equal_approx(_player.get_real_velocity().length(), straight_speed),
		"Diagonal keyboard movement uses the same speed as straight movement"
	)
	_key(KEY_D, false)
	_key(KEY_W, false)
	await _ticks(3)
	_check(_player.get_real_velocity().is_zero_approx(), "Releasing the keys stops movement")
	start = _player.position
	_key(KEY_LEFT, true)
	await _ticks(8)
	_key(KEY_LEFT, false)
	_check(_player.position.x < start.x - 12.0, "Left Arrow moves the hero left")


func _check_touch(gate: bool) -> void:
	await _ticks(3)
	_player.position = Vector2(0, 25)
	var start := _player.position
	var origin := root.get_visible_rect().size * Vector2(0.50, 0.70)
	var pause_button := _arena.find_child("PauseButton", true, false) as Button
	var pause_position := pause_button.get_global_rect().get_center()
	if not gate:
		var preview := _arena.find_child("WaveCaption", true, false) as Label
		_touch(2, preview.get_global_rect().get_center(), true)
		_drag(2, origin)
		await _ticks(5)
		_touch(2, origin, false)
		_check(_player.position.is_equal_approx(start), "A touch started on the HUD cannot steer into the field")

	_touch(0, origin, true)
	_drag(0, origin + Vector2(5, 0))
	await _ticks(5)
	_check(_player.position.is_equal_approx(start), "A short touch stays inside the dead zone")

	_drag(0, origin + Vector2(36, 0))
	await _ticks(5)
	var partial_speed := _player.get_real_velocity().length()
	_drag(0, origin + Vector2(100, 0))
	await _ticks(5)
	var full_speed := _player.get_real_velocity().length()
	_check(partial_speed > 0.0 and partial_speed < full_speed, "Touch distance controls analog speed")
	_check(_player.get_real_velocity().x > 120.0, "Dragging right steers the hero")
	await _capture("floating-stick")
	if gate:
		await _check_touch_release(pause_position)
	else:
		await _check_additional_touches(origin, pause_position)
	await _check_touch_pause(origin, pause_position, gate)


func _check_touch_release(pause_position: Vector2) -> void:
	_drag(0, pause_position)
	await _ticks(4)
	_check(not paused, "Dragging the movement finger across Pause does not activate it")
	_touch(0, pause_position, false)
	await _ticks(3)
	_check(_player.get_real_velocity().is_zero_approx(), "Releasing above the HUD ends movement")


func _check_additional_touches(origin: Vector2, pause_position: Vector2) -> void:
	_touch(1, origin, true)
	_drag(1, origin + Vector2(-100, 0))
	await _ticks(4)
	_check(_player.get_real_velocity().x > 120.0, "A second finger cannot steer while the first owns movement")
	await _check_touch_release(pause_position)
	_drag(1, origin + Vector2(-100, 0))
	await _ticks(3)
	_check(_player.get_real_velocity().is_zero_approx(), "A held second finger does not automatically take over")
	_touch(1, origin, false)

	_touch(1, origin, true)
	_drag(1, origin + Vector2(0, -100))
	await _ticks(5)
	_check(_player.get_real_velocity().y < -120.0, "A fresh touch can steer north")
	await _capture("facing-north")
	_touch(1, origin, false, true)
	await _ticks(3)
	_check(_player.get_real_velocity().is_zero_approx(), "A cancelled touch releases movement")

	_touch(1, origin, true)
	_drag(1, origin + Vector2(-100, 0))
	await _ticks(4)
	_arena.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _ticks(3)
	_check(_player.get_real_velocity().is_zero_approx(), "Losing focus clears a held touch")
	_touch(1, origin, false)


func _check_touch_pause(origin: Vector2, pause_position: Vector2, gate: bool) -> void:
	_touch(3, origin, true)
	_drag(3, origin + Vector2(0, 100))
	await _ticks(5)
	_touch(5, pause_position, true)
	_touch(5, pause_position, false)
	var frozen := _player.position
	await _ticks(5)
	_check(paused and _player.position.is_equal_approx(frozen), "Pause freezes the moving hero")
	var resume := _arena.find_child("Resume", true, false) as Button
	var resume_position := resume.get_global_rect().get_center()
	_touch(5, resume_position, true)
	_touch(5, resume_position, false)
	_check(not paused, "A touch on Resume returns to the arena")
	_drag(3, origin + Vector2(0, 100))
	await _ticks(5)
	_check(_player.position.is_equal_approx(frozen), "Resume requires a fresh touch")
	_touch(3, origin, false)
	if gate:
		return

	_touch(4, origin, true)
	_drag(4, origin + Vector2(90, 0))
	await _ticks(4)
	_arena.notification(NOTIFICATION_APPLICATION_PAUSED)
	await _ticks(2)
	_touch(5, resume_position, true)
	_touch(5, resume_position, false)
	frozen = _player.position
	_drag(4, origin + Vector2(90, 0))
	await _ticks(4)
	_check(_player.position.is_equal_approx(frozen), "App suspension clears touch ownership")
	_touch(4, origin, false)

	_touch(6, origin, true)
	_drag(6, origin + Vector2(80, 0))
	await _ticks(4)
	root.size_changed.emit()
	frozen = _player.position
	_drag(6, origin + Vector2(80, 0))
	await _ticks(4)
	_check(_player.position.is_equal_approx(frozen), "Viewport size changes clear touch ownership")
	_touch(6, origin, false)


func _check_facing() -> void:
	_player.position = Vector2(0, 25)
	var body := _player.get_node("VisualAnchor").get_child(0).get_node("Body") as Sprite2D
	var origin := root.get_visible_rect().size * Vector2(0.50, 0.70)
	_touch(0, origin, true)
	_drag(0, origin + Vector2(90, 0))
	await _ticks(3)
	_check(body.texture.resource_path.ends_with("grove_hero_side.svg") and not body.flip_h, "Right uses the right-facing side portrait")

	_drag(0, origin + Vector2(69, 70))
	await _ticks(3)
	_check(body.texture.resource_path.ends_with("grove_hero_side.svg"), "A small change around 45 degrees keeps the previous axis")
	_drag(0, origin + Vector2(0, -90))
	await _ticks(3)
	_check(body.texture.resource_path.ends_with("grove_hero_back.svg"), "North uses the back portrait")
	_touch(0, origin, false)
	await _ticks(4)
	_check(body.texture.resource_path.ends_with("grove_hero_back.svg"), "Idle keeps the last direction")

	_touch(0, origin, true)
	_drag(0, origin + Vector2(-90, 0))
	await _ticks(3)
	_check(body.texture.resource_path.ends_with("grove_hero_side.svg") and body.flip_h, "Left mirrors the side portrait")
	_drag(0, origin + Vector2(0, 90))
	await _ticks(3)
	_check(body.texture.resource_path.ends_with("grove_hero.svg") and not body.flip_h, "South restores the front portrait")
	_touch(0, origin, false)


func _check_bounds(gate: bool) -> void:
	await _approach_wall(KEY_LEFT, Vector2(-170, 25), Vector2(-189, 25))
	if gate:
		return
	await _approach_wall(KEY_RIGHT, Vector2(170, 25), Vector2(189, 25))
	await _approach_wall(KEY_UP, Vector2(0, -110), Vector2(0, -129))
	await _approach_wall(KEY_DOWN, Vector2(0, 326), Vector2(0, 346))

	_player.position = Vector2(188.0, 25.0)
	_key(KEY_RIGHT, true)
	_key(KEY_DOWN, true)
	await _ticks(12)
	_key(KEY_RIGHT, false)
	_key(KEY_DOWN, false)
	_check(_player.position.x <= 189.2 and _player.position.y > 35.0, "The hero slides along the edge at diagonal input")


func _approach_wall(keycode: Key, from: Vector2, expected: Vector2) -> void:
	_player.position = from
	_key(keycode, true)
	await _ticks(18)
	_key(keycode, false)
	_check(_player.position.distance_to(expected) < 0.7, "Collision stops movement at the %s edge" % OS.get_keycode_string(keycode))


func _key(keycode: Key, down: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _touch(index: int, point: Vector2, down: bool, cancelled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = root.get_final_transform() * point
	event.window_id = root.get_window_id()
	event.pressed = down
	event.canceled = cancelled
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _drag(index: int, point: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = root.get_final_transform() * point
	event.window_id = root.get_window_id()
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _ticks(count: int) -> void:
	for index in count:
		await physics_frame


func _capture(name: String) -> void:
	if _capture_dir.is_empty():
		return
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	_check(frame != null and frame.save_png(_capture_dir.path_join(name + ".png")) == OK, "Captured " + name)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(description)
