extends SceneTree
## Headless regression test for pill node-reference wiring (TDD §7.2).
##
## Guards the CI-BROKEN bug where typed @export NodePaths in the pill
## .tscn files loaded as null under a version-mismatched scene, leaving
## enemies inert (movement/eye null) and nobody able to fire (shooter or
## muzzle null). Each pill now re-resolves its own references in _ready();
## this test fails loudly if that ever stops working.
##
## Usage:
##   godot --headless --path . \
##     -s res://addons/laser_tag_tool/runners/test_pill_wiring.gd
##
## Exit code 0 = all checks passed, 1 = at least one failed.

const ENEMY_PILL := preload("../scenes/LT_EnemyPill.tscn")
const PLAYER_PILL := preload("../scenes/LT_PlayerPill.tscn")

var _failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_build_floor()

	# --- Enemy pill wiring ---
	var enemy: CharacterBody3D = ENEMY_PILL.instantiate()
	root.add_child(enemy)
	enemy.global_position = Vector3(0.0, 0.5, 0.0)
	await physics_frame

	var brain: LT_EnemyBrain = enemy.get_node("LT_EnemyBrain")
	var movement: LT_EnemyMovement = enemy.get_node("LT_EnemyMovement")
	var enemy_shooter: LT_Shooter = enemy.get_node("LT_Shooter")
	_check(brain.movement != null, "enemy brain.movement resolved")
	_check(brain.shooter != null, "enemy brain.shooter resolved")
	_check(brain.eye != null, "enemy brain.eye resolved")
	_check(enemy_shooter.muzzle != null, "enemy shooter.muzzle resolved")

	# --- Enemy actually moves toward a destination in fallback mode ---
	brain.set_physics_process(false)  # keep the brain from clearing the target
	movement.use_navigation = false
	var start: Vector3 = enemy.global_position
	movement.set_destination(start + Vector3(10.0, 0.0, 0.0))
	for _i in 40:
		await physics_frame
	var moved: Vector3 = enemy.global_position - start
	moved.y = 0.0
	_check(moved.length() > 1.0,
		"enemy walked toward destination (moved %.2fm)" % moved.length())

	# --- Bot pill wiring ---
	var bot_pill: CharacterBody3D = PLAYER_PILL.instantiate()
	root.add_child(bot_pill)
	bot_pill.global_position = Vector3(5.0, 0.5, 0.0)
	await physics_frame
	var bot: LT_BotPlayerController = bot_pill.get_node("LT_BotPlayerController")
	var bot_shooter: LT_Shooter = bot_pill.get_node("LT_Shooter")
	_check(bot.shooter != null, "bot shooter resolved")
	_check(bot_shooter.muzzle != null, "bot shooter.muzzle resolved")

	print("")
	if _failures == 0:
		print("[LT test] PASS — pill wiring intact")
		quit(0)
	else:
		print("[LT test] FAIL — %d check(s) failed" % _failures)
		quit(1)

func _build_floor() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 1.0, 60.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	root.add_child(floor_body)

func _check(condition: bool, label: String) -> void:
	if condition:
		print("[LT test] ok   — %s" % label)
	else:
		_failures += 1
		print("[LT test] FAIL — %s" % label)
