extends Node2D

signal back_requested
signal restart_requested

const English = preload("res://data/localization/english.gd")
const BasicAttack = preload("res://features/combat/basic_attack.gd")
const Player = preload("res://features/player/player.gd")
const SlimeSpawner = preload("res://features/enemies/slime_spawner.gd")
const FloatingStick = preload("res://ui/components/floating_stick.gd")
const GroveHud = preload("res://ui/hud/grove_hud.gd")

@onready var _player: Player = %Player
@onready var _spawner: SlimeSpawner = %SlimeSpawner
@onready var _hud: GroveHud = %HUD
@onready var _stick: FloatingStick = %MovementStick
@onready var _pause_overlay: Control = %PauseOverlay
@onready var _pause_panel: Control = %PausePanel
@onready var _game_over_panel: Control = %GameOverPanel
@onready var _pause_button: Button = _hud.get_node("%PauseButton")
@onready var _resume: Button = %Resume
@onready var _try_again: Button = %TryAgain

var _defeated := false
var _transition_requested := false


func _ready() -> void:
	var basic_attack := _player.get_node("BasicAttack") as BasicAttack
	basic_attack.projectile_parent = %Effects
	_player.health.changed.connect(_hud.set_health)
	_player.health.depleted.connect(_show_game_over)
	_hud.set_health(_player.health.current, _player.health.maximum)
	_stick.touch_region = _hud.get_node("%MovementArea")
	get_viewport().size_changed.connect(_clear_movement)
	%PauseHeading.text = tr(English.PAUSED)
	_resume.text = tr(English.RESUME)
	%BackToMenu.text = tr(English.BACK_TO_MENU)
	%GameOverHeading.text = tr(English.GAME_OVER)
	%GameOverMessage.text = tr(English.GAME_OVER_MESSAGE)
	_try_again.text = tr(English.TRY_AGAIN)
	%MainMenu.text = tr(English.MAIN_MENU)
	_pause_button.pressed.connect(_set_paused.bind(true))
	_resume.pressed.connect(_set_paused.bind(false))
	%BackToMenu.pressed.connect(_request_menu)
	_try_again.pressed.connect(_request_restart)
	%MainMenu.pressed.connect(_request_menu)
	_spawner.start(_player, %Entities, _spawn_bounds())


func _physics_process(_delta: float) -> void:
	if get_tree().paused:
		return
	var direction := _stick.direction
	if direction.is_zero_approx():
		direction = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	_player.move_direction = direction


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		_set_paused(not _pause_overlay.visible)
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if not is_node_ready():
		return
	match what:
		NOTIFICATION_APPLICATION_PAUSED:
			_set_paused(true)
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			_clear_movement()
		NOTIFICATION_WM_GO_BACK_REQUEST:
			if _defeated:
				_request_menu()
			else:
				_set_paused(not _pause_overlay.visible)


func _set_paused(value: bool) -> void:
	if _defeated or _pause_overlay.visible == value:
		return
	_apply_pause(value, _resume if value else _pause_button)


func _apply_pause(value: bool, focus_target: Control) -> void:
	if value:
		_clear_movement()
	_pause_overlay.visible = value
	_pause_button.disabled = value
	get_tree().paused = value
	if not OS.has_feature("mobile"):
		focus_target.grab_focus()


func _show_game_over() -> void:
	if _defeated:
		return
	_defeated = true
	_spawner.stop()
	_pause_panel.hide()
	_game_over_panel.show()
	_apply_pause(true, _try_again)


func _request_menu() -> void:
	if _transition_requested:
		return
	_transition_requested = true
	back_requested.emit()


func _request_restart() -> void:
	if not _defeated or _transition_requested:
		return
	_transition_requested = true
	restart_requested.emit()


func _spawn_bounds() -> Rect2:
	var west: CollisionShape2D = $World/ArenaBounds/West
	var east: CollisionShape2D = $World/ArenaBounds/East
	var north: CollisionShape2D = $World/ArenaBounds/North
	var south: CollisionShape2D = $World/ArenaBounds/South
	var top_left := Vector2(west.global_position.x, north.global_position.y)
	var bottom_right := Vector2(east.global_position.x, south.global_position.y)
	return Rect2(top_left, bottom_right - top_left)


func _clear_movement() -> void:
	_stick.cancel()
	_player.move_direction = Vector2.ZERO
