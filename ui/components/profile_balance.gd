extends PanelContainer

const English = preload("res://data/localization/english.gd")


func update_balance(value: int) -> void:
	%BalanceText.text = tr(English.ESSENCE_BALANCE) % value
