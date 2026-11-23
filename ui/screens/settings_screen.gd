extends Control

signal back_requested

const English = preload("res://data/localization/english.gd")

@onready var _heading: Label = %Heading
@onready var _music_label: Label = %MusicLabel
@onready var _sfx_label: Label = %SFXLabel
@onready var _music: HSlider = %Music
@onready var _sfx: HSlider = %SFX
@onready var _music_percent: Label = %MusicPercent
@onready var _sfx_percent: Label = %SFXPercent
@onready var _back: Button = %Back


func _ready() -> void:
	_heading.text = tr(English.SETTINGS)
	_music_label.text = tr(English.MUSIC_VOLUME)
	_sfx_label.text = tr(English.SFX_VOLUME)
	_music.accessibility_name = _music_label.text
	_sfx.accessibility_name = _sfx_label.text
	_back.text = tr(English.BACK)
	_back.pressed.connect(back_requested.emit)
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
