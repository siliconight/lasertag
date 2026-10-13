extends SceneTree
## An enemy held by another bot's body is BLOCKED, not stuck (0.30.0, factory roadmap 242).
##
## `LT_EnemyMovement._update_stuck` closed a 3 s window and recorded `EnemyStuck` whenever a guard trying to
## move had moved less than 0.5 m, whatever held it. Traced on the factory's lots
## (`docs/findings/stoop_breadth/enemy_stop_trace.py`, each stuck event's own frame of slide collisions), 73 of
## 75 were a guard pressed against another bot -- in SEEK every guard paths to the same crew member through
## the same corners, and none steers round another -- and NPC Pathing charged the map for every one.
##
## Real physics, the engine stepping: a floor, a guard (the contract's 0.35 m capsule) sent 20 m along +x
## with navigation off, and in its way, in three cases:
##   [1] nothing: the control that the guard moves at all -- neither stuck nor blocked
##   [2] a wall (a StaticBody3D): stuck, once, as before -- the level holds it
##   [3] another bot's body (a CharacterBody3D standing still): blocked, once, and not stuck
## and [4] the collector counts `EnemyBlocked` apart: `enemy_blocked_events`, with `enemy_stuck_events`
## unmoved. Each case runs FRAMES physics frames, past the 3 s window.

const FRAMES := 220

var failures: int = 0
var _stuck: int = 0
var _blocked: int = 0


func check(condition: bool, label: String) -> void:
	if condition:
		print("  ok: " + label)
	else:
		failures += 1
		print("  FAIL: " + label)


func _initialize() -> void:
	_main.call_deferred()


func _capsule() -> CollisionShape3D:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	shape.shape = capsule
	return shape


func _box(size: Vector3) -> CollisionShape3D:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	return shape


func _on_stuck(_position: Vector3) -> void:
	_stuck += 1


func _on_blocked(_position: Vector3) -> void:
	_blocked += 1


## One case: what stands in the guard's way, "none", "wall" or "bot". Returns [stuck, blocked, moved m].
func _case(what: String) -> Array:
	_stuck = 0
	_blocked = 0
	var world := Node3D.new()
	root.add_child(world)
	var ground := StaticBody3D.new()
	ground.add_child(_box(Vector3(60.0, 1.0, 20.0)))
	ground.position = Vector3(0.0, -0.5, 0.0)
	world.add_child(ground)
	var body := CharacterBody3D.new()
	body.name = "LT_Enemy_01"
	body.add_child(_capsule())
	body.position = Vector3(0.0, 0.92, 0.0)
	world.add_child(body)
	# each blocker leaves the guard less than the 0.5 m threshold to travel, so the FIRST 3 s window
	# closes on a held body: the wall's face 0.45 m off (0.10 m of travel), the bot's 0.20 m
	if what == "wall":
		var wall := StaticBody3D.new()
		wall.add_child(_box(Vector3(0.3, 3.0, 4.0)))
		wall.position = Vector3(0.6, 1.5, 0.0)
		world.add_child(wall)
	elif what == "bot":
		var other := CharacterBody3D.new()
		other.name = "LT_Enemy_02"
		other.add_child(_capsule())
		other.position = Vector3(0.9, 0.92, 0.0)
		world.add_child(other)
	var movement := LT_EnemyMovement.new()
	movement.body = body
	movement.use_navigation = false
	body.add_child(movement)
	movement.stuck_detected.connect(_on_stuck)
	# asked, not assumed: on a Laser Tag without the signal the cases still run to their checks and fail
	# there, rather than the script stopping on an error and never quitting
	if movement.has_signal("blocked_detected"):
		movement.connect("blocked_detected", _on_blocked)
	elif what == "bot":
		print("  (this Laser Tag has no blocked_detected)")
	var start: Vector3 = body.global_position
	movement.set_destination(Vector3(20.0, 0.0, 0.0))
	for _f in range(FRAMES):
		await physics_frame
	var moved: float = Vector2(body.global_position.x - start.x, body.global_position.z - start.z).length()
	var out: Array = [_stuck, _blocked, moved]
	world.free()
	return out


func _main() -> void:
	print("[1] nothing in the way: the control that the guard moves")
	var c1: Array = await _case("none")
	check(float(c1[2]) > 5.0, "it walked %.2f m" % float(c1[2]))
	check(int(c1[0]) == 0 and int(c1[1]) == 0, "neither stuck nor blocked (%d, %d)" % [c1[0], c1[1]])

	print("[2] a wall in the way: the level holds it, stuck as before")
	var c2: Array = await _case("wall")
	check(float(c2[2]) < 0.5, "it is held: %.3f m" % float(c2[2]))
	check(int(c2[0]) == 1, "stuck once (%d)" % c2[0])
	check(int(c2[1]) == 0, "not blocked (%d)" % c2[1])

	print("[3] another bot in the way: blocked, not stuck")
	var c3: Array = await _case("bot")
	check(float(c3[2]) < 0.5, "it is held: %.3f m" % float(c3[2]))
	check(int(c3[1]) == 1, "blocked once (%d)" % c3[1])
	check(int(c3[0]) == 0, "not stuck (%d)" % c3[0])

	print("[4] the collector counts EnemyBlocked apart")
	var m := LT_MetricsCollector.new()
	m.begin_run(1, 4, 6)
	m.record_event("EnemyBlocked", {"source": "LT_Enemy_01", "position": [1.0, 0.0, 2.0]})
	m.record_event("EnemyStuck", {"source": "LT_Enemy_02", "position": [3.0, 0.0, 4.0]})
	check(int(m.current.get("enemy_blocked_events", -1)) == 1, "one EnemyBlocked counted")
	check(int(m.current["enemy_stuck_events"]) == 1, "and EnemyStuck counted as before, once")
	m.free()

	print("QUEUE_NOT_STUCK %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(1 if failures else 0)
