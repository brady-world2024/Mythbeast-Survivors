extends MarginContainer

const SIDES: Array[StringName] = [&"margin_left", &"margin_top", &"margin_right", &"margin_bottom"]

@export_range(0, 80) var gutter_override: int = 0


func _ready() -> void:
	get_viewport().size_changed.connect(_refresh)
	_refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED and is_node_ready():
		_refresh()


func _refresh() -> void:
	var gutter := gutter_override
	if gutter == 0:
		gutter = get_theme_constant(&"gutter", &"GroveSpacing")
	var insets := _mobile_insets()
	for index in SIDES.size():
		add_theme_constant_override(SIDES[index], gutter + ceili(insets[index]))


func _mobile_insets() -> Vector4:
	if not OS.has_feature("mobile"):
		return Vector4.ZERO
	var window := get_window()
	var window_rect := Rect2i(window.position, window.size)
	var safe_rect := window_rect.intersection(DisplayServer.get_display_safe_area())
	if not safe_rect.has_area():
		return Vector4.ZERO
	var scaled := get_viewport().get_visible_rect().size / Vector2(window.size)
	var before := Vector2(safe_rect.position - window_rect.position) * scaled
	var after := Vector2(window_rect.end - safe_rect.end) * scaled
	return Vector4(before.x, before.y, after.x, after.y)
