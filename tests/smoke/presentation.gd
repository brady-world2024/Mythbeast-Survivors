extends SceneTree

const Arena := preload("res://features/levels/whispering_grove/whispering_grove.tscn")
const Comfort = preload("res://features/presentation/comfort.gd")

class CueRecorder extends Node:
	var calls: Array[StringName] = []

	func play_cue(cue: StringName) -> void:
		calls.append(cue)

var _arena: Node
var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var cues := CueRecorder.new()
	cues.add_to_group(&"audio_feedback")
	root.add_child(cues)
	Comfort.reduced_effects = false
	_arena = _fresh_arena()
	var hero := _arena.get_node("%Player")
	var feedback := _arena.get_node("%CombatFeedback")
	var camera := _arena.get_node("World/Camera2D") as Camera2D
	var health := hero.get_node("Health")
	var abilities: Node = hero.get("abilities")

	hero.call("receive_damage", 10)
	_check(cues.calls.count(&"player_hit") == 1 and not cues.calls.has(&"guard"),
		"An unmitigated hit gives ordinary feedback without a shield cue")
	var active: Array = feedback.get("_accents")
	_check(active.size() == 1 and int(active[0].amount) == 10, "The damage number represents the applied Health event")
	feedback.call("hit", hero, 3, true)
	_check(active.size() == 1 and int(active[0].amount) == 13, "Close hits on one actor combine into one accent")
	for index in range(36):
		feedback.call("sparkle", Vector2(index * 8.0, 0), false)
	_check(active.size() == 24, "A busy frame is bounded to 24 reusable accents")

	feedback.call("impact", 3.0)
	await _ticks(2)
	_check(camera.offset.length() > 0.0 and camera.offset.length() <= 4.3, "Boss impact offers a small optional camera accent")
	_arena.call("_set_paused", true)
	var view_age := float(active.back().age)
	await _ticks(6)
	_check(paused and float(active.back().age) == view_age and camera.offset == Vector2.ZERO,
		"Pause freezes world accents and clears camera movement")
	_arena.call("_set_paused", false)
	await _ticks(35)
	_check(active.is_empty() and not feedback.is_processing(), "Expired accents stop driving world redraw")

	abilities.call("apply_upgrade", &"iron_guard")
	hero.call("receive_damage", 10)
	_check(int(health.get("current")) == 81 and cues.calls.count(&"guard") == 1,
		"Iron Guard pulses and sounds only for a hit that it reduces")
	Comfort.reduced_effects = true
	await _ticks(36)
	hero.call("receive_damage", 10)
	feedback.call("impact", 3.0)
	await _ticks(2)
	_check(active.is_empty() and camera.offset == Vector2.ZERO and int(health.get("current")) == 72,
		"Reduced Effects skips optional accents without changing damage")

	var observed_counts: Array[int] = []
	if not "--gate" in OS.get_cmdline_user_args():
		for run in range(4):
			var previous := _arena
			_arena.queue_free()
			await process_frame
			_arena = _fresh_arena()
			await _ticks(3)
			observed_counts.append(get_node_count())
			_check(not is_instance_valid(previous), "Replacing a run releases its visual nodes")
		_check(observed_counts.min() == observed_counts.max(), "Four fresh runs retain a stable active node count")
	print("Presentation smoke: %d checks, %d failures, repeated run nodes %s" % [_checks, _failures, str(observed_counts)])
	Comfort.reduced_effects = false
	quit(0 if _failures == 0 else 1)


func _fresh_arena() -> Node:
	var arena := Arena.instantiate()
	root.add_child(arena)
	arena.get_node("%WaveSpawner").stop()
	return arena


func _ticks(count: int) -> void:
	for tick in range(count):
		await physics_frame


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
