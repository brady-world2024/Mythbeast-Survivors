extends Resource
## Immutable content and tuning for one run ability.

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
@export_enum("Automatic", "Modifier", "Passive") var category := "Automatic"
@export var icon: Texture2D
@export_range(0, 5) var starting_rank: int = 0
@export_range(1, 5) var max_rank: int = 5
@export var available := true
@export var rank_values: Array[Dictionary] = []
@export var limits: Dictionary = {}
@export var rank_detail_template: String


func value_at(rank: int, property: String, fallback: float = 0.0) -> float:
	if rank <= 0 or rank > rank_values.size():
		return fallback
	return float(rank_values[rank - 1].get(property, fallback))


func describe_rank(rank: int) -> String:
	if rank <= 0 or rank > rank_values.size():
		return ""
	return tr(rank_detail_template).format(rank_values[rank - 1])
