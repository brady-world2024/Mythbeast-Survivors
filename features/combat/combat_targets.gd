extends RefCounted

const Health = preload("res://features/combat/health.gd")


static func living_health(candidate: Node2D) -> Health:
	if not is_instance_valid(candidate) or candidate.is_queued_for_deletion():
		return null
	var health := candidate.get_node_or_null(^"Health") as Health
	return health if health != null and health.is_alive() else null


static func nearest(
	candidates: Array[Node],
	origin: Vector2,
	max_range: float,
	excluded: Array[Node2D] = [],
) -> Node2D:
	var best: Node2D
	var best_distance := max_range * max_range
	for candidate in candidates:
		var enemy := candidate as Node2D
		if enemy == null or excluded.has(enemy) or living_health(enemy) == null:
			continue
		var distance := origin.distance_squared_to(enemy.global_position)
		if distance <= best_distance:
			best = enemy
			best_distance = distance
	return best
