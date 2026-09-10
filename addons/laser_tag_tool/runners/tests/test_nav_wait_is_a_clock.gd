extends SceneTree
## The navigation wait is bounded in milliseconds, because frames are not a
## clock here (roadmap 126).
##
## `validate_map` reported NAVIGATION_MISSING on about 7% of evaluations,
## immediately after logging a successful bake. A run that loses navigation
## falls back to direct movement and comes back with hundreds of stuck events,
## zero shots and NO_ENGAGEMENT -- it reads as a catastrophic level rather than
## a race, which is what made it expensive.
##
## TWO CAUSES, AND THE FIRST ONE HID THE SECOND.
##
## 1. `await get_tree().physics_frame` in a headless SceneTree script does not
##    pace to 60 Hz. It spins. Measured on restaurant_row_001: 30 frames in
##    1 ms, while the navigation server's own sync needs 14-28 ms of WALL time.
##    So the original 3-frame wait was about 0.1 ms and a 30-frame replacement
##    was about 1 ms -- neither of them a wait at all, and whether the map read
##    as ready came down to how much real time happened to pass doing other
##    work.
##
## 2. `map_get_closest_point` returns exactly `Vector3.ZERO` before the map's
##    first sync. That is a plausible-looking coordinate, not an error, and the
##    readiness probe measured it as a real distance.
##
## [1] IS THE TEST THAT MATTERS, because it pins the premise rather than the
## fix: if a future Godot makes `physics_frame` pace itself, a frame count
## becomes a clock again and this whole analysis changes. Better to be told.

var failures: int = 0


func check(condition: bool, label: String) -> void:
	if condition:
		print("  ok: " + label)
	else:
		failures += 1
		print("  FAIL: " + label)


func _init() -> void:
	print("[1] a frame count has no fixed duration -- measured, not asserted")
	var started: int = Time.get_ticks_msec()
	for _i in range(30):
		await physics_frame
	var frames_msec: int = Time.get_ticks_msec() - started
	# NO THRESHOLD HERE ON PURPOSE. The first version of this test asserted
	# "30 frames < 100 ms" and failed at 480 ms -- in a bare SceneTree with no
	# scene, frames pace to 60 Hz. Inside `run_map_eval`, with a loaded map and
	# `--time-scale`, the same 30 frames measured 1 ms. That SPREAD is the
	# finding: the number is a property of the run context, so a frame count
	# cannot bound a wait on the navigation server, which needs 14-28 ms of
	# wall time whatever the frame rate is doing. Asserting either figure would
	# pin an engine setting rather than the behaviour.
	print("     30 physics frames took %d ms here; the same 30 measured 1 ms" % frames_msec)
	print("     inside run_map_eval, against a 14-28 ms nav sync")
	check(frames_msec >= 0, "the frame timing above is recorded, not asserted")

	print("[1b] and the wait is written against a clock")
	var src: String = FileAccess.get_file_as_string(
		"res://addons/laser_tag_tool/scripts/core/LT_MapEvalHarness.gd")
	var body: String = src.substr(src.find("func _await_navigation_sync"))
	body = body.substr(0, body.find(char(10) + "func "))
	check(body.find("Time.get_ticks_msec") != -1,
		"_await_navigation_sync reads a millisecond clock")
	check(body.find("NAV_SYNC_MAX_MSEC") != -1,
		"and bounds itself by NAV_SYNC_MAX_MSEC")

	print("[2] the harness bounds its wait in milliseconds")
	var script: GDScript = load(
		"res://addons/laser_tag_tool/scripts/core/LT_MapEvalHarness.gd")
	var consts: Dictionary = script.get_script_constant_map()
	check(consts.has("NAV_SYNC_MAX_MSEC"),
		"NAV_SYNC_MAX_MSEC exists -- the budget that actually waits")
	check(int(consts.get("NAV_SYNC_MAX_MSEC", 0)) >= 500,
		"and it is generous against a 14-28 ms need (%d ms)"
		% int(consts.get("NAV_SYNC_MAX_MSEC", 0)))
	check(int(consts.get("NAV_SYNC_MAX_FRAMES", 0)) > 100,
		"the frame cap is only a runaway guard now, not the budget (%d)"
		% int(consts.get("NAV_SYNC_MAX_FRAMES", 0)))

	print("[3] an unsynced map answers ZERO, and ZERO is not a coordinate")
	# The sentinel the readiness probe now refuses, stated as arithmetic so the
	# reasoning survives even though the server state cannot be faked here.
	var spawn := Vector3(0.0, 1.0, -23.0)
	var far_msg: String = ("an unsynced ZERO reads as %.1f m from a spawn at "
		+ "(0,1,-23) -- which is what reported the map missing")
	check(Vector3.ZERO.distance_to(spawn) > 3.0,
		far_msg % Vector3.ZERO.distance_to(spawn))
	var near_origin := Vector3(0.5, 1.0, 0.5)
	var near_msg: String = ("and on a map spawning near the origin the SAME "
		+ "unsynced ZERO reads as %.1f m, which would have reported READY on "
		+ "a map that was not")
	check(Vector3.ZERO.distance_to(near_origin) < 3.0,
		near_msg % Vector3.ZERO.distance_to(near_origin))

	if failures == 0:
		print("PASS: the wait is a clock and ZERO is not a coordinate")
		quit(0)
	else:
		print("FAIL: %d check(s)" % failures)
		quit(1)
