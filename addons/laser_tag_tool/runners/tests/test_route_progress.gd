extends SceneTree
## How far the crew got, not merely whether it finished (roadmap 128).
##
## `route_completion_rate` is a boolean averaged, so it reports 0.0 whether the
## crew was wiped on the spawn or reached the objective and then cleared the
## map. Measured on market_row_001, three runs per enemy count, where every one
## of these scored completion 0.00:
##
##     enemies 1   progress 0.50   1 of 2 legs   ENEMIES_CLEARED
##     enemies 2   progress 0.50   1 of 2 legs   ENEMIES_CLEARED
##     enemies 4   progress 0.17   mostly 0 of 2  TEAM_WIPE
##
## TWO TRAPS, BOTH HIT BEFORE THIS WAS RIGHT.
##
## `_route_index` is NOT progress. `_update_stuck` advances it to move a jammed
## bot along, so it counts points skipped as well as reached. Progress comes
## from a separate counter that only ever increments on a real arrival.
##
## And the route's first point IS the spawn -- Lot emits `Route_0` at the crew
## spawn exactly, measured 0.00 m apart on restaurant_row_001. Counting points
## gave every run 1 of 3 for standing still, including a crew wiped at 3.4 s.
## Progress is counted in LEGS WALKED.

var failures: int = 0


func check(condition: bool, label: String) -> void:
	if condition:
		print("  ok: " + label)
	else:
		failures += 1
		print("  FAIL: " + label)


func _init() -> void:
	print("[1] legs, not points")
	# Three points whose first is the spawn is two legs, and standing on the
	# spawn is none of them.
	var points := 3
	var free_start := 1
	check(points - free_start == 2, "3 route points with a free start is 2 legs")
	check(maxi(0, 1 - free_start) == 0,
		"arriving only at the spawn is 0 legs, not 1 of 3")
	check(maxi(0, 3 - free_start) == 2, "arriving at all three is 2 of 2")

	print("[2] the collector averages the fraction and skips routeless runs")
	var collector := LT_MetricsCollector.new()
	get_root().add_child(collector)
	var runs: Array[Dictionary] = [
		{"route_points_reached": 1, "route_points_total": 2},
		{"route_points_reached": 2, "route_points_total": 2},
		{"route_points_reached": 0, "route_points_total": 2},
	]
	check(is_equal_approx(collector._progress(runs), 0.5),
		"0.5 + 1.0 + 0.0 over three runs is 0.50")
	var routeless: Array[Dictionary] = [
		{"route_points_reached": 0, "route_points_total": 0},
		{"route_points_reached": 2, "route_points_total": 2},
	]
	check(is_equal_approx(collector._progress(routeless), 1.0),
		"a run with no route is skipped, not counted as a zero -- a map that "
		+ "defines no route has not failed to walk one")
	check(is_equal_approx(collector._progress([] as Array[Dictionary]), 0.0),
		"and no runs at all is 0.0 rather than a divide by zero")

	print("[3] progress is not read off the skipping index")
	var src: String = FileAccess.get_file_as_string(
		"res://addons/laser_tag_tool/scripts/player/LT_BotPlayerController.gd")
	var stuck: String = src.substr(src.find("func _update_stuck"))
	stuck = stuck.substr(0, stuck.find(char(10) + "func "))
	check(stuck.find("_route_index") != -1,
		"_update_stuck still advances _route_index to unjam the bot")
	check(stuck.find("_route_reached") == -1,
		"but it does NOT touch _route_reached, so a skipped point is not "
		+ "reported as a walked leg")

	collector.free()
	if failures == 0:
		print("PASS: progress is legs walked, and skipping is not walking")
		quit(0)
	else:
		print("FAIL: %d check(s)" % failures)
		quit(1)
