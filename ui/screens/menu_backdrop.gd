extends Control
## A small number of drifting lights in the forest illustration's reference space.

const Comfort = preload("res://features/presentation/comfort.gd")
const REFERENCE_SIZE := Vector2(540.0, 960.0)
const UPDATE_INTERVAL := 1.0 / 24.0
const MOTE_COLOR := Color(0.99, 0.90, 0.64)
const MOTES := [
	Vector2(79, 436), Vector2(99, 485), Vector2(140, 534), Vector2(133, 375),
	Vector2(162, 420), Vector2(186, 496), Vector2(195, 391), Vector2(226, 551),
	Vector2(326, 555), Vector2(353, 405), Vector2(372, 486), Vector2(386, 443),
	Vector2(412, 531), Vector2(429, 398), Vector2(445, 474), Vector2(464, 426),
]

var _elapsed := 0.0
var _time_since_draw := 0.0


func _ready() -> void:
	set_process(not Comfort.reduced_effects)


func _process(delta: float) -> void:
	_elapsed += delta
	_time_since_draw += delta
	if _time_since_draw >= UPDATE_INTERVAL:
		_time_since_draw = fmod(_time_since_draw, UPDATE_INTERVAL)
		queue_redraw()


func _draw() -> void:
	if Comfort.reduced_effects:
		return
	var cover := maxf(size.x / REFERENCE_SIZE.x, size.y / REFERENCE_SIZE.y)
	var image_offset := (size - REFERENCE_SIZE * cover) * 0.5
	for index in MOTES.size():
		var phase := _elapsed * 0.8 + index * 2.13
		var drift := Vector2(cos(phase * 0.72) * 7.0, sin(phase) * 9.0)
		var point: Vector2 = image_offset + (MOTES[index] + drift) * cover
		var alpha := 0.32 + 0.23 * sin(phase * 1.36)
		var radius := (1.55 + 0.40 * (index % 3)) * cover
		draw_circle(point, radius * 2.6, Color(MOTE_COLOR, alpha * 0.15), true, -1.0, true)
		draw_circle(point, radius, Color(MOTE_COLOR, alpha), true, -1.0, true)
