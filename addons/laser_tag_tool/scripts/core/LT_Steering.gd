extends RefCounted
class_name LT_Steering
## How a body of the contract walks the mesh it plans on: the crew bot's and the guards' one copy
## (0.31.0, factory roadmap 242).
##
## The crew bot learned to step up as the contract's player does (0.24.0, roadmap 203) and to keep to
## the mesh it plans on (0.29.0, roadmap 242), each in `LT_BotPlayerController`, and the guards'
## `LT_EnemyMovement` learned neither. So the guards met what the crew had stopped meeting: of the 23
## EnemyStuck events Laser Tag 0.30.0 still counted on the factory's sixteen lots, 13 stood at one wall's
## end, a guard 5 cm off the mesh, and 8 against one stair ramp's open side 0.18 m up (the factory's
## `docs/findings/stoop_breadth/`, "The 23 Laser Tag 0.30.0 still counts"). `agent_contract.json` says
## npc_standard shares the player's metrics until a distinct class ships, so a guard is the crew's body
## and walks by the crew's rules -- kept here once, so a body's next lesson is both bodies'.

## THE BODY KEEPS TO THE MESH IT PLANS ON (0.29.0, factory roadmap 242).
## How far the end of a step may sit from the mesh before it is turned back
## onto it: a centimetre, against the 5 cm the contract's bake (0.4 m) leaves
## the 0.35 m body. A tolerance for the closest-point query's own rounding,
## not a clearance.
const MESH_TOLERANCE_M: float = 0.01
## A nearest mesh point more than this above or below the step's end is on
## another level -- a floor above, a ramp's far side -- and not the step's to
## judge: the contract's step (`player_max_step_up_m`, 0.5).
const MESH_LEVEL_M: float = 0.5

## How far past the body the step probe looks, and how far above the limit it
## starts, so a top exactly at `max_step_up` is found. A tolerance, not a
## derivation: a top narrower than this is not one a body can stand on.
const STEP_PROBE_MARGIN: float = 0.05
## A rise below this is the floor's own unevenness, not a step.
const STEP_MIN_RISE: float = 0.01
## How squarely the wall must face the walk (cos of 72.5 deg). A wall the bot
## slides along at a shallower angle is not in its way.
const STEP_FACING_DOT: float = 0.3


## THE BODY KEEPS TO THE MESH IT PLANS ON (0.29.0, factory roadmap 242).
## A body turns toward its next path point once within its arrival radius,
## about 0.44 m (`LT_Const.arrival_radius`), and the straight line from there
## to a point round a corner cuts the corner: off the mesh, into the 0.4 m the
## contract's bake keeps from every collider, where the 0.35 m body has 5 cm.
## Measured in the factory (`docs/findings/route_snag/`): on restaurant_row_001
## 64 of a candidate's 72 player-stuck events stood at one deli counter's
## corner, pinned by Godot Physics; across sixteen lots Jolt pinned bodies at
## other corners. So a step whose end leaves the mesh is turned toward the
## mesh's nearest point to that end, at no more than the speed it had: the
## body slides along the mesh's edge round the corner at the bake's clearance.
## `velocity` is horizontal; what comes back is too. A body walking without
## navigation is its caller's to leave be.
static func velocity_on_mesh(body: CharacterBody3D, nav_agent: NavigationAgent3D,
		velocity: Vector3, delta: float) -> Vector3:
	if nav_agent == null or delta <= 0.0:
		return velocity
	var map: RID = nav_agent.get_navigation_map()
	if not map.is_valid() or NavigationServer3D.map_get_iteration_id(map) == 0:
		return velocity
	var here: Vector3 = body.global_position
	var want: Vector3 = here + Vector3(velocity.x, 0.0, velocity.z) * delta
	# the mesh sits a cell above the floor the feet stand on (`path_height_offset`)
	var lift: float = NavigationServer3D.map_get_cell_height(map)
	var on: Vector3 = NavigationServer3D.map_get_closest_point(map, want + Vector3.UP * lift)
	if absf(on.y - lift - want.y) > MESH_LEVEL_M:
		return velocity
	if Vector2(on.x - want.x, on.z - want.z).length() <= MESH_TOLERANCE_M:
		return velocity
	var to_mesh: Vector3 = Vector3(on.x - here.x, 0.0, on.z - here.z) / delta
	var speed: float = Vector2(velocity.x, velocity.z).length()
	if to_mesh.length() > speed:
		to_mesh = to_mesh.normalized() * speed
	return to_mesh


## A STEP, NEVER A SLOPE (0.24.0, roadmap 203).
##
## The lift is the height of a TOP the body can stand on: a surface found
## straight down, a body-width ahead, whose normal is within the body's own
## `floor_max_angle`. On a continuous incline a probe ahead always finds a
## higher surface, so a lift sized by the probe would throw the body up a ramp
## it cannot stand on (CLAUDE.md, "Step-up cannot rescue a slope"). The step is
## taken only when the lift and the move onto the top both clear the world.
## Called right after `move_and_slide` with the way the body MEANT to go, before
## the slide turned it along whatever it hit. True when the body stepped; the
## caller counts it.
static func try_step_up(body: CharacterBody3D, nav_agent: NavigationAgent3D,
		intended: Vector3, max_step_up: float) -> bool:
	if max_step_up <= 0.0 or not body.is_on_floor() or not body.is_on_wall():
		return false
	if intended.length() < 0.1:
		return false
	var fwd: Vector3 = intended.normalized()
	if body.get_wall_normal().dot(fwd) > -STEP_FACING_DOT:
		return false
	var reach: float = body_radius(body, nav_agent) + STEP_PROBE_MARGIN
	var feet: Vector3 = body.global_position
	var probe: Vector3 = feet + fwd * reach
	var excl: Array[RID] = [body.get_rid()]
	var query := PhysicsRayQueryParameters3D.create(
		probe + Vector3.UP * (max_step_up + STEP_PROBE_MARGIN),
		probe + Vector3.DOWN * STEP_PROBE_MARGIN, LT_Const.LAYER_WORLD, excl)
	var hit: Dictionary = body.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	var top: Vector3 = hit["position"]
	var normal: Vector3 = hit["normal"]
	var rise: float = top.y - feet.y
	if rise <= STEP_MIN_RISE or rise > max_step_up:
		return false
	if normal.angle_to(Vector3.UP) > body.floor_max_angle:
		return false
	# THE TOP'S HEIGHT FIRST, THE FULL LIFT SECOND. A top that rises ACROSS the
	# walk -- a stair ramp met from its open side, the bank's case -- stands
	# higher under the capsule's uphill side than under its centre, so a lift
	# sized to the centre leaves that side inside the ramp and the move refuses
	# it. The contract's full lift is tried before giving up: the body still
	# lands on the top it was cleared for, and never above max_step_up.
	var lifts: Array[float] = [rise + STEP_PROBE_MARGIN, max_step_up + STEP_PROBE_MARGIN]
	for lift_height: float in lifts:
		var lift: Vector3 = Vector3.UP * lift_height
		if body.test_move(body.global_transform, lift):
			continue
		if body.test_move(body.global_transform.translated(lift), fwd * reach):
			continue
		body.global_position = feet + lift + fwd * reach
		body.velocity.y = 0.0
		return true
	return false


## The body's radius: its capsule's, else the agent's, else the contract's.
static func body_radius(body: CharacterBody3D, nav_agent: NavigationAgent3D) -> float:
	var shape_node := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node != null and shape_node.shape is CapsuleShape3D:
		return (shape_node.shape as CapsuleShape3D).radius
	return nav_agent.radius if nav_agent != null else 0.35
