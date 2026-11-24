extends SceneTree

const SERVICE_PATH := "res://core/persistence/progression_service.gd"
const GROVE := &"whispering_grove"
const CAVERNS := &"crystal_caverns"
const NORMAL := &"normal"
const HARD := &"hard"
const VITALITY := &"heartwood_vitality"
const FOCUS := &"arcane_focus"
const BOOTS := &"windstep_boots"

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not _check(ResourceLoader.exists(SERVICE_PATH), "The progression service exists"):
		_finish()
		return
	var factory := load(SERVICE_PATH) as Script
	var suffix := Crypto.new().generate_random_bytes(8).hex_encode()
	var test_dir := OS.get_environment("TMPDIR").path_join("mythbeast-service-" + suffix)
	var save_path := test_dir.path_join("save.json")
	_check(DirAccess.make_dir_recursive_absolute(test_dir) == OK, "An isolated save directory was created")
	var service: RefCounted = factory.new(save_path)

	_check(service.balance() == 0 and service.rank(VITALITY) == 0, "A new profile starts with no currency or upgrades")
	_check(service.can_start(GROVE, NORMAL) and not service.can_start(GROVE, HARD), "Only Normal is initially available")
	_check(service.begin_run(CAVERNS, NORMAL).is_empty() and service.begin_run(GROVE, &"unknown").is_empty(),
		"Coming Soon and unknown difficulties cannot be launched")
	_check(service.purchase(VITALITY, 1) == &"unaffordable" and service.purchase(&"unknown", 1) == &"invalid",
		"Purchases validate the balance and catalog")
	var run: Dictionary = service.begin_run(GROVE, NORMAL)
	var result: Dictionary = service.settle(run.run_id, false, 500, 2, 29.99)
	_check(result.status == &"ok" and result.earned == 0 and service.balance() == 0,
		"Defeat before 30 seconds gives zero even with kills")

	run = service.begin_run(GROVE, NORMAL)
	result = service.settle(run.run_id, false, 198, 5, 30.0)
	_check(result.earned == 18 and service.balance() == 18 and not service.can_start(GROVE, HARD),
		"Eligible defeat caps its kill bonus and cannot unlock Hard")
	_check(service.settle(run.run_id, true, 300, 7, 180.0).status == &"duplicate" and service.balance() == 18,
		"A repeated or conflicting terminal result cannot award currency")
	var stale_run: Dictionary = service.begin_run(GROVE, NORMAL)
	run = service.begin_run(GROVE, NORMAL)
	_check(service.settle(stale_run.run_id, true, 99, 9, 180.0).status == &"invalid",
		"An abandoned run cannot be settled through a stale scene")
	_check(service.settle(run.run_id + 1, true, 99, 9, 180.0).status == &"invalid"
		and service.settle(run.run_id, true, -1, 9, 180.0).status == &"invalid"
		and service.settle(run.run_id, true, 99, 9, 179.0).status == &"invalid",
		"An unissued run or invalid outcome statistics are rejected")

	result = service.settle(run.run_id, true, 35, 9, 180.0)
	_check(result.earned == 43 and result.total == 61 and result.hard_unlocked
		and service.can_start(GROVE, HARD), "The first Normal clear awards the correct amount and unlocks Hard")
	var normal: Dictionary = service.record(GROVE, NORMAL)
	_check(normal.highest_level == 9 and normal.enemies_defeated == 500 and normal.clears == 1
		and is_equal_approx(normal.survival_seconds, 180.0), "Best statistics retain each maximum and count clears")
	_check(service.purchase(VITALITY, 1) == &"ok" and service.balance() == 41 and service.rank(VITALITY) == 1,
		"A valid purchase deducts the configured rank-one cost")
	_check(service.purchase(VITALITY, 1) == &"stale" and service.balance() == 41,
		"The same displayed rank cannot be purchased twice")

	run = service.begin_run(GROVE, HARD)
	var difficulty: Resource = run.difficulty
	_check(difficulty.id == HARD and is_equal_approx(difficulty.enemy_hp_multiplier, 1.25)
		and is_equal_approx(difficulty.enemy_damage_multiplier, 1.15)
		and is_equal_approx(difficulty.enemy_speed_multiplier, 1.05)
		and is_equal_approx(difficulty.spawn_interval_multiplier, 0.90)
		and is_equal_approx(difficulty.boss_hp_multiplier, 1.25)
		and is_equal_approx(difficulty.boss_damage_multiplier, 1.20), "Hard carries the configured gameplay multipliers")
	_check(run.bonus_hp == 10 and is_equal_approx(run.magic_multiplier, 1.0)
		and is_equal_approx(run.speed_multiplier, 1.0), "Only purchased permanent bonuses enter the next run")
	result = service.settle(run.run_id, true, 35, 6, 180.0)
	_check(result.earned == 65 and not result.hard_unlocked and service.record(GROVE, HARD).clears == 1,
		"Hard uses its reward multiplier with halves rounded up and its own record")
	_check(service.purchase(FOCUS, 1) == &"ok" and service.purchase(BOOTS, 1) == &"ok"
		and service.purchase(VITALITY, 2) == &"ok" and service.balance() == 31,
		"Each upgrade uses one configurable cost schedule")
	_check(service.set_audio(0.28, 0.63), "Audio settings save with the profile")
	var reloaded: RefCounted = factory.new(save_path)
	_check(reloaded.balance() == 31 and reloaded.rank(VITALITY) == 2 and reloaded.rank(FOCUS) == 1
		and reloaded.rank(BOOTS) == 1 and reloaded.can_start(GROVE, HARD),
		"Currency, all three ranks and the unlock survive reload")
	_check(reloaded.settle(run.run_id, true, 35, 6, 180.0).status == &"duplicate"
		and reloaded.record(GROVE, NORMAL) == normal
		and is_equal_approx(reloaded.audio_settings().music_volume, 0.28)
		and is_equal_approx(reloaded.audio_settings().sfx_volume, 0.63),
		"Settled IDs, stage records and audio survive reload")

	var replacement: Dictionary = reloaded.begin_run(GROVE, NORMAL)
	_check(replacement.run_id > run.run_id and replacement.bonus_hp == 20
		and is_equal_approx(replacement.magic_multiplier, 1.05)
		and is_equal_approx(replacement.speed_multiplier, 1.03), "A reloaded profile supplies fresh run IDs and derived bonuses")
	_check_failure_retry(reloaded, test_dir, replacement.run_id)
	_check_rank_cap(factory, test_dir.path_join("ranks.json"))
	_finish()


func _check_failure_retry(service: RefCounted, test_dir: String, run_id: int) -> void:
	var offline := test_dir + ".offline"
	if not _check(DirAccess.rename_absolute(test_dir, offline) == OK, "The isolated save can be made unavailable"):
		return
	var blocker := FileAccess.open(test_dir, FileAccess.WRITE)
	if not _check(blocker != null, "A file blocks writes to the test save directory"):
		DirAccess.rename_absolute(offline, test_dir)
		return
	blocker.close()
	var result: Dictionary = service.settle(run_id, true, 50, 8, 180.0)
	_check(result.status == &"save_failed" and service.balance() == 31, "A failed reward write publishes no currency")
	_check(service.settle(run_id, false, 50, 8, 180.0).status == &"invalid",
		"A retry cannot change the pending terminal outcome")
	_check(service.purchase(FOCUS, 2) == &"unaffordable" and service.purchase(BOOTS, 2) == &"unaffordable",
		"Pending unsaved rewards cannot be spent")
	_check(DirAccess.remove_absolute(test_dir) == OK and DirAccess.rename_absolute(offline, test_dir) == OK,
		"The isolated save directory is restored for retry")
	result = service.settle(run_id, true, 50, 8, 180.0)
	_check(result.status == &"ok" and result.total == 76
		and service.settle(run_id, true, 50, 8, 180.0).status == &"duplicate",
		"A successful retry commits the original reward exactly once")


func _check_rank_cap(factory: Script, path: String) -> void:
	var service: RefCounted = factory.new(path)
	for index in range(7):
		var run: Dictionary = service.begin_run(GROVE, NORMAL)
		service.settle(run.run_id, true, 300, 9, 180.0)
	var before: int = service.balance()
	var blocked_file := path + ".tmp"
	if _check(DirAccess.make_dir_absolute(blocked_file) == OK, "The test can interrupt an affordable purchase write"):
		_check(service.purchase(VITALITY, 1) == &"save_failed" and service.rank(VITALITY) == 0
			and service.balance() == before, "A failed purchase leaves the rank and balance unchanged")
		_check(DirAccess.remove_absolute(blocked_file) == OK, "The purchase save can be retried")
	for next_rank in range(1, 6):
		_check(service.purchase(VITALITY, next_rank) == &"ok", "Each valid next rank can be purchased")
	_check(service.purchase(VITALITY, 6) == &"max_rank" and service.rank(VITALITY) == 5
		and service.balance() == before - 300, "Five ranks cost 300 total and rank six is rejected")


func _check(condition: bool, message: String) -> bool:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
	return condition


func _finish() -> void:
	print("Profile progression smoke: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
