extends SceneTree

const Service = preload("res://core/persistence/progression_service.gd")
const Store = preload("res://core/persistence/save_store.gd")
const SafeArea = preload("res://ui/components/safe_area.gd")
const AppScene = preload("res://core/app/app.tscn")
const Comfort = preload("res://features/presentation/comfort.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_safe_area()
	var marker := FileAccess.create_temp(FileAccess.WRITE, "mythbeast-mobile-ux", "tmp", true)
	_check(marker != null, "Persistence fixtures can use an isolated temporary path.")
	if marker != null:
		var marker_path := marker.get_path_absolute()
		var test_dir := marker_path + ".fixtures"
		marker.close()
		DirAccess.remove_absolute(marker_path)
		if DirAccess.make_dir_absolute(test_dir) == OK:
			_test_settings(test_dir)
			await _test_settings_screen(test_dir.path_join("settings-screen.json"))
			for filename in DirAccess.get_files_at(test_dir):
				DirAccess.remove_absolute(test_dir.path_join(filename))
			DirAccess.remove_absolute(test_dir)
		else:
			_check(false, "The isolated save directory can be created.")
	print("Mobile UX smoke: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_safe_area() -> void:
	var window := Rect2i(100, 200, 1000, 2000)
	var viewport := Vector2(500, 800)
	_check(SafeArea.layout_insets(window, Rect2i(140, 280, 880, 1800), viewport).is_equal_approx(Vector4(20, 32, 40, 48)),
		"All sides use window-relative edges and their corresponding axis scale.")
	_check(SafeArea.layout_insets(window, Rect2i(-200, 300, 1200, 2500), viewport).is_equal_approx(Vector4(0, 40, 50, 0)),
		"A safe area crossing window edges is clipped before inset conversion.")
	_check(SafeArea.layout_insets(window, window, viewport) == Vector4.ZERO,
		"A matching safe rectangle introduces no margin.")
	_check(SafeArea.layout_insets(window, Rect2i(0, 0, 40, 40), viewport) == Vector4.ZERO,
		"A disjoint safe rectangle falls back to no margin.")
	_check(SafeArea.layout_insets(Rect2i(0, 0, 0, 2000), window, viewport) == Vector4.ZERO,
		"A zero-width window does not produce nonfinite margins.")
	var phone := Rect2i(0, 0, 1080, 2400)
	_check(SafeArea.layout_insets(phone, Rect2i(0, 120, 1080, 2190), Vector2(360, 800)).is_equal_approx(Vector4(0, 40, 0, 30)),
		"A synthetic portrait cutout and gesture strip scale to a compact viewport.")


func _test_settings(test_dir: String) -> void:
	var path := test_dir.path_join("old-settings.json")
	var old := Store.default_snapshot()
	old.profile.star_essence = 37
	old.profile.permanent_upgrades["arcane_focus"] = 2
	old.settings = {"music_volume": 0.29, "sfx_volume": 0.64}
	old.settlement.last_run_id = 11
	_write_fixture(path, old)
	var service := Service.new(path)
	_check(service.load_status == &"loaded" and service.balance() == 37 and service.rank(&"arcane_focus") == 2,
		"A v1 profile with existing progress is loaded with its prior values.")
	_check(_matches(service.audio_settings(), 0.29, 0.64, false),
		"An older settings object retains both volumes and defaults to normal effects.")
	_check(service.set_settings(0.29, 0.64, true) and _matches(service.audio_settings(), 0.29, 0.64, true),
		"Enabling reduced effects does not overwrite saved volumes.")
	var reopened := Service.new(path)
	_check(reopened.load_status == &"loaded" and _matches(reopened.audio_settings(), 0.29, 0.64, true),
		"Reduced effects persist through a fresh service instance.")
	_check(reopened.set_audio(0.0, 0.91) and _matches(reopened.audio_settings(), 0.0, 0.91, true),
		"Audio updates retain reduced effects, including when music is muted.")
	_check(not reopened.set_settings(-0.2, 0.91, false) and _matches(reopened.audio_settings(), 0.0, 0.91, true),
		"An invalid audio value rejects the combined settings write without changing comfort.")
	_check(reopened.set_settings(0.0, 0.91, false), "Reduced effects can be turned off again.")
	var final := Store.new(path).load_snapshot()
	_check(final.schema_version == 1 and final.settlement.last_run_id == 11
		and final.profile.star_essence == 37 and final.profile.permanent_upgrades.get("arcane_focus") == 2
		and _matches(final.settings, 0.0, 0.91, false),
		"Both changes persist in schema v1 with the original progress and settlement marker.")

	var optional_path := test_dir.path_join("no-settings.json")
	old.erase("settings")
	_write_fixture(optional_path, old)
	var optional := Service.new(optional_path)
	_check(optional.load_status == &"loaded" and _matches(optional.audio_settings(), 0.43, 0.8, false),
		"An older profile with no settings receives all three defaults.")
	old.settings = {"reduced_effects": "true"}
	var invalid_path := test_dir.path_join("invalid-setting.json")
	_write_fixture(invalid_path, old)
	_check(not bool(Service.new(invalid_path).audio_settings().reduced_effects),
		"An invalid comfort value defaults to Standard Effects.")


func _test_settings_screen(path: String) -> void:
	var app := AppScene.instantiate()
	app.set("save_path", path)
	app.set("_audio_enabled", false)
	root.add_child(app)
	await process_frame
	(app.find_child("Settings", true, false) as Button).pressed.emit()
	await process_frame
	await process_frame
	var toggle := app.find_child("ReducedEffects", true, false) as CheckButton
	if toggle == null:
		_check(false, "Settings exposes a Reduced Effects control.")
	else:
		_check(toggle.text == "Reduced Effects" and toggle.size.y >= 56.0 and not toggle.button_pressed,
			"Reduced Effects is a labeled, touch-sized control that defaults to off.")
		toggle.button_pressed = true
		(app.find_child("Back", true, false) as Button).pressed.emit()
		await process_frame
		await process_frame
		_check(Comfort.reduced_effects and bool(Service.new(path).audio_settings().reduced_effects),
			"Leaving Settings applies and persists the toggled choice.")
	app.queue_free()
	await process_frame
	Comfort.reduced_effects = false


func _write_fixture(path: String, content: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_check(false, "The legacy fixture can be written.")
		return
	file.store_string(JSON.stringify(content))
	file.close()


func _matches(settings: Dictionary, music: float, sfx: float, reduced: bool) -> bool:
	return is_equal_approx(float(settings.get("music_volume", -1.0)), music) \
		and is_equal_approx(float(settings.get("sfx_volume", -1.0)), sfx) \
		and settings.get("reduced_effects") == reduced


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr(message)
