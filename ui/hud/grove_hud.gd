extends Control

const English = preload("res://data/localization/english.gd")

const XP_FILL_DURATION := 0.14

@onready var _xp_bar: ProgressBar = %XP

var _xp_tween: Tween
var _boss_tween: Tween
var _displayed_level := 0


func _ready() -> void:
	%PauseButton.text = tr(English.PAUSE)
	%MoveHint.text = tr(English.TOUCH_MOVE_HINT if OS.has_feature("mobile") else English.KEYBOARD_MOVE_HINT)
	%BossWarningTitle.text = tr(English.BOSS_INCOMING)


func set_level_name(display_name: String) -> void:
	%GroveName.text = tr(display_name)


func set_wave(index: int, wave_count: int) -> void:
	%WaveCaption.text = tr(English.FINAL_WAVE) if index == wave_count - 1 and wave_count > 1 else (
		tr(English.WAVE_FORMAT) % (index + 1)
	)


func set_clock(elapsed: int, duration: int) -> void:
	%TimerCaption.text = tr(English.SURVIVAL_CLOCK) % [format_time(elapsed), format_time(duration)]


func show_boss_intro(display_name: String) -> void:
	%BossWarningName.text = tr(display_name)
	%BossWarning.show()


func show_boss(display_name: String, maximum: int) -> void:
	%BossWarning.hide()
	%WaveCaption.text = tr(English.BOSS_BATTLE)
	%BossName.text = tr(display_name)
	%BossHealth.max_value = maximum
	%BossHealth.value = maximum
	%BossHealthValue.text = tr(English.HEALTH_FRACTION) % [maximum, maximum]
	set_boss_phase(1)
	%BossVitals.show()


func set_boss_health(current: int, maximum: int) -> void:
	%BossHealthValue.text = tr(English.HEALTH_FRACTION) % [current, maximum]
	if _boss_tween != null:
		_boss_tween.kill()
	_boss_tween = create_tween()
	_boss_tween.tween_property(%BossHealth, "value", float(current), XP_FILL_DURATION)


func set_boss_phase(phase: int) -> void:
	%BossPhase.text = tr(English.BOSS_PHASE) % phase


func hide_boss_warning() -> void:
	%BossWarning.hide()


static func format_time(seconds: int) -> String:
	return "%02d:%02d" % [floori(seconds / 60.0), seconds % 60]


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
