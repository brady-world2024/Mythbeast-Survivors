extends Node2D

signal back_requested
signal restart_requested

enum RunState { PLAYING, PAUSED, CHOOSING_UPGRADE, DEFEATED }

const English = preload("res://data/localization/english.gd")
const BasicAttack = preload("res://features/combat/basic_attack.gd")
const Player = preload("res://features/player/player.gd")
const ForestSlime = preload("res://features/enemies/forest_slime.gd")
const SlimeSpawner = preload("res://features/enemies/slime_spawner.gd")
const Progression = preload("res://features/progression/progression.gd")
const XpGem = preload("res://features/progression/xp_gem.gd")
const UpgradePicker = preload("res://ui/screens/upgrade_picker.gd")
const FloatingStick = preload("res://ui/components/floating_stick.gd")
const GroveHud = preload("res://ui/hud/grove_hud.gd")
const XP_GEM_SCENE = preload("res://features/progression/xp_gem.tscn")
const MAX_ACTIVE_GEMS := 48

@export var upgrade_seed := 0

@onready var _player: Player = %Player
@onready var _spawner: SlimeSpawner = %SlimeSpawner
@onready var _progression: Progression = %Progression
@onready var _picker: UpgradePicker = %UpgradePicker
@onready var _rewards: Node2D = %Rewards
@onready var _hud: GroveHud = %HUD
@onready var _stick: FloatingStick = %MovementStick
@onready var _pause_overlay: Control = %PauseOverlay
@onready var _pause_panel: Control = %PausePanel
@onready var _game_over_panel: Control = %GameOverPanel
@onready var _pause_button: Button = _hud.get_node("%PauseButton")
@onready var _resume: Button = %Resume
@onready var _try_again: Button = %TryAgain

var _state := RunState.PLAYING
var _transition_requested := false
var _upgrade_random := RandomNumberGenerator.new()
var _offered_ids: Array[StringName] = []


func _ready() -> void:
	var basic_attack := _player.get_node("BasicAttack") as BasicAttack
	basic_attack.projectile_parent = %Effects
	_player.health.changed.connect(_hud.set_health)
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
	_pause_button.pressed.connect(_set_paused.bind(true))
	_resume.pressed.connect(_set_paused.bind(false))
	%BackToMenu.pressed.connect(_request_menu)
	_try_again.pressed.connect(_request_restart)
	%MainMenu.pressed.connect(_request_menu)
	_spawner.spawned.connect(_track_enemy_reward)
	_spawner.start(_player, %Entities, _spawn_bounds())


func _physics_process(_delta: float) -> void:
	if get_tree().paused:
		return
	var direction := _stick.direction
	if direction.is_zero_approx():
		direction = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	_player.move_direction = direction


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
			if _state == RunState.DEFEATED:
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
	_pause_button.disabled = value
	get_tree().paused = value
	if focus_target != null and not OS.has_feature("mobile"):
		focus_target.grab_focus()


func _show_game_over() -> void:
	if _state == RunState.DEFEATED:
		return
	_state = RunState.DEFEATED
	_offered_ids.clear()
	_picker.dismiss()
	_spawner.stop()
	_pause_panel.hide()
	_game_over_panel.show()
	_pause_overlay.show()
	_set_world_paused(true, _try_again)


func _track_enemy_reward(enemy: ForestSlime) -> void:
	enemy.health.depleted.connect(_drop_xp.bind(enemy), CONNECT_ONE_SHOT)


func _drop_xp(enemy: ForestSlime) -> void:
	if _state == RunState.DEFEATED or _transition_requested or enemy.definition.xp_reward <= 0:
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
	gem.collected.connect(_progression.grant_xp, CONNECT_ONE_SHOT)
	_rewards.add_child(gem)


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


func _select_upgrade(id: StringName) -> void:
	if _state != RunState.CHOOSING_UPGRADE or not _offered_ids.has(id):
		return
	_offered_ids.clear()
	if _player.abilities.apply_upgrade(id):
		_progression.consume_upgrade()
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
	if _state != RunState.DEFEATED or _transition_requested:
		return
	_transition_requested = true
	restart_requested.emit()


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
