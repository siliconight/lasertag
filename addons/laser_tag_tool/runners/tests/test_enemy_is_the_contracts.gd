extends SceneTree
## An enemy is the contract's body too (0.26.0, roadmap 197).
##
## `LT_MapEvalHarness._apply_body` has built the crew from the scenario's body
## since roadmap 123, and `LT_BotPlayerController._align_agent_to_mesh` has
## derived the crew's arrival radius since 0.18.0. The enemy got neither: it
## kept `LT_EnemyPill.tscn`'s capsule of radius 0.40 -- the BAKE's agent radius,
## which `deli_counter/agent_contract.json` says is "NOT a body radius and
## nothing should be built from it" -- and the scene's `path_desired_distance`
## 0.8, the value 0.18.0 measured cutting corners and jamming the crew
## (route completion 0.0 and 38 stuck events, four runs of four). 0.18.0's note
## said the 0.8 was left "as the authored fallback ... nothing in this repo's
## own evaluation path uses it any more": true of players, and every enemy the
## harness has spawned since took it. A navmesh eroded by 0.40 leaves a 0.40
## body no clearance at a door's jamb, and a waypoint counted reached from 0.8 m
## away turns it into the jamb.
##
##   [1] one derivation for every body: `LT_Const.arrival_radius` is the
##       0.18.0 formula, and the crew's controller calls it.
##   [2] the harness builds an enemy from the scenario: its capsule, mesh and
##       agent take the crew's radius and height (npc_standard shares the
##       player's metrics until a distinct class ships). FAILS ON 0.25.0: the
##       capsule stays 0.40.
##   [3] an enemy that sets out derives its arrival radius and its path height
##       offset from its body and the map, as the crew does. FAILS ON 0.25.0:
##       0.8 and 0.0.
##
## Run:  godot --headless --path lasertag -s res://addons/laser_tag_tool/runners/tests/test_enemy_is_the_contracts.gd

var failures: int = 0


func check(condition: bool, label: String) -> void:
	if condition:
		print("  ok: " + label)
	else:
		failures += 1
		print("  FAIL: " + label)


func _init() -> void:
	LT_Const.ensure_input_actions()

	print("[1] one derivation for every body")
	# 0.18.0's own figures: radius 0.35, speed 4.0, 60 Hz, cell height 0.25.
	var crew: float = LT_Const.arrival_radius(0.35, 4.0, 60.0, 0.25)
	var by_hand: float = sqrt(pow(0.35 + 4.0 / 60.0, 2.0) + pow(0.125, 2.0))
	check(absf(crew - by_hand) < 1e-6,
		"arrival_radius is the 0.18.0 formula (%.4f)" % crew)
	check(crew < 0.8, "and tighter than the scene's 0.8")
	var src: String = FileAccess.get_file_as_string(
		"res://addons/laser_tag_tool/scripts/player/LT_BotPlayerController.gd")
	check(src.find("LT_Const.arrival_radius(") != -1,
		"the crew's controller calls it rather than restating it")

	print("[2] the harness builds an enemy from the scenario's body")
	var harness := LT_MapEvalHarness.new()
	harness.scenario = LT_TestScenario.new()
	var radius: float = harness.scenario.player_radius_m
	var height: float = harness.scenario.player_height_m
	var enemy_scene: PackedScene = load("res://addons/laser_tag_tool/scenes/LT_EnemyPill.tscn")
	var enemy: Node = enemy_scene.instantiate()
	get_root().add_child(enemy)
	await process_frame
	harness._configure_enemy(enemy)
	var shape_node: CollisionShape3D = enemy.get_node("CollisionShape3D")
	var cap: CapsuleShape3D = shape_node.shape as CapsuleShape3D
	check(cap != null and absf(cap.radius - radius) < 1e-6,
		"the capsule's radius is the scenario's %.2f (was the bake's 0.40): %.2f"
		% [radius, cap.radius if cap != null else -1.0])
	check(cap != null and absf(cap.height - height) < 1e-6,
		"and its height the scenario's %.2f" % height)
	var agent: NavigationAgent3D = enemy.get_node("NavigationAgent3D")
	check(absf(agent.radius - radius) < 1e-6,
		"the agent's radius is the body's (%.2f)" % agent.radius)

	print("[3] an enemy that sets out derives its arrival radius from its body")
	var movement: LT_EnemyMovement = enemy.get_node("LT_EnemyMovement")
	movement.use_navigation = true
	await physics_frame
	movement.set_destination(Vector3(5.0, 0.0, 0.0))
	var map: RID = agent.get_navigation_map()
	var cell_height: float = NavigationServer3D.map_get_cell_height(map)
	var want: float = LT_Const.arrival_radius(agent.radius, movement.move_speed,
		float(Engine.physics_ticks_per_second), cell_height)
	check(absf(agent.path_desired_distance - want) < 1e-6,
		"path_desired_distance %.4f is the body's %.4f (the scene's was 0.8)"
		% [agent.path_desired_distance, want])
	check(absf(agent.path_height_offset - cell_height) < 1e-6,
		"path_height_offset is the map's cell height %.2f" % cell_height)
	movement.stop()

	enemy.queue_free()
	harness.free()
	if failures == 0:
		print("PASS: an enemy is built and steered as the contract's body")
		quit(0)
	else:
		print("FAIL: %d check(s)" % failures)
		quit(1)
