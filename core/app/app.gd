extends Node

enum Screen { MENU, SETTINGS, CREDITS, STAGES, UPGRADES, GROVE }

const ProgressionService = preload("res://core/persistence/progression_service.gd")
const AudioFeedback = preload("res://core/audio/audio_feedback.gd")
const Comfort = preload("res://features/presentation/comfort.gd")
const AUDIO_DRAIN_MS := 120
const SCREEN_PATHS: Dictionary[Screen, String] = {
	Screen.MENU: "res://ui/screens/main_menu.tscn",
	Screen.SETTINGS: "res://ui/screens/settings_screen.tscn",
	Screen.CREDITS: "res://ui/screens/credits_screen.tscn",
	Screen.STAGES: "res://ui/screens/stage_select.tscn",
	Screen.UPGRADES: "res://ui/screens/permanent_upgrades.tscn",
}

@export var save_path := "user://savegame.json"

@onready var _host: Node = $ScreenHost
@onready var _music: AudioStreamPlayer = $Music
@onready var _audio_feedback: AudioFeedback = $AudioFeedback

var service: ProgressionService

var _screen: Node
var _active_route := Screen.MENU
var _active_stage: StringName
var _active_difficulty: StringName
var _audio_enabled := DisplayServer.get_name() != "headless"
var _quitting := false


func _ready() -> void:
	service = ProgressionService.new(save_path)
	_restore_saved_audio()
	_audio_feedback.configure(_music, _audio_enabled)
	_show_screen(Screen.MENU)


func _notification(what: int) -> void:
	if not is_node_ready():
		return
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			request_quit()
		NOTIFICATION_APPLICATION_PAUSED:
			_flush_settings()
			_audio_feedback.set_backgrounded(true)
		NOTIFICATION_APPLICATION_RESUMED:
			_audio_feedback.set_backgrounded(false)
		NOTIFICATION_WM_GO_BACK_REQUEST:
			match _active_route:
				Screen.MENU:
					request_quit()
				Screen.SETTINGS, Screen.CREDITS, Screen.STAGES, Screen.UPGRADES:
					_show_screen.call_deferred(Screen.MENU)


func request_quit(exit_code: int = 0) -> void:
	if _quitting:
		return
	_quitting = true
	_flush_settings()
	if _audio_enabled:
		_audio_feedback.stop()
		# Native mixer work runs on wall time even during fixed-rate QA runs.
		var drain_until := Time.get_ticks_msec() + AUDIO_DRAIN_MS
		while Time.get_ticks_msec() < drain_until:
			await get_tree().process_frame
	get_tree().quit(exit_code)


func _choose_stage(stage: StringName, difficulty: StringName, source_id: int) -> void:
	if not _is_current(Screen.STAGES, source_id):
		return
	if not _start_run(stage, difficulty):
		_screen.call(&"show_start_error")


func _restart_grove(source_id: int) -> void:
	if _is_current(Screen.GROVE, source_id):
		_start_run(_active_stage, _active_difficulty)


func _start_run(stage: StringName, difficulty: StringName) -> bool:
	if _quitting:
		return false
	var config := service.begin_run(stage, difficulty)
	var scene := config.get("scene") as PackedScene
	if scene == null or not scene.can_instantiate():
		return false

	var next := scene.instantiate()
	next.call(&"configure_run", config, service.settle)
	next.connect(&"back_requested", _show_screen.bind(Screen.MENU), CONNECT_DEFERRED)
	next.connect(&"stages_requested", _show_screen.bind(Screen.STAGES), CONNECT_DEFERRED)
	next.connect(&"restart_requested", _restart_grove.bind(next.get_instance_id()), CONNECT_DEFERRED)
	_active_stage = stage
	_active_difficulty = difficulty
	_replace_screen(next, Screen.GROVE)
	_audio_feedback.play_cue(&"confirm")
	return true


func _is_current(route: Screen, source_id: int) -> bool:
	return _active_route == route and is_instance_valid(_screen) and _screen.get_instance_id() == source_id


func _show_screen(destination: Screen) -> void:
	if _quitting or (_screen != null and destination == _active_route):
		return
	var scene := load(SCREEN_PATHS[destination]) as PackedScene
	if scene == null:
		push_error("Unable to load the requested screen.")
		return
	var next := scene.instantiate()
	match destination:
		Screen.MENU:
			next.set("service", service)
			next.connect(&"play_requested", _show_screen.bind(Screen.STAGES), CONNECT_DEFERRED)
			next.connect(&"upgrades_requested", _show_screen.bind(Screen.UPGRADES), CONNECT_DEFERRED)
			next.connect(&"settings_requested", _show_screen.bind(Screen.SETTINGS), CONNECT_DEFERRED)
			next.connect(&"credits_requested", _show_screen.bind(Screen.CREDITS), CONNECT_DEFERRED)
		Screen.STAGES:
			next.set("service", service)
			next.set("selected_stage_id", _active_stage)
			next.set("selected_difficulty_id", _active_difficulty)
			next.connect(&"start_requested", _choose_stage.bind(next.get_instance_id()), CONNECT_DEFERRED)
		Screen.SETTINGS, Screen.UPGRADES:
			next.set("service", service)
	if destination != Screen.MENU:
		next.connect(&"back_requested", _show_screen.bind(Screen.MENU), CONNECT_DEFERRED)
	_replace_screen(next, destination)


func _replace_screen(next: Node, destination: Screen) -> void:
	var settings_saved := _flush_settings()
	if not settings_saved:
		_restore_saved_audio()
	get_tree().paused = false
	if is_instance_valid(_screen):
		_host.remove_child(_screen)
		_screen.queue_free()
	_screen = next
	_active_route = destination
	_host.add_child(_screen)
	_audio_feedback.enter_scene(&"grove" if destination == Screen.GROVE else &"menu")
	if not settings_saved and destination == Screen.MENU:
		_screen.call(&"show_settings_error")
	if _audio_enabled:
		var source_id := _screen.get_instance_id()
		for node in _screen.find_children("*", "Button", true, false):
			var button := node as Button
			button.pressed.connect(_play_tap.bind(destination, source_id))


func _flush_settings() -> bool:
	if _active_route == Screen.SETTINGS and is_instance_valid(_screen):
		return bool(_screen.call(&"flush_settings"))
	return true


func _restore_saved_audio() -> void:
	var settings := service.audio_settings()
	Comfort.reduced_effects = bool(settings.get("reduced_effects", false))
	_apply_sound(&"Music", float(settings["music_volume"]))
	_apply_sound(&"SFX", float(settings["sfx_volume"]))


func _apply_sound(bus_name: StringName, gain: float) -> void:
	var bus := AudioServer.get_bus_index(bus_name)
	if bus < 0:
		return
	if gain > 0.0:
		AudioServer.set_bus_volume_linear(bus, gain)
	AudioServer.set_bus_mute(bus, gain <= 0.0)


func _play_tap(route: Screen, source_id: int) -> void:
	if not _quitting and _is_current(route, source_id):
		_audio_feedback.play_cue(&"tap")
