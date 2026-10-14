extends SceneTree
## An arrival is at the point, not at the end of a path that stops short of it (0.32.0, factory roadmap 246).
##
## `_advance_route` counted a route point reached when `_nav_finished()` -- `NavigationAgent3D.
## is_navigation_finished()`, true at the end of the path the navigation server returned. For a point the
## network does not reach, that path ends at the closest point it does. The factory's roadmap 245 census found
## cold run 9185's restaurant_row_001 seed_9003 reading route completion 1.00 in every run while its walk test
## said the objective stood on a navmesh island, 60.99 m from the main network; traced in a run (the factory's
## `docs/findings/lt_arrival/arrival_trace.py`), every crew bot "arrived" at it 61.2 m away, 2.5 m from its
## spawn, `is_target_reached()` false and `get_final_position()` (-8.55, 0.0, -28.05).
##
## Run:  godot --headless --path lasertag -s res://addons/laser_tag_tool/runners/tests/test_an_arrival_is_at_the_point.gd

var failures: int = 0


func check(condition: bool, label: String) -> void:
	if condition:
		print("  ok: " + label)
	else:
		failures += 1
		print("  FAIL: " + label)


func _init() -> void:
	print("[1] where the path ends against the point, as traced on cold run 9185's seed_9003")
	var objective: Vector3 = Vector3(-54.0, 3.3, 12.47)
	check(not LT_BotPlayerController.path_reaches_point(Vector3(-8.550003, 0.0, -28.05), objective, 1.0),
		"a path ending 61 m short of the objective does not reach it")
	check(LT_BotPlayerController.path_reaches_point(Vector3(-6.0, 0.0, -29.5), Vector3(-6.0, 0.0, -29.5), 1.0),
		"a path ending on its point reaches it (the spawn)")
	check(LT_BotPlayerController.path_reaches_point(Vector3(-56.0, 0.15, 20.47), Vector3(-56.0, 0.0, 20.47), 1.0),
		"a path ending a cell above its point reaches it (the extraction)")

	print("[2] the controller counts an arrival only where the path reaches the point")
	var src: String = FileAccess.get_file_as_string(
		"res://addons/laser_tag_tool/scripts/player/LT_BotPlayerController.gd")
	var adv: String = src.substr(src.find("func _advance_route"))
	adv = adv.substr(0, adv.find(char(10) + "func "))
	var ask: int = adv.find("arrived = path_reaches_point(nav_agent.get_final_position(),")
	check(ask != -1, "_advance_route asks path_reaches_point of the path's end")
	var counted: int = adv.find("if arrived:" + char(10) + char(9) + char(9) + char(9) + "_route_reached += 1")
	check(counted > ask, "and counts the arrival only under that answer")
	check(adv.find("\"RoutePointUnreachable\"") > ask, "a point the path stops short of is said")
	check(adv.count("_route_reached += 1") == 1, "and nothing else in _advance_route counts an arrival")

	if failures == 0:
		print("PASS: an arrival is at the point")
		quit(0)
	else:
		print("FAIL: %d check(s)" % failures)
		quit(1)
