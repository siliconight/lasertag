extends SceneTree
## The bot keeps to the mesh it plans on (0.29.0, factory roadmap 242).
##
## The bot turns toward its next path point once within its arrival radius,
## about 0.44 m (`LT_Const.arrival_radius`), and the straight line from there
## to a point round a corner cuts the corner: off the navmesh, into the 0.4 m
## the contract's bake keeps from every collider, where the 0.35 m body has
## 5 cm to spare. So it met corners it was routed round, and on restaurant_row_
## 001 one engine pinned it there for good -- 64 of a candidate's 72 player-
## stuck events at one deli counter's corner (the factory's
## `docs/findings/route_snag/`); the other engine pinned it at other corners.
##
## Each case walks the real LT_PlayerPill, the contract's capsule, round a
## counter-sized box (6 x 0.9 x 1.1 m) on a navmesh baked at the contract's
## numbers (`run_map_eval.gd`'s NAV_*), and records how near the body's axis
## came to the box in plan:
##   [1] the box's corner, the route turning round it: the axis keeps within
##       2 cm of the clearance the mesh keeps (NAV_AGENT_RADIUS, 0.4 m) -- the
##       body stays on the mesh it planned on and never nears what the mesh
##       was eroded from. FAILS ON 0.28.1: its axis came 0.359 m from the box,
##       4 cm into the 5 cm the mesh leaves the 0.35 m body.
##   [2] the CONTROL: the same route with the box moved 5 m aside, nothing to
##       turn round -- the body arrives either way, so the scene, the bake and
##       the walk can pass.
##   [3] the route arrives round the corner too: keeping to the mesh does not
##       stop the walk.
##
## Run:  godot --headless --path lasertag -s res://addons/laser_tag_tool/runners/tests/test_bot_keeps_to_the_mesh.gd

const Runner := preload("res://addons/laser_tag_tool/runners/run_map_eval.gd")
const RADIUS: float = 0.35
const HEIGHT: float = 1.8
const FRAMES: int = 600
const BOX := Vector3(6.0, 1.1, 0.9)

var failures: int = 0


func check(condition: bool, label: String) -> void:
	if condition:
		print("  ok: " + label)
	else:
		failures += 1
		print("  FAIL: " + label)


func _solid(size: Vector3, at: Vector3) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = LT_Const.LAYER_WORLD
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	sb.add_child(cs)
	sb.position = at
	return sb


## The nearest the axis came to the box's plan rectangle, in metres.
func _plan_gap(p: Vector3, centre: Vector3) -> float:
	var dx: float = maxf(absf(p.x - centre.x) - BOX.x * 0.5, 0.0)
	var dz: float = maxf(absf(p.z - centre.z) - BOX.z * 0.5, 0.0)
	return sqrt(dx * dx + dz * dz)


## Walk the real pill from `start` to `target` round a box at `centre`, on a
## navmesh baked at the contract's numbers. Returns [nearest gap, completed,
## end position].
func _walk(centre: Vector3, start: Vector3, target: Vector3) -> Array:
	var world := Node3D.new()
	get_root().add_child(world)
	world.add_child(_solid(Vector3(40.0, 0.2, 40.0), Vector3(0.0, -0.1, 0.0)))
	world.add_child(_solid(BOX, centre + Vector3(0.0, BOX.y * 0.5, 0.0)))
	var region := NavigationRegion3D.new()
	world.add_child(region)
	await physics_frame
	LT_Const.synchronous_navigation(world)
	var nav := NavigationMesh.new()
	nav.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav.geometry_collision_mask = 1
	nav.agent_radius = Runner.NAV_AGENT_RADIUS
	nav.agent_height = Runner.NAV_AGENT_HEIGHT
	nav.agent_max_climb = Runner.NAV_AGENT_MAX_CLIMB
	nav.agent_max_slope = Runner.NAV_AGENT_MAX_SLOPE
	nav.cell_size = Runner.NAV_CELL_SIZE
	nav.cell_height = Runner.NAV_CELL_HEIGHT
	NavigationServer3D.map_set_cell_size(region.get_navigation_map(), Runner.NAV_CELL_SIZE)
	NavigationServer3D.map_set_cell_height(region.get_navigation_map(), Runner.NAV_CELL_HEIGHT)
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nav, source, world)
	NavigationServer3D.bake_from_source_geometry_data(nav, source)
	region.navigation_mesh = nav
	for i in 3:
		await physics_frame
	var pill_scene: PackedScene = load("res://addons/laser_tag_tool/scenes/LT_PlayerPill.tscn")
	var pill: CharacterBody3D = pill_scene.instantiate()
	world.add_child(pill)
	var shape_node: CollisionShape3D = pill.get_node("CollisionShape3D")
	var cap: CapsuleShape3D = (shape_node.shape as CapsuleShape3D).duplicate()
	cap.radius = RADIUS
	cap.height = HEIGHT
	shape_node.shape = cap
	shape_node.position.y = HEIGHT * 0.5
	var manual: Node = pill.get_node("LT_PlayerController")
	manual.set_physics_process(false)
	manual.set_process_unhandled_input(false)
	var agent: NavigationAgent3D = pill.get_node("NavigationAgent3D")
	agent.radius = RADIUS
	agent.height = HEIGHT
	var bot: LT_BotPlayerController = pill.get_node("LT_BotPlayerController")
	bot.use_navigation = true
	bot.move_speed = 4.0
	bot.max_step_up = 0.5
	pill.global_position = start
	await physics_frame
	var route: Array[Vector3] = [target]
	bot.start_route(route)
	var nearest: float = INF
	for i in FRAMES:
		await physics_frame
		nearest = minf(nearest, _plan_gap(pill.global_position, centre))
		if bot._completed:
			break
	var out: Array = [nearest, bot._completed, pill.global_position]
	world.queue_free()
	await process_frame
	return out


func _report(label: String, r: Array) -> void:
	var p: Vector3 = r[2]
	print("     %s: nearest the box %.3f m (the body's radius %.2f), completed %s, at (%.2f, %.2f, %.2f)"
		% [label, float(r[0]), RADIUS, str(r[1]), p.x, p.y, p.z])


func _on_watchdog() -> void:
	print("test_bot_keeps_to_the_mesh: WATCHDOG -- no verdict in 120 s")
	quit(2)


func _init() -> void:
	create_timer(120.0).timeout.connect(_on_watchdog)
	LT_Const.ensure_input_actions()
	# From north-west of the box's west end to south of it: the route turns
	# round the corner at x -3, z +0.45.
	var start := Vector3(-5.5, 0.0, -2.5)
	var target := Vector3(-1.5, 0.0, 2.5)

	print("[1] round a counter's corner")
	var a: Array = await _walk(Vector3.ZERO, start, target)
	_report("round the corner", a)
	check(float(a[0]) >= Runner.NAV_AGENT_RADIUS - 0.02,
		"the body's axis keeps within 2 cm of the mesh's own clearance from the box (%.2f m)"
		% Runner.NAV_AGENT_RADIUS)

	print("[2] the control: the box 5 m aside, nothing to turn round")
	var b: Array = await _walk(Vector3(0.0, 0.0, 6.5), start, target)
	_report("no corner", b)
	check(bool(b[1]), "the walk arrives with nothing in the way: the scene, the bake and the body can pass")

	print("[3] round the corner, the walk still arrives")
	check(bool(a[1]), "keeping to the mesh does not stop the walk round the corner")

	print("test_bot_keeps_to_the_mesh: %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(1 if failures else 0)
