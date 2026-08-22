extends SceneTree
## Regression proof for the "enemy elevator": spawning two
## CharacterBody3Ds at the SAME point feeds Godot's overlap recovery
## every physics frame -- each treats the other as floor, gravity never
## engages, and the stack ratchets skyward forever (measured 160 m up
## after 1.5 s). Field repro: press [N] in the showcase -- 6 enemies on
## the demo greybox's 2 spawn points stacked 3 pills per point.
##
##     godot --headless --path . \
##       -s res://addons/laser_tag_tool/runners/tests/test_spawn_separation.gd
##
## [1] proves LT_Const.spawn_ring_offset keeps every reuse level and a
## capsule diameter apart; [2] proves the physics claim both ways: a
## coincident trio climbs (the engine still needs the workaround), a
## ring-offset trio stays grounded.

var failures: int = 0

func check(condition: bool, label: String) -> void:
	if condition:
		print("  ok: " + label)
	else:
		failures += 1
		print("  FAIL: " + label)

## Replicates LT_EnemyMovement._physics_process's idle branch: gravity
## only while airborne, damp lateral velocity, move_and_slide.
class MiniMover:
	extends Node
	var body: CharacterBody3D
	var gravity: float = 9.8

	func _physics_process(delta: float) -> void:
		if not body.is_on_floor():
			body.velocity.y -= gravity * delta
		body.velocity.x = move_toward(body.velocity.x, 0.0, 4.0)
		body.velocity.z = move_toward(body.velocity.z, 0.0, 4.0)
		body.move_and_slide()

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _make_pill(pos: Vector3) -> CharacterBody3D:
	var pill := CharacterBody3D.new()
	pill.collision_layer = LT_Const.LAYER_ENEMY
	pill.collision_mask = LT_Const.LAYER_WORLD | LT_Const.LAYER_PLAYER | LT_Const.LAYER_ENEMY
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	shape.shape = capsule
	shape.position = Vector3(0, 0.9, 0)
	pill.add_child(shape)
	var mover := MiniMover.new()
	mover.body = pill
	pill.add_child(mover)
	root.add_child(pill)
	pill.global_position = pos
	return pill

func _run() -> void:
	print("[1] ring offsets: level, distinct, capsule-clear")
	check(LT_Const.spawn_ring_offset(0) == Vector3.ZERO, "first use spawns on the point itself")
	var points: Array[Vector3] = []
	for reuse in 10:
		points.append(LT_Const.spawn_ring_offset(reuse))
	var level := true
	var min_gap := INF
	for a in points.size():
		if absf(points[a].y) > 0.001:
			level = false
		for b in range(a + 1, points.size()):
			min_gap = minf(min_gap, points[a].distance_to(points[b]))
	check(level, "every offset stays level with the spawn point")
	check(min_gap >= 0.85, "any two of 10 reuses clear a capsule diameter (min %.2f m)" % min_gap)

	print("[2] physics: coincident trio climbs, ring-offset trio stays grounded")
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = LT_Const.LAYER_WORLD
	floor_body.collision_mask = 0
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 40)
	floor_shape.shape = box
	floor_body.add_child(floor_shape)
	root.add_child(floor_body)
	floor_body.global_position = Vector3(0, -0.5, 0)

	var stacked: Array = []
	var ringed: Array = []
	for i in 3:
		stacked.append(_make_pill(Vector3(0, 0.1, 0)))
		ringed.append(_make_pill(Vector3(15, 0.1, 0) + LT_Const.spawn_ring_offset(i)))

	for frame in 90:  # 1.5 s of physics
		await physics_frame

	var stacked_max_y := 0.0
	var ringed_max_y := 0.0
	for i in 3:
		stacked_max_y = maxf(stacked_max_y, stacked[i].global_position.y)
		ringed_max_y = maxf(ringed_max_y, absf(ringed[i].global_position.y))
	check(stacked_max_y > 1.0,
			"coincident pills still elevator (%.1f m up; workaround still required)" % stacked_max_y)
	check(ringed_max_y < 0.2,
			"ring-offset pills stay grounded (max |y| %.2f m)" % ringed_max_y)

	print("")
	if failures == 0:
		print("ALL CHECKS PASSED")
	else:
		print("%d CHECKS FAILED" % failures)
	quit(1 if failures > 0 else 0)
