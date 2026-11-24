extends RefCounted
## Reads and commits validated local snapshots. One process owns the writer.

const SCHEMA_VERSION := 1
const MAX_CURRENCY := 1_000_000_000
const MAX_RUN_ID := 1_000_000_000
const DEFAULT_MUSIC_VOLUME := 0.43
const DEFAULT_SFX_VOLUME := 0.8

const MAX_FILE_BYTES := 2_097_152
const MAX_RECORD_LEVEL := 1000
const MAX_RECORD_COUNT := 1_000_000_000
const MAX_RECORD_SECONDS := 86400.0

var load_status: StringName = &"new"

var _primary_path: String
var _backup_path: String
var _upgrade_caps: Dictionary[String, int] = {}
var _stage_ids: Array[String] = []
var _difficulty_ids: Array[String] = []


func _init(
	path: String = "user://savegame.json",
	upgrade_caps: Dictionary = {"heartwood_vitality": 5, "arcane_focus": 5, "windstep_boots": 5},
	stage_ids: Array = ["whispering_grove", "crystal_caverns"],
	difficulty_ids: Array = ["normal", "hard"]
) -> void:
	_primary_path = ProjectSettings.globalize_path(path)
	_backup_path = _primary_path + ".bak"
	for id in upgrade_caps:
		_upgrade_caps[String(id)] = int(upgrade_caps[id])
	for id in stage_ids:
		_stage_ids.append(String(id))
	for id in difficulty_ids:
		_difficulty_ids.append(String(id))


static func default_snapshot() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"profile": {"star_essence": 0, "permanent_upgrades": {}, "best_records": {}},
		"settings": {"music_volume": DEFAULT_MUSIC_VOLUME, "sfx_volume": DEFAULT_SFX_VOLUME},
		"settlement": {"last_run_id": 0},
	}


func load_snapshot() -> Dictionary:
	var primary := _read_candidate(_primary_path)
	var backup := _read_candidate(_backup_path)
	if primary.status == &"unsupported" or backup.status == &"unsupported":
		load_status = &"unsupported"
		if not primary.snapshot.is_empty():
			return primary.snapshot
		if not backup.snapshot.is_empty():
			return backup.snapshot
		return default_snapshot()
	if primary.status == &"loaded":
		load_status = &"loaded"
		return primary.snapshot
	if backup.status == &"loaded":
		load_status = &"recovered"
		return backup.snapshot

	var defaults := default_snapshot()
	if primary.status == &"unavailable" or backup.status == &"unavailable":
		load_status = &"unavailable"
	elif primary.status == &"damaged" or backup.status == &"damaged":
		load_status = &"damaged"
	else:
		load_status = &"new" if save_snapshot(defaults) else &"unavailable"
	return defaults


func save_snapshot(snapshot: Dictionary) -> bool:
	var normalized := _normalize(snapshot)
	if normalized.is_empty():
		return false
	var primary := _read_candidate(_primary_path)
	var backup := _read_candidate(_backup_path)
	if primary.status in [&"unsupported", &"unavailable"] or backup.status in [&"unsupported", &"unavailable"]:
		return false
	if DirAccess.make_dir_recursive_absolute(_primary_path.get_base_dir()) != OK:
		return false

	var staged_path := _primary_path + ".tmp"
	if not _write_verified(staged_path, normalized):
		_remove_temporary(staged_path)
		return false

	# Keep a validated snapshot while the primary is being replaced.
	var preserved := true
	if primary.status == &"loaded":
		preserved = _preserve_backup(primary.snapshot, backup.status)
	elif primary.status == &"damaged":
		preserved = _archive_damaged(_primary_path)
	if not preserved or DirAccess.rename_absolute(staged_path, _primary_path) != OK:
		_remove_temporary(staged_path)
		return false
	return true


func _preserve_backup(previous: Dictionary, existing_status: StringName) -> bool:
	if existing_status == &"damaged" and not _archive_damaged(_backup_path):
		return false
	var staged_backup := _backup_path + ".tmp"
	if not _write_verified(staged_backup, previous) or DirAccess.rename_absolute(staged_backup, _backup_path) != OK:
		_remove_temporary(staged_backup)
		return false
	return true


func _archive_damaged(path: String) -> bool:
	var stamp := "%d-%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
	var backup := path + ".corrupt." + stamp
	if FileAccess.file_exists(backup) or DirAccess.dir_exists_absolute(backup):
		return false
	return DirAccess.copy_absolute(path, backup) == OK


func _write_verified(path: String, normalized: Dictionary) -> bool:
	var content := JSON.stringify(normalized, "\t", true, true) + "\n"
	if content.to_utf8_buffer().size() > MAX_FILE_BYTES:
		return false
	var output := FileAccess.open(path, FileAccess.WRITE)
	if output == null:
		return false
	var wrote := output.store_string(content)
	output.flush()
	var flushed := output.get_error() == OK
	output.close()
	if not wrote or not flushed:
		return false
	var checked := _read_candidate(path)
	return checked.status == &"loaded" and checked.snapshot == normalized


func _read_candidate(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"status": &"unavailable" if DirAccess.dir_exists_absolute(path) else &"missing", "snapshot": {}}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"status": &"unavailable", "snapshot": {}}
	var size := file.get_length()
	if size == 0 or size > MAX_FILE_BYTES:
		file.close()
		return {"status": &"damaged", "snapshot": {}}
	var bytes := file.get_buffer(size)
	file.close()
	if bytes.size() != size:
		return {"status": &"unavailable", "snapshot": {}}

	var json := JSON.new()
	if json.parse(bytes.get_string_from_utf8()) != OK or not (json.data is Dictionary):
		return {"status": &"damaged", "snapshot": {}}
	var raw: Dictionary = json.data
	var version := _integer_or(raw.get("schema_version"), 1, MAX_RUN_ID, 0)
	if version > SCHEMA_VERSION:
		return {"status": &"unsupported", "snapshot": {}}
	var normalized := _normalize(raw)
	return {"status": &"damaged" if normalized.is_empty() else &"loaded", "snapshot": normalized}


func _normalize(raw: Dictionary) -> Dictionary:
	if _integer_or(raw.get("schema_version"), 1, SCHEMA_VERSION, 0) != SCHEMA_VERSION:
		return {}
	var profile := _dictionary_or_empty(raw.get("profile"))
	var essence := _integer_or(profile.get("star_essence"), 0, MAX_CURRENCY, -1)
	var settlement := _dictionary_or_empty(raw.get("settlement"))
	var run_id := _integer_or(settlement.get("last_run_id", 0), 0, MAX_RUN_ID, -1)
	if essence < 0 or run_id < 0:
		return {}

	var purchased := _dictionary_or_empty(profile.get("permanent_upgrades"))
	var ranks := {}
	for id in _upgrade_caps:
		if not purchased.has(id):
			continue
		var rank := _integer_or(purchased[id], 0, _upgrade_caps[id], -1)
		if rank < 0:
			return {}
		ranks[id] = rank

	var settings := _dictionary_or_empty(raw.get("settings"))
	return {
		"schema_version": SCHEMA_VERSION,
		"profile": {
			"star_essence": essence,
			"permanent_upgrades": ranks,
			"best_records": _normalize_records(_dictionary_or_empty(profile.get("best_records"))),
		},
		"settings": {
			"music_volume": _float_or(settings.get("music_volume"), 0.0, 1.0, DEFAULT_MUSIC_VOLUME),
			"sfx_volume": _float_or(settings.get("sfx_volume"), 0.0, 1.0, DEFAULT_SFX_VOLUME),
		},
		"settlement": {"last_run_id": run_id},
	}


func _normalize_records(source: Dictionary) -> Dictionary:
	var records := {}
	for stage_id in _stage_ids:
		var stage := _dictionary_or_empty(source.get(stage_id))
		var stage_records := {}
		for difficulty_id in _difficulty_ids:
			var record := _dictionary_or_empty(stage.get(difficulty_id))
			if record.is_empty():
				continue
			stage_records[difficulty_id] = {
				"highest_level": _integer_or(record.get("highest_level"), 0, MAX_RECORD_LEVEL, 0),
				"enemies_defeated": _integer_or(record.get("enemies_defeated"), 0, MAX_RECORD_COUNT, 0),
				"survival_seconds": _float_or(record.get("survival_seconds"), 0.0, MAX_RECORD_SECONDS, 0.0),
				"clears": _integer_or(record.get("clears"), 0, MAX_RECORD_COUNT, 0),
			}
		if not stage_records.is_empty():
			records[stage_id] = stage_records
	return records


static func _dictionary_or_empty(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


static func _integer_or(value: Variant, minimum: int, maximum: int, fallback: int) -> int:
	var numeric := _float_or(value, float(minimum), float(maximum), NAN)
	return int(numeric) if is_finite(numeric) and numeric == floorf(numeric) else fallback


static func _float_or(value: Variant, minimum: float, maximum: float, fallback: float) -> float:
	if not (value is float or value is int):
		return fallback
	var numeric := float(value)
	return numeric if is_finite(numeric) and numeric >= minimum and numeric <= maximum else fallback


static func _remove_temporary(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
