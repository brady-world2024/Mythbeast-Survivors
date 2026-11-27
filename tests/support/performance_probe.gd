extends SceneTree
## Render-load fixture. Invoke with -1 (idle), 10, 20, 28, or 0 (boss).

const Arena := preload("res://features/levels/whispering_grove/whispering_grove.tscn")
const Player = preload("res://features/player/player.gd")
const Actor = preload("res://features/enemies/enemy_actor.gd")
const Timeline = preload("res://features/levels/run_timeline.gd")
const Projectile = preload("res://features/combat/arcane_bolt.gd")
const Comfort = preload("res://features/presentation/comfort.gd")
const BOLT := preload("res://features/combat/arcane_bolt.tscn")
const SCENES: Array[PackedScene] = [
	preload("res://features/enemies/forest_slime.tscn"),
	preload("res://features/enemies/swift_fangling.tscn"),
	preload("res://features/enemies/moss_golem.tscn"),
]
const SAMPLE_TICKS := 180

var _arena: Node2D
var _player: Player
var _effects: Node2D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var argument := OS.get_cmdline_user_args()
	if argument.is_empty():
		quit(2)
		return
	var count := int(argument[0])
	Comfort.reduced_effects = argument.size() > 1 and argument[1] == "reduced"
	_arena = Arena.instantiate() as Node2D
	root.add_child(_arena)
	_arena.get_node("%WaveSpawner").stop()
	_player = _arena.get_node("%Player") as Player
	_effects = _arena.get_node("%Effects") as Node2D
	_player.health.configure(2000)
	for id in [&"arcane_bolt", &"chain_lightning", &"flame_aura", &"frost_touch"]:
		_player.abilities.apply_upgrade(id)
	if count > 0:
		_build_enemy_mix(count)
	elif count == 0:
		var timeline := _arena.get_node("%RunTimeline") as Timeline
		timeline.advance(180.0)
		for frame in range(160):
			await physics_frame
		if timeline.phase != Timeline.Phase.BOSS_FIGHT:
			push_error("Boss did not enter the fight.")
			quit(2)
			return
		var boss: Node = _arena.get("_boss")
		boss.get_node("Health").call("damage", 300)
	var sample: Array[float] = []
	var draw_peak := 0
	var physics_peak := 0.0
	var process_peak := 0.0
	var peak_nodes := 0
	var peak_projectiles := 0
	var active_min := 1000
	var active_max := 0
	for frame in range(45):
		await physics_frame
	for frame in range(SAMPLE_TICKS):
		if count > 0 and frame % 30 == 0:
			_emit_projectile_burst()
		if count >= 0:
			_cycle_movement(frame)
		var start := Time.get_ticks_usec()
		await process_frame
		sample.append(float(Time.get_ticks_usec() - start) * 0.001)
		var actors := get_nodes_in_group(&"combat_enemies").size()
		var projectiles := get_nodes_in_group(&"arcane_bolts").size()
		active_min = mini(active_min, actors)
		active_max = maxi(active_max, actors)
		peak_projectiles = maxi(peak_projectiles, projectiles)
		peak_nodes = maxi(peak_nodes, get_node_count())
		draw_peak = maxi(draw_peak, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		physics_peak = maxf(physics_peak, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		process_peak = maxf(process_peak, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	sample.sort()
	print("Profile enemies=", count, " reduced_effects=", Comfort.reduced_effects, " active_min=", active_min, " active_max=", active_max,
		" samples=", SAMPLE_TICKS, " measured_fps=", 1000.0 * SAMPLE_TICKS / sample.reduce(func(sum: float, value: float) -> float: return sum + value, 0.0), " median_ms=", sample[floori(SAMPLE_TICKS * 0.5)],
		" p95_ms=", sample[floori(float(SAMPLE_TICKS) * 0.95)], " max_ms=", sample.back(),
		" peak_nodes=", peak_nodes, " peak_projectiles=", peak_projectiles,
		" draw_peak=", draw_peak, " physics_peak_ms=", physics_peak, " process_peak_ms=", process_peak,
		" static_memory_mb=", Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0)
	for action in [&"move_right", &"move_down", &"move_left", &"move_up"]:
		Input.action_release(action)
	quit(0)


func _build_enemy_mix(count: int) -> void:
	for index in range(count):
		var actor := SCENES[index % SCENES.size()].instantiate() as Actor
		actor.position = Vector2(-155.0 + float(index % 6) * 60.0, -106.0 + floorf(index / 6.0) * 71.0)
		actor.target = _player
		actor.configure_spawn(55.0, 1.0, 1.0)
		_player.get_parent().add_child(actor)
		_arena.call("_track_enemy_reward", actor)


func _emit_projectile_burst() -> void:
	for index in range(8):
		var bolt := BOLT.instantiate() as Projectile
		_effects.add_child(bolt)
		var aim := Vector2.from_angle(float(index) * TAU / 8.0)
		bolt.launch(_player.global_position, aim, _player.abilities.bolt)


func _cycle_movement(frame: int) -> void:
	var directions := [&"move_right", &"move_down", &"move_left", &"move_up"]
	for action in directions:
		Input.action_release(action)
	Input.action_press(directions[floori(frame / 36.0) % directions.size()])
