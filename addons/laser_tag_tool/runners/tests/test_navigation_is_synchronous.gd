extends SceneTree
## The navigation map updates on the evaluation's own thread (0.27.0, factory
## roadmap 239).
##
## Godot 4.7 runs a navigation map's and a region's iterations on worker
## threads by default, so when an update landed was a matter of wall time and
## an evaluation repeated only as far as the machine was idle. Measured in the
## factory (`docs/findings/grader_speed/`): three evaluations at once moved a
## few event positions by 0.01 m, and the engine's `--fixed-fps` clock moved
## cold run 9247's seed_9104 crew stuck count 9 -> 21 with the physics step
## unchanged -- while with both iterations synchronous every report measured
## read the same twice, alone and three at once, under either clock.
##
##   [1] `LT_Const.synchronous_navigation` sets the world's map and every
##       region under a scene, nested ones too, and `navigation_is_synchronous`
##       reads the dial back once the commands have landed. FAILS ON 0.26.0:
##       neither exists.
##   [2] the evaluation runner does it in `_run`, before it bakes, and reads
##       the dial back. FAILS ON 0.26.0.
##
## The setters are deferred server commands -- read straight back, the map
## still said asynchronous when this was written -- which is why the runner
## lets a physics frame pass. That is printed below, not asserted: it is the
## engine's behaviour, and a future Godot that applies them at once changes
## nothing here.
##
## Run:  godot --headless --path lasertag -s res://addons/laser_tag_tool/runners/tests/test_navigation_is_synchronous.gd

var failures: int = 0


func check(condition: bool, label: String) -> void:
	if condition:
		print("  ok: " + label)
	else:
		failures += 1
		print("  FAIL: " + label)


func _init() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var region := NavigationRegion3D.new()
	scene.add_child(region)
	var nested := Node3D.new()
	scene.add_child(nested)
	var deeper := NavigationRegion3D.new()
	nested.add_child(deeper)
	await physics_frame

	print("[1] the map and every region under the scene, set and read back")
	var map: RID = scene.get_viewport().get_world_3d().navigation_map
	print("     Godot's default here: map asynchronous %s, region %s" % [
		NavigationServer3D.map_get_use_async_iterations(map),
		NavigationServer3D.region_get_use_async_iterations(region.get_rid())])
	var count: int = LT_Const.synchronous_navigation(scene)
	check(count == 2, "both regions set, the nested one too (%d)" % count)
	print("     read straight back: map asynchronous %s" %
		NavigationServer3D.map_get_use_async_iterations(map))
	await physics_frame
	check(not NavigationServer3D.map_get_use_async_iterations(map),
		"after a physics frame the world's map is synchronous")
	check(not NavigationServer3D.region_get_use_async_iterations(region.get_rid()),
		"and the region")
	check(not NavigationServer3D.region_get_use_async_iterations(deeper.get_rid()),
		"and the nested region")
	check(LT_Const.navigation_is_synchronous(scene), "and the reader agrees")
	var other := Node3D.new()
	root.add_child(other)
	var stray := NavigationRegion3D.new()
	other.add_child(stray)
	await physics_frame
	# The reader is not a constant: a region nobody set reads as it is, so
	# under Godot's default it says "not synchronous".
	var stray_async: bool = NavigationServer3D.region_get_use_async_iterations(stray.get_rid())
	check(LT_Const.navigation_is_synchronous(other) == (not stray_async),
		"a region it was never given reads as it is (asynchronous %s)" % stray_async)

	print("[2] the evaluation runner does it before it bakes")
	var src: String = FileAccess.get_file_as_string(
		"res://addons/laser_tag_tool/runners/run_map_eval.gd")
	var body: String = src.substr(src.find("func _run("))
	body = body.substr(0, body.find(char(10) + "func "))
	var sets: int = body.find("LT_Const.synchronous_navigation(")
	var bakes: int = body.find("_bake_navigation(")
	check(sets != -1, "_run calls LT_Const.synchronous_navigation")
	check(sets != -1 and bakes != -1 and sets < bakes, "before _bake_navigation")
	check(body.find("LT_Const.navigation_is_synchronous(") != -1,
		"and reads the dial back")

	scene.queue_free()
	other.queue_free()
	if failures == 0:
		print("PASS: the navigation map updates on the evaluation's thread")
		quit(0)
	else:
		print("FAIL: %d check(s)" % failures)
		quit(1)
