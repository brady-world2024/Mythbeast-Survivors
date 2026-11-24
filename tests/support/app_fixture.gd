extends RefCounted
## Keeps automated sessions out of the player's real save.

static func isolated_path() -> String:
	var scratch := OS.get_environment("MYTHBEAST_TEST_SAVE_DIR")
	if scratch.is_empty():
		scratch = OS.get_environment("TMPDIR")
	if scratch.is_empty():
		scratch = "user://test-profiles"
	return scratch.path_join("mythbeast-%d-%d.json" % [OS.get_process_id(), Time.get_ticks_usec()])


static func instantiate(profile_path: String = "") -> Node:
	var scene := load(str(ProjectSettings.get_setting("application/run/main_scene"))) as PackedScene
	if scene == null:
		return null
	var app := scene.instantiate()
	app.set("save_path", profile_path if not profile_path.is_empty() else isolated_path())
	return app
