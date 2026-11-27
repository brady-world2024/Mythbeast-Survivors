extends Control

const DEAD_ZONE := 10.0
const TRAVEL_RADIUS := 64.0
const RING_RADIUS := 64.0
const THUMB_RADIUS := 18.0
const THUMB_TRAVEL := 42.0

@export var touch_region: Control

var direction := Vector2.ZERO

var _finger := -1
var _touch_origin := Vector2.ZERO
var _ring_center := Vector2.ZERO


func cancel() -> void:
	if _finger == -1:
		return
	_finger = -1
	direction = Vector2.ZERO
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if _finger != -1 or not is_visible_in_tree() or not event is InputEventScreenTouch:
		return
	if not event.pressed or event.canceled:
		return
	var region := touch_region if is_instance_valid(touch_region) else self
	var region_transform := region.get_global_transform_with_canvas()
	var region_bounds := Rect2(Vector2.ZERO, region.size)
	if not region.is_visible_in_tree() or not region_bounds.has_point(region_transform.affine_inverse() * event.position):
		return
	var to_local := get_global_transform_with_canvas().affine_inverse()
	var visual_bounds := Rect2(Vector2.ZERO, size).intersection(to_local * region_transform * region_bounds)
	var available := (visual_bounds.size * 0.5 - Vector2.ONE * (RING_RADIUS + 3.0)).max(Vector2.ZERO)
	var center := visual_bounds.get_center()
	_finger = event.index
	_touch_origin = to_local * event.position
	_ring_center = _touch_origin.clamp(center - available, center + available)
	queue_redraw()
	get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if _finger == -1:
		return
	# Continue tracking the owner before GUI input can consume its drag or release.
	if event is InputEventScreenDrag and event.index == _finger:
		var position_in_stick: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		var offset := position_in_stick - _touch_origin
		var strength := clampf(inverse_lerp(DEAD_ZONE, TRAVEL_RADIUS, offset.length()), 0.0, 1.0)
		direction = offset.normalized() * strength
		queue_redraw()
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch and event.index == _finger and (not event.pressed or event.canceled):
		cancel()
		get_viewport().set_input_as_handled()


func _draw() -> void:
	if _finger == -1:
		return
	var cream := get_theme_color(&"cream", &"GrovePalette")
	var gold := get_theme_color(&"warm_gold", &"GrovePalette")
	var pine := get_theme_color(&"pine", &"GrovePalette")
	var thumb := _ring_center + direction * THUMB_TRAVEL
	draw_circle(_ring_center, RING_RADIUS, Color(pine, 0.49), true, -1.0, true)
	draw_circle(_ring_center, RING_RADIUS, Color(pine, 0.83), false, 4.0, true)
	draw_circle(_ring_center, RING_RADIUS - 2.0, Color(cream, 0.81), false, 2.0, true)
	for axis: Vector2 in [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]:
		draw_line(_ring_center + axis * (RING_RADIUS - 11.0),
			_ring_center + axis * (RING_RADIUS - 5.0), Color(cream, 0.76), 2.0, true)
	draw_line(_ring_center, thumb, Color(gold, 0.72), 3.0, true)
	draw_circle(thumb + Vector2(0.0, 2.0), THUMB_RADIUS, Color(pine, 0.56), true, -1.0, true)
	draw_circle(thumb, THUMB_RADIUS, Color(gold, 0.95), true, -1.0, true)
	draw_circle(thumb, THUMB_RADIUS, Color(cream, 0.88), false, 2.0, true)
