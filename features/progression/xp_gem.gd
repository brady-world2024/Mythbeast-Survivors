extends Area2D
## Waits for the pickup body to enter range before using physics ticks.

const Health = preload("res://features/combat/health.gd")
const GLOW_COLOR := Color("#aefff2")
const SPARKLE_DURATION := 0.16

signal collected(amount: int)

@export_range(1.0, 300.0, 1.0) var pickup_radius := 28.0
@export_range(1.0, 400.0, 1.0) var attraction_radius := 90.0
@export_range(1.0, 1000.0, 1.0) var attraction_speed := 235.0

var xp_value := 0

@onready var _visual: Sprite2D = $Crystal

var _player: CharacterBody2D
var _health: Health
var _picked_up := false
var _hover: Tween


func setup(player: CharacterBody2D, amount: int) -> void:
	_player = player
	_health = player.get_node_or_null(^"Health") as Health if is_instance_valid(player) else null
	xp_value = maxi(0, amount)


func _ready() -> void:
	if xp_value == 0:
		queue_free()
		return
	var zone := $AttractionZone.shape as CircleShape2D
	zone.radius = maxf(attraction_radius, pickup_radius)
	set_physics_process(false)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	var hover_time := 0.68 + float(get_instance_id() % 7) * 0.035
	_hover = create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_hover.tween_property(_visual, "position:y", -5.0, hover_time)
	_hover.tween_property(_visual, "position:y", -1.0, hover_time)


func _physics_process(delta: float) -> void:
	if not _can_collect():
		set_physics_process(false)
		return
	var destination := _player.global_position
	var distance_squared := global_position.distance_squared_to(destination)
	if distance_squared > pickup_radius * pickup_radius:
		if distance_squared > attraction_radius * attraction_radius:
			return
		global_position = global_position.move_toward(destination, attraction_speed * delta)
	if global_position.distance_squared_to(destination) <= pickup_radius * pickup_radius:
		_collect()


func _on_body_entered(body: Node2D) -> void:
	if body == _player and _can_collect():
		set_physics_process(true)


func _on_body_exited(body: Node2D) -> void:
	if body == _player:
		set_physics_process(false)


func _can_collect() -> bool:
	return (
		not _picked_up and is_instance_valid(_player) and not _player.is_queued_for_deletion()
		and is_instance_valid(_health) and _health.is_alive()
	)


func _collect() -> void:
	_picked_up = true
	set_physics_process(false)
	set_deferred(&"monitoring", false)
	remove_from_group(&"xp_gems")
	_hover.kill()
	_visual.modulate = GLOW_COLOR
	var sparkle := create_tween().set_parallel(true)
	sparkle.tween_property(_visual, "scale", Vector2(1.65, 1.65), SPARKLE_DURATION)
	sparkle.tween_property(_visual, "position:y", _visual.position.y - 12.0, SPARKLE_DURATION)
	sparkle.tween_property(_visual, "modulate:a", 0.0, SPARKLE_DURATION)
	sparkle.chain().tween_callback(queue_free)
	collected.emit(xp_value)
