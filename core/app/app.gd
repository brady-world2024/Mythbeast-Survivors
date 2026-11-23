extends Node

enum Screen { MENU, SETTINGS, CREDITS, GROVE }

const AUDIO_DRAIN_SECONDS := 0.1
const SCREEN_PATHS: Dictionary[Screen, String] = {
	Screen.MENU: "res://ui/screens/main_menu.tscn",
	Screen.SETTINGS: "res://ui/screens/settings_screen.tscn",
	Screen.CREDITS: "res://ui/screens/credits_screen.tscn",
	Screen.GROVE: "res://features/levels/whispering_grove/whispering_grove.tscn",
}

@onready var _host: Node = $ScreenHost
@onready var _music: AudioStreamPlayer = $Music
@onready var _tap: AudioStreamPlayer = $Tap

var _screen: Node
var _active_route := Screen.MENU
var _audio_enabled := DisplayServer.get_name() != "headless"
var _quitting := false


func _ready() -> void:
	_show_screen(Screen.MENU)
	if _audio_enabled:
		_music.play()


func _notification(what: int) -> void:
	if not is_node_ready():
		return
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		request_quit()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		match _active_route:
			Screen.MENU:
				request_quit()
			Screen.SETTINGS, Screen.CREDITS:
				_show_screen.call_deferred(Screen.MENU)


func request_quit(exit_code: int = 0) -> void:
	if _quitting:
		return
	_quitting = true
	if _audio_enabled:
		_music.stop()
		_tap.stop()
		# Playback stops on the audio mixer, so give it time to release its streams.
		await get_tree().create_timer(AUDIO_DRAIN_SECONDS).timeout
	get_tree().quit(exit_code)


func _show_screen(destination: Screen) -> void:
	if _quitting or (_screen != null and destination == _active_route):
		return
	var path := SCREEN_PATHS[destination]
	var scene := load(path) as PackedScene
	if scene == null:
		push_error("Unable to open screen: " + path)
		return

	var next := scene.instantiate()
	if destination == Screen.MENU:
		next.connect(&"play_requested", _show_screen.bind(Screen.GROVE), CONNECT_DEFERRED)
		next.connect(&"settings_requested", _show_screen.bind(Screen.SETTINGS), CONNECT_DEFERRED)
		next.connect(&"credits_requested", _show_screen.bind(Screen.CREDITS), CONNECT_DEFERRED)
	else:
		next.connect(&"back_requested", _show_screen.bind(Screen.MENU), CONNECT_DEFERRED)

	get_tree().paused = false
	if is_instance_valid(_screen):
		_host.remove_child(_screen)
		_screen.queue_free()
	_screen = next
	_active_route = destination
	_host.add_child(_screen)
	if _audio_enabled:
		for node in _screen.find_children("*", "Button", true, false):
			var button := node as Button
			button.pressed.connect(_play_tap)


func _play_tap() -> void:
	if not _quitting:
		_tap.play()
