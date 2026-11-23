extends Node2D

signal back_requested

const English = preload("res://data/localization/english.gd")

@onready var _pause_overlay: Control = %PauseOverlay
@onready var _pause_heading: Label = %PauseHeading
@onready var _pause_button: Button = %HUD.get_node("%PauseButton")
@onready var _resume: Button = %Resume
@onready var _back_to_menu: Button = %BackToMenu


func _ready() -> void:
	_pause_heading.text = tr(English.PAUSED)
	_resume.text = tr(English.RESUME)
	_back_to_menu.text = tr(English.BACK_TO_MENU)
	_pause_button.pressed.connect(_set_paused.bind(true))
	_resume.pressed.connect(_set_paused.bind(false))
	_back_to_menu.pressed.connect(back_requested.emit)


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
		NOTIFICATION_WM_GO_BACK_REQUEST:
			_set_paused(not _pause_overlay.visible)


func _set_paused(value: bool) -> void:
	if _pause_overlay.visible == value:
		return
	_pause_overlay.visible = value
	_pause_button.disabled = value
	get_tree().paused = value
	if not OS.has_feature("mobile"):
		var focus_target := _resume if value else _pause_button
		focus_target.grab_focus()
