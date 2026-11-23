extends Node2D

signal back_requested

const English = preload("res://data/localization/english.gd")
const Player = preload("res://features/player/player.gd")
const ForestSlime = preload("res://features/enemies/forest_slime.gd")
const FloatingStick = preload("res://ui/components/floating_stick.gd")
const GroveHud = preload("res://ui/hud/grove_hud.gd")

@onready var _player: Player = %Player
@onready var _slime: ForestSlime = %ForestSlime
@onready var _hud: GroveHud = %HUD
@onready var _stick: FloatingStick = %MovementStick
@onready var _pause_overlay: Control = %PauseOverlay
@onready var _pause_heading: Label = %PauseHeading
@onready var _pause_button: Button = _hud.get_node("%PauseButton")
@onready var _resume: Button = %Resume
@onready var _back_to_menu: Button = %BackToMenu

var _defeated := false


func _ready() -> void:
	_slime.target = _player
	_player.health.changed.connect(_hud.set_health)
	_player.health.depleted.connect(_show_defeat)
	_hud.set_health(_player.health.current, _player.health.maximum)
	_stick.touch_region = _hud.get_node("%MovementArea")
	get_viewport().size_changed.connect(_clear_movement)
	_pause_heading.text = tr(English.PAUSED)
	_resume.text = tr(English.RESUME)
	_back_to_menu.text = tr(English.BACK_TO_MENU)
	_pause_button.pressed.connect(_set_paused.bind(true))
	_resume.pressed.connect(_set_paused.bind(false))
	_back_to_menu.pressed.connect(back_requested.emit)


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
				back_requested.emit()
			else:
				_set_paused(not _pause_overlay.visible)


func _set_paused(value: bool) -> void:
	if _pause_overlay.visible == value or (_defeated and not value):
		return
	if value:
		_clear_movement()
	_pause_overlay.visible = value
	_pause_button.disabled = value
	get_tree().paused = value
	if not OS.has_feature("mobile"):
		var focus_target := _pause_button
		if value:
			focus_target = _back_to_menu if _defeated else _resume
		focus_target.grab_focus()


func _show_defeat() -> void:
	_defeated = true
	_pause_heading.text = tr(English.DEFEAT)
	_resume.hide()
	_set_paused(true)


func _clear_movement() -> void:
	_stick.cancel()
	_player.move_direction = Vector2.ZERO
