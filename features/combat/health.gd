extends Node

signal changed(current: int, maximum: int)
signal damaged(amount: int)
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
	var applied := mini(amount, current)
	current -= applied
	var depleted_by_hit := current == 0
	changed.emit(current, maximum)
	damaged.emit(applied)
	if depleted_by_hit:
		depleted.emit()


func heal(amount: int) -> void:
	if amount <= 0 or not is_alive() or current == maximum:
		return
	current += mini(amount, maximum - current)
	changed.emit(current, maximum)


func is_alive() -> bool:
	return current > 0
