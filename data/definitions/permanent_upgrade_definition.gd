extends Resource
## Authored permanent rank progression. Purchased ranks belong to the profile.

@export var id: StringName
@export var display_name: String
@export var description: String
@export var icon: Texture2D
@export_enum("maximum_health", "magic_damage", "movement_speed") var effect := "maximum_health"
@export_range(1, 5) var max_rank := 5
@export var costs := PackedInt32Array([20, 35, 55, 80, 110])
@export var per_rank: int
@export var bonus_format: String


func rank_limit() -> int:
	return mini(max_rank, costs.size())


func cost_for(next_rank: int) -> int:
	if next_rank < 1 or next_rank > rank_limit():
		return -1
	return costs[next_rank - 1]


func bonus_for(rank: int) -> int:
	return clampi(rank, 0, rank_limit()) * per_rank


func describe_bonus(rank: int) -> String:
	return tr(bonus_format) % bonus_for(rank)
