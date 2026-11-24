extends SceneTree

const AppFixture = preload("res://tests/support/app_fixture.gd")


func _initialize() -> void:
	_boot.call_deferred()


func _boot() -> void:
	var app := AppFixture.instantiate()
	if app == null:
		quit(1)
		return
	root.add_child(app)
	await process_frame
	var host := app.get_node("ScreenHost")
	var menu: Node = host.get_child(0)
	app.call(&"request_quit", 0 if menu != null and menu.name == &"MainMenu" else 1)
