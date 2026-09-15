extends SceneTree
## The runner bakes at `deli_counter/agent_contract.json`'s `nav_bake` (0.23.1).
##
## Cold run 9058: `run_map_eval._bake_navigation` set only agent_radius and
## baked at the engine defaults (cell 0.25, cell height 0.25, climb 0.25,
## height 1.5, slope 45). At 0.25 m cells twin_a01's 1.30 m front door and
## 1.20 m cross-wall door eroded shut, the bot's route to an upstairs objective
## stopped 6.05 m short and a real run scored TRAVERSAL 0%, while Lot's bake of
## the same scene at the contract's cells path-proved it at 81.0 m.
##
##     godot --headless --path lasertag -s res://addons/laser_tag_tool/runners/tests/test_nav_bake_is_the_contract.gd
##
## Reads the contract from the factory checkout beside this repo; with no
## contract there it exits 2, never a pass.

const Runner := preload("res://addons/laser_tag_tool/runners/run_map_eval.gd")

var failures: int = 0


func check(condition: bool, label: String) -> void:
	if condition:
		print("  ok: " + label)
	else:
		failures += 1
		print("  FAIL: " + label)


func _init() -> void:
	var path := ProjectSettings.globalize_path("res://").path_join("../deli_counter/agent_contract.json").simplify_path()
	if not FileAccess.file_exists(path):
		print("  cannot run: no agent_contract.json at %s" % path)
		quit(2)
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY or not (data as Dictionary).has("nav_bake"):
		print("  cannot run: %s has no nav_bake" % path)
		quit(2)
		return
	var bake: Dictionary = data["nav_bake"]
	var pairs := [
		["agent_radius_m", Runner.NAV_AGENT_RADIUS],
		["agent_height_m", Runner.NAV_AGENT_HEIGHT],
		["agent_max_climb_m", Runner.NAV_AGENT_MAX_CLIMB],
		["agent_max_slope_deg", Runner.NAV_AGENT_MAX_SLOPE],
		["cell_size_m", Runner.NAV_CELL_SIZE],
		["cell_height_m", Runner.NAV_CELL_HEIGHT],
	]
	print("[1] every nav_bake value the runner uses is the contract's")
	for p in pairs:
		var key: String = p[0]
		check(bake.has(key), "contract has %s" % key)
		if bake.has(key):
			check(absf(float(bake[key]) - float(p[1])) < 1e-6,
				"%s: runner %.3f, contract %.3f" % [key, float(p[1]), float(bake[key])])
	print("[2] the bake sets them, not only declares them")
	var src := FileAccess.get_file_as_string("res://addons/laser_tag_tool/runners/run_map_eval.gd")
	for prop in ["agent_radius = NAV_AGENT_RADIUS", "agent_height = NAV_AGENT_HEIGHT",
			"agent_max_climb = NAV_AGENT_MAX_CLIMB", "agent_max_slope = NAV_AGENT_MAX_SLOPE",
			"cell_size = NAV_CELL_SIZE", "cell_height = NAV_CELL_HEIGHT",
			"map_set_cell_size(", "map_set_cell_height("]:
		check(src.contains(prop), "run_map_eval.gd sets " + prop)
	if failures == 0:
		print("nav bake contract test: all checks passed")
		quit(0)
	else:
		print("nav bake contract test: %d FAILED" % failures)
		quit(1)
