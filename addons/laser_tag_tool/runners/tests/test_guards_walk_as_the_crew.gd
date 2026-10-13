extends SceneTree
## The guards walk as the crew does (0.31.0, factory roadmap 242).
##
## The crew bot steps up as the contract's player does (0.24.0) and keeps to the mesh it plans on (0.29.0);
## the guards' `LT_EnemyMovement` did neither. Of the 23 EnemyStuck events Laser Tag 0.30.0 still counted on
## the factory's sixteen lots, 13 stood at one wall's end, a guard 5 cm off the mesh, and 8 against one stair
## ramp's open side 0.18 m up (`docs/findings/stoop_breadth/`). `agent_contract.json`'s npc_standard shares
## the player's metrics, so the guard now walks by the crew's rules, `LT_Steering`'s one copy.
##
## Each case walks the real LT_EnemyPill -- the contract's capsule, its brain taken out so nothing but the
## movement drives it -- over real colliders:
##   [1] round a counter-sized box's corner on a navmesh baked at the contract's numbers: the guard's axis
##       keeps within 2 cm of the mesh's clearance from the box (0.4 m). FAILS ON 0.30.0.
##   [2] the CONTROL: the box 5 m aside, nothing to turn round -- the guard arrives, so the scene, the bake
##       and the walk can pass.
##   [3] round the corner, the guard still arrives: keeping to the mesh does not stop it.
##   [4] a 37.9 degree ramp met from its open side, as the crew's test meets it: the guard steps on, walks
##       across it and arrives standing on it. FAILS ON 0.30.0.
##   [5] the CONTROL: a 0.08 m step, under the unassisted line -- walked, and no step taken.
##   [6] a 0.6 m box, over the contract's 0.5: not climbed, no step taken.
##   [7] the harness gives a guard the scenario's step (`player_max_step_up_m`), as it gives the crew. FAILS
##       ON 0.30.0.
## On 0.30.0 the cases still run to their checks, asked rather than assumed (`in`), and fail there.
##
## Run:  godot --headless --path lasertag -s res://addons/laser_tag_tool/runners/tests/test_guards_walk_as_the_crew.gd

const Runner := preload("res://addons/laser_tag_tool/runners/run_map_eval.gd")
const RADIUS: float = 0.35
const HEIGHT: float = 1.8
const BOX := Vector3(6.0, 1.1, 0.9)

var failures: int = 0


func check(condition: bool, label: String) -> void:
	if condition:
		print("  ok: " + label)
	else:
		failures += 1
		print("  FAIL: " + label)


func _solid(shape: Shape3D, at: Vector3) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = LT_Const.LAYER_WORLD
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	sb.add_child(cs)
	sb.position = at
	return sb


func _box(size: Vector3, at: Vector3) -> StaticBody3D:
	var b := BoxShape3D.new()
	b.size = size
	return _solid(b, at)


## A wedge rising along +X from height 0 at x = 0 to `rise` at x = `run`, `width` deep in Z from z = 0,
## placed at `at`: a flight's smooth ramp, the crew's test's own.
func _wedge(run: float, rise: float, width: float, at: Vector3) -> StaticBody3D:
	var w := ConvexPolygonShape3D.new()
	w.points = PackedVector3Array([
		Vector3(0.0, 0.0, 0.0), Vector3(run, 0.0, 0.0), Vector3(run, rise, 0.0),
		Vector3(0.0, 0.0, width), Vector3(run, 0.0, width), Vector3(run, rise, width)])
	return _solid(w, at)


## The nearest the axis came to the box's plan rectangle, in metres.
func _plan_gap(p: Vector3, centre: Vector3) -> float:
	var dx: float = maxf(absf(p.x - centre.x) - BOX.x * 0.5, 0.0)
	var dz: float = maxf(absf(p.z - centre.z) - BOX.z * 0.5, 0.0)
	return sqrt(dx * dx + dz * dz)


## The real enemy pill as the harness builds its body -- the contract's capsule, origin at the feet --
## with its brain and the brain's label taken out, so only `LT_EnemyMovement` moves it.
func _guard() -> CharacterBody3D:
	var scene: PackedScene = load("res://addons/laser_tag_tool/scenes/LT_EnemyPill.tscn")
	var pill: CharacterBody3D = scene.instantiate()
	pill.get_node("LT_EnemyBrain").free()
	pill.get_node("LT_EnemyLabel").free()
	var shape_node: CollisionShape3D = pill.get_node("CollisionShape3D")
	var cap: CapsuleShape3D = (shape_node.shape as CapsuleShape3D).duplicate()
	cap.radius = RADIUS
	cap.height = HEIGHT
	shape_node.shape = cap
	shape_node.position.y = HEIGHT * 0.5
	var agent: NavigationAgent3D = pill.get_node("NavigationAgent3D")
	agent.radius = RADIUS
	agent.height = HEIGHT
	return pill


func _steps(movement: Node) -> int:
	return int(movement.get("steps_taken")) if "steps_taken" in movement else 0


## Walk a guard from `start` to `target` round a box at `centre`, on a navmesh baked at the contract's
## numbers (`run_map_eval.gd`'s NAV_*). Returns [nearest gap, arrived, end position].
func _walk_nav(centre: Vector3, start: Vector3, target: Vector3, frames: int) -> Array:
	var world := Node3D.new()
	get_root().add_child(world)
	world.add_child(_box(Vector3(40.0, 0.2, 40.0), Vector3(0.0, -0.1, 0.0)))
	world.add_child(_box(BOX, centre + Vector3(0.0, BOX.y * 0.5, 0.0)))
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
	var pill: CharacterBody3D = _guard()
	world.add_child(pill)
	var movement: LT_EnemyMovement = pill.get_node("LT_EnemyMovement")
	movement.use_navigation = true
	movement.move_speed = 4.0
	pill.global_position = start
	await physics_frame
	movement.set_destination(target)
	var nearest: float = INF
	var arrived: bool = false
	for i in frames:
		await physics_frame
		nearest = minf(nearest, _plan_gap(pill.global_position, centre))
		if movement.is_navigation_finished():
			arrived = true
			break
	var out: Array = [nearest, arrived, pill.global_position]
	world.queue_free()
	await process_frame
	return out


## Walk a guard straight at `target` with no navigation, past `obstacle`. Returns [position, arrived, steps].
func _walk_direct(obstacle: StaticBody3D, start: Vector3, target: Vector3, frames: int) -> Array:
	var world := Node3D.new()
	get_root().add_child(world)
	world.add_child(_box(Vector3(40.0, 0.2, 40.0), Vector3(0.0, -0.1, 0.0)))
	world.add_child(obstacle)
	var pill: CharacterBody3D = _guard()
	world.add_child(pill)
	var movement: LT_EnemyMovement = pill.get_node("LT_EnemyMovement")
	movement.use_navigation = false
	movement.move_speed = 4.0
	if "max_step_up" in movement:
		movement.set("max_step_up", 0.5)
	pill.global_position = start
	await physics_frame
	movement.set_destination(target)
	var arrived: bool = false
	for i in frames:
		await physics_frame
		if movement.is_navigation_finished():
			arrived = true
			break
	var out: Array = [pill.global_position, arrived, _steps(movement)]
	world.queue_free()
	await process_frame
	return out


func _report_nav(label: String, r: Array) -> void:
	var p: Vector3 = r[2]
	print("     %s: nearest the box %.3f m (the body's radius %.2f), arrived %s, at (%.2f, %.2f, %.2f)"
		% [label, float(r[0]), RADIUS, str(r[1]), p.x, p.y, p.z])


func _report_direct(label: String, r: Array) -> void:
	var p: Vector3 = r[0]
	print("     %s: at (%.2f, %.3f, %.2f), arrived %s, steps %d" % [label, p.x, p.y, p.z, str(r[1]), int(r[2])])


func _on_watchdog() -> void:
	print("test_guards_walk_as_the_crew: WATCHDOG -- no verdict in 180 s")
	quit(2)


func _init() -> void:
	create_timer(180.0).timeout.connect(_on_watchdog)
	LT_Const.ensure_input_actions()
	# the crew's corner: from north-west of the box's west end to south of it, the route turning round
	# the corner at x -3, z +0.45
	var start := Vector3(-5.5, 0.0, -2.5)
	var target := Vector3(-1.5, 0.0, 2.5)

	print("[1] round a counter's corner")
	var a: Array = await _walk_nav(Vector3.ZERO, start, target, 600)
	_report_nav("round the corner", a)
	check(float(a[0]) >= Runner.NAV_AGENT_RADIUS - 0.02,
		"the guard's axis keeps within 2 cm of the mesh's own clearance from the box (%.2f m)"
		% Runner.NAV_AGENT_RADIUS)

	print("[2] the control: the box 5 m aside, nothing to turn round")
	var b: Array = await _walk_nav(Vector3(0.0, 0.0, 6.5), start, target, 600)
	_report_nav("no corner", b)
	check(bool(b[1]), "the guard arrives with nothing in the way: the scene, the bake and the walk can pass")

	print("[3] round the corner, the guard still arrives")
	check(bool(a[1]), "keeping to the mesh does not stop the guard round the corner")

	print("[4] a 37.9 degree ramp met from its open side")
	# the crew's case [3]: 4.2 m over 5.4 m, met across its 3 m width at x = 0.25 where its top stands
	# 0.195 m, the target 2.6 m in, so the guard must step on, cross the slope and arrive standing on it
	var c: Array = await _walk_direct(_wedge(5.4, 4.2, 3.0, Vector3.ZERO),
		Vector3(0.25, 0.02, -2.0), Vector3(0.25, 0.195, 2.6), 360)
	_report_direct("ramp", c)
	var c_at: Vector3 = c[0]
	var pitch: float = atan(4.2 / 5.4)
	var top_h: float = c_at.x * 4.2 / 5.4
	var stand_h: float = top_h + RADIUS * (1.0 / cos(pitch) - 1.0)
	check(int(c[2]) >= 1 and c_at.z > 1.0, "the guard steps onto the ramp and walks across it (z %.2f)" % c_at.z)
	check(absf(c_at.y - stand_h) < 0.03,
		("and it is STANDING on the ramp: feet at y %.3f, where a capsule resting there stands at %.3f"
		+ " (the top's %.3f plus r(1/cos - 1))") % [c_at.y, stand_h, top_h])

	print("[5] the control: a 0.08 m step, under the unassisted line")
	var d: Array = await _walk_direct(_box(Vector3(4.0, 0.08, 4.0), Vector3(3.0, 0.04, 0.0)),
		Vector3(0.0, 0.02, 0.0), Vector3(4.0, 0.08, 0.0), 360)
	_report_direct("0.08 m", d)
	check(bool(d[1]) and (d[0] as Vector3).y > 0.05 and int(d[2]) == 0,
		"the guard walks onto 0.08 m and takes no step it does not need")

	print("[6] a 0.6 m box, over the contract's 0.5")
	var e: Array = await _walk_direct(_box(Vector3(4.0, 0.6, 4.0), Vector3(3.0, 0.3, 0.0)),
		Vector3(0.0, 0.02, 0.0), Vector3(4.0, 0.6, 0.0), 360)
	_report_direct("0.6 m", e)
	check(not bool(e[1]) and (e[0] as Vector3).y < 0.05 and int(e[2]) == 0,
		"too tall to step: not climbed, and no step taken")

	print("[7] the harness gives a guard the scenario's step")
	var harness := LT_MapEvalHarness.new()
	harness.scenario = LT_TestScenario.new()
	harness.scenario.player_max_step_up_m = 0.37
	var pill: CharacterBody3D = _guard()
	harness._apply_body(pill)
	var movement: Node = pill.get_node("LT_EnemyMovement")
	var given: float = float(movement.get("max_step_up")) if "max_step_up" in movement else -1.0
	check(absf(given - 0.37) < 1e-6, "the guard's step is the scenario's 0.37 (%.2f)" % given)
	pill.free()
	harness.free()

	print("test_guards_walk_as_the_crew: %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(1 if failures else 0)
