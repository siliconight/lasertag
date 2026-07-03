extends Node
class_name LT_ReportWriter
## Writes JSON, CSV, and a printed human summary (TDD §19).

func write_json(path: String, map_name: String, scenario_name: String,
		summary: Dictionary, score: Dictionary, runs: Array[Dictionary],
		events: Array[Dictionary], include_events: bool = false,
		extras: Dictionary = {}) -> bool:
	var report := {
		"map": map_name,
		"scenario": scenario_name,
		"runs": summary.get("runs", 0),
		"overall_score": score.get("overall_score", 0),
		"grade": score.get("grade", "BROKEN"),
		"categories": score.get("categories", {}),
		"summary": _rounded(summary),
		"coop": {
			"enabled": false,
			"connected_players": runs[0].get("player_count", 1) if not runs.is_empty() else 1,
			"avg_player_spacing_meters": 0.0,
			"body_block_events": 0,
			"doorway_congestion_events": 0,
			"team_wipe_count": summary.get("team_wipe_count", 0),
		},
		"findings": score.get("findings", []),
	}
	if include_events:
		report["events"] = events
	report.merge(extras)

	_ensure_directory(path)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("LT_ReportWriter: cannot open %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	return true

const CSV_COLUMNS := [
	"run_id", "map_name", "scenario_name", "player_count", "enemy_count",
	"time_to_first_contact", "player_survival_time", "route_completed",
	"shots_fired", "shots_hit", "shots_blocked", "player_deaths",
	"enemy_deaths", "player_stuck_events", "enemy_stuck_events",
	"end_reason", "duration_seconds", "score", "grade",
]

func write_csv(path: String, map_name: String, scenario_name: String,
		runs: Array[Dictionary], score: Dictionary) -> bool:
	_ensure_directory(path)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("LT_ReportWriter: cannot open %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return false

	file.store_csv_line(PackedStringArray(CSV_COLUMNS))
	for run in runs:
		file.store_csv_line(PackedStringArray([
			str(run.get("run_id", -1)),
			map_name,
			scenario_name,
			str(run.get("player_count", 1)),
			str(run.get("enemy_count", 0)),
			"%.2f" % float(run.get("time_to_first_contact", -1.0)),
			"%.2f" % float(run.get("player_survival_time", -1.0)),
			str(run.get("route_completed", false)),
			str(run.get("shots_fired", 0)),
			str(run.get("shots_hit", 0)),
			str(run.get("shots_blocked", 0)),
			str(run.get("player_deaths", 0)),
			str(run.get("enemy_deaths", 0)),
			str(run.get("player_stuck_events", 0)),
			str(run.get("enemy_stuck_events", 0)),
			str(run.get("end_reason", "NONE")),
			"%.2f" % float(run.get("duration_seconds", 0.0)),
			str(score.get("overall_score", 0)),
			str(score.get("grade", "BROKEN")),
		]))
	file.close()
	return true

func human_summary(map_name: String, score: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append("Map: %s" % map_name)
	lines.append("Grade: %s" % score.get("grade", "BROKEN"))
	lines.append("Score: %d / 100" % score.get("overall_score", 0))
	lines.append("")

	var good: Array[String] = []
	var bad: Array[String] = []
	for finding in score.get("findings", []):
		var line := "- %s" % finding.get("message", "")
		if finding.get("severity", "") == "PASS":
			good.append(line)
		else:
			bad.append("%s [%s]" % [line, finding.get("severity", "")])

	lines.append("Good:")
	lines.append_array(good if not good.is_empty() else ["- (nothing passed)"])
	lines.append("")
	lines.append("Needs Work:")
	lines.append_array(bad if not bad.is_empty() else ["- (no issues found)"])
	return "\n".join(lines)

func _ensure_directory(path: String) -> void:
	var directory := path.get_base_dir()
	if directory != "" and not DirAccess.dir_exists_absolute(directory):
		DirAccess.make_dir_recursive_absolute(directory)

func _rounded(summary: Dictionary) -> Dictionary:
	var out := {}
	for key in summary:
		var value = summary[key]
		out[key] = snappedf(value, 0.01) if value is float else value
	return out
