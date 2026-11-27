extends Control

signal back_requested

const English = preload("res://data/localization/english.gd")
const Comfort = preload("res://features/presentation/comfort.gd")

var service: RefCounted
var _pending_save := false

@onready var _heading: Label = %Heading
@onready var _music_label: Label = %MusicLabel
@onready var _sfx_label: Label = %SFXLabel
@onready var _music: HSlider = %Music
@onready var _sfx: HSlider = %SFX
@onready var _reduced_effects: CheckButton = %ReducedEffects
@onready var _music_percent: Label = %MusicPercent
@onready var _sfx_percent: Label = %SFXPercent
@onready var _back: Button = %Back
@onready var _save_timer: Timer = %SaveTimer


func _ready() -> void:
	_heading.text = tr(English.SETTINGS)
	_music_label.text = tr(English.MUSIC_VOLUME)
	_sfx_label.text = tr(English.SFX_VOLUME)
	_music.accessibility_name = _music_label.text
	_sfx.accessibility_name = _sfx_label.text
	_reduced_effects.text = tr(English.REDUCED_EFFECTS)
	%ReducedEffectsDescription.text = tr(English.REDUCED_EFFECTS_DESCRIPTION)
	_reduced_effects.accessibility_description = %ReducedEffectsDescription.text
	_reduced_effects.set_pressed_no_signal(Comfort.reduced_effects)
	_reduced_effects.toggled.connect(func(_pressed: bool) -> void: _schedule_save())
	_back.text = tr(English.BACK)
	_back.pressed.connect(back_requested.emit)
	%SettingsRetry.text = tr(English.RETRY_SAVE)
	%SettingsRetry.pressed.connect(flush_settings)
	_save_timer.timeout.connect(flush_settings)
	_connect_slider(_music, _music_percent, &"Music")
	_connect_slider(_sfx, _sfx_percent, &"SFX")


func _connect_slider(slider: HSlider, percent_label: Label, bus_name: StringName) -> void:
	var bus := AudioServer.get_bus_index(bus_name)
	if bus < 0:
		slider.editable = false
		push_error("Missing audio bus: " + bus_name)
		return

	var gain := 0.0 if AudioServer.is_bus_mute(bus) else AudioServer.get_bus_volume_linear(bus)
	slider.set_value_no_signal(gain * 100.0)
	percent_label.text = tr(English.PERCENT_FORMAT) % roundi(slider.value)
	slider.value_changed.connect(_set_volume.bind(bus, percent_label))


func _set_volume(percent: float, bus: int, percent_label: Label) -> void:
	if percent > 0.0:
		AudioServer.set_bus_volume_linear(bus, percent / 100.0)
	AudioServer.set_bus_mute(bus, percent <= 0.0)
	percent_label.text = tr(English.PERCENT_FORMAT) % roundi(percent)
	_schedule_save()


func _schedule_save() -> void:
	if service != null:
		_pending_save = true
		_save_timer.start()


func flush_settings() -> bool:
	if service == null or not _pending_save:
		return true
	_save_timer.stop()
	var reduced := _reduced_effects.button_pressed
	var saved := bool(service.call(&"set_settings", _music.value / 100.0, _sfx.value / 100.0, reduced))
	if saved:
		Comfort.reduced_effects = reduced
	_pending_save = not saved
	%SettingsStatus.text = tr(English.SETTINGS_SAVE_FAILED)
	%SettingsStatus.visible = not saved
	%SettingsRetry.visible = not saved
	return saved
