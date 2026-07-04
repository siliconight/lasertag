extends Node3D
class_name LT_MapEvalHarness
## Drop-in map evaluation harness (TDD §11.1).
## Add this node to a level, press Play, and it will:
##   1. Discover LT_ map hooks
##   2. Validate the map (TDD §24)
##   3. Spawn players and enemies
##   4. Run a manual test with crosshair/HUD/debug lasers
## In headless mode, runners/run_map_eval.gd drives it instead via
## run_evaluation().

signal evaluation_finished(score: Dictionary)

const PLAYER_PILL := preload("../../scenes/LT_PlayerPill.tscn")
const ENEMY_PILL := preload("../../scenes/LT_EnemyPill.tscn")

enum Mode { MANUAL, HEADLESS_BOT }
enum CoopMode { OFF, HOST, JOIN }

@export var scenario: LT_TestScenario
@export var auto_start_manual: bool = true

@export_group("Coop Spike (cosmetic replication)")
## Overridden by command-line args: `--lt-host` / `--lt-join <ip>`.
## Editor demo: Debug > Customize Run Instances..., give instance 1 the
## arguments `-- --lt-host` and instance 2 `-- --lt-join 127.0.0.1`.
@export var coop_mode: CoopMode = CoopMode.OFF
@export var coop_ip: String = "127.0.0.1"
@export var coop_port: int = 24565

var mode: Mode = Mode.MANUAL
var validation_findings: Array[Dictionary] = []
var navigation_available: bool = false

# Discovered hooks
var player_spawns: Array[Node3D] = []
var enemy_spawns: Array[Node3D] = []
var objective_points: Array[Node3D] = []
var route_points: Array[Node3D] = []
var cover_points: Array[Node3D] = []

# Built children
var registry: LT_PlayerRegistry
var run_state: LT_RunState
var metrics: LT_MetricsCollector
var score_calculator: LT_ScoreCalculator
var report_writer: LT_ReportWriter
var map_sampler: LT_MapSampler
var debug_laser: LT_DebugLaser
var shot_audio: LT_ShotAudio
var crosshair: LT_Crosshair
var health_bar: LT_HealthBar
var hud: LT_DebugHUD
var settings_panel: LT_TracerSettingsPanel
var coop_session: LT_CoopSession

var sightline_data: Dictionary = {}

var _run_counter: int = 0
var _live_pills: Array[Node] = []
var _headless: bool = false
var _last_score: Dictionary = {}

## --trace diagnostics
var trace_enabled: bool = false
var _physics_ticks: int = 0
var _trace_marks: Array[float] = []

func _physics_process(_delta: float) -> void:
	_physics_ticks += 1

func _process(_delta: float) -> void:
	if not trace_enabled or mode != Mode.HEADLESS_BOT or not run_state.is_running:
		return
	if _trace_marks.is_empty():
		return
	if run_state.elapsed_seconds >= _trace_marks[0]:
		_trace_marks.pop_front()
		_print_trace_snapshot()

func _print_trace_snapshot() -> void:
	print("[LT trace] t=%.1fs run=%d physics_ticks=%d nav=%s" % [
		run_state.elapsed_seconds, run_state.run_id, _physics_ticks, navigation_available])
	for player in registry.get_all_players():
		var bot := player.get_node_or_null("LT_BotPlayerController")
		if bot != null:
			print("[LT trace]   " + bot.debug_status())
	for enemy in get_tree().get_nodes_in_group(LT_Const.GROUP_ENEMY):
		var brain := enemy.get_node_or_null("LT_EnemyBrain")
		if brain != null:
			print("[LT trace]   " + brain.debug_status())

func _ready() -> void:
	add_to_group(LT_Const.GROUP_HARNESS)
	_headless = DisplayServer.get_name() == "headless"
	if scenario == null:
		scenario = LT_TestScenario.new()

	LT_Const.ensure_input_actions()
	_build_children()
	discover_hooks(get_tree().current_scene if get_tree().current_scene != null else get_parent())

	if _headless or not auto_start_manual:
		return

	mode = Mode.MANUAL
	_setup_coop_session()
	# Defer so navigation maps have a chance to sync before validation.
	_start_manual_run.call_deferred()

func _setup_coop_session() -> void:
	# Session exists even offline — it owns the local cosmetic
	# (load/save + [C]/[V] editing). Networking only starts when asked.
	coop_session = LT_CoopSession.new()
	coop_session.name = "LT_CoopSession"
	add_child(coop_session)

	var requested := coop_mode
	var ip := coop_ip
	var loopback := false
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--lt-host":
			requested = CoopMode.HOST
		elif args[i] == "--lt-join":
			requested = CoopMode.JOIN
			if i + 1 < args.size() and not args[i + 1].begins_with("--"):
				ip = args[i + 1]
		elif args[i] == "--lt-loopback":
			loopback = true

	if loopback:
		var loop := LT_LoopbackAdapter.new()
		loop.name = "LT_NetAdapter"
		coop_session.add_child(loop)
		coop_session.set_adapter(loop)
		loop.start()
		_finish_session_setup()
		return

	var adapter := LT_GodotHighLevelAdapter.new()
	adapter.name = "LT_NetAdapter"
	coop_session.add_child(adapter)
	coop_session.set_adapter(adapter)
	_finish_session_setup()

	# Integration path first: if the host game already configured a
	# MultiplayerPeer (ENet, WebRTC, WebSocket, Steam, ...), ride it —
	# LT opens no connection of its own.
	if adapter.attach():
		return

	match requested:
		CoopMode.HOST:
			adapter.host_enet(coop_port)
		CoopMode.JOIN:
			adapter.join_enet(ip, coop_port)

func _finish_session_setup() -> void:
	if settings_panel != null:
		settings_panel.session = coop_session
	coop_session.cosmetic_changed.connect(_on_cosmetic_changed)

## Your own pill visibly changes too — the local half of "change
## something about your character and other players see it."
func _on_cosmetic_changed(peer_id: int, cosmetic: Dictionary) -> void:
	if peer_id != multiplayer.get_unique_id():
		return
	for player in registry.get_all_players():
		if player.get_meta("lt_peer_id", 1) != peer_id:
			continue
		_tint_pill(player, LT_Cosmetic.color_of(cosmetic))

func _tint_pill(pill: Node, color: Color) -> void:
	var mesh := pill.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh == null:
		return
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.surface_material_override = material

func _build_children() -> void:
	registry = LT_PlayerRegistry.new()
	registry.name = "LT_PlayerRegistry"
	add_child(registry)

	run_state = LT_RunState.new()
	run_state.name = "LT_RunState"
	run_state.run_ended.connect(_on_run_ended)
	add_child(run_state)

	metrics = LT_MetricsCollector.new()
	metrics.name = "LT_MetricsCollector"
	metrics.run_state = run_state
	metrics.record_debug_events = scenario.record_debug_events
	add_child(metrics)

	score_calculator = LT_ScoreCalculator.new()
	score_calculator.name = "LT_ScoreCalculator"
	add_child(score_calculator)

	report_writer = LT_ReportWriter.new()
	report_writer.name = "LT_ReportWriter"
	add_child(report_writer)

	map_sampler = LT_MapSampler.new()
	map_sampler.name = "LT_MapSampler"
	add_child(map_sampler)

	debug_laser = LT_DebugLaser.new()
	debug_laser.name = "LT_DebugRoot"
	debug_laser.enabled = scenario.enable_debug_lasers
	add_child(debug_laser)

	shot_audio = LT_ShotAudio.new()
	shot_audio.name = "LT_ShotAudio"
	shot_audio.enabled = scenario.enable_shot_audio
	add_child(shot_audio)

	if not _headless:
		var canvas := CanvasLayer.new()
		canvas.name = "LT_Canvas"
		add_child(canvas)

		crosshair = LT_Crosshair.new()
		crosshair.name = "LT_Crosshair"
		canvas.add_child(crosshair)
		debug_laser.crosshair = crosshair

		health_bar = LT_HealthBar.new()
		health_bar.name = "LT_HealthBar"
		canvas.add_child(health_bar)

		hud = LT_DebugHUD.new()
		hud.name = "LT_DebugHUD"
		hud.harness = self
		canvas.add_child(hud)

		settings_panel = LT_TracerSettingsPanel.new()
		settings_panel.name = "LT_TracerSettingsPanel"
		canvas.add_child(settings_panel)

## ---- Hook discovery (TDD §8) ----

func discover_hooks(root: Node) -> void:
	player_spawns.clear()
	enemy_spawns.clear()
	objective_points.clear()
	route_points.clear()
	cover_points.clear()
	if root == null:
		return
	_walk(root)
	_sort_by_name(player_spawns)
	_sort_by_name(enemy_spawns)
	_sort_by_name(route_points)

func _walk(node: Node) -> void:
	if node is Node3D:
		var node_name := String(node.name)
		if node_name.begins_with(LT_Const.HOOK_PLAYER_SPAWN):
			player_spawns.append(node)
		elif node_name.begins_with(LT_Const.HOOK_ENEMY_SPAWNS):
			for child in node.get_children():
				if child is Node3D:
					enemy_spawns.append(child)
		elif node_name.begins_with(LT_Const.HOOK_OBJECTIVE):
			objective_points.append(node)
		elif node_name.begins_with(LT_Const.HOOK_ROUTE):
			if node.get_child_count() > 0:
				for child in node.get_children():
					if child is Node3D:
						route_points.append(child)
			else:
				route_points.append(node)
		elif node_name.begins_with(LT_Const.HOOK_COVER):
			if node.get_child_count() > 0:
				for child in node.get_children():
					if child is Node3D:
						cover_points.append(child)
			else:
				cover_points.append(node)
	for child in node.get_children():
		if child == self:
			continue
		_walk(child)

func _sort_by_name(nodes: Array[Node3D]) -> void:
	nodes.sort_custom(func(a: Node3D, b: Node3D) -> bool: return String(a.name) < String(b.name))

## ---- Validation (TDD §24) ----

func validate_map() -> bool:
	validation_findings.clear()
	var ok := true

	if player_spawns.is_empty():
		_add_finding("FAIL", "MISSING_PLAYER_SPAWN", "No LT_PlayerSpawn node found.")
		if scenario.fail_on_missing_player_spawn:
			ok = false

	if enemy_spawns.is_empty():
		_add_finding("FAIL", "MISSING_ENEMY_SPAWNS", "No LT_EnemySpawnPoints children found.")
		if scenario.fail_on_missing_enemy_spawns:
			ok = false

	navigation_available = _navigation_ready()
	if not navigation_available:
		var severity := "FAIL" if scenario.require_navigation else "WARN"
		_add_finding(severity, "NAVIGATION_MISSING",
			"No usable NavigationRegion3D/NavigationMesh found. Falling back to direct movement (TDD §29.1).")
		if scenario.require_navigation:
			ok = false

	for spawn in player_spawns:
		if _point_inside_collision(spawn.global_position + Vector3.UP * 0.9):
			_add_finding("FAIL", "SPAWN_IN_COLLISION",
				"%s is inside world collision." % spawn.name)
			ok = false

	if navigation_available and not player_spawns.is_empty():
		for spawn in enemy_spawns:
			if not _spawn_can_reach(spawn.global_position, player_spawns[0].global_position):
				_add_finding("FAIL", "UNREACHABLE_SPAWN",
					"%s could not path to the player spawn." % spawn.name)
				if scenario.fail_on_unreachable_spawns:
					ok = false

	if not _world_collision_present():
		_add_finding("FAIL", "NO_WORLD_COLLISION",
			"Laser test ray hit nothing on the World layer — check collision layers.")
		ok = false

	return ok

func _navigation_ready() -> bool:
	var map_rid := get_world_3d().navigation_map
	# Force a synchronous server sync so readiness doesn't depend on how many
	# frames happened to elapse since the bake. Early CI runs raced this and
	# intermittently reported a freshly-baked map as missing.
	NavigationServer3D.map_force_update(map_rid)
	if NavigationServer3D.map_get_iteration_id(map_rid) == 0 \
			or NavigationServer3D.map_get_regions(map_rid).is_empty():
		return false
	# A region existing isn't enough — a 0-polygon or misplaced navmesh
	# would pass the checks above and then fail every reachability test
	# (first real-engine CI run failed exactly this way). Probe: the
	# navmesh must actually cover the play space near the player spawn.
	var probe := player_spawns[0].global_position \
		if not player_spawns.is_empty() else global_position
	var closest := NavigationServer3D.map_get_closest_point(map_rid, probe)
	return closest.distance_to(probe) < 3.0

func _spawn_can_reach(from_position: Vector3, to_position: Vector3) -> bool:
	var map_rid := get_world_3d().navigation_map
	var start := NavigationServer3D.map_get_closest_point(map_rid, from_position)
	if start.distance_to(from_position) > 3.0:
		return false
	var path := NavigationServer3D.map_get_path(map_rid, start, to_position, true)
	if path.is_empty():
		return false
	var path_end: Vector3 = path[path.size() - 1]
	return path_end.distance_to(to_position) < 3.0

func _point_inside_collision(point: Vector3) -> bool:
	var params := PhysicsPointQueryParameters3D.new()
	params.position = point
	params.collision_mask = LT_Const.LAYER_WORLD
	return not get_world_3d().direct_space_state.intersect_point(params, 1).is_empty()

func _world_collision_present() -> bool:
	# Fire a validation ray straight down from above the first spawn.
	var origin := player_spawns[0].global_position + Vector3.UP * 2.0 \
		if not player_spawns.is_empty() else global_position + Vector3.UP * 2.0
	var query := PhysicsRayQueryParameters3D.create(origin, origin + Vector3.DOWN * 50.0)
	query.collision_mask = LT_Const.LAYER_WORLD
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _add_finding(severity: String, type_name: String, message: String) -> void:
	validation_findings.append({"severity": severity, "type": type_name, "message": message})
	if _headless:
		print("[LT %s] %s: %s" % [severity, type_name, message])

## ---- Spawning ----

func spawn_players(bot: bool) -> Array[Node]:
	var players: Array[Node] = []
	var count := scenario.player_count if bot else 1
	for i in count:
		var spawn := player_spawns[i % player_spawns.size()] if not player_spawns.is_empty() else self
		var pill := PLAYER_PILL.instantiate()
		pill.name = "LT_Player_%02d" % (i + 1)
		add_child(pill)
		pill.global_position = spawn.global_position
		_configure_player(pill, bot)
		registry.register_player(pill)
		_live_pills.append(pill)
		players.append(pill)
	return players

func _configure_player(pill: Node, bot: bool) -> void:
	pill.set_meta("lt_peer_id", multiplayer.get_unique_id() if not bot else 1)

	var health: LT_Health = pill.get_node("LT_Health")
	health.max_health = scenario.player_health
	health.reset_health()
	health.died.connect(_on_player_died.bind(pill))

	var shooter: LT_Shooter = pill.get_node("LT_Shooter")
	shooter.laser_range = scenario.player_laser_range
	shooter.setup(pill)

	var manual: LT_PlayerController = pill.get_node("LT_PlayerController")
	var bot_controller: LT_BotPlayerController = pill.get_node("LT_BotPlayerController")

	if bot:
		manual.set_physics_process(false)
		manual.set_process_unhandled_input(false)
		var camera: Camera3D = pill.get_node("Camera3D")
		camera.current = false
		bot_controller.use_navigation = navigation_available
		bot_controller.start_route(_bot_route(), _points_to_positions(cover_points))
	else:
		bot_controller.set_physics_process(false)
		if not _headless and health != null:
			if crosshair != null:
				health.died.connect(func() -> void: crosshair.set_dead(true))
			if health_bar != null:
				health_bar.bind(health)
		if coop_session != null:
			_tint_pill(pill, LT_Cosmetic.color_of(coop_session.local_cosmetic))

func _bot_route() -> Array[Vector3]:
	# Prefer explicit route points, then objectives, then enemy spawn
	# positions as a fallback tour of the combat space.
	if not route_points.is_empty():
		return _points_to_positions(route_points)
	if not objective_points.is_empty():
		return _points_to_positions(objective_points)
	return _points_to_positions(enemy_spawns)

func _points_to_positions(nodes: Array[Node3D]) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	for node in nodes:
		positions.append(node.global_position)
	return positions

func spawn_enemies() -> void:
	if not scenario.enemies_enabled:
		return
	if enemy_spawns.is_empty():
		return
	var spawn_order := enemy_spawns.duplicate()
	if scenario.use_random_spawn_permutations:
		spawn_order.shuffle()
	for i in scenario.enemy_count:
		var spawn: Node3D = spawn_order[i % spawn_order.size()]
		var pill := ENEMY_PILL.instantiate()
		pill.name = "LT_Enemy_%02d" % (i + 1)
		add_child(pill)
		pill.global_position = spawn.global_position
		_configure_enemy(pill)
		_live_pills.append(pill)

func _configure_enemy(pill: Node) -> void:
	var health: LT_Health = pill.get_node("LT_Health")
	health.max_health = scenario.enemy_health
	health.reset_health()
	health.died.connect(_check_enemies_cleared, CONNECT_DEFERRED)

	var shooter: LT_Shooter = pill.get_node("LT_Shooter")
	shooter.laser_range = scenario.enemy_laser_range
	shooter.setup(pill)

	var brain: LT_EnemyBrain = pill.get_node("LT_EnemyBrain")
	brain.fire_cooldown = scenario.enemy_fire_cooldown
	brain.sight_range = scenario.enemy_sight_range
	brain.preferred_distance = scenario.enemy_preferred_distance
	brain.reaction_delay_min = scenario.enemy_reaction_delay_min
	brain.reaction_delay_max = scenario.enemy_reaction_delay_max

	var movement: LT_EnemyMovement = pill.get_node("LT_EnemyMovement")
	movement.use_navigation = navigation_available

## ---- Run lifecycle ----

func _start_manual_run() -> void:
	await _await_navigation_sync()
	validate_map()
	start_run(false)

func start_run(bot: bool) -> void:
	_run_counter += 1
	metrics.begin_run(_run_counter, scenario.player_count if bot else 1, scenario.enemy_count)
	spawn_players(bot)
	spawn_enemies()
	run_state.start_run(_run_counter, scenario.max_run_time_seconds)

func stop_run(reason: LT_RunState.EndReason = LT_RunState.EndReason.MANUAL) -> void:
	run_state.end_run(reason)

func reset_run() -> void:
	stop_run(LT_RunState.EndReason.MANUAL)
	_clear_pills()
	if crosshair != null:
		crosshair.set_dead(false)
	start_run(mode == Mode.HEADLESS_BOT)

func _clear_pills() -> void:
	for pill in _live_pills:
		if is_instance_valid(pill):
			pill.queue_free()
	_live_pills.clear()
	registry.clear()

func _on_player_died(pill: Node) -> void:
	metrics.record_event("PlayerKilled", {"source": pill.name})
	if registry.all_players_dead():
		metrics.record_event("TeamWipe", {})
		run_state.end_run(LT_RunState.EndReason.TEAM_WIPE)

func _check_enemies_cleared() -> void:
	for enemy in get_tree().get_nodes_in_group(LT_Const.GROUP_ENEMY):
		if enemy.has_node("LT_Health") and not (enemy.get_node("LT_Health") as LT_Health).is_dead:
			return
	run_state.end_run(LT_RunState.EndReason.ENEMIES_CLEARED)

func _on_run_ended(_run_id: int, reason: String) -> void:
	metrics.end_run(reason)
	if mode == Mode.MANUAL and not _headless:
		_print_manual_summary()

func _unhandled_input(event: InputEvent) -> void:
	if mode != Mode.MANUAL:
		return
	if event.is_action_pressed(LT_Const.ACTION_RESET):
		reset_run()
	elif event.is_action_pressed(LT_Const.ACTION_TOGGLE_ENEMIES):
		set_enemies_enabled(not scenario.enemies_enabled)

## Free-roam switch. OFF despawns all live enemies immediately (no death
## events — they vanish, they don't die); ON respawns the scenario's
## enemy count at the spawn points. Local-only in coop: each peer runs
## its own enemy sim, so each peer chooses its own mode.
func set_enemies_enabled(enabled: bool) -> void:
	if scenario.enemies_enabled == enabled:
		return
	scenario.enemies_enabled = enabled
	metrics.record_event("EnemiesToggled", {"enabled": enabled})
	print("[LT] Enemies: %s" % ("ON" if enabled else "OFF"))

	if enabled:
		spawn_enemies()
		return

	for enemy in get_tree().get_nodes_in_group(LT_Const.GROUP_ENEMY):
		_live_pills.erase(enemy)
		enemy.queue_free()

## ---- Headless evaluation API (used by runners/run_map_eval.gd) ----

func run_evaluation(eval_scenario: LT_TestScenario) -> Dictionary:
	mode = Mode.HEADLESS_BOT
	scenario = eval_scenario
	metrics.record_debug_events = scenario.record_debug_events
	debug_laser.enabled = false

	await _await_navigation_sync()
	discover_hooks(get_parent())
	var valid := validate_map()
	if not valid:
		_last_score = score_calculator.calculate({}, scenario, validation_findings)
		evaluation_finished.emit(_last_score)
		return _last_score

	sightline_data = {}
	if scenario.enable_map_sampling and not enemy_spawns.is_empty():
		map_sampler.sample_spacing = scenario.sample_spacing
		map_sampler.overexposed_threshold = scenario.overexposed_threshold
		var anchors := _points_to_positions(player_spawns)
		anchors.append_array(_points_to_positions(enemy_spawns))
		anchors.append_array(_points_to_positions(route_points))
		sightline_data = map_sampler.sample_map(
			get_world_3d(), navigation_available,
			_points_to_positions(enemy_spawns), anchors)
		if not sightline_data.is_empty():
			print("[LT] Sampled %d positions: %.0f%% blind, %.0f%% overexposed" % [
				sightline_data["total_samples"],
				sightline_data["blind_fraction"] * 100.0,
				sightline_data["overexposed_fraction"] * 100.0])

	for i in scenario.run_count:
		if scenario.random_seed != 0:
			seed(scenario.random_seed + i)
		_clear_pills()
		start_run(scenario.use_bot_players)
		if trace_enabled and i == 0:
			_trace_marks = [0.5, 2.0, 5.0, 10.0, 20.0]
		await run_state.run_ended
		metrics.end_run(run_state.end_reason_name())
		print("[LT] run %d/%d ended: %s (%.1fs)" % [
			i + 1, scenario.run_count, run_state.end_reason_name(), run_state.elapsed_seconds])

	_clear_pills()
	_last_score = score_calculator.calculate(
		metrics.summary(), scenario, validation_findings, sightline_data)
	evaluation_finished.emit(_last_score)
	return _last_score

func write_reports(json_path: String, map_name: String, scenario_name: String,
		extras: Dictionary = {}) -> void:
	var summary := metrics.summary()
	var merged_extras := extras.duplicate()
	if not sightline_data.is_empty():
		merged_extras["sightlines"] = sightline_data
	report_writer.write_json(json_path, map_name, scenario_name, summary,
		_last_score, metrics.completed_runs, metrics.events,
		scenario.record_debug_events, merged_extras)
	report_writer.write_csv(json_path.get_basename() + ".csv", map_name,
		scenario_name, metrics.completed_runs, _last_score)
	print("")
	print(report_writer.human_summary(map_name, _last_score))
	print("")
	print("[LT] JSON report: %s" % ProjectSettings.globalize_path(json_path))

func _await_navigation_sync() -> void:
	# Navigation maps sync on the server a few frames after scene load.
	for i in 3:
		await get_tree().physics_frame

## ---- HUD ----

func hud_text() -> String:
	var alive_enemies := 0
	var total_enemies := 0
	for enemy in get_tree().get_nodes_in_group(LT_Const.GROUP_ENEMY):
		total_enemies += 1
		if enemy.has_node("LT_Health") and not (enemy.get_node("LT_Health") as LT_Health).is_dead:
			alive_enemies += 1

	var player_health_text := "-"
	var players := registry.get_all_players()
	if not players.is_empty() and players[0].has_node("LT_Health"):
		var health: LT_Health = players[0].get_node("LT_Health")
		player_health_text = "%d / %d" % [health.current_health, health.max_health]

	var current := metrics.current
	var format := "LT MAP EVAL — %s\nHP: %s\nEnemies: %s\nTime: %.1fs" \
		+ "\nShots: %d  Blocked: %d\nStuck (enemy): %d%s" \
		+ "\n[Tab] tracer settings  [R] reset  [N] enemies  [Esc] mouse"
	var coop_line := ""
	if coop_session != null:
		var cosmetic := coop_session.local_cosmetic
		coop_line = "\nTracer: %s %s" % [
			cosmetic.get("color", "?"), cosmetic.get("style", "?")]
		if coop_session.is_active():
			coop_line += "  |  Coop: peer %d, %d other(s), %s" % [
				coop_session.local_peer_id(), coop_session.peer_cosmetics.size(),
				coop_session.describe_transport()]
	var enemies_text := "%d / %d" % [alive_enemies, total_enemies]
	if not scenario.enemies_enabled:
		enemies_text = "OFF (free-roam)"
	return format % [
		"MANUAL" if mode == Mode.MANUAL else "BOT",
		player_health_text,
		enemies_text,
		run_state.elapsed_seconds,
		current.get("shots_fired", 0), current.get("shots_blocked", 0),
		current.get("enemy_stuck_events", 0),
		coop_line,
	]

func _print_manual_summary() -> void:
	var current_runs := metrics.completed_runs
	if current_runs.is_empty():
		return
	var run: Dictionary = current_runs[current_runs.size() - 1]
	print("[LT] Run %d ended (%s): shots %d, hit %d, blocked %d, enemies killed %d, deaths %d" % [
		run["run_id"], run["end_reason"], run["shots_fired"], run["shots_hit"],
		run["shots_blocked"], run["enemy_deaths"], run["player_deaths"]])
