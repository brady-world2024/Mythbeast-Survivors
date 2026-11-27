extends Node
## One music channel and a bounded pool of short presentation sounds.

const VOICE_LIMIT := 4
const VOICE_GAIN := 0.64
const RESULT_MUSIC_GAIN := 0.36
const TRACK_SWITCH_SECONDS := 0.18
const TRACK_PATHS := {
	&"menu": "res://assets/audio/grove_theme.wav",
	&"grove": "res://assets/audio/music/grove_walk.wav",
	&"boss": "res://assets/audio/music/guardian_glade.wav",
}
# Priority and minimum elapsed milliseconds between identical cues.
const CUE_PROFILES := {
	&"tap": Vector2i(2, 80),
	&"confirm": Vector2i(3, 120),
	&"bolt_fire": Vector2i(1, 110),
	&"bolt_impact": Vector2i(1, 90),
	&"player_hit": Vector2i(3, 180),
	&"enemy_hit": Vector2i(0, 120),
	&"enemy_death": Vector2i(1, 160),
	&"xp_pickup": Vector2i(1, 115),
	&"level_up": Vector2i(4, 220),
	&"upgrade_pick": Vector2i(3, 220),
	&"chain": Vector2i(2, 150),
	&"flame": Vector2i(1, 170),
	&"frost": Vector2i(1, 145),
	&"guard": Vector2i(3, 180),
	&"boss_intro": Vector2i(5, 500),
	&"boss_stomp": Vector2i(3, 175),
	&"boss_charge": Vector2i(3, 175),
	&"boss_phase": Vector2i(4, 400),
	&"victory": Vector2i(6, 700),
	&"game_over": Vector2i(6, 700),
	&"purchase": Vector2i(3, 240),
}

var _music: AudioStreamPlayer
var _enabled := false
var _backgrounded := false
var _ducked := false
var _tracks: Dictionary[StringName, AudioStream] = {}
var _cues: Dictionary[StringName, AudioStream] = {}
var _voices: Array[AudioStreamPlayer] = []
var _voice_keys: Array[StringName] = []
var _last_played: Dictionary[StringName, int] = {}
var _mood: StringName
var _requested_mood: StringName
var _transition: Tween


func configure(player: AudioStreamPlayer, enabled: bool) -> void:
	_music = player
	_enabled = enabled
	for mood: StringName in TRACK_PATHS:
		_tracks[mood] = load(TRACK_PATHS[mood]) as AudioStream
	for cue: StringName in CUE_PROFILES:
		var path := "res://assets/audio/tap.wav" if cue == &"tap" else "res://assets/audio/sfx/%s.wav" % cue
		_cues[cue] = load(path) as AudioStream
	for index in range(VOICE_LIMIT):
		var voice := AudioStreamPlayer.new()
		voice.name = "Voice%d" % (index + 1)
		voice.bus = &"SFX"
		voice.volume_linear = VOICE_GAIN
		add_child(voice)
		_voices.append(voice)
		_voice_keys.append(&"")
	set_mood(&"menu", true)


func enter_scene(mood: StringName) -> void:
	_stop_cues(mood == &"menu")
	var was_ducked := _ducked
	_ducked = false
	set_mood(mood)
	if was_ducked and _mood == mood and _requested_mood == mood:
		_music.volume_linear = 1.0


func set_mood(mood: StringName, immediate: bool = false) -> void:
	if not _tracks.has(mood) or mood == _requested_mood:
		return
	_requested_mood = mood
	_cancel_transition()
	if immediate or not _enabled or not _music.playing:
		_install_track(mood, _music_gain())
		return
	_transition = create_tween()
	_transition.tween_property(_music, "volume_linear", 0.0, TRACK_SWITCH_SECONDS)
	_transition.tween_callback(_install_track.bind(mood, 0.0))
	_transition.tween_property(_music, "volume_linear", _music_gain(), TRACK_SWITCH_SECONDS)


func set_backgrounded(backgrounded: bool) -> void:
	_backgrounded = backgrounded
	_music.stream_paused = backgrounded
	if backgrounded:
		_stop_cues()


func play_cue(cue: StringName) -> bool:
	if not CUE_PROFILES.has(cue):
		return false
	if cue == &"boss_intro":
		set_mood(&"boss")
	elif cue == &"victory" or cue == &"game_over":
		_duck_for_results()
	if not _enabled or _backgrounded:
		return false
	var profile: Vector2i = CUE_PROFILES[cue]
	var now := Time.get_ticks_msec()
	if now - _last_played.get(cue, -profile.y) < profile.y:
		return false

	var slot := _find_voice(cue, profile.x)
	if slot < 0:
		return false
	var voice := _voices[slot]
	voice.stop()
	voice.stream = _cues[cue]
	voice.play()
	_voice_keys[slot] = cue
	_last_played[cue] = now
	return true


func stop() -> void:
	_enabled = false
	_cancel_transition()
	_stop_cues()
	_music.stop()
	_music.stream = null


func _find_voice(cue: StringName, priority: int) -> int:
	var free_slot := -1
	var lower_slot := -1
	var lower_priority := priority
	for index in range(_voices.size()):
		if not _voices[index].playing:
			if free_slot == -1:
				free_slot = index
			continue
		var playing_cue := _voice_keys[index]
		if playing_cue == cue:
			return -1
		var playing_priority: int = CUE_PROFILES[playing_cue].x
		if playing_priority < lower_priority:
			lower_slot = index
			lower_priority = playing_priority
	return free_slot if free_slot >= 0 else lower_slot


func _stop_cues(keep_tap := false) -> void:
	for index in range(_voices.size()):
		if keep_tap and _voice_keys[index] == &"tap":
			continue
		_voices[index].stop()
		_voices[index].stream = null
		_voice_keys[index] = &""
	var last_tap: int = _last_played.get(&"tap", -1)
	_last_played.clear()
	if keep_tap and last_tap >= 0:
		_last_played[&"tap"] = last_tap


func _install_track(mood: StringName, gain: float) -> void:
	_music.stop()
	_music.stream = _tracks[mood]
	_music.volume_linear = gain
	_mood = mood
	if _enabled:
		_music.play()
		_music.stream_paused = _backgrounded


func _music_gain() -> float:
	return RESULT_MUSIC_GAIN if _ducked else 1.0


func _duck_for_results() -> void:
	if _ducked:
		return
	_ducked = true
	_cancel_transition()
	if _mood != _requested_mood:
		_install_track(_requested_mood, RESULT_MUSIC_GAIN)
	else:
		_music.volume_linear = RESULT_MUSIC_GAIN


func _cancel_transition() -> void:
	if _transition != null:
		_transition.kill()
		_transition = null
