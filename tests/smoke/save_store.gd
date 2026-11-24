extends SceneTree

const STORE_PATH := "res://core/persistence/save_store.gd"

var _store_script: GDScript
var _root: String
var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not ResourceLoader.exists(STORE_PATH):
		_check(false, "The offline save store is available")
		_finish()
		return
	_store_script = load(STORE_PATH)
	if not _check(_store_script != null, "The save store loads"):
		_finish()
		return
	var temporary := FileAccess.create_temp(FileAccess.WRITE, "mythbeast-save-test", "tmp", true)
	if not _check(temporary != null, "The test has isolated temporary storage"):
		_finish()
		return
	var marker := temporary.get_path_absolute()
	temporary.close()
	_root = marker + ".fixtures"
	DirAccess.remove_absolute(marker)
	DirAccess.make_dir_absolute(_root)
	_test_round_trip()
	_test_optional_and_invalid_fields()
	_test_corruption_and_recovery()
	_test_unsupported_schema()
	_test_failed_write()
	for filename in DirAccess.get_files_at(_root):
		DirAccess.remove_absolute(_root.path_join(filename))
	DirAccess.remove_absolute(_root)
	_finish()


func _test_round_trip() -> void:
	var path := _root.path_join("round-trip.json")
	var store = _store_script.new(path)
	var snapshot: Dictionary = store.load_snapshot()
	_check(store.load_status == &"new" and FileAccess.file_exists(path), "First load creates a versioned primary")
	_check(snapshot.schema_version == 1 and snapshot.profile.star_essence == 0 and snapshot.settlement.last_run_id == 0,
		"First load starts with an empty profile and settlement history")
	_check(is_equal_approx(snapshot.settings.music_volume, 0.43) and is_equal_approx(snapshot.settings.sfx_volume, 0.8),
		"First load preserves the authored audio balance")
	snapshot.profile.star_essence = 126
	snapshot.profile.permanent_upgrades = {"arcane_focus": 4, "windstep_boots": 1}
	snapshot.profile.best_records = {"whispering_grove": {"hard": {
		"highest_level": 9, "enemies_defeated": 42, "survival_seconds": 180.0, "clears": 2,
	}}}
	snapshot.settings.music_volume = 0.0
	snapshot.settings.sfx_volume = 0.65
	snapshot.settlement.last_run_id = 27
	_check(store.save_snapshot(snapshot), "A valid profile snapshot commits")
	var reopened = _store_script.new(path)
	var recovered: Dictionary = reopened.load_snapshot()
	_check(reopened.load_status == &"loaded" and recovered == snapshot,
		"A fresh store reloads currency, ranks, records, audio and the settlement marker")
	var backup = _store_script.new(path + ".bak")
	var previous: Dictionary = backup.load_snapshot()
	_check(backup.load_status == &"loaded" and previous.profile.star_essence == 0,
		"The previous valid snapshot remains in the backup")


func _test_optional_and_invalid_fields() -> void:
	var path := _root.path_join("optional.json")
	_write(path, JSON.stringify({"schema_version": 1, "profile": {"star_essence": 23, "new_field": true}}))
	var store = _store_script.new(path)
	var snapshot: Dictionary = store.load_snapshot()
	_check(store.load_status == &"loaded" and snapshot.profile.star_essence == 23
		and snapshot.profile.permanent_upgrades.is_empty() and snapshot.profile.best_records.is_empty()
		and snapshot.settlement.last_run_id == 0, "Missing optional fields default without losing currency")
	var before := FileAccess.get_file_as_string(path)
	snapshot.profile.star_essence = -1
	_check(not store.save_snapshot(snapshot) and FileAccess.get_file_as_string(path) == before,
		"Out-of-range currency rejects a write without changing the primary")
	snapshot.profile.star_essence = 23
	snapshot.profile.permanent_upgrades["heartwood_vitality"] = 6
	_check(not store.save_snapshot(snapshot) and FileAccess.get_file_as_string(path) == before,
		"Ranks above the configured cap are rejected")
	var custom = _store_script.new(_root.path_join("custom.json"), {"test_upgrade": 2}, ["test_stage"], ["test_mode"])
	var custom_data: Dictionary = custom.load_snapshot()
	custom_data.profile.permanent_upgrades["test_upgrade"] = 2
	custom_data.profile.best_records["test_stage"] = {"test_mode": {"clears": 1}}
	_check(custom.save_snapshot(custom_data) and custom.load_snapshot().profile.best_records.test_stage.test_mode.clears == 1,
		"Save validation accepts registered future content")


func _test_corruption_and_recovery() -> void:
	var path := _root.path_join("recovery.json")
	var store = _store_script.new(path)
	var snapshot: Dictionary = store.load_snapshot()
	snapshot.profile.star_essence = 40
	var first_ok: bool = store.save_snapshot(snapshot)
	snapshot.profile.star_essence = 55
	_check(first_ok and store.save_snapshot(snapshot), "Recovery setup writes two distinct valid states")
	var corrupt := "{\"schema_version\":1,\"profile\":"
	_write(path, corrupt)
	var reopened = _store_script.new(path)
	var recovered: Dictionary = reopened.load_snapshot()
	_check(reopened.load_status == &"recovered" and recovered.profile.star_essence == 40
		and FileAccess.get_file_as_string(path) == corrupt, "Truncated JSON uses the last valid backup and leaves the damaged primary intact")
	recovered.profile.star_essence = 41
	_check(reopened.save_snapshot(recovered) and reopened.load_snapshot().profile.star_essence == 41,
		"A new transaction can commit after recovery")
	_check(_has_archive(path, corrupt), "Recovery archives the original damaged primary before replacement")
	var missing := _root.path_join("missing-primary.json")
	_write(missing + ".bak", JSON.stringify(recovered))
	var missing_store = _store_script.new(missing)
	_check(missing_store.load_snapshot().profile.star_essence == 41 and missing_store.load_status == &"recovered",
		"A missing primary can recover from a valid backup")
	var damaged := _root.path_join("damaged.json")
	_write(damaged, corrupt)
	var damaged_store = _store_script.new(damaged)
	var fallback: Dictionary = damaged_store.load_snapshot()
	_check(damaged_store.load_status == &"damaged" and fallback.profile.star_essence == 0
		and FileAccess.get_file_as_string(damaged) == corrupt, "An unrecoverable existing save is distinguished from first launch")
	_check(damaged_store.save_snapshot(fallback) and _has_archive(damaged, corrupt),
		"Recovering with defaults preserves the original data on the first write")


func _test_unsupported_schema() -> void:
	var path := _root.path_join("future-version.json")
	var future := "{\"schema_version\":2,\"profile\":{\"star_essence\":123}}"
	_write(path, future)
	var store = _store_script.new(path)
	var snapshot: Dictionary = store.load_snapshot()
	_check(store.load_status == &"unsupported" and not store.save_snapshot(snapshot)
		and FileAccess.get_file_as_string(path) == future, "An unsupported future schema is read-only and is never replaced")


func _test_failed_write() -> void:
	var path := _root.path_join("failed-write.json")
	var store = _store_script.new(path)
	var snapshot: Dictionary = store.load_snapshot()
	var prior := FileAccess.get_file_as_string(path)
	DirAccess.make_dir_absolute(path + ".tmp")
	snapshot.profile.star_essence = 10
	_check(not store.save_snapshot(snapshot) and FileAccess.get_file_as_string(path) == prior,
		"An unavailable temporary file fails without changing the primary data")
	DirAccess.remove_absolute(path + ".tmp")
	_check(store.save_snapshot(snapshot) and store.load_snapshot().profile.star_essence == 10,
		"A retry can commit after the file is writable again")


func _has_archive(path: String, expected: String) -> bool:
	for filename in DirAccess.get_files_at(_root):
		if filename.begins_with(path.get_file() + ".corrupt.") and FileAccess.get_file_as_string(_root.path_join(filename)) == expected:
			return true
	return false


func _write(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(content)
		file.close()


func _check(condition: bool, message: String) -> bool:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
	return condition


func _finish() -> void:
	print("Save store smoke: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
