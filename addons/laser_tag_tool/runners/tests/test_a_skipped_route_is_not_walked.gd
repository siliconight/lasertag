extends SceneTree
## A route that ended on a skip is not a route walked (0.25.0, roadmap 206).
##
## `route_completion_rate` is the share of runs that recorded `ObjectiveReached`,
## and that used to fire when `_route_index` ran off the end of the route. The
## index is not progress: `_update_stuck` advances it past a point the bot is
## jammed on (roadmap 128 says so, and counts arrivals in `_route_reached`).
##
## THE GETAWAY VAN MADE IT A HEIST FOR FREE. Lot 0.98.0 parks the crew's van at
## its spawn, so the route is spawn, objective, and back to the van -- whose
## point is the spawn's. A bot jammed in its first seconds was skipped past the
## objective to "back at the van", arrived at once because it was standing
## beside it, and recorded a finished heist for a crew that never left. The
## candidate picker reads completion right after the majors.
##
## Run:  godot --headless --path lasertag -s res://addons/laser_tag_tool/runners/tests/test_a_skipped_route_is_not_walked.gd

var failures: int = 0


func check(condition: bool, label: String) -> void:
	if condition:
		print("  ok: " + label)
	else:
		failures += 1
		print("  FAIL: " + label)


func _init() -> void:
	print("[1] a route is walked when every point on it was reached")
	check(LT_BotPlayerController.route_walked(3, 3), "3 of 3 reached is walked")
	check(not LT_BotPlayerController.route_walked(2, 3),
		"2 of 3 -- one skipped -- is not")
	check(not LT_BotPlayerController.route_walked(0, 0),
		"no route at all is not a route walked")

	print("[2] the getaway van's route: spawn, objective, the van at the spawn")
	# jammed at the start: the free arrival at the spawn, the objective
	# skipped, and the van -- standing beside it -- "reached"
	check(not LT_BotPlayerController.route_walked(2, 3),
		"jammed at the start and skipped home is not a heist done")
	check(LT_BotPlayerController.route_walked(3, 3),
		"out to the objective and back to the van is")

	print("[3] the controller records ObjectiveReached only for a walked route")
	var src: String = FileAccess.get_file_as_string(
		"res://addons/laser_tag_tool/scripts/player/LT_BotPlayerController.gd")
	var adv: String = src.substr(src.find("func _advance_route"))
	adv = adv.substr(0, adv.find(char(10) + "func "))
	var gate: int = adv.find("if route_walked(_route_reached, route_points.size()):")
	check(gate != -1, "_advance_route asks route_walked of the arrivals")
	check(adv.find("\"ObjectiveReached\"") > gate,
		"and ObjectiveReached sits under that question")
	check(adv.find("\"RouteEndedShort\"") > gate,
		"a route that ended short is said, as RouteEndedShort")
	var stuck: String = src.substr(src.find("func _update_stuck"))
	stuck = stuck.substr(0, stuck.find(char(10) + "func "))
	check(stuck.find("_route_reached") == -1,
		"and the stuck skip still never touches the arrivals")

	print("[4] the harness ends a short route as ENEMIES_CLEARED, not OBJECTIVE")
	var h: String = FileAccess.get_file_as_string(
		"res://addons/laser_tag_tool/scripts/core/LT_MapEvalHarness.gd")
	check(h.find("route_completed.connect(_on_route_walked.bind(bot_controller))") != -1,
		"each bot's route end reaches the harness with the bot")
	check(h.find("OBJECTIVE if bot.walked_whole_route()") != -1,
		"and OBJECTIVE is only for a bot that walked it")

	if failures == 0:
		print("PASS: a route ended on a skip is not a route walked")
		quit(0)
	else:
		print("FAIL: %d check(s)" % failures)
		quit(1)
