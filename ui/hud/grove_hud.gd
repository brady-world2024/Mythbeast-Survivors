extends Control

const English = preload("res://data/localization/english.gd")

const TIME_PREVIEW := "0:00"
const XP_FILL_DURATION := 0.14

@onready var _xp_bar: ProgressBar = %XP

var _xp_tween: Tween
var _displayed_level := 0


func _ready() -> void:
	%GroveName.text = tr(English.GROVE)
	%Preview.text = tr(English.PREVIEW)
	%PauseButton.text = tr(English.PAUSE)
	%MoveHint.text = tr(English.TOUCH_MOVE_HINT if OS.has_feature("mobile") else English.KEYBOARD_MOVE_HINT)
	%TimerCaption.text = _metric(English.TIMER, TIME_PREVIEW)


func set_health(current: int, maximum: int) -> void:
	%Health.max_value = maximum
	%Health.value = current
	%HealthCaption.text = _metric(English.HEALTH, tr(English.HEALTH_FRACTION) % [current, maximum])


func set_progress(current_xp: int, required_xp: int, level: int) -> void:
	if _xp_tween != null:
		_xp_tween.kill()
	var at_maximum := required_xp == 0
	var bar_value := 1.0 if at_maximum else float(current_xp)
	_xp_bar.max_value = maxf(1.0, float(required_xp))
	%XpCaption.text = _metric(English.XP, tr(English.MAX_LEVEL) if at_maximum else (
		tr(English.XP_FRACTION) % [current_xp, required_xp]
	))
	%LevelCaption.text = _metric(English.LEVEL, str(level))
	if level != _displayed_level or at_maximum:
		_displayed_level = level
		_xp_bar.value = bar_value
		return
	_xp_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_xp_tween.tween_property(_xp_bar, "value", bar_value, XP_FILL_DURATION)


func _metric(label: String, value: String) -> String:
	return tr(English.VALUE_FORMAT) % [tr(label), value]
