extends Node
class_name LT_MetricsCollector
## Central metrics sink (TDD §17, §25).
## Everything that matters calls into this via the "lt_metrics" group:
##   record_shot(shot: LT_ShotResult)
##   record_event(event_name: String, metadata: Dictionary)
## One instance per harness. Aggregates per-run, keeps all completed runs.

var run_state: LT_RunState
var record_debug_events: bool = true

var completed_runs: Array[Dictionary] = []
var current: Dictionary = {}
var events: Array[Dictionary] = []

func _ready() -> void:
	add_to_group(LT_Const.GROUP_METRICS)

func begin_run(run_id: int, player_count: int, enemy_count: int) -> void:
	current = {
		"run_id": run_id,
		"player_count": player_count,
		"enemy_count": enemy_count,
		"shots_fired": 0,
		"shots_hit": 0,
		"shots_missed": 0,
		"shots_blocked": 0,
		"player_shots_fired": 0,
		"player_shots_blocked": 0,
		"enemy_shots_fired": 0,
		"enemy_shots_blocked": 0,
		"player_deaths": 0,
		"enemy_deaths": 0,
		"player_stuck_events": 0,
		"enemy_stuck_events": 0,
		"time_to_first_contact": -1.0,
		"time_to_first_player_shot": -1.0,
		"time_to_first_enemy_shot": -1.0,
		"engagement_distance_total": 0.0,
		"engagement_distance_samples": 0,
		"player_survival_time": -1.0,
		"route_completed": false,
		"team_wipe": false,
		"end_reason": "NONE",
		"duration_seconds": 0.0,
	}

func end_run(end_reason: String) -> void:
	if current.is_empty():
		return
	current["end_reason"] = end_reason
	current["duration_seconds"] = _now()
	if current["player_survival_time"] < 0.0:
		# Player survived the whole run.
		current["player_survival_time"] = _now()
	completed_runs.append(current.duplicate(true))
	current = {}

func record_shot(shot: LT_ShotResult) -> void:
	if current.is_empty():
		return

	current["shots_fired"] += 1

	if shot.shooter_is_player:
		current["player_shots_fired"] += 1
		if current["time_to_first_player_shot"] < 0.0:
			current["time_to_first_player_shot"] = _now()
	else:
		current["enemy_shots_fired"] += 1
		if current["time_to_first_enemy_shot"] < 0.0:
			current["time_to_first_enemy_shot"] = _now()

	if current["time_to_first_contact"] < 0.0:
		current["time_to_first_contact"] = _now()

	match shot.hit_type:
		"MISS", "INVALID":
			current["shots_missed"] += 1
		"WORLD_BLOCKED":
			current["shots_blocked"] += 1
			if shot.shooter_is_player:
				current["player_shots_blocked"] += 1
			else:
				current["enemy_shots_blocked"] += 1
			_log_event("ShotBlocked", shot.shooter, shot.hit_position, {
				"hit_type": shot.hit_type,
				"collider": _collider_name(shot),
			})
		"ENEMY_HIT":
			current["shots_hit"] += 1
			current["engagement_distance_total"] += shot.distance()
			current["engagement_distance_samples"] += 1
			_log_event("ShotHitEnemy", shot.shooter, shot.hit_position, {})
		"PLAYER_HIT":
			current["shots_hit"] += 1
			current["engagement_distance_total"] += shot.distance()
			current["engagement_distance_samples"] += 1
			_log_event("ShotHitPlayer", shot.shooter, shot.hit_position, {})
		_:
			current["shots_hit"] += 1

func record_event(event_name: String, metadata: Dictionary = {}) -> void:
	if current.is_empty():
		return
	match event_name:
		"PlayerKilled":
			current["player_deaths"] += 1
			if current["player_survival_time"] < 0.0:
				current["player_survival_time"] = _now()
		"EnemyKilled":
			current["enemy_deaths"] += 1
		"PlayerStuck":
			current["player_stuck_events"] += 1
		"EnemyStuck":
			current["enemy_stuck_events"] += 1
		"ObjectiveReached":
			current["route_completed"] = true
		"TeamWipe":
			current["team_wipe"] = true
	_log_event(event_name, null, Vector3.ZERO, metadata)

func _log_event(event_name: String, source: Node, position: Vector3, metadata: Dictionary) -> void:
	if not record_debug_events:
		return
	events.append({
		"run_id": current.get("run_id", -1),
		"time": snappedf(_now(), 0.01),
		"event": event_name,
		"source": source.name if source != null else metadata.get("source", null),
		"position": [snappedf(position.x, 0.01), snappedf(position.y, 0.01), snappedf(position.z, 0.01)],
		"metadata": metadata,
	})

func _collider_name(shot: LT_ShotResult) -> String:
	var node := shot.collider as Node
	return node.name if node != null else "unknown"

func _now() -> float:
	return run_state.elapsed_seconds if run_state != null else 0.0

## ---- Aggregation across runs (used by score calculator / reports) ----

func summary() -> Dictionary:
	var runs := completed_runs
	if runs.is_empty():
		return {}

	var total_shots := 0
	var total_blocked := 0
	var distance_total := 0.0
	var distance_samples := 0

	var summary_data := {
		"runs": runs.size(),
		"avg_player_survival_seconds": _avg(runs, "player_survival_time"),
		"avg_time_to_first_contact": _avg(runs, "time_to_first_contact"),
		"route_completion_rate": _rate(runs, "route_completed"),
		"team_wipe_count": _count_true(runs, "team_wipe"),
		"player_deaths": _sum(runs, "player_deaths"),
		"enemy_deaths": _sum(runs, "enemy_deaths"),
		"player_stuck_events": _sum(runs, "player_stuck_events"),
		"enemy_stuck_events": _sum(runs, "enemy_stuck_events"),
		"shots_fired": _sum(runs, "shots_fired"),
		"shots_hit": _sum(runs, "shots_hit"),
		"shots_missed": _sum(runs, "shots_missed"),
		"shots_blocked": _sum(runs, "shots_blocked"),
		"timeout_count": 0,
	}

	for run in runs:
		total_shots += run["shots_fired"]
		total_blocked += run["shots_blocked"]
		distance_total += run["engagement_distance_total"]
		distance_samples += run["engagement_distance_samples"]
		if run["end_reason"] == "TIMEOUT":
			summary_data["timeout_count"] += 1

	summary_data["shots_blocked_by_collision_percent"] = \
		(float(total_blocked) / float(total_shots)) if total_shots > 0 else 0.0
	summary_data["avg_engagement_distance"] = \
		(distance_total / float(distance_samples)) if distance_samples > 0 else 0.0
	summary_data["avg_enemy_deaths_per_run"] = \
		float(summary_data["enemy_deaths"]) / float(runs.size())

	# Variance — averages hide flaky maps.
	summary_data.merge(_spread(runs, "player_survival_time", "survival"))
	summary_data.merge(_spread(runs, "time_to_first_contact", "first_contact"))

	return summary_data

## min/max/stddev over runs where the value was recorded (>= 0).
func _spread(runs: Array[Dictionary], key: String, prefix: String) -> Dictionary:
	var values: Array[float] = []
	for run in runs:
		var value: float = run.get(key, -1.0)
		if value >= 0.0:
			values.append(value)
	if values.is_empty():
		return {}
	var minimum := values[0]
	var maximum := values[0]
	var total := 0.0
	for value in values:
		minimum = minf(minimum, value)
		maximum = maxf(maximum, value)
		total += value
	var mean := total / float(values.size())
	var variance := 0.0
	for value in values:
		variance += (value - mean) * (value - mean)
	variance /= float(values.size())
	return {
		prefix + "_min": minimum,
		prefix + "_max": maximum,
		prefix + "_stddev": sqrt(variance),
	}

func _avg(runs: Array[Dictionary], key: String) -> float:
	var total := 0.0
	var count := 0
	for run in runs:
		var value: float = run.get(key, -1.0)
		if value >= 0.0:
			total += value
			count += 1
	return (total / float(count)) if count > 0 else -1.0

func _sum(runs: Array[Dictionary], key: String) -> int:
	var total := 0
	for run in runs:
		total += int(run.get(key, 0))
	return total

func _rate(runs: Array[Dictionary], key: String) -> float:
	return float(_count_true(runs, key)) / float(runs.size())

func _count_true(runs: Array[Dictionary], key: String) -> int:
	var count := 0
	for run in runs:
		if run.get(key, false):
			count += 1
	return count
