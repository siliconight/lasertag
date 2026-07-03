extends Node
class_name LT_ScoreCalculator
## Turns aggregated metrics + validation findings into a 0-100 score,
## a grade, and a findings list (TDD §18, §26).
##
## Categories: Traversal 25, NPC Pathing 20, Sightlines 20, Cover 20,
## Combat Pacing 15.

const GRADE_BANDS := [
	[90, "PASS"],
	[75, "PASS_WITH_TUNING"],
	[50, "WARN"],
	[25, "FAIL"],
	[0, "BROKEN"],
]

func calculate(summary: Dictionary, scenario: LT_TestScenario,
		validation_findings: Array[Dictionary],
		sightline_data: Dictionary = {}) -> Dictionary:
	var findings: Array[Dictionary] = []
	findings.append_array(validation_findings)

	if summary.is_empty():
		return {
			"overall_score": 0,
			"grade": "BROKEN",
			"categories": {},
			"findings": [_finding("FAIL", "NO_RUNS", "No runs completed — map could not be evaluated.")],
		}

	var unreachable_spawns := _count_findings(validation_findings, "UNREACHABLE_SPAWN")

	var traversal := _score_traversal(summary, findings)
	var pathing := _score_pathing(summary, unreachable_spawns, findings)
	var sightlines := _score_sightlines(summary, sightline_data, findings)
	var cover := _score_cover(summary, findings)
	var pacing := _score_pacing(summary, scenario, findings)

	var total := clampi(traversal + pathing + sightlines + cover + pacing, 0, 100)

	return {
		"overall_score": total,
		"grade": grade_for(total),
		"categories": {
			"traversal": traversal,
			"npc_pathing": pathing,
			"sightlines": sightlines,
			"cover": cover,
			"combat_pacing": pacing,
		},
		"findings": findings,
	}

static func grade_for(score: int) -> String:
	for band in GRADE_BANDS:
		if score >= band[0]:
			return band[1]
	return "BROKEN"

## Traversal: 25 points (TDD §18.2)
func _score_traversal(summary: Dictionary, findings: Array[Dictionary]) -> int:
	var score := 0
	var completion_rate: float = summary.get("route_completion_rate", 0.0)

	if completion_rate >= 0.9:
		score = 25
		findings.append(_finding("PASS", "TRAVERSAL",
			"Bot completed the route in %d%% of runs." % int(completion_rate * 100)))
	elif completion_rate >= 0.5:
		score = 15
		findings.append(_finding("WARN", "TRAVERSAL",
			"Bot completed the route in only %d%% of runs." % int(completion_rate * 100)))
	else:
		score = 0
		findings.append(_finding("FAIL", "TRAVERSAL",
			"Bot rarely completed the route (%d%% of runs)." % int(completion_rate * 100)))

	var player_stuck: int = summary.get("player_stuck_events", 0)
	if player_stuck > 0:
		score -= 10
		findings.append(_finding("WARN", "PLAYER_STUCK",
			"Player got stuck %d time(s)." % player_stuck))

	return clampi(score, 0, 25)

## NPC Pathing: 20 points
func _score_pathing(summary: Dictionary, unreachable_spawns: int,
		findings: Array[Dictionary]) -> int:
	var score := 20
	var enemy_stuck: int = summary.get("enemy_stuck_events", 0)
	var runs: int = summary.get("runs", 1)

	score -= unreachable_spawns * 5
	if unreachable_spawns > 0:
		findings.append(_finding("FAIL", "UNREACHABLE_SPAWN_SCORING",
			"%d enemy spawn point(s) could not reach the play space." % unreachable_spawns))

	var stuck_per_run := float(enemy_stuck) / float(runs)
	if stuck_per_run > 0.25:
		var penalty := mini(int(stuck_per_run * 8.0), 10)
		score -= penalty
		findings.append(_finding("WARN", "ENEMY_STUCK",
			"Enemies got stuck %d time(s) across %d run(s)." % [enemy_stuck, runs]))
	elif enemy_stuck == 0:
		findings.append(_finding("PASS", "ENEMY_PATHING",
			"No enemy stuck events recorded."))

	return clampi(score, 0, 20)

## Sightlines: 20 points
func _score_sightlines(summary: Dictionary, sightline_data: Dictionary,
		findings: Array[Dictionary]) -> int:
	var shots_fired: int = summary.get("shots_fired", 0)
	var enemy_kills_per_run: float = summary.get("avg_enemy_deaths_per_run", 0.0)

	if shots_fired == 0:
		findings.append(_finding("FAIL", "NO_ENGAGEMENT",
			"No shots were ever fired — enemies and players never got line of sight."))
		return 0

	var score := 20

	# Real sampled exposure data, when available (LT_MapSampler).
	if not sightline_data.is_empty():
		var overexposed_fraction: float = sightline_data.get("overexposed_fraction", 0.0)
		var blind_fraction: float = sightline_data.get("blind_fraction", 0.0)
		var threshold: int = sightline_data.get("overexposed_threshold", 3)

		if overexposed_fraction > 0.15:
			score -= 10
			var worst: Array = sightline_data.get("worst_overexposed", [])
			var where := ""
			var finding := _finding("WARN", "OVEREXPOSED_ZONE",
				"%d%% of walkable positions are visible to %d+ enemy spawns." % [
					int(overexposed_fraction * 100), threshold])
			if not worst.is_empty():
				finding["position"] = worst[0]["position"]
				finding["message"] += " Worst at (%s), visible to %d." % [
					", ".join(worst[0]["position"].map(func(v): return str(v))),
					worst[0]["visible_to"]]
			findings.append(finding)
		elif overexposed_fraction > 0.0:
			findings.append(_finding("PASS", "EXPOSURE",
				"Only %d%% of positions are overexposed." % int(overexposed_fraction * 100)))

		if blind_fraction > 0.5:
			score -= 10
			findings.append(_finding("WARN", "BLIND_MAP",
				("%d%% of positions can never be seen from any enemy spawn" +
				" — enemies may rarely get line of sight.") % int(blind_fraction * 100)))
	else:
		# Fallback heuristics from engagement data only.
		if enemy_kills_per_run < 0.5:
			score -= 10
			findings.append(_finding("WARN", "LOW_ENGAGEMENT",
				"Very few enemies were killed per run — sightlines may not support engagement."))

	var survival: float = summary.get("avg_player_survival_seconds", -1.0)
	var contact: float = summary.get("avg_time_to_first_contact", -1.0)
	if survival >= 0.0 and contact >= 0.0 and survival - contact < 5.0 and summary.get("player_deaths", 0) > 0:
		score -= 10
		findings.append(_finding("WARN", "OVEREXPOSED",
			"Players died within seconds of first contact — likely overexposed positions."))

	return clampi(score, 0, 20)

## Cover: 20 points
func _score_cover(summary: Dictionary, findings: Array[Dictionary]) -> int:
	var blocked_percent: float = summary.get("shots_blocked_by_collision_percent", 0.0)
	var shots_fired: int = summary.get("shots_fired", 0)

	if shots_fired == 0:
		return 0

	var score := 0
	if blocked_percent >= 0.15:
		score = 20
		findings.append(_finding("PASS", "COVER_BLOCKING",
			"World collision blocked %d%% of shots." % int(blocked_percent * 100)))
	elif blocked_percent >= 0.05:
		score = 12
		findings.append(_finding("WARN", "LOW_COVER",
			"Only %d%% of shots were blocked by collision — cover may be sparse." % int(blocked_percent * 100)))
	else:
		score = 5
		findings.append(_finding("WARN", "NO_COVER_INTERACTION",
			"Almost no shots were blocked by collision (%d%%) — open-field combat." % int(blocked_percent * 100)))

	return clampi(score, 0, 20)

## Combat Pacing: 15 points
func _score_pacing(summary: Dictionary, scenario: LT_TestScenario,
		findings: Array[Dictionary]) -> int:
	var contact: float = summary.get("avg_time_to_first_contact", -1.0)
	var survival: float = summary.get("avg_player_survival_seconds", -1.0)
	var contact_min := scenario.first_contact_min_seconds if scenario != null else 3.0
	var contact_max := scenario.first_contact_max_seconds if scenario != null else 30.0
	var min_survival := scenario.min_reasonable_survival_seconds if scenario != null else 10.0

	if contact < 0.0:
		findings.append(_finding("FAIL", "NO_CONTACT",
			"Combat never started in any run."))
		return 0

	var score := 15
	if contact < contact_min:
		score -= 10
		findings.append(_finding("WARN", "INSTANT_CONTACT",
			"First contact happened almost instantly (%.1fs) — spawns may be too close." % contact))
	elif contact > contact_max:
		score -= 10
		findings.append(_finding("WARN", "SLOW_CONTACT",
			"First contact took %.1fs on average — enemies may be too far or unable to path." % contact))
	else:
		findings.append(_finding("PASS", "CONTACT_TIMING",
			"First contact averaged %.1fs — inside the target window." % contact))

	if survival >= 0.0 and survival < min_survival and summary.get("player_deaths", 0) > 0:
		score -= 10
		findings.append(_finding("FAIL", "NO_REACTION_TIME",
			"Average player survival was %.1fs — players die before they can react." % survival))

	return clampi(score, 0, 15)

func _count_findings(findings: Array[Dictionary], type_name: String) -> int:
	var count := 0
	for finding in findings:
		if finding.get("type", "") == type_name:
			count += 1
	return count

static func _finding(severity: String, type_name: String, message: String) -> Dictionary:
	return {"severity": severity, "type": type_name, "message": message}
