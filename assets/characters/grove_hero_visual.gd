extends Node2D
## Original hero presentation. Local origin is the center of the feet.

const IDLE_DURATION := 1.9
const IDLE_HEIGHT := 2.4
const SHADOW_COLOR := Color(0.12, 0.2, 0.17, 0.14)

@onready var _body: Sprite2D = $Body


func _ready() -> void:
	var idle := create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	idle.tween_property(_body, "position:y", -IDLE_HEIGHT, IDLE_DURATION / 2.0)
	idle.tween_property(_body, "position:y", 0.0, IDLE_DURATION / 2.0)


func _draw() -> void:
	for ring in range(5):
		var radius := Vector2(38.0 - 3.0 * ring, 11.0 - 1.3 * ring)
		draw_set_transform(Vector2(0, 1.0), 0.0, Vector2(1.0, radius.y / radius.x))
		draw_circle(Vector2.ZERO, radius.x, SHADOW_COLOR, true, -1.0, true)
