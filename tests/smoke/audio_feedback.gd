extends SceneTree

const Feedback = preload("res://core/audio/audio_feedback.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var test_scene := Node.new()
	test_scene.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(test_scene)

	var music := AudioStreamPlayer.new()
	music.bus = &"Music"
	test_scene.add_child(music)
	var feedback := Feedback.new()
	test_scene.add_child(feedback)
	feedback.configure(music, true)

	_check(AudioServer.get_bus_index(&"Music") >= 0 and AudioServer.get_bus_index(&"SFX") >= 0,
		"Persistent Music and SFX buses are available.")
	_check(music.playing and music.bus == &"Music" and music.stream.resource_path.ends_with("grove_theme.wav"),
		"The original menu soundtrack plays on one music channel.")
	_check(feedback.get_child_count() == Feedback.VOICE_LIMIT, "SFX voices are allocated once.")
	for voice: AudioStreamPlayer in feedback.get_children():
		_check(voice.bus == &"SFX", "A pooled voice routes through SFX.")

	for mood: StringName in Feedback.TRACK_PATHS:
		var stream := load(Feedback.TRACK_PATHS[mood]) as AudioStreamWAV
		_check(stream != null and stream.loop_mode == AudioStreamWAV.LOOP_FORWARD,
			"The authored %s track imports as looping audio." % String(mood))
	for cue: StringName in Feedback.CUE_PROFILES:
		var path := "res://assets/audio/tap.wav" if cue == &"tap" else "res://assets/audio/sfx/%s.wav" % cue
		var stream := load(path) as AudioStreamWAV
		_check(stream != null and stream.get_length() > 0.0 and stream.get_length() < 1.0
			and stream.loop_mode == AudioStreamWAV.LOOP_DISABLED,
			"The %s cue is audible-length, bounded, and one-shot." % String(cue))

	feedback.enter_scene(&"grove")
	await create_timer(0.5).timeout
	_check(music.playing and music.stream.resource_path.ends_with("grove_walk.wav"),
		"Entering the grove replaces the menu music.")
	_check(feedback.play_cue(&"boss_intro"), "The boss entrance requests its cue.")
	await create_timer(0.5).timeout
	_check(music.playing and music.stream.resource_path.ends_with("guardian_glade.wav"),
		"The boss entrance moves the shared player to the boss track.")

	feedback.enter_scene(&"boss")
	_check(feedback.play_cue(&"bolt_fire"), "A first cast can play.")
	_check(not feedback.play_cue(&"bolt_fire"), "A duplicate cast is suppressed.")
	_check(feedback.play_cue(&"bolt_impact") and feedback.play_cue(&"flame") and feedback.play_cue(&"enemy_death"),
		"The remaining three reusable voices can fill.")
	_check(not feedback.play_cue(&"enemy_hit"), "A lower-priority impact is dropped under pressure.")
	_check(feedback.play_cue(&"victory") and music.volume_linear < 0.5,
		"Victory preempts a quiet voice and lowers music.")
	_check(feedback.get_child_count() == Feedback.VOICE_LIMIT and _playing_count(feedback) <= Feedback.VOICE_LIMIT,
		"Burst pressure leaves node and playing voice counts within bounds.")

	feedback.set_backgrounded(true)
	_check(music.stream_paused and not feedback.play_cue(&"tap") and _playing_count(feedback) == 0,
		"Backgrounding pauses music and discards stale effects.")
	feedback.set_backgrounded(false)
	_check(music.playing and not music.stream_paused, "Returning resumes the current music channel.")
	_check(feedback.play_cue(&"tap") and feedback.play_cue(&"bolt_fire"), "An exit tap can accompany an in-flight world cue.")
	feedback.enter_scene(&"menu")
	_check(_playing_count(feedback) == 1, "Returning to menus keeps the exit tap and clears world cues.")
	feedback.enter_scene(&"menu")
	_check(_playing_count(feedback) == 1, "Menu navigation lets the tap finish.")
	await create_timer(0.5).timeout
	_check(music.playing and music.stream.resource_path.ends_with("grove_theme.wav")
		and is_equal_approx(music.volume_linear, 1.0), "Returning to the menu restores the original mix.")
	feedback.stop()
	_check(not music.playing and _playing_count(feedback) == 0 and not feedback.play_cue(&"confirm"),
		"Stopping releases streams and rejects new cues.")
	test_scene.queue_free()
	# Fixed simulation FPS can outrun the separate native mixer.
	var drain_until := Time.get_ticks_msec() + 120
	while Time.get_ticks_msec() < drain_until:
		OS.delay_msec(8)
		await process_frame

	print("Audio presentation smoke: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _playing_count(this_feedback: Feedback) -> int:
	var playing := 0
	for voice: AudioStreamPlayer in this_feedback.get_children():
		if voice.playing:
			playing += 1
	return playing


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr(message)
