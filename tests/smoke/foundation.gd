extends SceneTree

const MENU := &"MainMenu"
const SETTINGS := &"SettingsScreen"
const CREDITS := &"CreditsScreen"
const GROVE := &"WhisperingGrove"

var _app: Node
var _checks := 0
var _failures := 0
var _capture_dir := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	var gate_only := not arguments.is_empty() and arguments[0] == "--gate"
	if not arguments.is_empty() and not gate_only:
		_capture_dir = arguments[0]
		if not _check(DisplayServer.get_name() != "headless" and DirAccess.dir_exists_absolute(_capture_dir), "Screenshot directory exists and rendering is enabled"):
			_finish()
			return
	var main_path: String = ProjectSettings.get_setting("application/run/main_scene")
	var scene := load(main_path) as PackedScene
	if not _check(scene != null, "The configured main scene loads"):
		_finish()
		return
	_app = scene.instantiate()
	root.add_child(_app)
	await process_frame
	if not _check(_screen_name() == MENU, "Boot opens the main menu"):
		_finish()
		return

	var main := _screen()
	var play := main.find_child("Play", true, false) as Button
	_check(play != null and play.text == "Play" and play.size.y >= 56.0, "Play has English text and a touch-sized target")
	if not gate_only:
		_check_music()
	await _capture("main-menu")
	await _press("Settings")
	_check(_screen_name() == SETTINGS, "Settings opens from the menu")
	if not gate_only:
		_check_volume("Music", &"Music")
		_check_volume("SFX", &"SFX")
	await _capture("settings")
	await _press("Back")
	_check(_screen_name() == MENU, "Settings returns to the menu")
	if not gate_only:
		await _check_secondary_menu_navigation()

	await _press("Play")
	_check(_screen_name() == GROVE, "Play opens Whispering Grove")
	var player := _screen().find_child("Player", true, false) as CharacterBody2D
	if _check(player != null, "The arena owns a reusable player") and not gate_only:
		var definition := player.get("definition") as Resource
		_check(definition != null and definition.get("id") == &"grove_keeper", "The player references the grove keeper definition")
		_check(player.get_node("VisualAnchor").get_child_count() == 1, "The player instantiates the definition's visual")
	_check(_screen().find_child("Camera2D", true, false) is Camera2D, "The arena owns a camera")
	if not gate_only:
		var preview := _screen().find_child("WaveCaption", true, false) as Label
		_check(preview != null and preview.text == "Wave 1", "The HUD identifies the opening wave")
	await _capture("whispering-grove")
	await _press("PauseButton")
	_check(paused, "Pause stops the scene tree")
	await _capture("pause")
	await _press("Resume")
	_check(not paused and _screen_name() == GROVE, "Resume returns to the grove")
	if gate_only:
		await _press("PauseButton")
	else:
		await _check_pause_lifecycle()
	await _press("BackToMenu")
	_check(not paused and _screen_name() == MENU, "Paused return opens a running main menu")
	if not gate_only:
		await _press("Play")
		_check(not paused and _screen_name() == GROVE, "The grove can be entered again")
	_finish()


func _check_music() -> void:
	var music_player := _app.get_node("Music") as AudioStreamPlayer
	var music := music_player.stream as AudioStreamWAV
	_check(
		music_player.playing == (DisplayServer.get_name() != "headless")
		and music.loop_mode == AudioStreamWAV.LOOP_FORWARD
		and music.loop_end < roundi(music.get_length() * music.mix_rate),
		"The soundtrack loops within the imported source data"
	)


func _check_secondary_menu_navigation() -> void:
	await _press("Credits")
	_check(_screen_name() == CREDITS, "Credits opens from the menu")
	await _capture("credits")
	await _press("Back")
	_check(_screen_name() == MENU, "Credits returns to the menu")
	await _press("Settings")
	_app.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await process_frame
	await process_frame
	_check(_screen_name() == MENU, "Android Back returns from settings to the menu")


func _check_pause_lifecycle() -> void:
	var escape := InputEventKey.new()
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	root.push_input(escape, true)
	await process_frame
	_check(paused, "Escape opens the pause overlay")
	escape = InputEventKey.new()
	escape.physical_keycode = KEY_ESCAPE
	root.push_input(escape, true)
	await _press("Resume")
	_screen().notification(NOTIFICATION_APPLICATION_PAUSED)
	await process_frame
	_check(paused, "App suspension opens the arena pause overlay")
	_screen().notification(NOTIFICATION_APPLICATION_RESUMED)
	await process_frame
	_check(paused, "Returning from suspension requires an explicit resume")


func _screen() -> Node:
	var host := _app.get_node_or_null("ScreenHost")
	if host != null and host.get_child_count() == 1:
		return host.get_child(0)
	return _app


func _screen_name() -> StringName:
	return _screen().name


func _press(name_to_find: String) -> void:
	var button := _screen().find_child(name_to_find, true, false) as Button
	if _check(button != null and button.is_visible_in_tree() and not button.disabled, "Usable button: " + name_to_find):
		if _capture_dir.is_empty():
			button.pressed.emit()
		else:
			var location := button.get_global_rect().get_center()
			_send_click(location, true)
			_send_click(location, false)
	await process_frame
	await process_frame


func _send_click(location: Vector2, pressed: bool) -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = location
	click.global_position = location
	click.pressed = pressed
	root.push_input(click, true)


func _capture(file_name: String) -> void:
	if _capture_dir.is_empty():
		return
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var file_path := _capture_dir.path_join(file_name + ".png")
	_check(image != null and image.save_png(file_path) == OK, "Rendered screenshot: " + file_name)


func _check_volume(slider_name: String, bus_name: StringName) -> void:
	var slider := _screen().find_child(slider_name, true, false) as Slider
	var bus := AudioServer.get_bus_index(bus_name)
	if not _check(slider != null and bus >= 0, "Audio slider and bus exist: " + slider_name):
		return
	var original := slider.value
	slider.value = 35.0
	_check(
		not AudioServer.is_bus_mute(bus) and is_equal_approx(AudioServer.get_bus_volume_linear(bus), 0.35),
		"Volume slider updates the " + slider_name + " bus"
	)
	slider.value = 0.0
	_check(AudioServer.is_bus_mute(bus), "Zero volume mutes the " + slider_name + " bus")
	slider.value = original


func _check(ok: bool, message: String) -> bool:
	_checks += 1
	if not ok:
		_failures += 1
		push_error(message)
	return ok


func _finish() -> void:
	paused = false
	print("Foundation smoke: %d checks, %d failures" % [_checks, _failures])
	var exit_code := 0 if _failures == 0 else 1
	if is_instance_valid(_app) and _app.has_method(&"request_quit"):
		_app.call(&"request_quit", exit_code)
	else:
		quit(exit_code)
