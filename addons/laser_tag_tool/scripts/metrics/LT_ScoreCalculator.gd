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
		# The validation findings are the only record of WHY the harness
		# refused, and they were being dropped here -- the console printed
		# NO_WORLD_COLLISION while the report said nothing but "BROKEN".
		# "The map plays badly" and "the map was never played" are different
		# statements; keep the one that is true.
		findings.append(_finding("FAIL", "NO_RUNS", _no_runs_message(validation_findings)))
		return {
			"overall_score": 0,
			"grade": "BROKEN",
			"categories": {},
			"findings": findings,
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

## "No runs completed" on its own reads as a verdict on the map. The reason the
## harness refused is already in hand when this path is taken -- validation
## produced it -- so name it here, and keep the findings that carry the detail.
static func _no_runs_message(validation_findings: Array[Dictionary]) -> String:
	var blockers: Array[String] = []
	for finding in validation_findings:
		if finding.get("severity", "") != "FAIL":
			continue
		var type_name: String = finding.get("type", "")
		if type_name != "" and not blockers.has(type_name):
			blockers.append(type_name)
	if blockers.is_empty():
		return ("No runs completed — map could not be evaluated, and "
			+ "validation reported no failure to explain it.")
	return "No runs completed — validation refused the map: %s." % ", ".join(blockers)


static func grade_for(score: int) -> String:
	for band in GRADE_BANDS:
		if score >= band[0]:
			return band[1]
	return "BROKEN"

## Traversal: 25 points (TDD §18.2)
## Traversal: 25 points, scored on HOW FAR THE CREW GOT (roadmap 128).
##
## This was a three-band step on `route_completion_rate`, a boolean averaged,
## so a crew that walked 65% of its route scored exactly what a crew wiped on
## the spawn scored: nothing. 0.19.0 put the fraction in the finding's text and
## left the number alone, which made the zero interpretable and still let it
## drive the grade. This reads the fraction.
##
## `route_progress_rate` is the mean fraction of route points reached, over
## runs that HAD a route -- and it is 1.00 exactly when every run finished, so
## it subsumes the old top band rather than sitting beside it. The bands
## survive as the finding's SEVERITY, because a reader wants "is this a
## problem" and not only a number.
##
## The -1.0 fallback is a run recorded before 0.19.0 published the field. Those
## keep the old behaviour rather than silently scoring zero.
func _score_traversal(summary: Dictionary, findings: Array[Dictionary]) -> int:
	var completion_rate: float = summary.get("route_completion_rate", 0.0)
	var progress: float = summary.get("route_progress_rate", -1.0)
	var walked: float = progress if progress >= 0.0 else completion_rate
	var score := int(round(25.0 * clampf(walked, 0.0, 1.0)))

	var detail: String = ""
	if progress >= 0.0 and absf(progress - completion_rate) > 0.005:
		detail = (" It FINISHED in %d%% of runs; the score reads how far it"
			+ " got, not how often it arrived.") % int(completion_rate * 100)
	if walked >= 0.9:
		findings.append(_finding("PASS", "TRAVERSAL",
			("Bot walked %d%% of the route on average." % int(walked * 100))
			+ detail))
	elif walked >= 0.5:
		findings.append(_finding("WARN", "TRAVERSAL",
			("Bot walked only %d%% of the route on average." % int(walked * 100))
			+ detail))
	else:
		findings.append(_finding("FAIL", "TRAVERSAL",
			("Bot walked %d%% of the route on average." % int(walked * 100))
			+ detail))

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
	# PER ENEMY PER RUN, because a raw count says nothing across maps: six
	# enemies over 25 runs and two over five are not comparable, and the
	# question is whether the AVERAGE GUARD is jamming (roadmap 132).
	var per_enemy: float = float(summary.get("enemy_stuck_per_enemy_run", 0.0))
	if stuck_per_run > 0.25:
		# THE PENALTY SCALES WITH THE RATE, AND THE CAP IS GONE (roadmap 128,
		# raised by 132). It was `mini(int(stuck_per_run * 8.0), 10)` -- half
		# this category -- so a map whose every guard jams in every run cost
		# the same ten points as one with a sticky corner, and
		# `county_hospital_001` scored 80 PASS_WITH_TUNING while stranding its
		# guards at 0.71 per enemy per run.
		#
		# Per enemy per run, so it means the same on two maps, and 1.0 -- the
		# average guard jamming once per run -- takes the whole 20. A category
		# called NPC Pathing should be able to read zero when the NPCs cannot
		# path.
		var penalty: int = mini(int(stuck_per_run * 8.0), 10)
		if per_enemy > 0.0:
			penalty = int(round(20.0 * minf(1.0, per_enemy)))
		score -= penalty
		# ONE FINDING, TWO DIFFERENT FACTS, and they were being reported as the
		# same one. A sticky corner and a map the enemy side cannot cross both
		# printed "Enemies got stuck N time(s)" at WARN, and a severity that
		# does not move with the magnitude trains its reader to skip it.
		#
		# The line is 0.5 -- a guard jamming every second run. It is measured,
		# not chosen: across three cold runs the healthy maps sit at 0.00-0.03
		# per enemy-run and the sick one at 0.71-1.00, twenty-six times apart
		# with nothing in between, so any line in that gap picks the same
		# maps. county_hospital_001 stranded its guards at 0.71, 0.91 and 1.00
		# while two of its three candidates scored 80 PASS_WITH_TUNING.
		#
		# NOTE WHAT THIS DOES NOT DO. The penalty is still capped at 10, so a
		# map whose guards cannot move loses 10 of 100 and can still pass. The
		# finding now says so; whether the SCORE should say so is roadmap
		# 128's open question and is not decided here.
		if per_enemy >= 0.5:
			findings.append(_finding("FAIL", "ENEMY_PATHING_BROKEN",
				("Enemies got stuck %d time(s) across %d run(s) -- %.2f per "
				+ "enemy per run, so the average guard jams in every second "
				+ "run or worse. This is not a sticky corner: the map is not "
				+ "traversable for the enemy side, and every combat number "
				+ "below describes a fight the guards could not reach.")
				% [enemy_stuck, runs, per_enemy]))
		else:
			findings.append(_finding("WARN", "ENEMY_STUCK",
				("Enemies got stuck %d time(s) across %d run(s), %.2f per "
				+ "enemy per run.") % [enemy_stuck, runs, per_enemy]))
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

		# INFORMATIONAL NOW, NOT A DEDUCTION. This number says how much of the
		# level six particular markers can see, so it moves when somebody
		# nudges a spawn and says nothing about the level's cover. The points
		# come off `peer_exposed_fraction` below instead, which asks the same
		# question of the geometry. Kept and still reported, because it
		# becomes meaningful again the moment a real gameplay layer supplies
		# considered spawns.
		if overexposed_fraction > 0.15:
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
			findings.append(_finding("WARN", "BLIND_MAP",
				("%d%% of positions can never be seen from any enemy spawn" +
				" — enemies may rarely get line of sight.") % int(blind_fraction * 100)))
	# THE LEVEL'S OWN COVER, which is what this category is supposed to score.
	# Needs no spawns, so it survives the gameplay layer moving out.
	# COVER, ASKED OF THE GEOMETRY. `has_cover_fraction` is the share of
	# positions with at least half their 8 directions blocked inside weapon
	# range -- somewhere to put your back. The earlier draft of this scored
	# `peer_exposed_fraction` against a 0.25 cut, which measured 0.248 as the
	# mean on the first site it ran on: the threshold was the average, so
	# "exposed" meant "above average" and the result was arithmetic rather
	# than a reading. Peer exposure is still reported; it no longer decides.
	if sightline_data.has("has_cover_fraction"):
		var has_cover: float = sightline_data["has_cover_fraction"]
		var fully_open: float = sightline_data["fully_open_fraction"]
		var reach: float = sightline_data.get("sightline_limit_m", 35.0)
		if fully_open > 0.5:
			score -= 15
			var worst_peer: Array = sightline_data.get("worst_peer_exposed", [])
			var peer_finding := _finding("WARN", "NO_COVER",
				("%d%% of walkable positions have no occluder in ANY direction"
				+ " within %d m -- nothing to break a sightline anywhere.") % [
					int(fully_open * 100), int(reach)])
			if not worst_peer.is_empty():
				peer_finding["position"] = worst_peer[0]["position"]
			findings.append(peer_finding)
		elif has_cover < 0.25:
			score -= 5
			findings.append(_finding("WARN", "THIN_COVER",
				("Only %d%% of positions have half their approaches blocked"
				+ " within %d m.") % [int(has_cover * 100), int(reach)]))
		else:
			findings.append(_finding("PASS", "COVER",
				"%d%% of positions have real cover; %d%% are open on all sides." % [
					int(has_cover * 100), int(fully_open * 100)]))

	if sightline_data.is_empty():
		# Fallback heuristics from engagement data only.
		if enemy_kills_per_run < 0.5:
			score -= 10
			findings.append(_finding("WARN", "LOW_ENGAGEMENT",
				"Very few enemies were killed per run — sightlines may not support engagement."))

	var survival: float = summary.get("avg_player_survival_seconds", -1.0)
	# The enemy's opening, not the run's. See _score_pacing for why.
	var contact: float = summary.get("avg_time_to_first_enemy_shot", -1.0)
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
	# "When did the crew come under fire?" is the enemy's first shot, not the
	# run's first shot. `avg_time_to_first_contact` is stamped by whichever
	# side shoots first (LT_MetricsCollector.record_shot sets it outside the
	# shooter_is_player branch), and a map placed so the crew acquires first --
	# 45m player sight against 35m enemy sight, which is the intended design --
	# produces a SMALL value precisely because it is correct. Judging spawn
	# proximity by it marked down the maps that got the opening right.
	var contact: float = summary.get("avg_time_to_first_enemy_shot", -1.0)
	var survival: float = summary.get("avg_player_survival_seconds", -1.0)
	var contact_min := scenario.first_contact_min_seconds if scenario != null else 3.0
	var contact_max := scenario.first_contact_max_seconds if scenario != null else 30.0
	var min_survival := scenario.min_reasonable_survival_seconds if scenario != null else 10.0

	if contact < 0.0:
		# No enemy ever fired. If nothing fired at all, combat never started
		# and that is a real failure. If the crew was shooting, the opening was
		# simply never contested -- an uncontested map is not a badly paced
		# one, and scoring it zero would punish the crew for winning.
		if int(summary.get("shots_fired", 0)) > 0:
			findings.append(_finding("PASS", "NO_INCOMING_FIRE",
				"No enemy fired on the crew in any run — the opening was never contested."))
			return 15
		findings.append(_finding("FAIL", "NO_CONTACT",
			"Combat never started in any run."))
		return 0

	var score := 15
	if contact < contact_min:
		score -= 10
		findings.append(_finding("WARN", "INSTANT_CONTACT",
			"The crew came under fire almost instantly (%.1fs) — spawns may be too close." % contact))
	elif contact > contact_max:
		score -= 10
		findings.append(_finding("WARN", "SLOW_CONTACT",
			"The crew was first fired on after %.1fs — enemies may be too far or unable to path." % contact))
	else:
		findings.append(_finding("PASS", "CONTACT_TIMING",
			"The crew came under fire at %.1fs on average — inside the target window." % contact))

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
