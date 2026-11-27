extends RefCounted
## Owns the validated profile and publishes changes only after a successful save.

const SaveStore = preload("res://core/persistence/save_store.gd")
const StageDefinition = preload("res://data/definitions/stage_definition.gd")
const DifficultyDefinition = preload("res://data/definitions/difficulty_definition.gd")
const UpgradeDefinition = preload("res://data/definitions/permanent_upgrade_definition.gd")

const GROVE = preload("res://data/progression/whispering_grove.tres")
const CAVERNS = preload("res://data/progression/crystal_caverns.tres")
const NORMAL = preload("res://data/progression/normal.tres")
const HARD = preload("res://data/progression/hard.tres")
const VITALITY = preload("res://data/progression/heartwood_vitality.tres")
const FOCUS = preload("res://data/progression/arcane_focus.tres")
const BOOTS = preload("res://data/progression/windstep_boots.tres")
const REWARDS = preload("res://data/progression/star_essence_rewards.tres")

const MAX_ENEMIES := 1_000_000
const MAX_LEVEL := 100
const MAX_ACTIVE_SECONDS := 86_400.0

var _store: SaveStore
var _snapshot: Dictionary
var _last_issued_run := 0
var _active_run_id := 0
var _active_stage: StageDefinition
var _active_difficulty: DifficultyDefinition
var _pending_outcome: Dictionary = {}

var load_status: StringName:
	get:
		return _store.load_status


func _init(path: String = "user://savegame.json") -> void:
	var caps: Dictionary = {}
	var stage_ids: Array[String] = []
	var difficulty_ids: Array[String] = []
	for upgrade in upgrades():
		caps[String(upgrade.id)] = upgrade.rank_limit()
	for stage in stages():
		stage_ids.append(String(stage.id))
	for difficulty in difficulties():
		difficulty_ids.append(String(difficulty.id))
	_store = SaveStore.new(path, caps, stage_ids, difficulty_ids)
	_snapshot = _store.load_snapshot()
	_last_issued_run = _last_settled_run()


func balance() -> int:
	return int(_snapshot.profile.star_essence)


func rank(id: StringName) -> int:
	return int(_snapshot.profile.permanent_upgrades.get(String(id), 0))


func upgrades() -> Array[UpgradeDefinition]:
	return [VITALITY, FOCUS, BOOTS]


func stages() -> Array[StageDefinition]:
	return [GROVE, CAVERNS]


func difficulties() -> Array[DifficultyDefinition]:
	return [NORMAL, HARD]


func stage_definition(id: StringName) -> StageDefinition:
	for definition in stages():
		if definition.id == id:
			return definition
	return null


func difficulty_definition(id: StringName) -> DifficultyDefinition:
	for definition in difficulties():
		if definition.id == id:
			return definition
	return null


func upgrade_definition(id: StringName) -> UpgradeDefinition:
	for definition in upgrades():
		if definition.id == id:
			return definition
	return null


func record(stage_id: StringName, difficulty_id: StringName) -> Dictionary:
	var stage_records: Dictionary = _snapshot.profile.best_records.get(String(stage_id), {})
	var entry: Dictionary = stage_records.get(String(difficulty_id), {})
	return entry.duplicate()


func stage_unlocked(stage_id: StringName) -> bool:
	var stage := stage_definition(stage_id)
	return stage != null and _requirements_met(stage.requires_stage, stage.requires_difficulty)


func difficulty_unlocked(difficulty_id: StringName) -> bool:
	var difficulty := difficulty_definition(difficulty_id)
	return difficulty != null and _requirements_met(difficulty.requires_stage, difficulty.requires_difficulty)


func can_start(stage_id: StringName, difficulty_id: StringName) -> bool:
	var stage := stage_definition(stage_id)
	if stage == null or not stage.available or stage.level_definition == null \
		or not stage_unlocked(stage_id) or not difficulty_unlocked(difficulty_id):
		return false
	var scene := stage.scene
	return scene != null and scene.can_instantiate()


func begin_run(stage_id: StringName, difficulty_id: StringName) -> Dictionary:
	if _last_issued_run >= SaveStore.MAX_RUN_ID or not can_start(stage_id, difficulty_id):
		return {}
	_last_issued_run += 1
	_active_run_id = _last_issued_run
	_active_stage = stage_definition(stage_id)
	_active_difficulty = difficulty_definition(difficulty_id)
	_pending_outcome.clear()

	var bonuses := _permanent_bonuses()
	return {
		&"stage_id": stage_id,
		&"difficulty_id": difficulty_id,
		&"scene": _active_stage.scene,
		&"level_definition": _active_stage.level_definition,
		&"difficulty": _active_difficulty,
		&"run_id": _active_run_id,
		&"bonus_hp": bonuses.maximum_health,
		&"magic_multiplier": 1.0 + bonuses.magic_damage * 0.01,
		&"speed_multiplier": 1.0 + bonuses.movement_speed * 0.01,
	}


func settle(run_id: int, victory: bool, kills: int, level: int, active_seconds: float) -> Dictionary:
	if run_id <= 0:
		return _result(&"invalid")
	if run_id <= _last_settled_run():
		return _result(&"duplicate")
	if run_id != _active_run_id or not _valid_outcome(victory, kills, level, active_seconds):
		return _result(&"invalid")

	var outcome := {"victory": victory, "kills": kills, "level": level, "seconds": active_seconds}
	if not _pending_outcome.is_empty() and _pending_outcome != outcome:
		return _result(&"invalid")
	_pending_outcome = outcome

	var hard_was_unlocked := difficulty_unlocked(HARD.id)
	var next := _snapshot.duplicate(true)
	var prior := balance()
	var reward: int = REWARDS.calculate(victory, kills, active_seconds, _active_difficulty.reward_multiplier)
	next.profile.star_essence = clampi(prior + reward, prior, SaveStore.MAX_CURRENCY)
	next.settlement.last_run_id = run_id
	_update_record(next, victory, kills, level, active_seconds)
	if not _save(next):
		return _result(&"save_failed")

	_pending_outcome.clear()
	_active_run_id = 0
	_active_stage = null
	_active_difficulty = null
	return _result(&"ok", balance() - prior, not hard_was_unlocked and difficulty_unlocked(HARD.id))


func purchase(id: StringName, requested_rank: int) -> StringName:
	var definition := upgrade_definition(id)
	if definition == null:
		return &"invalid"

	var current := rank(id)
	if current >= definition.rank_limit():
		return &"max_rank"
	if requested_rank != current + 1:
		return &"stale"

	var cost := definition.cost_for(requested_rank)
	if cost <= 0:
		return &"invalid"
	if cost > balance():
		return &"unaffordable"

	var next := _snapshot.duplicate(true)
	next.profile.star_essence = balance() - cost
	next.profile.permanent_upgrades[String(id)] = requested_rank
	if not _save(next):
		return &"save_failed"
	return &"ok"


func audio_settings() -> Dictionary:
	return _snapshot.settings.duplicate()


func set_audio(music: float, sfx: float) -> bool:
	return set_settings(music, sfx, _snapshot.settings.reduced_effects)


func set_settings(music: float, sfx: float, reduced_effects: bool) -> bool:
	if not is_finite(music) or not is_finite(sfx) or music < 0.0 or music > 1.0 or sfx < 0.0 or sfx > 1.0:
		return false
	if is_equal_approx(float(_snapshot.settings.music_volume), music) \
		and is_equal_approx(float(_snapshot.settings.sfx_volume), sfx) \
		and _snapshot.settings.reduced_effects == reduced_effects:
		return true

	var next := _snapshot.duplicate(true)
	next.settings.music_volume = music
	next.settings.sfx_volume = sfx
	next.settings.reduced_effects = reduced_effects
	return _save(next)


func _requirements_met(stage_id: StringName, difficulty_id: StringName) -> bool:
	if stage_id.is_empty() and difficulty_id.is_empty():
		return true
	return int(record(stage_id, difficulty_id).get("clears", 0)) > 0


func _permanent_bonuses() -> Dictionary:
	var values := {"maximum_health": 0, "magic_damage": 0, "movement_speed": 0}
	for definition in upgrades():
		values[definition.effect] += definition.bonus_for(rank(definition.id))
	return values


func _valid_outcome(victory: bool, kills: int, level: int, active_seconds: float) -> bool:
	if _active_stage == null or _active_difficulty == null:
		return false
	if kills < 0 or kills > MAX_ENEMIES or level < 1 or level > MAX_LEVEL \
		or not is_finite(active_seconds) or active_seconds < 0.0 or active_seconds > MAX_ACTIVE_SECONDS:
		return false
	return not victory or active_seconds >= _active_stage.target_survival_seconds


func _update_record(next: Dictionary, victory: bool, kills: int, level: int, seconds: float) -> void:
	var stage_id := String(_active_stage.id)
	var difficulty_id := String(_active_difficulty.id)
	var records: Dictionary = next.profile.best_records
	var stage_records: Dictionary = records.get(stage_id, {})
	var prior: Dictionary = stage_records.get(difficulty_id, {})
	stage_records[difficulty_id] = {
		"highest_level": maxi(int(prior.get("highest_level", 1)), level),
		"enemies_defeated": maxi(int(prior.get("enemies_defeated", 0)), kills),
		"survival_seconds": maxf(float(prior.get("survival_seconds", 0.0)), minf(seconds, _active_stage.target_survival_seconds)),
		"clears": mini(SaveStore.MAX_RUN_ID, int(prior.get("clears", 0)) + int(victory)),
	}
	records[stage_id] = stage_records


func _last_settled_run() -> int:
	return int(_snapshot.settlement.last_run_id)


func _result(status: StringName, earned: int = 0, hard_unlocked: bool = false) -> Dictionary:
	return {"status": status, "earned": earned, "total": balance(), "hard_unlocked": hard_unlocked}


func _save(next: Dictionary) -> bool:
	if not _store.save_snapshot(next):
		return false
	_snapshot = next
	return true
