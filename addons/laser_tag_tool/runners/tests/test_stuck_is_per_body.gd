extends SceneTree
## A stuck count without its units cannot be compared to another one (132).
##
## `enemy_stuck_events` is a sum over a sweep, so it depends on how many runs
## the sweep did and how many bodies were in them. Six enemies over 25 runs and
## two over five produce numbers that cannot be put beside each other -- and
## putting them beside each other is the only way to tell a STICKY CORNER from
## a map one side cannot cross.
##
## Measured across three cold runs, per enemy per run:
##
##     county_hospital 9005 / 9106 / 9207   0.71 / 1.00 / 0.91
##     warehouse_yard  9004 / 9105 / 9206   0.03 / 0.00 / 0.00
##     restaurant_row  9003 / 9104 / 9205   0.00 / 0.00 / 0.00
##
## Twenty-six times between the worst healthy map and the best sick one, with
## nothing in between -- which is why 0.5 is a measured line rather than a
## chosen one, and why any line inside that gap picks the same maps.
##
## county_hospital_001 is the map roadmap 132 is about: the route's middle leg
## is a rooftop helipad and every guard is on the ground. Two of its three
## candidates scored 80 PASS_WITH_TUNING while stranding their guards.

var failures: int = 0


func check(condition: bool, label: String) -> void:
	if condition:
		print("  ok: " + label)
	else:
		failures += 1
		print("  FAIL: " + label)


func run_row(enemies: int, players: int, enemy_stuck: int,
		player_stuck: int) -> Dictionary:
	return {"enemy_count": enemies, "player_count": players,
		"enemy_stuck_events": enemy_stuck, "player_stuck_events": player_stuck,
		"route_points_total": 0, "shots_fired": 0}


func _init() -> void:
	var metrics := LT_MetricsCollector.new()

	print("[1] the rate is per body per run, not per run")
	# Six enemies, two runs, twelve stuck events: every guard jammed once in
	# every run. Per RUN that reads 6.0 and means nothing without the roster.
	var runs: Array[Dictionary] = [run_row(6, 4, 6, 0), run_row(6, 4, 6, 0)]
	var per := metrics._per_body(runs, "enemy_stuck_events", "enemy_count")
	print("     6 enemies x 2 runs, 12 events -> %.3f per enemy-run" % per)
	check(absf(per - 1.0) < 0.0005, "twelve events over twelve enemy-runs is 1.0")

	print("[2] the same map at a different sweep size reads the same")
	# THE POINT OF NORMALISING. Double the runs and the raw count doubles
	# while the map has not changed.
	var longer: Array[Dictionary] = []
	for i in 8:
		longer.append(run_row(6, 4, 6, 0))
	check(absf(metrics._per_body(longer, "enemy_stuck_events", "enemy_count")
		- per) < 0.0005, "four times the runs, same rate")

	print("[3] the healthy maps and the sick one land either side of 0.5")
	# warehouse_yard 9004: 4 events, 25 runs, 6 enemies.
	var healthy: Array[Dictionary] = []
	for i in 25:
		healthy.append(run_row(6, 4, 0, 0))
	healthy[0]["enemy_stuck_events"] = 4
	var healthy_rate := metrics._per_body(healthy, "enemy_stuck_events",
		"enemy_count")
	# county_hospital 9106: 150 events, 25 runs, 6 enemies.
	var sick: Array[Dictionary] = []
	for i in 25:
		sick.append(run_row(6, 4, 6, 0))
	var sick_rate := metrics._per_body(sick, "enemy_stuck_events", "enemy_count")
	print("     healthy %.3f   sick %.3f   line 0.5" % [healthy_rate, sick_rate])
	check(healthy_rate < 0.5, "warehouse_yard 9004's 4 events stay a WARN")
	check(sick_rate >= 0.5, "county_hospital 9106's 150 events do not")
	check(sick_rate / maxf(healthy_rate, 0.0001) > 20.0,
		"and the gap between them is more than twenty times")

	print("[4] a run with no bodies of that kind is skipped, not zeroed")
	# An enemyless run is not a run whose enemies never jammed. Counting it as
	# zero would dilute the rate with runs that could not contribute to it --
	# the same defect `_progress` avoids for routeless runs.
	var mixed: Array[Dictionary] = [run_row(6, 4, 6, 0), run_row(0, 4, 0, 0)]
	check(absf(metrics._per_body(mixed, "enemy_stuck_events", "enemy_count")
		- 1.0) < 0.0005, "the enemyless run does not halve the rate")
	check(metrics._per_body([run_row(0, 4, 0, 0)], "enemy_stuck_events",
		"enemy_count") == 0.0, "and an all-enemyless sweep is 0.0, not a crash")

	print("[5] the crew is measured the same way")
	check(absf(metrics._per_body([run_row(6, 4, 0, 8)], "player_stuck_events",
		"player_count") - 2.0) < 0.0005, "eight events over four crew is 2.0")

	print("[6] the summary publishes both")
	# Guarded against the field being added to one side only: the asymmetry
	# between the two is what says a map is crossable for one side and not the
	# other, and it needs both halves to say it.
	var src: String = FileAccess.get_file_as_string(
		"res://addons/laser_tag_tool/scripts/metrics/LT_MetricsCollector.gd")
	check(src.contains("\"enemy_stuck_per_enemy_run\""), "enemy rate in summary")
	check(src.contains("\"player_stuck_per_player_run\""), "crew rate in summary")

	print("[7] the finding escalates instead of staying WARN")
	var score_src: String = FileAccess.get_file_as_string(
		"res://addons/laser_tag_tool/scripts/metrics/LT_ScoreCalculator.gd")
	check(score_src.contains("ENEMY_PATHING_BROKEN"),
		"a map the enemy side cannot cross gets its own finding type")
	check(score_src.contains("enemy_stuck_per_enemy_run"),
		"and it reads the normalised rate rather than the raw count")

	print("")
	if failures == 0:
		print("test_stuck_is_per_body: PASS")
	else:
		print("test_stuck_is_per_body: %d FAILURE(S)" % failures)
	quit(1 if failures > 0 else 0)
