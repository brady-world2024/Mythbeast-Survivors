extends CharacterBody2D

const CharacterDefinition = preload("res://data/definitions/character_definition.gd")

@export var definition: CharacterDefinition


func _ready() -> void:
	if definition == null or definition.visual_scene == null:
		push_error("Player requires a character definition with a visual scene.")
		return
	$VisualAnchor.add_child(definition.visual_scene.instantiate())
