extends SceneTree
## Moving a marker must not change what the sampler measures.
##
## 0.12.0 replaced a marker-derived sample region with a geometry-derived one
## and then appended the markers anyway, so they could still EXTEND it. The
## cost showed up when Lot 0.53.0 moved only where enemies stand on
## restaurant_row_001 seed 9003: `total_samples` went 3876 -> 2904 on
## byte-identical geometry, and every cover figure moved with the denominator
## (has_cover 0.764 -> 0.729, fully_open 0.211 -> 0.269). Worse, it was read
## as a TRADE the placement change had made, when re-measuring both placements
## over the same region showed blind_fraction 0.527 against 0.521 -- above the
## warning threshold either way, and nothing to do with the placement.
##
## A denominator that moves when the level does not makes every figure over it
## a statement about somebody's marker placement.

var failures: int = 0


func check(condition: bool, label: String) -> void:
	if condition:
		print("  ok: " + label)
	else:
		failures += 1
		print("  FAIL: " + label)


func _build(marker_span: float) -> Dictionary:
	"""One ground slab, and two markers `marker_span` metres out either side."""
	var host := Node3D.new()
	get_root().add_child(host)
	var ground := StaticBody3D.new()
	ground.collision_layer = LT_Const.LAYER_WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# COLLISION IS WIDER THAN THE MESH, which is what made this reachable on a
	# real site: `_collect_samples` finds a floor by raycasting COLLISION, and
	# `_geometry_anchors` bounds the grid by MESHES. Wherever collision runs
	# past the visual geometry there is samplable ground outside the bounds,
	# and a marker out there used to drag the region onto it.
	box.size = Vector3(200.0, 1.0, 200.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	ground.add_child(shape)
	# A visual mesh over the same extent: `_geometry_anchors` reads
	# MeshInstance3D, and collision alone would give it nothing to bound.
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(40.0, 1.0, 40.0)
	mesh.mesh = bm
	mesh.position = Vector3(0.0, -0.5, 0.0)
	ground.add_child(mesh)
	host.add_child(ground)
	return {"host": host, "span": marker_span}


func _sample(host: Node3D, anchors: Array[Vector3]) -> int:
	var sampler := LT_MapSampler.new()
	host.add_child(sampler)
	sampler.sample_spacing = 4.0
	var none: Array[Vector3] = []
	var data: Dictionary = sampler.sample_map(
		host.get_world_3d(), false, none, anchors)
	var n: int = int(data.get("total_samples", -1))
	sampler.free()
	return n


func _init() -> void:
	LT_Const.ensure_input_actions()
	var a: Dictionary = _build(0.0)
	var host: Node3D = a["host"]
	for _i in range(4):
		await physics_frame

	# The level's own corners, which is what the harness now passes.
	var geom: Array[Vector3] = [Vector3(-20.0, 0.0, -20.0), Vector3(20.0, 0.0, 20.0)]
	var near_markers: Array[Vector3] = geom.duplicate()
	near_markers.append(Vector3(5.0, 0.0, 5.0))
	var far_markers: Array[Vector3] = geom.duplicate()
	far_markers.append(Vector3(90.0, 0.0, 90.0))

	print("[1] the level alone")
	var base: int = _sample(host, geom)
	check(base > 0, "the slab samples (%d positions)" % base)

	print("[2] a marker INSIDE the level changes nothing")
	check(_sample(host, near_markers) == base,
		"same count with a marker at (5, 5)")

	print("[3] a marker OUTSIDE the level drags the region onto ground the")
	print("    level does not cover -- which is why the harness stopped")
	print("    passing markers while it has geometry")
	var stretched: int = _sample(host, far_markers)
	var msg: String = ("a marker at (90, 90) stretches the region when it is "
		+ "PASSED: %d samples against %d")
	check(stretched > base, msg % [stretched, base])
	check(_sample(host, geom) == base,
		"and the geometry-only bounds are stable across all of it")

	host.queue_free()
	if failures == 0:
		print("PASS: the sampled region is the level, not the marker spread")
		quit(0)
	else:
		print("FAIL: %d check(s)" % failures)
		quit(1)
