extends SceneTree
## `path_desired_distance` comes from the body and the bake (roadmap 123).
##
## It was 0.8 in both pill scenes: a number with no stated origin, sitting in
## the scene files the size contract exists to stop being the source of truth.
## It decides when a waypoint counts as reached, so it is a property of the
## body that walks and the mesh it walks on, and both are readable at spawn.
##
## AND IT WAS NOT MERELY UNTIDY. Measured on restaurant_row_001 seed 9003 with
## no enemies, 180 s, four runs either side -- the only difference the constant:
##
##     0.8 authored     route_completion 0.0  x4     player_stuck 38 x4
##     0.435 derived    route_completion 1.0  x4     player_stuck  0 x4
##
## Three further seeds on the derived value completed 1.0 with 0 stuck. At 0.8
## the agent counts a waypoint reached from 0.8 m away, cuts the corner and
## jams; that is the OPPOSITE failure to item 122, where the distance was too
## small to register arrival at all. Both directions are real, which is the
## argument for deriving it rather than picking a value that survives one map.

var failures: int = 0


func check(condition: bool, label: String) -> void:
	if condition:
		print("  ok: " + label)
	else:
		failures += 1
		print("  FAIL: " + label)


func _init() -> void:
	print("[1] the derivation, on the shipped contract")
	# radius 0.35 and speed 4.0 are agent_contract.json's characters.player;
	# 0.25 is map_get_cell_height on these bakes; 60 is the physics tick.
	var radius := 0.35
	var speed := 4.0
	var cell := 0.25
	var ticks := 60.0
	var horizontal: float = radius + speed / ticks
	var vertical: float = cell * 0.5
	var derived: float = sqrt(horizontal * horizontal + vertical * vertical)
	print("     radius %.2f + %.2f/%.0f per frame, half-cell %.3f -> %.4f" % [
		radius, speed, ticks, vertical, derived])
	check(derived > radius,
		"a waypoint inside the body's own footprint counts as reached")
	check(derived < 0.8,
		"and it is TIGHTER than the 0.8 it replaces (%.3f)" % derived)
	check(derived > speed / ticks,
		"while still exceeding one frame of travel (%.4f), below which the "
		% (speed / ticks) + "body steps over the threshold between samples")

	print("[2] a bigger body or a coarser bake asks for more room")
	var wide: float = sqrt(pow(0.60 + speed / ticks, 2.0) + vertical * vertical)
	check(wide > derived, "a 0.60 m body gets %.3f against %.3f" % [wide, derived])
	var coarse: float = sqrt(horizontal * horizontal + pow(0.50 * 0.5, 2.0))
	check(coarse > derived, "a 0.50 m cell gets %.3f against %.3f" % [coarse, derived])

	print("[3] the controller derives it rather than reading the scene")
	var src: String = FileAccess.get_file_as_string(
		"res://addons/laser_tag_tool/scripts/player/LT_BotPlayerController.gd")
	var body_src: String = src.substr(src.find("func _align_agent_to_mesh"))
	body_src = body_src.substr(0, body_src.find(char(10) + "func "))
	check(body_src.find("path_desired_distance") != -1,
		"_align_agent_to_mesh sets path_desired_distance")
	for term in ["nav_agent.radius", "move_speed", "physics_ticks_per_second",
			"map_get_cell_height"]:
		check(body_src.find(term) != -1, "and reads %s" % term)

	if failures == 0:
		print("PASS: the arrival radius is a property of the body and the bake")
		quit(0)
	else:
		print("FAIL: %d check(s)" % failures)
		quit(1)
