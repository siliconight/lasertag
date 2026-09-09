extends SceneTree
## Who collides with whom (roadmap 124).
##
##     godot --headless --path . \
##       -s res://addons/laser_tag_tool/runners/tests/test_body_collision_rules.gd
##
## THE RULES, as stated by the design:
##   - players do NOT collide with each other
##   - players do NOT collide with corpses
##   - players DO collide with enemies, while those enemies are alive
##
## The evaluation bot walked into a dead enemy 0.8 m from its next path point
## and stood there for the rest of the run -- 76 of 79 stuck events on
## market_row_001 in a single 3 m cell. `_on_died` stopped the movement
## component and left the collider on `LAYER_ENEMY` forever, and the navmesh is
## baked before anyone dies, so nothing in the path knew a body had arrived.
##
## Leaving the layer settles three things, because they were one cause: bodies
## stop colliding with it, `LT_LineOfSightTester` stops treating it as an
## occluder (it masks `LASER_HIT_MASK`, which includes `LAYER_ENEMY`), and
## `LT_Shooter` stops recording a ray that lands on it as `ENEMY_HIT` -- a
## corpse still carries an `LT_Health`, so shots absorbed by one were counted
## as hits while `apply_hit` early-returned on `is_dead`.

var failures: int = 0


func check(condition: bool, label: String) -> void:
	if condition:
		print("  ok: " + label)
	else:
		failures += 1
		print("  FAIL: " + label)


func _init() -> void:
	# The pill's controller reads these on _ready; the harness normally
	# registers them, and without it the load is a wall of InputMap errors.
	LT_Const.ensure_input_actions()

	print("[1] the player pill's mask")
	var pill_scene: PackedScene = load("res://addons/laser_tag_tool/scenes/LT_PlayerPill.tscn")
	var player: Node = pill_scene.instantiate()
	get_root().add_child(player)
	await process_frame
	var pmask: int = (player as CollisionObject3D).collision_mask
	check(pmask & LT_Const.LAYER_PLAYER == 0,
		"players do not collide with each other (mask %d excludes PLAYER)" % pmask)
	check(pmask & LT_Const.LAYER_ENEMY != 0,
		"players do collide with enemies")
	check(pmask & LT_Const.LAYER_WORLD != 0,
		"players still collide with the world")

	print("[2] an enemy is solid while it is alive")
	var enemy_scene: PackedScene = load("res://addons/laser_tag_tool/scenes/LT_EnemyPill.tscn")
	var enemy: Node = enemy_scene.instantiate()
	get_root().add_child(enemy)
	await process_frame
	var body: CollisionObject3D = enemy as CollisionObject3D
	check(body.collision_layer & LT_Const.LAYER_ENEMY != 0,
		"a live enemy is on LAYER_ENEMY, so the player's mask catches it")

	print("[3] a corpse is not a wall")
	var health: LT_Health = enemy.get_node("LT_Health")
	var guard := 0
	while not health.is_dead and guard < 50:
		guard += 1
		health.apply_hit(1)
	check(health.is_dead, "the enemy died after %d hit(s)" % guard)
	await process_frame
	await process_frame
	check(body.collision_layer == 0,
		"a dead enemy leaves every layer (was %d)" % body.collision_layer)
	check(body.collision_layer & LT_Const.LAYER_ENEMY == 0,
		"so nothing masking LAYER_ENEMY collides with it, sees it as an "
		+ "occluder, or scores a hit on it")

	player.queue_free()
	enemy.queue_free()
	if failures == 0:
		print("PASS: players pass through each other and through corpses")
		quit(0)
	else:
		print("FAIL: %d check(s)" % failures)
		quit(1)
