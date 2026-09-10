extends SceneTree
## The score says what the findings say (roadmap 128, and 132's residue).
##
## Two numbers were measured, published, and then not read by the thing that
## decides whether a level passes.
##
## TRAVERSAL was a three-band step on `route_completion_rate`, a boolean
## averaged. A crew that walked 65% of its route scored what a crew wiped on
## the spawn scored: nothing. 0.19.0 put the fraction into the finding's TEXT
## and deliberately left the number alone; this reads the fraction.
##
## NPC PATHING capped its stuck penalty at 10 of the category's 20, so a map
## whose every guard jams in every run cost the same ten points as one with a
## sticky corner. `county_hospital_001` scored 80 PASS_WITH_TUNING while
## stranding its guards at 0.71 per enemy per run (roadmap 132).

var failures: int = 0


func check(condition: bool, label: String) -> void:
	if condition:
		print("  ok: " + label)
	else:
		failures += 1
		print("  FAIL: " + label)


func summary_of(d: Dictionary) -> Dictionary:
	var base := {
		"runs": 25, "route_completion_rate": 0.0, "route_progress_rate": -1.0,
		"player_stuck_events": 0, "enemy_stuck_events": 0,
		"enemy_stuck_per_enemy_run": 0.0,
	}
	base.merge(d, true)
	return base


func traversal(calc: LT_ScoreCalculator, d: Dictionary) -> int:
	var found: Array[Dictionary] = []
	return calc._score_traversal(summary_of(d), found)


func pathing(calc: LT_ScoreCalculator, d: Dictionary) -> int:
	var found: Array[Dictionary] = []
	return calc._score_pathing(summary_of(d), 0, found)


func severity_of(calc: LT_ScoreCalculator, d: Dictionary, type_name: String) -> String:
	var found: Array[Dictionary] = []
	calc._score_traversal(summary_of(d), found)
	calc._score_pathing(summary_of(d), 0, found)
	for f in found:
		if f.get("type", "") == type_name:
			return str(f.get("severity", ""))
	return ""


func _init() -> void:
	var calc := LT_ScoreCalculator.new()

	print("[1] traversal reads how far the crew got")
	# THE CASE THE ITEM IS ABOUT. Both of these completed nothing; one walked
	# two thirds of the route and the other was wiped on the spawn, and they
	# used to score the same.
	var walked := traversal(calc, {"route_completion_rate": 0.0,
		"route_progress_rate": 0.65})
	var wiped := traversal(calc, {"route_completion_rate": 0.0,
		"route_progress_rate": 0.0})
	print("     progress 0.65 -> %d of 25,  progress 0.00 -> %d" % [walked, wiped])
	check(walked > wiped, "walking two thirds beats walking none")
	check(walked == 16, "and it is 25 * 0.65 rounded, not a band")
	check(wiped == 0, "a crew that never moved still scores zero")

	print("[2] a completed route is unchanged")
	# `route_progress_rate` is 1.00 exactly when every run finished, so it
	# subsumes the old top band rather than sitting beside it. A map that
	# scored 25 before still scores 25.
	check(traversal(calc, {"route_completion_rate": 1.0,
		"route_progress_rate": 1.0}) == 25, "1.00 completion is still 25")

	print("[3] a report from before the field existed keeps the old reading")
	# -1.0 is the sentinel for a run recorded before 0.19.0 published it.
	# Falling through to zero would mark every archived report as untraversable.
	check(traversal(calc, {"route_completion_rate": 1.0,
		"route_progress_rate": -1.0}) == 25, "the sentinel falls back to completion")
	check(traversal(calc, {"route_completion_rate": 0.6,
		"route_progress_rate": -1.0}) == 15, "and mid completion still scores")

	print("[4] the finding says which number it read")
	# Progress and completion diverging is the interesting case and the reader
	# has to be told, or the sentence contradicts the number beside it.
	var found: Array[Dictionary] = []
	calc._score_traversal(summary_of({"route_completion_rate": 0.0,
		"route_progress_rate": 0.65}), found)
	var msg := ""
	for f in found:
		if f.get("type", "") == "TRAVERSAL":
			msg = str(f.get("message", ""))
	print("     " + msg)
	check(msg.contains("65%"), "it names the fraction walked")
	check(msg.contains("FINISHED in 0%"), "and the fraction finished, separately")

	print("[5] pathing can read zero when the NPCs cannot path")
	# county_hospital_001 seed 9005: 0.71 per enemy per run, 106 events over
	# 25 runs. The cap made that cost 10 of 20; the map scored 80.
	var stranded := pathing(calc, {"enemy_stuck_events": 106,
		"enemy_stuck_per_enemy_run": 0.71})
	var sticky := pathing(calc, {"enemy_stuck_events": 8,
		"enemy_stuck_per_enemy_run": 0.05})
	print("     0.71 per enemy-run -> %d of 20,  0.05 -> %d" % [stranded, sticky])
	check(stranded < 10, "a map the guards cannot cross loses more than the old cap")
	check(sticky > stranded, "and a sticky corner still costs less")
	check(pathing(calc, {"enemy_stuck_events": 150,
		"enemy_stuck_per_enemy_run": 1.0}) == 0,
		"every guard jamming every run takes the whole category")

	print("[6] the severities still separate the two")
	check(severity_of(calc, {"enemy_stuck_events": 106,
		"enemy_stuck_per_enemy_run": 0.71}, "ENEMY_PATHING_BROKEN") == "FAIL",
		"stranded guards are a FAIL")
	check(severity_of(calc, {"enemy_stuck_events": 8,
		"enemy_stuck_per_enemy_run": 0.05}, "ENEMY_STUCK") == "WARN",
		"a sticky corner is a WARN")

	print("[7] the crew being stuck still costs, and cannot go negative")
	check(traversal(calc, {"route_completion_rate": 0.0,
		"route_progress_rate": 0.1, "player_stuck_events": 3}) == 0,
		"a barely-moving crew that also jams floors at zero, not below")

	print("")
	if failures == 0:
		print("test_score_reads_the_measurements: PASS")
	else:
		print("test_score_reads_the_measurements: %d FAILURE(S)" % failures)
	quit(1 if failures > 0 else 0)
