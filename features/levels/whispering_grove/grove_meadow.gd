extends Node2D
## Sparse motes drift at the edges of the painted clearing.

const MOTE_CYCLE_SECONDS := 9.0
const MOTE_POSITIONS := [
	Vector2(-158, -337), Vector2(132, -281), Vector2(-191, -109),
	Vector2(187, -47), Vector2(-166, 118), Vector2(194, 239),
	Vector2(-134, 353), Vector2(133, 412),
]
const MOTE_COLOR := Color("#f8eed7")

var _cycle := 0.0


func _process(delta: float) -> void:
	_cycle = fposmod(_cycle + delta / MOTE_CYCLE_SECONDS, 1.0)
	queue_redraw()


func _draw() -> void:
	for index in MOTE_POSITIONS.size():
		var phase := (_cycle + 0.37 * index) * TAU
		var drift := Vector2(cos(phase) * 7.0, sin(phase) * 11.0)
		var brightness := 0.32 + 0.19 * sin(phase + 1.2)
		var position_on_ground: Vector2 = MOTE_POSITIONS[index] + drift
		draw_circle(position_on_ground, 4.4, Color(MOTE_COLOR, brightness * 0.24), true, -1.0, true)
		draw_circle(position_on_ground, 1.6, Color(MOTE_COLOR, brightness), true, -1.0, true)
