extends Control

signal selected(id: StringName)

const English = preload("res://data/localization/english.gd")
const Comfort = preload("res://features/presentation/comfort.gd")
const UpgradeCard = preload("res://ui/components/upgrade_card.gd")
const PANEL_WIDTH := 476.0

@onready var _center: CenterContainer = %UpgradeCenter
@onready var _panel: PanelContainer = %UpgradePanel
@onready var _buttons: Array[UpgradeCard] = [%Choice1, %Choice2, %Choice3]

var _offered_ids: Array[StringName] = []
var _selection_locked := true
var _offer_version := 0
var _entrance: Tween


func _ready() -> void:
	%UpgradeHeading.text = tr(English.UPGRADE_HEADING)
	%UpgradeSubtitle.text = tr(English.UPGRADE_SUBTITLE)
	for index in _buttons.size():
		_buttons[index].pressed.connect(_select.bind(index))
	_center.resized.connect(_resize_panel)
	_resize_panel()


func present(cards: Array[Dictionary]) -> void:
	_offered_ids.clear()
	for card in cards:
		var id := StringName(card.get("id", &""))
		if id == &"" or _offered_ids.has(id):
			continue
		var button := _buttons[_offered_ids.size()]
		_offered_ids.append(id)
		button.configure(card)
		if _offered_ids.size() == _buttons.size():
			break

	if _offered_ids.is_empty():
		dismiss()
		return

	_offer_version += 1
	_selection_locked = false
	for index in _buttons.size():
		var is_offered := index < _offered_ids.size()
		_buttons[index].visible = is_offered
		_buttons[index].disabled = not is_offered
	show()
	if not OS.has_feature("mobile"):
		_buttons[0].grab_focus()
	_animate_entrance()


func dismiss() -> void:
	_offer_version += 1
	_selection_locked = true
	_offered_ids.clear()
	hide()


func _resize_panel() -> void:
	_panel.custom_minimum_size.x = minf(PANEL_WIDTH, _center.size.x)


func _animate_entrance() -> void:
	if _entrance != null:
		_entrance.kill()
	if Comfort.reduced_effects:
		_panel.modulate.a = 1.0
		return
	_panel.modulate.a = 0.0
	_entrance = create_tween()
	_entrance.tween_property(_panel, "modulate:a", 1.0, 0.20).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _select(index: int) -> void:
	if _selection_locked or not visible or index >= _offered_ids.size():
		return
	_selection_locked = true
	for button in _buttons:
		button.disabled = true
	# Deliver after the current input event so repeated presses cannot spill into the next set.
	_emit_selection.call_deferred(_offered_ids[index], _offer_version)


func _emit_selection(id: StringName, version: int) -> void:
	if version == _offer_version and visible:
		selected.emit(id)
