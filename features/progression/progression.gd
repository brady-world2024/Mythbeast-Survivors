extends Node
## Owns experience toward the next level and pending choices for one run.

signal changed(current_xp: int, required_xp: int, level: int)
signal upgrades_pending

# Keep thresholds representable at every supported growth rate and level cap.
const MAXIMUM_THRESHOLD := 1_000_000_000

@export_range(1, 1000) var initial_requirement: int = 20
@export_range(1.0, 3.0, 0.01) var growth: float = 1.25
@export_range(1, 100) var max_level: int = 30

var level := 1
var current_xp := 0
var pending_upgrades := 0

var required_xp: int:
	get:
		if level >= max_level:
			return 0
		var scaled := float(initial_requirement) * pow(growth, level - 1)
		return roundi(clampf(scaled, 1.0, float(MAXIMUM_THRESHOLD)))


func grant_xp(amount: int) -> void:
	if amount <= 0 or level >= max_level:
		return

	var remaining := amount
	var starting_level := level
	while level < max_level:
		var missing := required_xp - current_xp
		if remaining < missing:
			current_xp += remaining
			break
		remaining -= missing
		current_xp = 0
		level += 1

	var gained_levels := level - starting_level
	pending_upgrades += gained_levels
	changed.emit(current_xp, required_xp, level)
	if gained_levels > 0:
		upgrades_pending.emit()


func consume_upgrade() -> bool:
	if pending_upgrades == 0:
		return false
	pending_upgrades -= 1
	return true
