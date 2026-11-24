extends Control

signal back_requested

const English = preload("res://data/localization/english.gd")
const UpgradeCard = preload("res://ui/components/permanent_upgrade_card.tscn")

var service: RefCounted

var _definitions: Array[Resource] = []
var _cards: Dictionary[StringName, PanelContainer] = {}
var _purchasing := false


func _ready() -> void:
	%Heading.text = tr(English.PERMANENT_UPGRADES)
	%Back.text = tr(English.BACK)
	%Back.pressed.connect(back_requested.emit)
	%PurchaseCooldown.timeout.connect(_release_purchase)
	if service == null:
		return

	_definitions.assign(service.call(&"upgrades"))
	for definition in _definitions:
		var id := StringName(definition.get(&"id"))
		var card := UpgradeCard.instantiate() as PanelContainer
		card.name = String(id).to_pascal_case()
		%Upgrades.add_child(card)
		card.call(&"setup", definition)
		card.connect(&"purchase_requested", _purchase)
		_cards[id] = card
	_refresh()


func _refresh() -> void:
	var available := int(service.call(&"balance"))
	%Balance.update_balance(available)
	for definition in _definitions:
		var id := StringName(definition.get(&"id"))
		_cards[id].call(&"update_rank", int(service.call(&"rank", id)), available, _purchasing)


func _purchase(id: StringName, expected_next_rank: int) -> void:
	if _purchasing:
		return
	_purchasing = true
	var status := StringName(service.call(&"purchase", id, expected_next_rank))
	match status:
		&"ok":
			%PurchaseStatus.text = tr(English.UPGRADE_PURCHASED)
		&"unaffordable":
			%PurchaseStatus.text = tr(English.NOT_ENOUGH_ESSENCE)
		&"max_rank":
			%PurchaseStatus.text = tr(English.MAXIMUM_RANK_REACHED)
		&"save_failed":
			%PurchaseStatus.text = tr(English.PROGRESS_SAVE_FAILED)
		_:
			%PurchaseStatus.text = tr(English.PURCHASE_UNAVAILABLE)
	%PurchaseStatus.show()
	_refresh()
	%PurchaseCooldown.start()


func _release_purchase() -> void:
	_purchasing = false
	_refresh()
