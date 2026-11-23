extends Control

const English = preload("res://data/localization/english.gd")

const HEALTH_PREVIEW := "100 / 100"
const XP_PREVIEW := "0 / 10"
const LEVEL_PREVIEW := "1"
const TIME_PREVIEW := "0:00"


func _ready() -> void:
	%GroveName.text = tr(English.GROVE)
	%Preview.text = tr(English.PREVIEW)
	%PauseButton.text = tr(English.PAUSE)
	%MoveHint.text = tr(English.TOUCH_MOVE_HINT if OS.has_feature("mobile") else English.KEYBOARD_MOVE_HINT)
	%HealthCaption.text = _metric(English.HEALTH, HEALTH_PREVIEW)
	%XpCaption.text = _metric(English.XP, XP_PREVIEW)
	%LevelCaption.text = _metric(English.LEVEL, LEVEL_PREVIEW)
	%TimerCaption.text = _metric(English.TIMER, TIME_PREVIEW)


func _metric(label: String, value: String) -> String:
	return tr(English.VALUE_FORMAT) % [tr(label), value]
