extends Control

signal play_requested
signal upgrades_requested
signal settings_requested
signal credits_requested

const COPY := preload("res://data/localization/english.gd")

var service: RefCounted

@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _play: Button = %Play
@onready var _upgrades: Button = %PermanentUpgrades
@onready var _settings: Button = %Settings
@onready var _credits: Button = %Credits


func _ready() -> void:
	_title.text = tr(COPY.TITLE)
	_subtitle.text = tr(COPY.SUBTITLE)
	_play.text = tr(COPY.PLAY)
	_upgrades.text = tr(COPY.PERMANENT_UPGRADES)
	_settings.text = tr(COPY.SETTINGS)
	_credits.text = tr(COPY.CREDITS)
	_play.pressed.connect(play_requested.emit)
	_upgrades.pressed.connect(upgrades_requested.emit)
	_settings.pressed.connect(settings_requested.emit)
	_credits.pressed.connect(credits_requested.emit)
	_show_save_status()


func show_settings_error() -> void:
	%SaveNotice.text = tr(COPY.SETTINGS_SAVE_FAILED)
	%SaveNotice.show()


func _show_save_status() -> void:
	if service == null:
		return
	var message := ""
	match service.get("load_status"):
		&"recovered":
			message = COPY.SAVE_RECOVERED
		&"damaged":
			message = COPY.SAVE_DAMAGED
		&"unsupported":
			message = COPY.SAVE_UNSUPPORTED
		&"unavailable":
			message = COPY.SAVE_UNAVAILABLE
	%SaveNotice.visible = not message.is_empty()
	%SaveNotice.text = tr(message)
