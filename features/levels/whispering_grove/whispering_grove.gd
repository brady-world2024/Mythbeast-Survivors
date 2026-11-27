extends Node2D

signal back_requested
signal restart_requested
signal stages_requested

enum RunState { PLAYING, PAUSED, CHOOSING_UPGRADE, ENDED }

const English = preload("res://data/localization/english.gd")
const BasicAttack = preload("res://features/combat/basic_attack.gd")
const Player = preload("res://features/player/player.gd")
const EnemyActor = preload("res://features/enemies/enemy_actor.gd")
const WaveSpawner = preload("res://features/enemies/wave_spawner.gd")
const LevelDefinition = preload("res://data/definitions/level_definition.gd")
const DifficultyDefinition = preload("res://data/definitions/difficulty_definition.gd")
const RunTimeline = preload("res://features/levels/run_timeline.gd")
const Progression = preload("res://features/progression/progression.gd")
const XpGem = preload("res://features/progression/xp_gem.gd")
const UpgradePicker = preload("res://ui/screens/upgrade_picker.gd")
const FloatingStick = preload("res://ui/components/floating_stick.gd")
const GroveHud = preload("res://ui/hud/grove_hud.gd")
const RunRewards = preload("res://ui/components/run_rewards.gd")
const CombatFeedback = preload("res://features/presentation/combat_feedback.gd")
const Feedback = preload("res://features/presentation/feedback.gd")
const XP_GEM_SCENE = preload("res://features/progression/xp_gem.tscn")
const MAX_ACTIVE_GEMS := 48

@export var definition: LevelDefinition
@export var upgrade_seed := 0

@onready var _player: Player = %Player
@onready var _spawner: WaveSpawner = %WaveSpawner
@onready var _timeline: RunTimeline = %RunTimeline
@onready var _progression: Progression = %Progression
@onready var _picker: UpgradePicker = %UpgradePicker
@onready var _rewards: Node2D = %Rewards
@onready var _hud: GroveHud = %HUD
@onready var _feedback: CombatFeedback = %CombatFeedback
@onready var _stick: FloatingStick = %MovementStick
@onready var _pause_overlay: Control = %PauseOverlay
@onready var _pause_panel: Control = %PausePanel
@onready var _game_over_panel: Control = %GameOverPanel
@onready var _victory_panel: Control = %VictoryPanel
@onready var _pause_button: Button = _hud.get_node("%PauseButton")
@onready var _resume: Button = %Resume
@onready var _try_again: Button = %TryAgain

var _state := RunState.PLAYING
var _transition_requested := false
var _upgrade_random := RandomNumberGenerator.new()
var _offered_ids: Array[StringName] = []
var _boss: CharacterBody2D
var _placement_retry := 0.0
var _clock_second := -1
var run_id := 0
var _difficulty: DifficultyDefinition
var _run_setup: Dictionary
var _settle: Callable
var _reward_panel: RunRewards
var _reward_saved := false
var _run_won := false


func configure_run(setup: Dictionary, settle_run: Callable) -> void:
	_run_setup = setup
	var authored_level := setup.get("level_definition") as LevelDefinition
	if authored_level != null:
		definition = authored_level
	run_id = int(setup["run_id"])
	_difficulty = setup.get("difficulty") as DifficultyDefinition
	_settle = settle_run


func _ready() -> void:
	_feedback.camera = $World/Camera2D
	if not _run_setup.is_empty():
		_player.initialize_run_bonuses(int(_run_setup["bonus_hp"]), float(_run_setup["magic_multiplier"]),
			float(_run_setup["speed_multiplier"]))
		_run_setup = {}
	_spawner.difficulty = _difficulty
	%Player.position = definition.player_start
	$World/ArenaBounds/West.position.x = definition.arena_bounds.position.x
	$World/ArenaBounds/East.position.x = definition.arena_bounds.end.x
	$World/ArenaBounds/North.position.y = definition.arena_bounds.position.y
	$World/ArenaBounds/South.position.y = definition.arena_bounds.end.y
	if definition.environment_scene != null:
		%Environment.add_child(definition.environment_scene.instantiate())
	_hud.set_level_name(definition.display_name)
	_spawner.minimum_spawn_distance = definition.minimum_spawn_distance
	_spawner.spawned.connect(_track_enemy_reward)
	_timeline.wave_changed.connect(_apply_wave)
	_timeline.boss_intro_started.connect(_begin_boss_intro)
	_timeline.begin(definition)
	_update_clock()
	var basic_attack := _player.get_node("BasicAttack") as BasicAttack
	basic_attack.projectile_parent = %Effects
	_player.health.changed.connect(_hud.set_health)
	_player.health.damaged.connect(_on_actor_hit.bind(_player, true))
	_player.health.depleted.connect(_show_game_over)
	_hud.set_health(_player.health.current, _player.health.maximum)
	_progression.changed.connect(_hud.set_progress)
	_progression.upgrades_pending.connect(_offer_next_upgrade)
	_hud.set_progress(_progression.current_xp, _progression.required_xp, _progression.level)
	_picker.selected.connect(_select_upgrade)
	if upgrade_seed == 0:
		_upgrade_random.randomize()
	else:
		_upgrade_random.seed = upgrade_seed
	_stick.touch_region = _hud.get_node("%MovementArea")
	get_viewport().size_changed.connect(_clear_movement)
	%PauseHeading.text = tr(English.PAUSED)
	_resume.text = tr(English.RESUME)
	%BackToMenu.text = tr(English.BACK_TO_MENU)
	%GameOverHeading.text = tr(English.GAME_OVER)
	%GameOverMessage.text = tr(English.GAME_OVER_MESSAGE)
	_try_again.text = tr(English.TRY_AGAIN)
	%MainMenu.text = tr(English.MAIN_MENU)
	%VictoryHeading.text = tr(English.VICTORY)
	%VictoryMessage.text = tr(English.CLEARED) % tr(definition.display_name)
	%PlayAgain.text = tr(English.PLAY_AGAIN)
	%VictoryMainMenu.text = tr(English.MAIN_MENU)
	%VictoryStages.text = tr(English.STAGES)
	%DefeatStages.text = tr(English.STAGES)
	_pause_button.pressed.connect(_set_paused.bind(true))
	_resume.pressed.connect(_set_paused.bind(false))
	%BackToMenu.pressed.connect(_request_menu)
	_try_again.pressed.connect(_request_restart)
	%MainMenu.pressed.connect(_request_menu)
	%PlayAgain.pressed.connect(_request_restart)
	%VictoryMainMenu.pressed.connect(_request_menu)
	%VictoryStages.pressed.connect(_request_stages)
	%DefeatStages.pressed.connect(_request_stages)
	%VictoryRewards.retry_requested.connect(_settle_rewards)
	%DefeatRewards.retry_requested.connect(_settle_rewards)


func _physics_process(delta: float) -> void:
	if get_tree().paused:
		return
	var direction := _stick.direction
	if direction.is_zero_approx():
		direction = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	_player.move_direction = direction
	_timeline.advance(delta)
	_update_clock()
	if _timeline.phase == RunTimeline.Phase.BOSS_INTRO:
		_continue_boss_intro(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		_set_paused(not _pause_overlay.visible)
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if not is_node_ready():
		return
	match what:
		NOTIFICATION_APPLICATION_PAUSED:
			_set_paused(true)
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			_clear_movement()
		NOTIFICATION_WM_GO_BACK_REQUEST:
			if _state == RunState.ENDED:
				_request_menu()
			else:
				_set_paused(not _pause_overlay.visible)


func _set_paused(value: bool) -> void:
	if value and _state == RunState.PLAYING:
		_state = RunState.PAUSED
		_pause_overlay.show()
		_set_world_paused(true, _resume)
	elif not value and _state == RunState.PAUSED:
		_state = RunState.PLAYING
		_pause_overlay.hide()
		_offer_next_upgrade()
		if _state == RunState.PLAYING:
			_set_world_paused(false, _pause_button)


func _set_world_paused(value: bool, focus_target: Control = null) -> void:
	if value:
		_clear_movement()
		_feedback.clear_shake()
	_pause_button.disabled = value
	get_tree().paused = value
	if focus_target != null and not OS.has_feature("mobile"):
		focus_target.grab_focus()


func _show_game_over() -> void:
	if not _timeline.finish(false):
		return
	_finish_run(_game_over_panel, _try_again)


func _finish_run(panel: Control, focus: Button) -> void:
	_state = RunState.ENDED
	_offered_ids.clear()
	_picker.dismiss()
	_spawner.stop()
	_hud.hide_boss_warning()
	_update_clock()
	_pause_panel.hide()
	panel.show()
	_pause_overlay.show()
	_set_world_paused(true, focus)
	_run_won = panel == _victory_panel
	_player.play_result(_run_won)
	Feedback.sound(self, &"victory" if _run_won else &"game_over")
	if not _run_won:
		%DefeatKills.text = _result_value(English.ENEMIES_DEFEATED, str(_timeline.enemies_defeated))
		%DefeatLevel.text = _result_value(English.LEVEL_REACHED, str(_progression.level))
		%DefeatTime.text = _result_value(English.SURVIVAL_TIME, _result_time())
	_reward_panel = %VictoryRewards if _run_won else %DefeatRewards
	_settle_rewards()


func _settle_rewards() -> void:
	if _reward_saved or _state != RunState.ENDED or not _settle.is_valid():
		return
	var receipt: Dictionary = _settle.call(run_id, _run_won, _timeline.enemies_defeated, _progression.level, _timeline.elapsed)
	var status: StringName = receipt.get("status", &"invalid")
	_reward_saved = status == &"ok" or status == &"duplicate"
	_reward_panel.show_receipt(receipt, _run_won)


func _result_value(label: String, amount: String) -> String:
	return tr(English.VALUE_FORMAT) % [tr(label), amount]


func _result_time() -> String:
	return GroveHud.format_time(floori(_timeline.elapsed + RunTimeline.EPSILON))


func _apply_wave(index: int) -> void:
	if index < 0:
		_spawner.stop()
		return
	_spawner.use_wave(definition.waves[index])
	if not _spawner.is_spawning():
		_spawner.start(_player, %Entities, _spawn_bounds())
	_hud.set_wave(index, definition.waves.size())


func _update_clock() -> void:
	var next := floori(_timeline.elapsed + RunTimeline.EPSILON)
	if next == _clock_second:
		return
	_clock_second = next
	_hud.set_clock(next, ceili(definition.survival_duration))


func _begin_boss_intro() -> void:
	_spawner.stop()
	_spawner.clear_enemies()
	# Existing shots belong to the survival phase and must not fire into the introduction.
	for effect in %Effects.get_children():
		effect.queue_free()


func _continue_boss_intro(delta: float) -> void:
	if not is_instance_valid(_boss):
		_placement_retry = move_toward(_placement_retry, 0.0, delta)
		if _placement_retry > 0.0:
			return
		var boss := definition.boss_scene.instantiate() as CharacterBody2D
		var location := _boss_spawn_position(float(boss.get("spawn_radius")))
		if not location.is_finite():
			_placement_retry = 0.4
			boss.free()
			return
		var entities: Node2D = %Entities
		boss.position = entities.to_local(location)
		if _difficulty != null:
			boss.call(&"configure_difficulty", _difficulty.boss_hp_multiplier, _difficulty.boss_damage_multiplier)
		entities.add_child(boss)
		_boss = boss
		_hud.show_boss_intro(_boss.get("definition").display_name)
		Feedback.sound(self, &"boss_intro")
		_timeline.mark_boss_visible()
	if not _timeline.begin_boss():
		return
	var health: Node = _boss.get_node("Health")
	_hud.show_boss(_boss.get("definition").display_name, health.get("maximum"))
	health.connect(&"changed", _hud.set_boss_health)
	health.connect(&"damaged", _on_actor_hit.bind(_boss, false))
	_boss.connect(&"phase_changed", _hud.set_boss_phase)
	if _boss.has_signal(&"presentation_cue"):
		_boss.connect(&"presentation_cue", _on_boss_cue)
	_boss.connect(&"defeated", _boss_defeated, CONNECT_ONE_SHOT)
	_boss.call(&"start", _player)


func _boss_spawn_position(radius: float) -> Vector2:
	var bounds := _spawn_bounds().grow(-(radius + 4.0))
	var space := get_world_2d().direct_space_state
	var footprint := CircleShape2D.new()
	footprint.radius = radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = footprint
	query.collision_mask = 3 # World and player. The ordinary wave has been cleared.
	var best := Vector2.INF
	var best_distance := -1.0
	for fraction: Vector2 in [Vector2(0.50, 0.24), Vector2(0.24, 0.28), Vector2(0.76, 0.28),
			Vector2(0.27, 0.58), Vector2(0.73, 0.58), Vector2(0.50, 0.78)]:
		var candidate := bounds.position + bounds.size * fraction
		query.transform = Transform2D(0.0, candidate)
		if not space.intersect_shape(query, 1).is_empty():
			continue
		var distance := candidate.distance_squared_to(_player.global_position)
		if distance >= 125.0 * 125.0:
			return candidate
		if distance > best_distance:
			best_distance = distance
			best = candidate
	return best


func _boss_defeated() -> void:
	# A player death in the same physics step wins the terminal-state arbitration.
	_complete_victory.call_deferred()


func _complete_victory() -> void:
	if not _player.health.is_alive() or not _timeline.finish(true):
		return
	%VictoryKills.text = _result_value(English.ENEMIES_DEFEATED, str(_timeline.enemies_defeated))
	%VictoryLevel.text = _result_value(English.LEVEL_REACHED, str(_progression.level))
	%VictoryTime.text = _result_value(English.SURVIVAL_TIME, _result_time())
	_finish_run(_victory_panel, %PlayAgain)


func _track_enemy_reward(enemy: EnemyActor) -> void:
	enemy.health.damaged.connect(_on_actor_hit.bind(enemy, false))
	enemy.health.depleted.connect(_drop_xp.bind(enemy), CONNECT_ONE_SHOT)


func _on_actor_hit(amount: int, actor: Node2D, hero: bool) -> void:
	_feedback.hit(actor, amount, hero)
	Feedback.sound(self, &"player_hit" if hero else &"enemy_hit")


func _on_boss_cue(cue: StringName) -> void:
	Feedback.sound(self, cue)
	if cue == &"boss_stomp" or cue == &"boss_phase":
		_feedback.impact(2.8 if cue == &"boss_stomp" else 1.7)


func _drop_xp(enemy: EnemyActor) -> void:
	if _timeline.phase != RunTimeline.Phase.SURVIVAL or _transition_requested:
		return
	_timeline.record_enemy_defeat()
	_feedback.sparkle(enemy.global_position, true)
	Feedback.sound(self, &"enemy_death")
	if enemy.definition.xp_reward <= 0:
		return
	var reward := enemy.definition.xp_reward
	var position := _rewards.to_local(enemy.global_position)
	if _rewards.get_child_count() >= MAX_ACTIVE_GEMS:
		# Consolidate uncollected rewards to keep the arena's pickup count bounded.
		var nearest: XpGem
		var nearest_distance := INF
		for node in _rewards.get_children():
			if node.is_queued_for_deletion() or not node.is_in_group(&"xp_gems"):
				continue
			var other := node as XpGem
			var distance := other.position.distance_squared_to(position)
			if distance < nearest_distance:
				nearest_distance = distance
				nearest = other
		if nearest != null:
			nearest.xp_value += reward
			return
	var gem := XP_GEM_SCENE.instantiate() as XpGem
	gem.position = position
	gem.setup(_player, reward)
	gem.collected.connect(_collect_xp.bind(gem), CONNECT_ONE_SHOT)
	_rewards.add_child(gem)


func _collect_xp(amount: int, gem: XpGem) -> void:
	_feedback.sparkle(gem.global_position)
	Feedback.sound(self, &"xp_pickup")
	_progression.grant_xp(amount)


func _offer_next_upgrade() -> void:
	if _state != RunState.PLAYING and _state != RunState.CHOOSING_UPGRADE:
		return
	if not _offered_ids.is_empty():
		return
	if _progression.pending_upgrades == 0:
		_finish_upgrades()
		return
	var choices := _player.abilities.roll_choices(_upgrade_random)
	if choices.is_empty():
		while _progression.consume_upgrade():
			pass
		_finish_upgrades()
		return
	var cards: Array[Dictionary] = []
	for ability in choices:
		var next_rank := _player.abilities.rank_of(ability.id) + 1
		_offered_ids.append(ability.id)
		cards.append({
			"id": ability.id,
			"name": tr(ability.display_name),
			"description": tr(ability.description),
			"rank": next_rank,
			"max_rank": ability.max_rank,
			"icon": ability.icon,
			"detail": ability.describe_rank(next_rank),
		})
	_state = RunState.CHOOSING_UPGRADE
	_set_world_paused(true)
	_picker.present(cards)
	Feedback.sound(self, &"level_up")


func _select_upgrade(id: StringName) -> void:
	if _state != RunState.CHOOSING_UPGRADE or not _offered_ids.has(id):
		return
	_offered_ids.clear()
	if _player.abilities.apply_upgrade(id):
		_progression.consume_upgrade()
		Feedback.sound(self, &"upgrade_pick")
	_offer_next_upgrade.call_deferred()


func _finish_upgrades() -> void:
	if _state != RunState.CHOOSING_UPGRADE:
		return
	_picker.dismiss()
	_state = RunState.PLAYING
	_set_world_paused(false, _pause_button)


func _request_menu() -> void:
	if _transition_requested:
		return
	_transition_requested = true
	back_requested.emit()


func _request_restart() -> void:
	if _state != RunState.ENDED or _transition_requested:
		return
	_transition_requested = true
	restart_requested.emit()


func _request_stages() -> void:
	if _state != RunState.ENDED or _transition_requested:
		return
	_transition_requested = true
	stages_requested.emit()


func _spawn_bounds() -> Rect2:
	var west: CollisionShape2D = $World/ArenaBounds/West
	var east: CollisionShape2D = $World/ArenaBounds/East
	var north: CollisionShape2D = $World/ArenaBounds/North
	var south: CollisionShape2D = $World/ArenaBounds/South
	var top_left := Vector2(west.global_position.x, north.global_position.y)
	var bottom_right := Vector2(east.global_position.x, south.global_position.y)
	return Rect2(top_left, bottom_right - top_left)


func _clear_movement() -> void:
	_stick.cancel()
	_player.move_direction = Vector2.ZERO
