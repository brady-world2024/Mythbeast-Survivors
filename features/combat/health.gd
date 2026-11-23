extends Node

signal changed(current: int, maximum: int)
signal depleted

var current: int
var maximum: int


func configure(max_health: int) -> void:
	maximum = maxi(1, max_health)
	current = maximum
	changed.emit(current, maximum)


func damage(amount: int) -> void:
	if amount <= 0 or not is_alive():
		return
	current = maxi(0, current - amount)
	changed.emit(current, maximum)
	if not is_alive():
		depleted.emit()


func is_alive() -> bool:
	return current > 0
