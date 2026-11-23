extends Control

signal play_requested
signal settings_requested
signal credits_requested

const COPY := preload("res://data/localization/english.gd")

@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _play: Button = %Play
@onready var _settings: Button = %Settings
@onready var _credits: Button = %Credits


func _ready() -> void:
	_title.text = tr(COPY.TITLE)
	_subtitle.text = tr(COPY.SUBTITLE)
	_play.text = tr(COPY.PLAY)
	_settings.text = tr(COPY.SETTINGS)
	_credits.text = tr(COPY.CREDITS)
	_play.pressed.connect(play_requested.emit)
	_settings.pressed.connect(settings_requested.emit)
	_credits.pressed.connect(credits_requested.emit)
