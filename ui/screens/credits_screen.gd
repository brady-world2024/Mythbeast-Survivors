extends Control

signal back_requested

const English = preload("res://data/localization/english.gd")

@onready var _heading: Label = %Heading
@onready var _game_title: Label = %GameTitle
@onready var _description: Label = %Description
@onready var _engine_credit: Label = %EngineCredit
@onready var _back: Button = %Back


func _ready() -> void:
	_heading.text = tr(English.CREDITS)
	_game_title.text = tr(English.TITLE)
	_description.text = tr(English.CREDITS_DESCRIPTION)
	_engine_credit.text = tr(English.ENGINE_CREDIT)
	_back.text = tr(English.BACK)
	_back.pressed.connect(back_requested.emit)
