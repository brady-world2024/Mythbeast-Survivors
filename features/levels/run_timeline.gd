extends Node
## Owns the active-play clock and terminal state for one encounter.

signal wave_changed(index: int)
signal boss_intro_started

enum Phase { SURVIVAL, BOSS_INTRO, BOSS_FIGHT, VICTORY, DEFEAT }

const LevelDefinition = preload("res://data/definitions/level_definition.gd")
const EPSILON := 0.0001

var phase := Phase.SURVIVAL
var elapsed := 0.0
var wave_index := -1
var intro_remaining := 0.0
var enemies_defeated := 0
var boss_defeated := false

var _level: LevelDefinition
var _boss_visible := false


func begin(level: LevelDefinition) -> void:
	_level = level
	_update_wave()


func advance(delta: float) -> void:
	if delta <= 0.0 or _level == null:
		return
	match phase:
		Phase.SURVIVAL:
			elapsed = minf(elapsed + delta, _level.survival_duration)
			if elapsed + EPSILON >= _level.survival_duration:
				elapsed = _level.survival_duration
				phase = Phase.BOSS_INTRO
				intro_remaining = _level.boss_intro_duration
				boss_intro_started.emit()
			else:
				_update_wave()
		Phase.BOSS_INTRO:
			if _boss_visible:
				intro_remaining = move_toward(intro_remaining, 0.0, delta)


func mark_boss_visible() -> void:
	if phase == Phase.BOSS_INTRO:
		_boss_visible = true


func begin_boss() -> bool:
	if phase != Phase.BOSS_INTRO or not _boss_visible or intro_remaining > EPSILON:
		return false
	phase = Phase.BOSS_FIGHT
	return true


func record_enemy_defeat() -> void:
	if phase == Phase.SURVIVAL:
		enemies_defeated += 1


func finish(won: bool) -> bool:
	if is_finished() or (won and phase != Phase.BOSS_FIGHT):
		return false
	phase = Phase.VICTORY if won else Phase.DEFEAT
	if won:
		enemies_defeated += 1
		boss_defeated = true
	return true


func is_finished() -> bool:
	return phase == Phase.VICTORY or phase == Phase.DEFEAT


func _update_wave() -> void:
	var next := _level.wave_index_at(elapsed + EPSILON)
	if wave_index != next:
		wave_index = next
		wave_changed.emit(wave_index)
