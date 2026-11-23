extends RefCounted
## One timed movement slow. Equal-strength hits refresh the timer.

var multiplier: float:
	get:
		return _multiplier

var _multiplier := 1.0
var _remaining := 0.0


func apply(slow_ratio: float, duration: float, minimum_speed_ratio: float) -> void:
	var next := clampf(1.0 - slow_ratio, clampf(minimum_speed_ratio, 0.01, 1.0), 1.0)
	if duration <= 0.0 or next >= 1.0 or next > _multiplier:
		return
	_remaining = maxf(_remaining, duration) if is_equal_approx(next, _multiplier) else duration
	_multiplier = next


func tick(delta: float) -> bool:
	if _remaining <= 0.0:
		return false
	_remaining = move_toward(_remaining, 0.0, delta)
	if _remaining > 0.0:
		return false
	clear()
	return true


func clear() -> void:
	_remaining = 0.0
	_multiplier = 1.0
