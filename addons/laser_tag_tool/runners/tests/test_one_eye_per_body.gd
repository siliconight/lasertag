extends SceneTree
## Seven heights described one firefight and no two agreed (roadmap 131).
##
##     crew   sees from   1.40   hardcoded in LT_BotPlayerController
##     crew   camera      1.60   scenario.player_eye_height_m, since 0.11.0
##     crew   shoots from 1.55   Marker3D_Muzzle, a child of that camera
##     enemy  sees from   1.50   LT_EnemyPill.tscn Marker3D_Eye
##     enemy  shoots from 1.30   LT_EnemyPill.tscn Marker3D_Muzzle
##     enemy  targeted at 1.40   LT_PlayerRegistry.get_best_target_for_enemy
##     sampler            1.50   LT_MapSampler's own const EYE_HEIGHT
##
## Two of those are defects on their own. A body that sights 0.15 m BELOW its
## own barrel can decline a shot it has, and take one it cannot; an enemy that
## sights 0.2 m ABOVE its barrel shoots into the cover it is looking over. The
## registry's 1.4 went live only when crews grew past one member (roadmap 129),
## so target SELECTION and target ENGAGEMENT had disagreed since the day
## multi-member crews started running.
##
## The sampler's is the quietest and the worst: it is the number that decides
## what the report says about the MAP rather than about a run, so cover was
## being measured 0.1 m below the eye that plays the level.
##
## THE TEST THAT MATTERS IS [4]: what a body can see, it can shoot.

var failures: int = 0


func check(condition: bool, label: String) -> void:
	if condition:
		print("  ok: " + label)
	else:
		failures += 1
		print("  FAIL: " + label)


func near(a: float, b: float) -> bool:
	return absf(a - b) < 0.0005


func _init() -> void:
	var scenario := LT_TestScenario.new()

	print("[1] the scenario can reach every height")
	# Not "the fields exist": the fields the SCENARIO exposes are the whole
	# surface a consumer has, and three of the seven used to be unreachable
	# from here at all.
	check(near(scenario.player_eye_height_m, 1.6), "crew eye is a scenario field")
	check(near(scenario.enemy_eye_height_m, 1.6), "enemy eye is a scenario field")
	check(near(scenario.aim_height_m, 1.0), "aim height is a scenario field")

	print("[2] the aim height is settable, and the const is only a fallback")
	var before := LT_LineOfSightTester.aim_height
	check(near(before, LT_LineOfSightTester.CHEST_OFFSET.y),
		"defaults to the ratified CHEST_OFFSET")
	LT_LineOfSightTester.aim_height = 1.23
	check(near(LT_LineOfSightTester.chest_offset().y, 1.23),
		"chest_offset() follows the variable, not the const")
	LT_LineOfSightTester.aim_height = before

	print("[3] a body's eye is its own node")
	var pill: CharacterBody3D = load(
		"res://addons/laser_tag_tool/scenes/LT_PlayerPill.tscn").instantiate()
	var enemy: CharacterBody3D = load(
		"res://addons/laser_tag_tool/scenes/LT_EnemyPill.tscn").instantiate()
	root.add_child(pill)
	root.add_child(enemy)
	# `global_position` is Transform3D() until the node is actually in the
	# tree, and reading it early returns 0 for everything -- which makes an
	# "are these two equal" check pass by agreeing about nothing. Same wait
	# `test_body_collision_rules` takes for the same reason.
	await process_frame
	pill.global_position = Vector3.ZERO
	enemy.global_position = Vector3.ZERO

	var cam: Camera3D = pill.get_node("Camera3D")
	cam.position.y = 2.05                       # a taller studio's character
	check(near(LT_LineOfSightTester.eye_position(pill).y, 2.05),
		"crew eye follows the camera the harness places")

	var eye_marker: Marker3D = enemy.get_node("Marker3D_Eye")
	eye_marker.position.y = 1.77
	check(near(LT_LineOfSightTester.eye_position(enemy).y, 1.77),
		"enemy eye follows its own marker")

	print("[4] what a body can see, it can shoot")
	# The harness puts the muzzle AT the eye for both sides. Reproduced here
	# rather than instantiating the harness, because the claim under test is
	# that the two coincide -- so the test has to be able to state the target
	# without asking the code that produces it.
	var crew_muzzle: Marker3D = cam.get_node("Marker3D_Muzzle")
	crew_muzzle.position = Vector3.ZERO
	check(near(crew_muzzle.global_position.y,
		LT_LineOfSightTester.eye_position(pill).y),
		"crew muzzle sits at the crew eye")
	check(near(crew_muzzle.global_position.x, 0.0)
		and near(crew_muzzle.global_position.z, 0.0),
		"crew muzzle has no forward offset to push it through a wall")

	var enemy_muzzle: Marker3D = enemy.get_node("Marker3D_Muzzle")
	enemy_muzzle.position = Vector3(0.0, 1.77, 0.0)
	check(near(enemy_muzzle.global_position.y,
		LT_LineOfSightTester.eye_position(enemy).y),
		"enemy muzzle sits at the enemy eye")

	print("[5] no call site carries a height of its own")
	# The defect was six literals, so the guard is against literals rather
	# than against behaviour: a future edit that reintroduces one puts the
	# tool straight back where it was, and no run-level assertion catches it
	# on a map with no geometry in the band that moved.
	for path in [
			"res://addons/laser_tag_tool/scripts/player/LT_BotPlayerController.gd",
			"res://addons/laser_tag_tool/scripts/core/LT_PlayerRegistry.gd",
			"res://addons/laser_tag_tool/scripts/enemy/LT_EnemyBrain.gd"]:
		var text: String = FileAccess.get_file_as_string(path)
		var code := ""
		for line in text.split("\n"):
			if not line.strip_edges().begins_with("#"):
				code += line + "\n"
		check(not code.contains("Vector3.UP * 1."),
			path.get_file() + " sights from a node, not a literal")

	var sampler: LT_MapSampler = LT_MapSampler.new()
	check(near(sampler.eye_height, 1.6),
		"the sampler measures the map from the crew's eye, not its own 1.5")

	print("[6] the crossing height these produce")
	# What a solid must reach to break a MUTUAL line, which is the number
	# deli_counter/agent_contract.json derives from these three and which
	# combat_audit judges every room against. Printed rather than merely
	# asserted, because when this moves the contract has to move with it.
	var a: float = scenario.player_eye_height_m
	var b: float = scenario.enemy_eye_height_m
	var c: float = scenario.aim_height_m
	var crossing: float = a - (a - c) * (a - c) / (a + b - 2.0 * c)
	print("     crew %.2f, enemy %.2f, chest %.2f  ->  cover must reach %.4f m"
		% [a, b, c, crossing])
	check(near(crossing, 1.3), "1.6 / 1.6 / 1.0 crosses at 1.30")
	check(crossing > 1.2222,
		"and it is ABOVE the 1.2222 the mismatched heights produced")

	print("")
	if failures == 0:
		print("test_one_eye_per_body: PASS")
	else:
		print("test_one_eye_per_body: %d FAILURE(S)" % failures)
	quit(1 if failures > 0 else 0)
