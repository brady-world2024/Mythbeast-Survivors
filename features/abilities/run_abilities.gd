extends Node2D
## The hero's ability ranks, derived stats, and automatic effects for this run.

const AbilityDefinition = preload("res://data/definitions/ability_definition.gd")
const WeaponDefinition = preload("res://data/definitions/weapon_definition.gd")
const Health = preload("res://features/combat/health.gd")
const Targets = preload("res://features/combat/combat_targets.gd")

const ARCANE_BOLT := &"arcane_bolt"
const CHAIN_LIGHTNING := &"chain_lightning"
const FLAME_AURA := &"flame_aura"
const FROST_TOUCH := &"frost_touch"
const SWIFT_STEPS := &"swift_steps"
const IRON_GUARD := &"iron_guard"
const ENEMIES := &"combat_enemies"
const CHAIN_DURATION := 0.24
const GAIN_DURATION := 0.55
const AURA_PULSE_DURATION := 0.27

@export var catalog: Array[AbilityDefinition] = [
	preload("res://data/abilities/arcane_bolt.tres"),
	preload("res://data/abilities/chain_lightning.tres"),
	preload("res://data/abilities/flame_aura.tres"),
	preload("res://data/abilities/frost_touch.tres"),
	preload("res://data/abilities/swift_steps.tres"),
	preload("res://data/abilities/iron_guard.tres"),
]

@onready var _hero: Node2D = get_parent()
@onready var _health: Health = _hero.get_node("Health")

var bolt: WeaponDefinition

var _definitions: Dictionary[StringName, AbilityDefinition] = {}
var _ranks: Dictionary[StringName, int] = {}
var _base_weapon: WeaponDefinition
var _aura_cooldown := 0.0
var _aura_pulse := 0.0
var _chain_points := PackedVector2Array()
var _chain_remaining := 0.0
var _gain_color := Color.WHITE
var _gain_remaining := 0.0


func _ready() -> void:
	for definition in catalog:
		if definition == null or definition.id == &"" or _definitions.has(definition.id):
			continue
		_definitions[definition.id] = definition
		if definition.available:
			_ranks[definition.id] = clampi(definition.starting_rank, 0, _max_rank(definition))
	_health.depleted.connect(_clear_effects)
	_update_processing()


func set_base_weapon(weapon: WeaponDefinition) -> void:
	_base_weapon = weapon
	_refresh_bolt()
	_update_processing()


func definition_for(id: StringName) -> AbilityDefinition:
	return _definitions.get(id)


func rank_of(id: StringName) -> int:
	return _ranks.get(id, 0)


func can_upgrade(id: StringName) -> bool:
	var definition := definition_for(id)
	return definition != null and definition.available and rank_of(id) < _max_rank(definition)


func apply_upgrade(id: StringName) -> bool:
	if not can_upgrade(id):
		return false
	_ranks[id] = rank_of(id) + 1
	match id:
		ARCANE_BOLT:
			_refresh_bolt()
		SWIFT_STEPS:
			_show_gain(Color("83d88b"))
		IRON_GUARD:
			_show_gain(Color("f5c471"))
	_update_processing()
	queue_redraw()
	return true


func roll_choices(rng: RandomNumberGenerator, count: int = 3) -> Array[AbilityDefinition]:
	var choices: Array[AbilityDefinition] = []
	for definition: AbilityDefinition in _definitions.values():
		if can_upgrade(definition.id):
			choices.append(definition)
	choices.sort_custom(func(left: AbilityDefinition, right: AbilityDefinition) -> bool:
		return String(left.id) < String(right.id)
	)
	var offer_count := clampi(count, 0, choices.size())
	for index in range(offer_count):
		var pick := rng.randi_range(index, choices.size() - 1)
		var original := choices[index]
		choices[index] = choices[pick]
		choices[pick] = original
	choices.resize(offer_count)
	return choices


func movement_speed(base_speed: float) -> float:
	return base_speed * (1.0 + _value(SWIFT_STEPS, "bonus_percent") * 0.01)


func damage_after_guard(incoming: int) -> int:
	if incoming <= 0:
		return 0
	var limit := clampf(_limit(IRON_GUARD, "reduction_cap_percent", 40.0), 0.0, 100.0)
	var reduction := clampf(_value(IRON_GUARD, "reduction_percent"), 0.0, limit) * 0.01
	var blocked := incoming if reduction >= 1.0 else roundi(float(incoming) * reduction)
	return maxi(1, incoming - blocked)


func on_bolt_hit(enemy: Node2D, origin: Vector2, bolt_damage: int) -> void:
	if not _health.is_alive():
		return
	if rank_of(FROST_TOUCH) > 0 and Targets.living_health(enemy) != null and enemy.has_method(&"apply_slow"):
		var slow := _value(FROST_TOUCH, "slow_percent") * 0.01
		var duration := _value(FROST_TOUCH, "duration")
		var minimum_speed := _limit(FROST_TOUCH, "minimum_speed_percent", 40.0) * 0.01
		enemy.call(&"apply_slow", slow, duration, minimum_speed)
	if rank_of(CHAIN_LIGHTNING) > 0:
		_chain(origin, enemy, bolt_damage)


func _physics_process(delta: float) -> void:
	_chain_remaining = move_toward(_chain_remaining, 0.0, delta)
	_gain_remaining = move_toward(_gain_remaining, 0.0, delta)
	_aura_pulse = move_toward(_aura_pulse, 0.0, delta)
	if rank_of(FLAME_AURA) > 0:
		_aura_cooldown = move_toward(_aura_cooldown, 0.0, delta)
		if _aura_cooldown == 0.0:
			_pulse_aura()
	_update_processing()
	queue_redraw()


func _refresh_bolt() -> void:
	if _base_weapon == null:
		bolt = null
		return
	bolt = _base_weapon.duplicate() as WeaponDefinition
	bolt.damage = maxi(1, _base_weapon.damage + roundi(_value(ARCANE_BOLT, "damage_bonus")))
	var floor_interval := minf(_base_weapon.attack_interval, _limit(ARCANE_BOLT, "minimum_interval", 0.25))
	var cooldown_scale := 1.0 - _value(ARCANE_BOLT, "cooldown_percent") * 0.01
	bolt.attack_interval = maxf(floor_interval, _base_weapon.attack_interval * cooldown_scale)


func _chain(origin: Vector2, first_enemy: Node2D, bolt_damage: int) -> void:
	var candidates := get_tree().get_nodes_in_group(ENEMIES)
	var visited: Array[Node2D] = [first_enemy]
	var points := PackedVector2Array([origin])
	var damage := maxi(1, roundi(float(bolt_damage) * _value(CHAIN_LIGHTNING, "damage_percent") * 0.01))
	var radius := _value(CHAIN_LIGHTNING, "range")
	for jump in range(roundi(_value(CHAIN_LIGHTNING, "targets"))):
		var enemy := Targets.nearest(candidates, points[-1], radius, visited)
		if enemy == null:
			break
		visited.append(enemy)
		points.append(enemy.global_position)
		Targets.living_health(enemy).damage(damage)
	if points.size() > 1:
		_chain_points = points
		_chain_remaining = CHAIN_DURATION
		_update_processing()
		queue_redraw()


func _pulse_aura() -> void:
	_aura_cooldown = maxf(0.05, _value(FLAME_AURA, "interval", 1.0))
	_aura_pulse = AURA_PULSE_DURATION
	var radius := _value(FLAME_AURA, "radius")
	var damage := roundi(_value(FLAME_AURA, "damage"))
	for candidate in get_tree().get_nodes_in_group(ENEMIES):
		var enemy := candidate as Node2D
		var health := Targets.living_health(enemy)
		if health != null and global_position.distance_squared_to(enemy.global_position) <= radius * radius:
			health.damage(damage)


func _show_gain(color: Color) -> void:
	_gain_color = color
	_gain_remaining = GAIN_DURATION


func _clear_effects() -> void:
	_chain_points.clear()
	_chain_remaining = 0.0
	_gain_remaining = 0.0
	_aura_pulse = 0.0
	_update_processing()
	queue_redraw()


func _update_processing() -> void:
	set_physics_process(
		_health.is_alive() and (rank_of(FLAME_AURA) > 0 or _chain_remaining > 0.0 or _gain_remaining > 0.0)
	)


func _max_rank(definition: AbilityDefinition) -> int:
	return mini(definition.max_rank, definition.rank_values.size())


func _value(id: StringName, property: String, fallback: float = 0.0) -> float:
	var definition := definition_for(id)
	return definition.value_at(rank_of(id), property, fallback) if definition != null else fallback


func _limit(id: StringName, property: String, fallback: float) -> float:
	var definition := definition_for(id)
	return float(definition.limits.get(property, fallback)) if definition != null else fallback


func _draw() -> void:
	if _health == null or not _health.is_alive():
		return
	if rank_of(FLAME_AURA) > 0:
		_draw_aura()
	if _chain_remaining > 0.0:
		_draw_chain()
	if _gain_remaining > 0.0:
		_draw_gain()


func _draw_aura() -> void:
	var radius := _value(FLAME_AURA, "radius")
	var pulse := _aura_pulse / AURA_PULSE_DURATION
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(1.0, 0.53, 0.22, 0.18 + 0.33 * pulse), 6.0, true)
	draw_arc(Vector2.ZERO, radius - 1.0, 0.0, TAU, 48, Color(1.0, 0.85, 0.43, 0.37 + 0.4 * pulse), 2.0, true)
	for index in range(8):
		var spot := Vector2.from_angle(index * TAU / 8.0) * (radius - 3.0)
		draw_circle(spot, 2.2 + 2.0 * pulse, Color(1.0, 0.72, 0.36, 0.46 + 0.43 * pulse), true, -1.0, true)


func _draw_chain() -> void:
	var fade := _chain_remaining / CHAIN_DURATION
	for index in range(_chain_points.size() - 1):
		var start := to_local(_chain_points[index]) + Vector2(0.0, -28.0)
		var end := to_local(_chain_points[index + 1]) + Vector2(0.0, -28.0)
		var offset := (end - start).normalized().orthogonal() * 7.0
		var path := PackedVector2Array([start, start.lerp(end, 0.3) + offset, start.lerp(end, 0.65) - offset, end])
		draw_polyline(path, Color(0.44, 0.47, 1.0, 0.34 * fade), 8.0, true)
		draw_polyline(path, Color(0.79, 0.88, 1.0, fade), 3.3, true)
		draw_circle(end, 6.0 * fade, Color(0.8, 0.9, 1.0, fade), true, -1.0, true)


func _draw_gain() -> void:
	var fade := _gain_remaining / GAIN_DURATION
	var radius := lerpf(64.0, 28.0, fade)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, Color(_gain_color, 0.7 * fade), 3.2, true)
	for index in range(6):
		var spot := Vector2.from_angle(index * TAU / 6.0) * radius + Vector2(0.0, -16.0)
		draw_circle(spot, 3.8 * fade, Color(_gain_color, fade), true, -1.0, true)
