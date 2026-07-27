extends SceneTree
## Headless map evaluation runner (TDD §7.2, §23.1).
##
## Usage (note the `--` separator before tool args — Godot 4 passes
## everything after it through as user args):
##
##   godot --headless --path . -s res://addons/laser_tag_tool/runners/run_map_eval.gd -- \
##     --map res://levels/gas_station_test.tscn \
##     --scenario res://addons/laser_tag_tool/resources/default_laser_tag_scenario.tres \
##     --runs 25 \
##     --output user://reports/gas_station_eval.json
##
## Optional flags:
##   --seed N          deterministic runs (run i seeds with N + i)
##   --baseline PATH   diff score/metrics against a previous report JSON
##   --bake-nav        runtime-bake NavigationRegion3D nodes before eval
##   --time-scale X    sim speed multiplier (default 4.0)
##   --enemies N --players N --max-run-time SECONDS
##
## Args without `--` also work for compatibility with the TDD examples.

const HarnessScript := preload("../scripts/core/LT_MapEvalHarness.gd")
const ScenarioScript := preload("../resources/LT_TestScenario.gd")

func _initialize() -> void:
	var args := _parse_args()

	var map_path: String = args.get("map", "")
	if map_path.is_empty():
		push_error("run_map_eval: --map <res://path/to/level.tscn> is required")
		quit(2)
		return

	var scenario: LT_TestScenario
	var scenario_path: String = args.get("scenario", "")
	if not scenario_path.is_empty():
		scenario = load(scenario_path)
		if scenario == null:
			push_error("run_map_eval: could not load scenario %s" % scenario_path)
			quit(2)
			return
	else:
		scenario = ScenarioScript.new()

	if args.has("runs"):
		scenario.run_count = int(args["runs"])
	if args.has("enemies"):
		scenario.enemy_count = int(args["enemies"])
	if args.has("players"):
		scenario.player_count = int(args["players"])
	if args.has("max-run-time"):
		scenario.max_run_time_seconds = float(args["max-run-time"])
	if args.has("seed"):
		scenario.random_seed = int(args["seed"])
		print("[LT] Seeded: run N uses seed %d + N" % scenario.random_seed)
	if args.has("no-enemies"):
		scenario.enemies_enabled = false
		push_warning("run_map_eval: --no-enemies — combat categories will score 0; traversal-only run")

	var trace := args.has("trace")

	var output_path: String = args.get("output",
		"user://reports/%s_eval.json" % map_path.get_file().get_basename())

	# Headless evaluation shouldn't wait on real-world seconds. Raise the
	# per-frame physics step cap so high time scales don't fall behind.
	Engine.time_scale = float(args.get("time-scale", 4.0))
	Engine.max_physics_steps_per_frame = maxi(8, int(Engine.time_scale) * 2 + 4)

	print("[LT] Loading map: %s" % map_path)
	var map_scene: PackedScene = load(map_path)
	if map_scene == null:
		push_error("run_map_eval: could not load map %s" % map_path)
		quit(2)
		return

	var map_root := map_scene.instantiate()
	root.add_child(map_root)

	var harness: LT_MapEvalHarness = _find_harness(map_root)
	if harness == null:
		harness = HarnessScript.new()
		harness.name = "LT_MapEvalHarness"
		harness.auto_start_manual = false
		map_root.add_child(harness)
	else:
		harness.auto_start_manual = false
	harness.trace_enabled = trace
	if trace:
		print("[LT] Trace enabled — snapshots during run 1")

	_run.call_deferred(harness, scenario, output_path, map_path, scenario_path, args)

func _run(harness: LT_MapEvalHarness, scenario: LT_TestScenario,
		output_path: String, map_path: String, scenario_path: String,
		args: Dictionary) -> void:
	if args.has("bake-nav"):
		await _bake_navigation(harness.get_parent())

	print("[LT] Starting evaluation: %d run(s), %d enemy, %d player(s)" % [
		scenario.run_count, scenario.enemy_count, scenario.player_count])

	var score: Dictionary = await harness.run_evaluation(scenario)

	var extras := {}
	if scenario.random_seed != 0:
		extras["seed"] = scenario.random_seed
	var baseline_path: String = args.get("baseline", "")
	if not baseline_path.is_empty():
		var delta := _baseline_delta(baseline_path, score, harness.metrics.summary())
		if not delta.is_empty():
			extras["baseline"] = delta
			_print_baseline_delta(delta)

	harness.write_reports(output_path, map_path.get_file(),
		scenario_path.get_file() if not scenario_path.is_empty() else "default",
		extras)

	var grade: String = score.get("grade", "BROKEN")
	print("[LT] DONE — score %d, grade %s" % [score.get("overall_score", 0), grade])
	Engine.time_scale = 1.0
	# Exit code: 0 pass, 1 warn, 2 fail — CI-friendly.
	match grade:
		"PASS", "PASS_WITH_TUNING":
			quit(0)
		"WARN":
			quit(1)
		_:
			quit(2)

## How long to wait for a bake the *map* started before taking the region over.
## A site-sized bake finishes in well under a second; this is a ceiling, not an
## expectation, and hitting it is reported rather than waited out forever.
const BAKE_HANDOVER_FRAMES := 240

## Runtime-bake every NavigationRegion3D under root (for CI and greybox
## levels that ship without a baked navmesh). Parses source geometry
## from the MAP ROOT using static colliders on the World layer —
## region.bake_navigation_mesh() only parses the region's own children,
## which are typically empty in a greybox (geometry lives elsewhere in
## the scene), yielding a 0-polygon mesh.
func _bake_navigation(map_root: Node) -> void:
	var regions: Array[NavigationRegion3D] = []
	_collect_regions(map_root, regions)
	if regions.is_empty():
		print("[LT] --bake-nav: no NavigationRegion3D found")
		return
	for region in regions:
		# A map's own _ready() may have kicked off region.bake_navigation_mesh(),
		# which is threaded and returns immediately. Let it land before taking
		# the region over, rather than racing it.
		var waited := 0
		while region.is_baking() and waited < BAKE_HANDOVER_FRAMES:
			await physics_frame
			waited += 1
		if region.is_baking():
			push_warning(("[LT] %s was still baking after %d frames; the map "
				+ "started a bake this runner cannot wait out. Baking a "
				+ "separate mesh anyway — the map's result is discarded.") % [
				region.name, BAKE_HANDOVER_FRAMES])

		# Bake into a FRESH resource, never the region's own. Baking a
		# NavigationMesh that is already baking is refused outright, and the
		# refusal leaves the polygon count at 0 — a refused bake and a map with
		# no collision at all print the identical number. Every parameter below
		# is overridden anyway, so reusing the region's resource bought nothing
		# but that race. A new NavigationMesh also carries the engine-default
		# cell_size/cell_height, which is what the navigation map itself uses,
		# so the rasterization-mismatch warning goes with it.
		var nav_mesh := NavigationMesh.new()
		nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
		nav_mesh.geometry_collision_mask = 1  # World layer — collision is truth
		nav_mesh.agent_radius = 0.4  # matches the pill capsule

		var source := NavigationMeshSourceGeometryData3D.new()
		NavigationServer3D.parse_source_geometry_data(nav_mesh, source, map_root)

		# "Found no geometry" and "found geometry that bakes to nothing" are
		# different faults with different fixes, and the old message guessed at
		# the first while the truth was usually neither. Say which one happened.
		if not source.has_data():
			push_warning(("[LT] Nothing to bake for %s: parsing %s found no "
				+ "static colliders on layer 1. Check that the map's geometry "
				+ "carries collision bodies, not just visual meshes.") % [
				region.name, map_root.name])
			continue

		NavigationServer3D.bake_from_source_geometry_data(nav_mesh, source)
		region.navigation_mesh = nav_mesh

		var polygons := nav_mesh.get_polygon_count()
		if polygons == 0:
			var vertices := source.get_vertices().size() / 3
			push_warning(("[LT] Baked 0 polygons on %s from %d source vertices "
				+ "under %s. Geometry was found, so this is not missing "
				+ "collision: nothing in it is walkable at agent_radius %.2f / "
				+ "agent_height %.2f / agent_max_slope %.1f°.") % [
				region.name, vertices, map_root.name, nav_mesh.agent_radius,
				nav_mesh.agent_height, nav_mesh.agent_max_slope])
		else:
			print("[LT] Baked navmesh on %s (%d polygons, %d source vertices)" % [
				region.name, polygons, source.get_vertices().size() / 3])
	# Let the navigation map sync the freshly baked regions.
	for i in 3:
		await physics_frame

func _collect_regions(node: Node, out: Array[NavigationRegion3D]) -> void:
	if node is NavigationRegion3D:
		out.append(node)
	for child in node.get_children():
		_collect_regions(child, out)

const DELTA_KEYS := [
	"avg_time_to_first_contact", "avg_player_survival_seconds",
	"shots_blocked_by_collision_percent", "route_completion_rate",
	"enemy_stuck_events", "player_stuck_events",
]

func _baseline_delta(baseline_path: String, score: Dictionary,
		summary: Dictionary) -> Dictionary:
	var file := FileAccess.open(baseline_path, FileAccess.READ)
	if file == null:
		push_warning("run_map_eval: cannot read baseline %s" % baseline_path)
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed == null or parsed is not Dictionary:
		push_warning("run_map_eval: baseline %s is not valid JSON" % baseline_path)
		return {}

	var old_summary: Dictionary = parsed.get("summary", {})
	var metric_deltas := {}
	for key in DELTA_KEYS:
		if summary.has(key) and old_summary.has(key):
			metric_deltas[key] = snappedf(float(summary[key]) - float(old_summary[key]), 0.01)

	return {
		"compared_to": baseline_path.get_file(),
		"old_score": parsed.get("overall_score", 0),
		"new_score": score.get("overall_score", 0),
		"score_delta": int(score.get("overall_score", 0)) - int(parsed.get("overall_score", 0)),
		"old_grade": parsed.get("grade", "?"),
		"new_grade": score.get("grade", "?"),
		"metric_deltas": metric_deltas,
	}

func _print_baseline_delta(delta: Dictionary) -> void:
	print("")
	print("[LT] Baseline comparison vs %s:" % delta["compared_to"])
	print("  Score: %d -> %d (%+d)   Grade: %s -> %s" % [
		delta["old_score"], delta["new_score"], delta["score_delta"],
		delta["old_grade"], delta["new_grade"]])
	var metric_deltas: Dictionary = delta["metric_deltas"]
	for key in metric_deltas:
		print("  %s: %+.2f" % [key, metric_deltas[key]])

func _find_harness(node: Node) -> LT_MapEvalHarness:
	if node is LT_MapEvalHarness:
		return node
	for child in node.get_children():
		var found: LT_MapEvalHarness = _find_harness(child)
		if found != null:
			return found
	return null

func _parse_args() -> Dictionary:
	var out := {}
	var raw: PackedStringArray = OS.get_cmdline_user_args()
	if raw.is_empty():
		raw = OS.get_cmdline_args()
	var i := 0
	while i < raw.size():
		var arg := raw[i]
		if arg.begins_with("--"):
			var key := arg.trim_prefix("--")
			if i + 1 < raw.size() and not raw[i + 1].begins_with("--"):
				out[key] = raw[i + 1]
				i += 1
			else:
				out[key] = "true"
		i += 1
	return out
