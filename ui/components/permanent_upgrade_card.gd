extends PanelContainer

signal purchase_requested(id: StringName, expected_next_rank: int)

const English = preload("res://data/localization/english.gd")

var _definition: Resource
var _next_rank := 1

@onready var _buy: Button = %Purchase


func _ready() -> void:
	_buy.pressed.connect(_request_purchase)


func setup(definition: Resource) -> void:
	_definition = definition
	%UpgradeIcon.texture = definition.get(&"icon") as Texture2D
	%UpgradeTitle.text = tr(String(definition.get(&"display_name")))
	%UpgradeDescription.text = tr(String(definition.get(&"description")))
	_buy.name = "Buy" + String(definition.get(&"id")).to_pascal_case()


func update_rank(rank: int, balance: int, busy: bool) -> void:
	_next_rank = rank + 1
	var cap := int(_definition.call(&"rank_limit"))
	var cost := int(_definition.call(&"cost_for", _next_rank))
	%UpgradeRank.text = tr(English.ABILITY_RANK_FORMAT) % [rank, cap]
	%CurrentBonus.text = tr(English.CURRENT_BONUS) % String(_definition.call(&"describe_bonus", rank))
	%NextBonus.visible = cost >= 0
	if cost >= 0:
		%NextBonus.text = tr(English.NEXT_BONUS) % String(_definition.call(&"describe_bonus", _next_rank))
	_buy.text = tr(English.MAXIMUM_RANK) if cost < 0 else tr(English.BUY_UPGRADE) % cost
	_buy.disabled = busy or cost < 0 or balance < cost
	_buy.accessibility_name = "%s, %s" % [%UpgradeTitle.text, _buy.text]
	_buy.accessibility_description = tr(English.NOT_ENOUGH_ESSENCE) if cost >= 0 and balance < cost else ""


func _request_purchase() -> void:
	if not _buy.disabled:
		purchase_requested.emit(StringName(_definition.get(&"id")), _next_rank)
