extends SceneTree
## The sampler describes the LEVEL, and says nothing it did not measure.
##
##     godot --headless --path . \
##       -s res://addons/laser_tag_tool/runners/tests/test_sampler_without_spawns.gd
##
## WHY THIS EXISTS. `LT_MapSampler` keyed every exposure figure off enemy spawn
## positions, and the harness refused to run it at all without them. Spawn
## placement is gameplay-layer work that is expected to live outside this
## toolchain, so an instrument that goes silent -- or worse, answers anyway --
## when the spawns are gone was measuring the wrong subject.
##
## The trap is the "answers anyway" half. With an empty eye list every sample
## is visible to zero spawns, which reads as `blind_fraction` 1.0 and
## `overexposed_fraction` 0.0 -- a bare plane reporting as perfectly covered
## and scoring a PASS on exposure. A reader that cannot find its field has to
## know the field is missing (CLAUDE.md: never write a checker against a
## guessed schema, and make an unrecognised shape fail rather than pass).

var failures: int = 0


func check(condition: bool, label: String) -> void:
	if condition:
		print("  ok: " + label)
	else:
		failures += 1
		print("  FAIL: " + label)


func _init() -> void:
	var root_node := Node3D.new()
	get_root().add_child(root_node)

	# A bare 40 x 40 plane: no cover anywhere, which is the clearest case for
	# "open on all sides" and the one a spawn-relative reading gets backwards.
	var ground := StaticBody3D.new()
	ground.collision_layer = LT_Const.LAYER_WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 1.0, 40.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	ground.add_child(shape)
	root_node.add_child(ground)
	for _i in range(4):
		await physics_frame

	var sampler := LT_MapSampler.new()
	root_node.add_child(sampler)
	sampler.sample_spacing = 4.0
	sampler.sightline_limit_m = 35.0

	var corners: Array[Vector3] = [Vector3(-18.0, 0.0, -18.0), Vector3(18.0, 0.0, 18.0)]
	var no_spawns: Array[Vector3] = []
	var data: Dictionary = sampler.sample_map(
		root_node.get_world_3d(), false, no_spawns, corners)

	print("[1] it measures the level with no spawns at all")
	check(not data.is_empty(), "sample_map returns data without enemy spawns")
	check(int(data.get("total_samples", 0)) > 0,
		"it found walkable samples (%d)" % int(data.get("total_samples", 0)))
	check(data.has("has_cover_fraction"),
		"cover is reported -- it needs no spawns")
	check(data.has("avg_open_directions"),
		"open approaches are reported")

	print("[2] it OMITS what it could not measure")
	for key in ["blind_fraction", "overexposed_fraction", "overexposed_count",
			"worst_overexposed", "avg_exposure"]:
		check(not data.has(key),
			"%s absent rather than defaulted" % key)

	print("[3] a bare plane reads as open, not as covered")
	# The failure this guards: zeroed spawn stats would have called this
	# 0% overexposed, which the scorer prints as a PASS.
	check(float(data.get("fully_open_fraction", 0.0)) > 0.5,
		"most of an empty plane is open on all sides (%.2f)"
		% float(data.get("fully_open_fraction", -1.0)))
	check(float(data.get("has_cover_fraction", 1.0)) < 0.25,
		"almost nothing on it has cover (%.2f)"
		% float(data.get("has_cover_fraction", -1.0)))

	sampler.free()
	if failures == 0:
		print("PASS: the sampler describes the level and omits what it cannot see")
		quit(0)
	else:
		print("FAIL: %d check(s)" % failures)
		quit(1)
