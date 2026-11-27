extends Button

const English = preload("res://data/localization/english.gd")

@onready var _icon: TextureRect = %AbilityIcon
@onready var _title: Label = %AbilityName
@onready var _rank: Label = %AbilityRank
@onready var _description: Label = %AbilityDescription
@onready var _detail: Label = %AbilityDetail


func configure(choice: Dictionary) -> void:
	_icon.texture = choice.get("icon") as Texture2D
	_title.text = tr(String(choice.get("name", "")))
	var rank := int(choice.get("rank", 1))
	_rank.text = tr(English.NEW_ABILITY) if rank == 1 else tr(English.ABILITY_RANK_FORMAT) % [rank, choice.get("max_rank", 1)]
	_description.text = tr(String(choice.get("description", "")))
	_detail.text = String(choice.get("detail", ""))
	_detail.visible = not _detail.text.is_empty()
	accessibility_name = _title.text
	accessibility_description = "%s. %s %s" % [_rank.text, _description.text, _detail.text]
