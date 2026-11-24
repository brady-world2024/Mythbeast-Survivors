extends Resource
## Victory and defeat rewards are authored here and settled by the profile.

@export_range(0.0, 900.0, 0.1) var minimum_defeat_seconds := 30.0
@export_range(0, 100000) var defeat_base := 3
@export_range(0, 100000) var defeat_kill_cap := 15
@export_range(0, 100000) var victory_base := 40
@export_range(0, 100000) var victory_kill_cap := 20
@export_range(1, 10000) var kills_per_bonus := 10


func calculate(victory: bool, enemies_defeated: int, active_seconds: float, multiplier: float) -> int:
	if not victory and active_seconds < minimum_defeat_seconds:
		return 0
	var kill_bonus := floori(float(enemies_defeated) / maxi(1, kills_per_bonus))
	var base := victory_base if victory else defeat_base
	var cap := victory_kill_cap if victory else defeat_kill_cap
	# For nonnegative rewards roundi rounds a half to the next integer.
	return roundi(float(base + mini(cap, kill_bonus)) * multiplier)
