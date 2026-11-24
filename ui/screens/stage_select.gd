extends Control

signal back_requested
signal start_requested(stage_id: StringName, difficulty_id: StringName)

const English = preload("res://data/localization/english.gd")
const StageCard = preload("res://ui/components/stage_card.tscn")

var service: RefCounted
var selected_stage_id: StringName
var selected_difficulty_id: StringName

var _stages: Array[Resource] = []
var _difficulties: Array[Resource] = []
var _stage_buttons: Dictionary[StringName, Button] = {}
var _difficulty_buttons: Dictionary[StringName, Button] = {}
var _starting := false


func _ready() -> void:
	%Heading.text = tr(English.CHOOSE_A_STAGE)
	%DifficultyHeading.text = tr(English.DIFFICULTY)
	%BestRunHeading.text = tr(English.BEST_RUNS)
	%NoRecord.text = tr(English.NO_RECORD)
	%StartAdventure.text = tr(English.START_ADVENTURE)
	%Back.text = tr(English.BACK)
	%Back.pressed.connect(back_requested.emit)
	%StartAdventure.pressed.connect(_request_start)
	if service == null:
		show_start_error()
		return
	%Balance.update_balance(int(service.call(&"balance")))
	_create_options()
	_refresh_selection()


func show_start_error() -> void:
	_starting = false
	%StageStatus.text = tr(English.START_UNAVAILABLE)
	%StageStatus.show()
	%StartAdventure.disabled = not _can_start(selected_stage_id, selected_difficulty_id)


func _create_options() -> void:
	_stages.assign(service.call(&"stages"))
	_difficulties.assign(service.call(&"difficulties"))
	for stage in _stages:
		var id := StringName(stage.get(&"id"))
		var playable := _stage_is_playable(stage)
		var status := English.STAGE_CLEARED if _has_clear(id) else English.STAGE_AVAILABLE
		if not playable:
			status = English.LOCKED if stage.get(&"available") else English.COMING_SOON

		var card := StageCard.instantiate() as Button
		card.name = String(id).to_pascal_case()
		%Stages.add_child(card)
		_stage_buttons[id] = card
		var reason := tr(String(stage.get(&"lock_reason"))) if not playable else ""
		if reason == tr(status):
			reason = ""
		if status == English.LOCKED and reason.is_empty():
			reason = tr(English.STAGE_CONTENT_UNAVAILABLE)
		card.call(&"configure", tr(String(stage.get(&"display_name"))), tr(status), reason, stage.get(&"illustration"), playable)
		card.pressed.connect(_choose_stage.bind(id))
		if selected_stage_id.is_empty() and playable:
			selected_stage_id = id

	for difficulty in _difficulties:
		var id := StringName(difficulty.get(&"id"))
		var button := Button.new()
		button.name = String(id).to_pascal_case()
		button.toggle_mode = true
		button.theme_type_variation = &"SecondaryButton"
		button.custom_minimum_size.y = 56.0
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.pressed.connect(_choose_difficulty.bind(id))
		%Difficulties.add_child(button)
		_difficulty_buttons[id] = button


func _choose_stage(id: StringName) -> void:
	if not _starting and _stage_buttons.has(id) and not _stage_buttons[id].disabled:
		selected_stage_id = id
		_refresh_selection()


func _choose_difficulty(id: StringName) -> void:
	if not _starting and _can_start(selected_stage_id, id):
		selected_difficulty_id = id
		_refresh_selection()


func _refresh_selection() -> void:
	if not _can_start(selected_stage_id, selected_difficulty_id):
		selected_difficulty_id = &""
		for difficulty in _difficulties:
			var id := StringName(difficulty.get(&"id"))
			if _can_start(selected_stage_id, id):
				selected_difficulty_id = id
				break

	for id in _stage_buttons:
		_stage_buttons[id].set_pressed_no_signal(id == selected_stage_id)

	var lock_reasons := PackedStringArray()
	for difficulty in _difficulties:
		var id := StringName(difficulty.get(&"id"))
		var button := _difficulty_buttons[id]
		var title := tr(String(difficulty.get(&"display_name")))
		var unlocked := _can_start(selected_stage_id, id)
		var reason := tr(String(difficulty.get(&"lock_reason")))
		button.disabled = not unlocked
		button.set_pressed_no_signal(id == selected_difficulty_id)
		button.text = title if unlocked else "%s · %s" % [title, tr(English.LOCKED)]
		button.accessibility_description = reason if not unlocked else ""
		if not unlocked and not reason.is_empty() and not lock_reasons.has(reason):
			lock_reasons.append(reason)

	%DifficultyNote.text = "\n".join(lock_reasons)
	%DifficultyNote.visible = not lock_reasons.is_empty()
	%StageStatus.hide()
	%StartAdventure.disabled = not _can_start(selected_stage_id, selected_difficulty_id)
	_show_records()


func _stage_is_playable(stage: Resource) -> bool:
	if not stage.get(&"available") or not stage.get(&"scene") is PackedScene:
		return false
	for difficulty in _difficulties:
		if _can_start(StringName(stage.get(&"id")), StringName(difficulty.get(&"id"))):
			return true
	return false


func _has_clear(stage_id: StringName) -> bool:
	for difficulty in _difficulties:
		var record: Dictionary = service.call(&"record", stage_id, difficulty.get(&"id"))
		if int(record.get("clears", 0)) > 0:
			return true
	return false


func _can_start(stage_id: StringName, difficulty_id: StringName) -> bool:
	return service != null and not stage_id.is_empty() and not difficulty_id.is_empty() and bool(
		service.call(&"can_start", stage_id, difficulty_id)
	)


func _request_start() -> void:
	if _starting:
		return
	if not _can_start(selected_stage_id, selected_difficulty_id):
		show_start_error()
		return
	_starting = true
	%StartAdventure.disabled = true
	start_requested.emit(selected_stage_id, selected_difficulty_id)


func _show_records() -> void:
	var record: Dictionary = service.call(&"record", selected_stage_id, selected_difficulty_id)
	%NoRecord.visible = record.is_empty()
	%RecordGrid.visible = not record.is_empty()
	if record.is_empty():
		return
	var seconds := floori(float(record.get("survival_seconds", 0.0)))
	var time := "%02d:%02d" % [floori(seconds / 60.0), seconds % 60]
	%BestLevel.text = tr(English.VALUE_FORMAT) % [tr(English.LEVEL_REACHED), str(record.get("highest_level", 0))]
	%BestKills.text = tr(English.VALUE_FORMAT) % [tr(English.ENEMIES_DEFEATED), str(record.get("enemies_defeated", 0))]
	%BestTime.text = tr(English.VALUE_FORMAT) % [tr(English.SURVIVAL_TIME), time]
	%BestClears.text = tr(English.VALUE_FORMAT) % [tr(English.CLEARS), str(record.get("clears", 0))]
