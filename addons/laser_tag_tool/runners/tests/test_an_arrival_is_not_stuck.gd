extends SceneTree
## A crew bot that reaches where it was going is not stuck (0.28.1, factory
## roadmap 242).
##
##     godot --headless --path . \
##       -s res://addons/laser_tag_tool/runners/tests/test_an_arrival_is_not_stuck.gd
##
## WHY THIS EXISTS. `_update_stuck` measures NET displacement over its 4 s
## window, so a body that walked out to a route point and back inside one
## window ended near where the window began and read as stuck -- 10 traversal
## points and a skipped route point. The factory traced every stuck event
## 0.28.0 added on its sixteen lots to such round trips, the route point
## reached halfway through the window (`docs/findings/route_snag/`,
## `pin_trace.py trace --wide`).
##
## Driven through `_physics_process` at 0.25 s a frame, so a window closes on
## exactly its 16th frame. The bot cannot move itself (`move_speed` 0, no
## gravity, no step-up); the TEST walks the body, a metre a frame, out along x
## and back -- `move_and_slide` outside a physics frame takes the idle delta,
## which no test can fix. A route point counts as reached within 1.2 m
## (`_nav_finished` without navigation). A sink in the metrics group counts
## PlayerStuck.
##
## [1] THE CONTROL: out to x 8 and back to 0 by frame 16, reaching nothing --
##     stuck on frame 16. The round trip alone does trip the window.
## [2] the same walk with a route point at x 8.5, reached on frame 8: no stuck
##     event on frame 16. 0.28.0 records one -- the check that fails without
##     the change.
## [3] a route point reached on frame 8 and the body held there after: stuck on
##     frame 23, a window after the arrival -- the arrival's own frame is the
##     new window's first, since `_advance_route` runs before `_update_stuck`
##     adds the frame (0.28.0: frame 32). An arrival restarts the window, it
##     does not hide a jam.
## [4] the same round trip to a COVER point the bot was sent to: no stuck event
##     on frame 16.

const STEP: float = 0.25

var failures: int = 0


class Sink extends Node:
	var stuck: int = 0

	func record_event(event_name: String, _data: Dictionary) -> void:
		if event_name == "PlayerStuck":
			stuck += 1


func check(condition: bool, label: String) -> void:
	if condition:
		print("  ok: " + label)
	else:
		failures += 1
		print("  FAIL: " + label)


func _initialize() -> void:
	_main.call_deferred()


func _case(points: Array[Vector3]) -> Array:
	var world := Node3D.new()
	root.add_child(world)
	var sink := Sink.new()
	sink.add_to_group(LT_Const.GROUP_METRICS)
	world.add_child(sink)
	var body := CharacterBody3D.new()
	body.name = "LT_Player_01"
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	shape.shape = capsule
	body.add_child(shape)
	world.add_child(body)
	var bot := LT_BotPlayerController.new()
	bot.body = body
	bot.use_navigation = false
	bot.move_speed = 0.0
	bot.gravity = 0.0
	bot.max_step_up = 0.0
	world.add_child(bot)
	# the test steps the bot itself; the engine must not. Each case's world is
	# FREED before the next is built: a body left at the origin would stand in
	# the next one's way.
	bot.set_physics_process(false)
	bot.start_route(points)
	return [world, bot, sink, body]


## Frames `from` to `to`, the body put at x(frame) before each.
func _walk(c: Array, from: int, to: int, x: Callable) -> void:
	var bot: LT_BotPlayerController = c[1]
	var body: CharacterBody3D = c[3]
	for f in range(from, to + 1):
		body.global_position = Vector3(float(x.call(f)), 0.0, 0.0)
		bot._physics_process(STEP)


func _out_and_back(f: int) -> int:
	return f if f <= 8 else 16 - f


func _main() -> void:
	var far: Vector3 = Vector3(-30.0, 0.0, 0.0)

	print("[1] the control: out to x 8 and back, nothing reached")
	var c1: Array = _case([Vector3(20.0, 0.0, 0.0), far] as Array[Vector3])
	_walk(c1, 1, 15, _out_and_back)
	check((c1[2] as Sink).stuck == 0, "nothing by frame 15 (%d)" % (c1[2] as Sink).stuck)
	_walk(c1, 16, 16, _out_and_back)
	check((c1[2] as Sink).stuck == 1,
		"stuck on frame 16: the window ended where it began (%d)" % (c1[2] as Sink).stuck)
	(c1[0] as Node).free()

	print("[2] the same walk, a route point at x 8.5 reached on frame 8")
	var c2: Array = _case([Vector3(8.5, 0.0, 0.0), far] as Array[Vector3])
	_walk(c2, 1, 16, _out_and_back)
	check((c2[1] as LT_BotPlayerController).route_points.size() == 2 and int((c2[1] as LT_BotPlayerController).get("_route_reached")) == 1,
		"the route point was reached (%d)" % int((c2[1] as LT_BotPlayerController).get("_route_reached")))
	check((c2[2] as Sink).stuck == 0, "no stuck event on frame 16: the bot got where it was going (%d)" % (c2[2] as Sink).stuck)
	(c2[0] as Node).free()

	print("[3] reached on frame 8, then held there")
	var c3: Array = _case([Vector3(8.5, 0.0, 0.0), far] as Array[Vector3])
	var held := func(f: int) -> int: return mini(f, 8)
	_walk(c3, 1, 22, held)
	var by22: int = (c3[2] as Sink).stuck
	check(by22 == 0, "nothing by frame 22 (%d)" % by22)
	_walk(c3, 23, 23, held)
	check((c3[2] as Sink).stuck - by22 == 1,
		"one stuck event on frame 23, a window after the arrival (%d more)" % ((c3[2] as Sink).stuck - by22))
	(c3[0] as Node).free()

	print("[4] out to a cover point and back")
	var c4: Array = _case([far, far + Vector3(0.0, 0.0, 5.0)] as Array[Vector3])
	var bot4: LT_BotPlayerController = c4[1]
	bot4.set("_seeking_cover", true)
	bot4.call("_set_destination", Vector3(8.5, 0.0, 0.0))
	_walk(c4, 1, 16, _out_and_back)
	check(not bool(bot4.get("_seeking_cover")), "the cover point was reached")
	check((c4[2] as Sink).stuck == 0, "no stuck event on frame 16 (%d)" % (c4[2] as Sink).stuck)
	(c4[0] as Node).free()

	print("")
	if failures == 0:
		print("test_an_arrival_is_not_stuck: PASS")
	else:
		print("test_an_arrival_is_not_stuck: %d FAILURE(S)" % failures)
	quit(1 if failures > 0 else 0)
