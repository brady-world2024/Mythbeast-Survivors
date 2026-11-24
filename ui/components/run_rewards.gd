extends PanelContainer

signal retry_requested

const English = preload("res://data/localization/english.gd")

@onready var _earned: Label = %Earned
@onready var _total: Label = %Total
@onready var _message: Label = %RewardMessage
@onready var _retry: Button = %RetrySave


func _ready() -> void:
	_retry.text = tr(English.RETRY_SAVE)
	_retry.pressed.connect(retry_requested.emit)


func show_receipt(receipt: Dictionary, victory: bool) -> void:
	var status: StringName = receipt.get("status", &"invalid")
	var saved := status == &"ok" or status == &"duplicate"
	_earned.visible = saved
	_total.visible = saved
	_retry.visible = not saved
	_message.visible = not saved or bool(receipt.get("hard_unlocked", false))
	if _message.visible:
		_message.text = tr(English.HARD_MODE_UNLOCKED if saved else English.REWARD_SAVE_FAILED)
	if saved:
		_earned.text = tr(English.VALUE_FORMAT) % [tr(English.STAR_ESSENCE_EARNED), str(receipt.get("earned", 0))]
		_total.text = tr(English.VALUE_FORMAT) % [tr(English.TOTAL_STAR_ESSENCE), str(receipt.get("total", 0))]
	show()
	if saved and victory and int(receipt.get("earned", 0)) > 0:
		modulate = Color(1.0, 0.91, 0.66)
		create_tween().tween_property(self, "modulate", Color.WHITE, 0.38)
