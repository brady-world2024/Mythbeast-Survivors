extends Resource
## A catalog entry can be visible before its level is available.

const LevelDefinition = preload("res://data/definitions/level_definition.gd")

@export var id: StringName
@export var display_name: String
@export var illustration: Texture2D
@export var available := false
@export_file("*.tscn") var scene_path: String
@export var level_definition: LevelDefinition
@export var requires_stage: StringName
@export var requires_difficulty: StringName
@export var lock_reason: String

var scene: PackedScene:
	get:
		if not available or scene_path.is_empty() or not ResourceLoader.exists(scene_path, "PackedScene"):
			return null
		return load(scene_path) as PackedScene

var target_survival_seconds: float:
	get:
		return level_definition.survival_duration if level_definition != null else 0.0
