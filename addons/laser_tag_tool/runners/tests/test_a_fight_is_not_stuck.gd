extends SceneTree
## A crew bot standing to fight is not stuck (0.28.0, factory roadmap 242).
##
##     godot --headless --path . \
##       -s res://addons/laser_tag_tool/runners/tests/test_a_fight_is_not_stuck.gd
##
## WHY THIS EXISTS. `_update_stuck` closes a 4 s window and records
## PlayerStuck when the body moved less than 0.5 m and no enemy is in sight AT
## THAT INSTANT -- and `_score_traversal` takes 10 points for any at all, and
## the bot skips a route point, so a route that ends on the skip is not walked.
## A bot that stands to fight (`advance_while_engaging` off, the factory's
## setting) and loses sight of its enemy as the window closes was counted:
## the factory found 18 of the 21 stuck events a draft added on five lots to
## be such windows, an enemy in sight in 59 or 60 of their 60 frames
## (`docs/findings/route_snag/pin_trace.py`, `census --why`).
##
## Driven through `_physics_process`, the bot's own entry point, at 0.25 s a
## frame so a 4 s window closes on exactly the 16th. The bot cannot move
## (`move_speed` 0, no gravity, no step-up), so the body never leaves its
## anchor; a fake enemy is in sight when the test says so; a sink in the
## metrics group counts PlayerStuck.
##
## [1] THE CONTROL: no enemy at all -- nothing on frame 15, stuck on frame 16.
##     A detector that never fired would pass [2].
## [2] an enemy in sight on frames 1-15 and gone on 16, the frame the window
##     closes: no stuck event. 0.27.0 records one here -- the check that fails
##     without the change.
## [3] the fight over and the bot still unable to move: stuck on frame 31,
##     sixteen frames after the enemy left -- a fight restarts the window, it
##     does not hide a jam.
## [4] advancing while engaging (a brief can ask for it): the bot is trying to
##     move, so a fight does not restart its window -- stuck on frame 16 as
##     before, once no enemy is in sight as the window closes.

const STEP: float = 0.25

var failures: int = 0


class FightBot extends LT_BotPlayerController:
	var in_sight: bool = false
	var fake: Node3D = null

	func _find_visible_enemy() -> Node3D:
		return fake if in_sight else null

	func _fire_at(_target: Node3D) -> void:
		pass


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


func _case(advance: bool) -> Array:
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
	var bot := FightBot.new()
	bot.body = body
	bot.use_navigation = false
	bot.move_speed = 0.0
	bot.gravity = 0.0
	bot.max_step_up = 0.0
	bot.advance_while_engaging = advance
	bot.fake = Node3D.new()
	world.add_child(bot.fake)
	bot.fake.position = Vector3(10.0, 1.0, 0.0)
	world.add_child(bot)
	# the test steps the bot itself, at STEP a frame; the engine must not too.
	# Each case's world is FREED before the next is built, not queued: a body
	# left standing at the origin lifts the next one 1.8 m onto itself, and a
	# body that moved is not stuck (the first draft of this test, on 0.27.0).
	bot.set_physics_process(false)
	var route: Array[Vector3] = [Vector3(20.0, 0.0, 0.0)]
	bot.start_route(route)
	return [world, bot, sink]


## Frames `from` to `to`, the enemy in sight on those up to `sight_until`.
func _frames(bot: FightBot, from: int, to: int, sight_until: int) -> void:
	for f in range(from, to + 1):
		bot.in_sight = f <= sight_until
		bot._physics_process(STEP)


func _main() -> void:
	print("[1] the control: no enemy, the window closes on frame 16")
	var c1: Array = _case(false)
	var bot1: FightBot = c1[1]
	var sink1: Sink = c1[2]
	_frames(bot1, 1, 15, 0)
	check(sink1.stuck == 0, "nothing by frame 15 (%d)" % sink1.stuck)
	_frames(bot1, 16, 16, 0)
	check(sink1.stuck == 1, "stuck on frame 16, a body that cannot move and sees no one (%d)" % sink1.stuck)
	(c1[0] as Node).free()

	print("[2] in sight on frames 1-15, gone on frame 16, the window's last")
	var c2: Array = _case(false)
	var bot2: FightBot = c2[1]
	var sink2: Sink = c2[2]
	_frames(bot2, 1, 16, 15)
	check(sink2.stuck == 0, "no stuck event: the bot stood to fight (%d)" % sink2.stuck)

	print("[3] the fight over, the body still held")
	_frames(bot2, 17, 30, 15)
	var by30: int = sink2.stuck
	check(by30 == 0, "nothing by frame 30 (%d)" % by30)
	_frames(bot2, 31, 31, 15)
	check(sink2.stuck - by30 == 1,
		"one stuck event on frame 31, sixteen frames after the enemy left (%d more)" % (sink2.stuck - by30))
	(c2[0] as Node).free()

	print("[4] advancing while engaging: the window runs through the fight")
	var c4: Array = _case(true)
	var bot4: FightBot = c4[1]
	var sink4: Sink = c4[2]
	_frames(bot4, 1, 16, 15)
	check(sink4.stuck == 1, "stuck on frame 16, as before (%d)" % sink4.stuck)
	(c4[0] as Node).free()

	print("")
	if failures == 0:
		print("test_a_fight_is_not_stuck: PASS")
	else:
		print("test_a_fight_is_not_stuck: %d FAILURE(S)" % failures)
	quit(1 if failures > 0 else 0)
