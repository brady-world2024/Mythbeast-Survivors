extends RefCounted
## Gameplay events may request audio even when an isolated test has no playback.

static func sound(source: Node, cue: StringName) -> void:
	if not source.is_inside_tree():
		return
	var output := source.get_tree().get_first_node_in_group(&"audio_feedback")
	if output != null:
		output.call(&"play_cue", cue)
