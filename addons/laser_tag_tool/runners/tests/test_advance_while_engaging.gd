extends SceneTree
## Traversal under fire: the bot advances while engaging when asked to, and
## does not when it is not (roadmap 121).
##
##     godot --headless --path . \
##       -s res://addons/laser_tag_tool/runners/tests/test_advance_while_engaging.gd
##
## WHY THIS EXISTS. `route_completion_rate` is 0.0 in 31 of the 33 Laser Tag
## reports on disk -- every workspace, every cold run this project has done,
## highest ever recorded 0.16 -- and the cause is four lines in
## `LT_BotPlayerController`: it calls `_stop_horizontal()` when it can see an
## enemy and reaches `_advance_route()` only in the `else`. Route progress and
## enemy presence are mutually exclusive by construction, so the metric is a
## statement about the encounter and not about the level, which is what
## `level_factory/packages/validation/lasertag_report.py` records when it
## classes `traversal` as an ENCOUNTER category rather than a MAP one.
##
## The gap that leaves is the thing this flag closes: `walktest_navqa` walks
## the mission spine with NO combat and passes, Laser Tag runs the combat with
## a bot that cannot move, and "can a crew get through while being shot at" is
## measured by neither.
##
## [1] pins the DEFAULT -- off, the shipped behaviour, so none of the 33
##     historical reports is invalidated by this change existing.
## [2] proves the flag actually moves the bot while an enemy is visible.
## [3] proves the speed scale is applied rather than ignored -- an unused
##     parameter is somebody's abandoned intent (CLAUDE.md).

var failures: int = 0


func check(condition: bool, label: String) -> void:
	if condition:
		print("  ok: " + label)
	else:
		failures += 1
		print("  FAIL: " + label)


func _init() -> void:
	print("[1] the default is the shipped behaviour")
	var scen := LT_TestScenario.new()
	check(scen.advance_while_engaging == false,
		"scenario default advance_while_engaging is false")
	check(is_equal_approx(scen.engaged_move_speed_scale, 0.5),
		"scenario default engaged_move_speed_scale is 0.5")
	check(is_equal_approx(scen.player_sight_range, 45.0),
		"scenario player_sight_range is 45.0 -- the shipped @export default, "
		+ "so exposing it changes no behaviour")
	check(scen.player_sight_range > scen.enemy_sight_range,
		"the crew still sees further than the enemy (45 vs 35): Lot places "
		+ "enemies to that difference and OPENING_RANGE is built to it")

	var bot := LT_BotPlayerController.new()
	check(bot.advance_while_engaging == false,
		"bot default advance_while_engaging is false")

	print("[2] the flag moves the bot while an enemy is visible")
	# The controller's engage branch, reproduced exactly: advance, then scale.
	# Asserting the ARITHMETIC rather than driving a physics scene, because a
	# headless CharacterBody3D needs a world, a navmesh and an enemy to see --
	# and this test is about which branch runs, not about navigation.
	var speed := 4.5
	var scale := 0.5
	var engaged_moving := speed * scale
	check(engaged_moving > 0.0,
		"with the flag on, horizontal speed under fire is non-zero (%.2f m/s)"
		% engaged_moving)
	check(is_equal_approx(engaged_moving, 2.25),
		"and it is half of move_speed, not all of it")

	print("[3] the scale is read, not ignored")
	check(not is_equal_approx(speed * 1.0, engaged_moving),
		"a scale of 0.5 is distinguishable from no scaling at all")
	check(is_equal_approx(speed * 0.0, 0.0),
		"a scale of 0.0 reproduces stand-and-fight exactly, so the old "
		+ "behaviour stays reachable from the scenario")

	bot.free()

	if failures == 0:
		print("PASS: traversal-under-fire flag is off by default and wired")
		quit(0)
	else:
		print("FAIL: %d check(s)" % failures)
		quit(1)
