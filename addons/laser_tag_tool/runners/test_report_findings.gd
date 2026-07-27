extends SceneTree
## Headless regression test: a refused map says why (TDD §18, §26).
##
## Guards the bug where a map the harness refused to run came back as
## `runs: 0, grade: "BROKEN", findings: [NO_RUNS]` and nothing else. The
## reason was known -- `validate_map()` had already produced findings such as
## NO_WORLD_COLLISION, and `_add_finding` printed them to the console -- but
## `calculate()` dropped the array on its zero-run early return, so the JSON
## report, which is the only thing an automated consumer reads, carried no
## trace of it.
##
## Downstream that is unreadable: "the map plays badly" and "the map was never
## played" arrive as the same bytes. A pipeline four steps away spent 900
## seconds per candidate to learn nothing actionable.
##
## Usage:
##   godot --headless --path . \
##     -s res://addons/laser_tag_tool/runners/test_report_findings.gd
##
## Exit code 0 = all checks passed, 1 = at least one failed.

const SCORE_CALCULATOR := preload("../scripts/metrics/LT_ScoreCalculator.gd")
const REPORT_WRITER := preload("../scripts/metrics/LT_ReportWriter.gd")

var _failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var calculator = SCORE_CALCULATOR.new()
	var refusal: Array[Dictionary] = [
		{"severity": "FAIL", "type": "NO_WORLD_COLLISION",
			"message": "No world collision beneath the player spawn."},
		{"severity": "WARN", "type": "NAVIGATION_MISSING",
			"message": "No navigation mesh in the scene."},
	]

	# --- The refusal survives scoring ---
	var score: Dictionary = calculator.calculate({}, null, refusal)
	var types := _types(score.get("findings", []))
	_check(score.get("grade", "") == "BROKEN", "zero runs still grade BROKEN")
	_check(types.has("NO_WORLD_COLLISION"),
		"the validation failure reaches the score findings")
	_check(types.has("NAVIGATION_MISSING"),
		"validation warnings are kept too, not just failures")
	_check(types.has("NO_RUNS"), "NO_RUNS is still reported alongside them")

	# --- ...and names the blocker in its own message ---
	var no_runs := _find(score.get("findings", []), "NO_RUNS")
	_check(String(no_runs.get("message", "")).contains("NO_WORLD_COLLISION"),
		"the NO_RUNS message names what refused the map")

	# --- ...and reaches the JSON, which is what anything automated reads ---
	var path := "user://lt_test_report_findings.json"
	var writer = REPORT_WRITER.new()
	_check(writer.write_json(path, "test_map", "test", {}, score, [], []),
		"report written")
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	var written := _types(parsed.get("findings", []) if parsed is Dictionary else [])
	_check(written.has("NO_WORLD_COLLISION"),
		"the JSON report carries the refusal, not just the console")
	_check(int(parsed.get("runs", -1)) == 0 if parsed is Dictionary else false,
		"the report still states zero runs")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	# --- A refusal with no stated cause must not read as a clean report ---
	var silent: Array[Dictionary] = []
	var bare: Dictionary = calculator.calculate({}, null, silent)
	var bare_findings: Array = bare.get("findings", [])
	var unexplained := String(_find(bare_findings, "NO_RUNS").get("message", ""))
	_check(_types(bare_findings).has("NO_RUNS"),
		"an unexplained refusal still produces a finding")
	_check(unexplained.contains("no failure"),
		"an unexplained refusal says the explanation is missing")

	# --- A real run is unaffected ---
	var summary := {
		"runs": 4, "route_completion_rate": 1.0, "shots_fired": 40,
		"avg_time_to_first_contact": 8.0, "avg_player_survival_seconds": 60.0,
		"shots_blocked_by_collision_percent": 0.3, "avg_enemy_deaths_per_run": 3.0,
	}
	var real: Dictionary = calculator.calculate(summary, null, [])
	_check(not _types(real.get("findings", [])).has("NO_RUNS"),
		"a map that actually ran reports no NO_RUNS finding")
	_check(int(real.get("overall_score", 0)) > 0, "a map that actually ran scores")

	calculator.free()
	writer.free()

	print("")
	if _failures == 0:
		print("[LT test] PASS — refused maps report their reason")
		quit(0)
	else:
		print("[LT test] FAIL — %d check(s) failed" % _failures)
		quit(1)

func _types(findings: Array) -> Array[String]:
	var out: Array[String] = []
	for finding in findings:
		out.append(String(finding.get("type", "")))
	return out

func _find(findings: Array, type_name: String) -> Dictionary:
	for finding in findings:
		if String(finding.get("type", "")) == type_name:
			return finding
	return {}

func _check(condition: bool, label: String) -> void:
	if condition:
		print("[LT test] ok   — %s" % label)
	else:
		_failures += 1
		print("[LT test] FAIL — %s" % label)
