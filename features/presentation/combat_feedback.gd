extends Node2D
## Bounded world-space accents. Authoritative health and movement stay in combat.

const Comfort = preload("res://features/presentation/comfort.gd")
const LIFETIME := 0.52
const MAX_ACCENTS := 24
const GOLD := Color("#ffe5a6")
const CORAL := Color("#f18d86")
const MINT := Color("#b4f1cb")
const INK := Color("#354b45")

class Accent:
	var position: Vector2
	var owner_id: int
	var amount: int
	var color: Color
	var age := 0.0

var camera: Camera2D

var _accents: Array[Accent] = []
var _shake_time := 0.0
var _shake_strength := 0.0


func _ready() -> void:
	z_index = 5
	set_process(false)


func hit(actor: Node2D, amount: int, hero := false) -> void:
	if Comfort.reduced_effects or amount <= 0:
		return
	for item in _accents:
		if item.owner_id == actor.get_instance_id() and item.age < 0.13:
			item.amount += amount
			queue_redraw()
			return
	_append(actor.global_position, CORAL if hero else GOLD, amount, actor.get_instance_id())


func sparkle(position_in_world: Vector2, gold := false) -> void:
	if not Comfort.reduced_effects:
		_append(position_in_world, GOLD if gold else MINT, 0, 0)


func impact(strength: float) -> void:
	if Comfort.reduced_effects or not is_instance_valid(camera):
		return
	_shake_time = 0.17
	_shake_strength = clampf(strength, 0.0, 3.0)
	set_process(true)


func clear_shake() -> void:
	_shake_time = 0.0
	if is_instance_valid(camera):
		camera.offset = Vector2.ZERO


func _append(position_in_world: Vector2, color: Color, amount: int, owner_id: int) -> void:
	if _accents.size() == MAX_ACCENTS:
		_accents.pop_front()
	var item := Accent.new()
	item.position = to_local(position_in_world)
	item.color = color
	item.amount = amount
	item.owner_id = owner_id
	_accents.append(item)
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	for index in range(_accents.size() - 1, -1, -1):
		_accents[index].age += delta
		if _accents[index].age >= LIFETIME:
			_accents.remove_at(index)
	if _shake_time > 0.0:
		_shake_time = move_toward(_shake_time, 0.0, delta)
		if Comfort.reduced_effects or _shake_time == 0.0:
			clear_shake()
		elif is_instance_valid(camera):
			var phase := _shake_time * 125.0
			camera.offset = Vector2(sin(phase), cos(phase * 1.16)) * (_shake_strength * _shake_time / 0.17)
	queue_redraw()
	if _accents.is_empty() and _shake_time == 0.0:
		set_process(false)


func _draw() -> void:
	var font := ThemeDB.fallback_font
	for item in _accents:
		var progress := item.age / LIFETIME
		var fade := 1.0 - progress * progress
		if item.amount > 0:
			var caption := str(item.amount)
			var at := item.position + Vector2(-font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 21).x * 0.5,
				-56.0 - 20.0 * progress)
			draw_string_outline(font, at, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 21, 4, Color(INK, fade))
			draw_string(font, at, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 21, Color(item.color, fade))
		var radius := 9.0 + 24.0 * progress
		if progress < 0.58:
			for ray in range(5):
				var direction := Vector2.from_angle(ray * TAU / 5.0 + 0.48)
				var point := item.position + Vector2(0, -12) + direction * radius
				draw_line(point, point + direction * 4.0, Color(item.color, fade * (1.0 - progress)), 2.0, true)
