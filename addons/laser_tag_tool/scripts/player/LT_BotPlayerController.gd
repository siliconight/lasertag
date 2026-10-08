extends Node
class_name LT_BotPlayerController
## Bot player for headless evaluation (TDD §16).
## Useful, not clever: walk the route, shoot what it can see, take cover
## when hurt, report when stuck. No wallhacks, no perfect aim.

signal route_completed
signal bot_stuck(position: Vector3)

@export var body: CharacterBody3D
@export var shooter: LT_Shooter
@export var nav_agent: NavigationAgent3D

@export var move_speed: float = 4.5
@export var fire_cooldown: float = 0.7
@export var sight_range: float = 45.0
## Aim error in degrees — keeps the bot honest (TDD §16.3).
@export var aim_error_degrees: float = 2.5
## After taking this many hits in a short window, seek a cover point.
@export var cover_seek_hit_threshold: int = 2
## How far the bot will travel to reach cover, in metres. Cover further than
## this is not cover; it is a destination, and walking to it under fire is
## worse than holding the route.
##
## Measured on category5_baie_dore_001 seed 5017: the crew spawns at (-29, 0),
## the nearest of the four cover points is 69.4 m away, and every one of them
## sits 10.8-19.3 m from an enemy spawn because they are all clustered at the
## objective. Taking two hits sent the bot on a 69 m walk toward the enemies
## that it had no chance of finishing -- it died at 11.9 s having fired twice.
## Unbounded "nearest cover" is only sane when cover exists near the crew, and
## whether it does is exactly what the evaluation is supposed to find out.
##
## When nothing is in range the bot keeps its route rather than pretending to
## take cover, so the map is marked down for having none within reach instead
## of the harness hiding it.
@export var cover_seek_max_distance: float = 25.0
## Advance the route WHILE engaging, instead of stopping to shoot
## (roadmap 121). False is the original behaviour and the default.
@export var advance_while_engaging: bool = false
## Fraction of `move_speed` kept while engaging, when the above is on.
@export var engaged_move_speed_scale: float = 0.5

@export var use_navigation: bool = true

@export var stuck_window_seconds: float = 4.0
@export var stuck_distance_threshold: float = 0.5

## THE CONTRACT'S STEP-UP (0.24.0, roadmap 203). `characters.player.
## max_step_up_m` in `deli_counter/agent_contract.json` is 0.5: the player's
## controller lifts itself over a step that tall, and a transition above
## `clearances.unassisted_step_max_m` (0.1025, what a stock capsule walks over)
## "requires the consumer to have implemented step-up". This bot implemented
## none, and the navmesh routes over anything up to `agent_max_climb_m` (0.15),
## so it stopped where the contract's player walks on. Measured on cold run
## 9194: bank_branch_a04's crew wedged against a stair ramp's open side 0.118 m
## high -- 1,302 of 1,306 stuck events in one 2 m cell, route completion 8% --
## while the walktest's walker, which steps, walked past it. The harness sets
## this from the scenario (`player_max_step_up_m`), which Level Factory fills
## from the contract. 0 turns step-up off.
@export var max_step_up: float = 0.5
## Step-ups taken: what the step-up did, for a reader of a run.
var steps_taken: int = 0

## How far past the body the step probe looks, and how far above the limit it
## starts, so a top exactly at `max_step_up` is found. A tolerance, not a
## derivation: a top narrower than this is not one a body can stand on.
const STEP_PROBE_MARGIN: float = 0.05
## A rise below this is the floor's own unevenness, not a step.
const STEP_MIN_RISE: float = 0.01
## How squarely the wall must face the walk (cos of 72.5 deg). A wall the bot
## slides along at a shallower angle is not in its way.
const STEP_FACING_DOT: float = 0.3

var route_points: Array[Vector3] = []
var cover_points: Array[Vector3] = []

var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))

var _route_index: int = 0
## Route points genuinely ARRIVED at, which is not the same as `_route_index`.
## `_update_stuck` advances the index to move a jammed bot along, so the index
## counts points SKIPPED as well as reached and cannot answer "how far did the
## crew get" (roadmap 128). This only ever increments on a real arrival.
var _route_reached: int = 0
## 1 when the route's first point IS the spawn, so arriving at it is free.
## Lot emits `Route_0` at the crew spawn exactly -- measured 0.00 m apart on
## restaurant_row_001 -- so counting points reached gave every run 1 of 3 for
## standing still, including a crew wiped at 3.4 seconds. Progress is counted
## in LEGS WALKED, and this is how many the route starts you with.
var _route_free_start: int = 0
var _route_points_dirty: bool = true
var _fire_timer: float = 0.0
var _dead: bool = false
var _recent_hits: int = 0
var _recent_hit_timer: float = 0.0
var _seeking_cover: bool = false
var _stuck_timer: float = 0.0
var _stuck_anchor: Vector3 = Vector3.ZERO
var _completed: bool = false

func _ready() -> void:
	if body == null and get_parent() is CharacterBody3D:
		body = get_parent()
	if nav_agent == null and body != null and body.has_node("NavigationAgent3D"):
		nav_agent = body.get_node("NavigationAgent3D")
	# See LT_EnemyBrain._ready(): typed @export NodePaths can load null under
	# a version-mismatched scene; re-resolve so the bot can actually fire.
	if shooter == null and body != null and body.has_node("LT_Shooter"):
		shooter = body.get_node("LT_Shooter")
	if body != null:
		_stuck_anchor = body.global_position
		if body.has_node("LT_Health"):
			var health: LT_Health = body.get_node("LT_Health")
			health.damaged.connect(_on_damaged)
			health.died.connect(func() -> void: _dead = true)

func start_route(points: Array[Vector3], covers: Array[Vector3] = []) -> void:
	_align_agent_to_mesh()
	route_points = points
	cover_points = covers
	_route_index = 0
	_route_reached = 0
	_route_points_dirty = true
	_completed = false
	_go_to_current_route_point()

func _physics_process(delta: float) -> void:
	if body == null or _dead or _completed:
		return

	_fire_timer -= delta
	_recent_hit_timer -= delta
	if _recent_hit_timer <= 0.0:
		_recent_hits = 0

	var enemy := _find_visible_enemy()
	if enemy != null:
		# STAND AND FIGHT, or FIGHT AND MOVE (roadmap 121). The first is the
		# original and still the default: route progress and enemy presence
		# are then mutually exclusive, which is why `route_completion_rate`
		# reads zero on any map with live guards whatever the map looks like.
		#
		# Advancing first and scaling the velocity afterwards keeps ONE copy
		# of the routing logic -- `_advance_route` also steps the waypoint
		# index and emits `route_completed`, and a second movement path here
		# would be a second place for those to happen.
		#
		# Facing is applied AFTER, so the bot looks at what it is shooting
		# rather than where it is walking. Aim does not depend on it:
		# `_fire_at` aims at the enemy's chest directly.
		if advance_while_engaging:
			_advance_route(delta)
			body.velocity.x *= engaged_move_speed_scale
			body.velocity.z *= engaged_move_speed_scale
		else:
			_stop_horizontal()
		_face_point(enemy.global_position)
		if _fire_timer <= 0.0:
			_fire_at(enemy)
	else:
		_advance_route(delta)

	if not body.is_on_floor():
		body.velocity.y -= gravity * delta
	# The way the bot MEANT to go, before the slide turns it along whatever
	# it hit: the step-up asks about that wall, not about the slide.
	var intended := Vector3(body.velocity.x, 0.0, body.velocity.z)
	body.move_and_slide()
	_try_step_up(intended)
	_update_stuck(delta)

## A STEP, NEVER A SLOPE (0.24.0, roadmap 203).
##
## The lift is the height of a TOP the body can stand on: a surface found
## straight down, a body-width ahead, whose normal is within the body's own
## `floor_max_angle`. On a continuous incline a probe ahead always finds a
## higher surface, so a lift sized by the probe would throw the body up a ramp
## it cannot stand on (CLAUDE.md, "Step-up cannot rescue a slope"). The step is
## taken only when the lift and the move onto the top both clear the world.
func _try_step_up(intended: Vector3) -> bool:
	if max_step_up <= 0.0 or not body.is_on_floor() or not body.is_on_wall():
		return false
	if intended.length() < 0.1:
		return false
	var fwd: Vector3 = intended.normalized()
	if body.get_wall_normal().dot(fwd) > -STEP_FACING_DOT:
		return false
	var reach: float = _body_radius() + STEP_PROBE_MARGIN
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
		steps_taken += 1
		return true
	return false


func _body_radius() -> float:
	var shape_node := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node != null and shape_node.shape is CapsuleShape3D:
		return (shape_node.shape as CapsuleShape3D).radius
	return nav_agent.radius if nav_agent != null else 0.35


func _fire_at(enemy: Node3D) -> void:
	if shooter == null or shooter.muzzle == null:
		return
	var aim_point := enemy.global_position + LT_LineOfSightTester.chest_offset()
	var direction := (aim_point - shooter.muzzle.global_position).normalized()
	direction = _apply_aim_error(direction)

	var shot := shooter.fire(direction)
	_fire_timer = fire_cooldown

	get_tree().call_group(LT_Const.GROUP_METRICS, "record_shot", shot)
	get_tree().call_group(LT_Const.GROUP_DEBUG, "draw_shot", shot)
	get_tree().call_group(LT_Const.GROUP_AUDIO, "play_shot", shot)
	get_tree().call_group(LT_Const.GROUP_NET, "relay_shot", shot)

func _apply_aim_error(direction: Vector3) -> Vector3:
	var error_rad := deg_to_rad(aim_error_degrees)
	var axis := direction.cross(Vector3.UP).normalized()
	if axis.is_zero_approx():
		axis = Vector3.RIGHT
	direction = direction.rotated(axis, randf_range(-error_rad, error_rad))
	direction = direction.rotated(Vector3.UP, randf_range(-error_rad, error_rad))
	return direction.normalized()

func _find_visible_enemy() -> Node3D:
	# THE BODY'S OWN EYE, not a number in this file. It was a hardcoded
	# `Vector3.UP * 1.4` -- the one point on this body `player_eye_height_m`
	# never reached, so the harness moved the camera to 1.6 and the muzzle
	# rode under it at 1.55 while the probe stayed at 1.4. The bot could
	# decline a shot its own barrel had (roadmap 131).
	var eye := LT_LineOfSightTester.eye_position(body)
	var best: Node3D = null
	var best_distance := INF
	for enemy in get_tree().get_nodes_in_group(LT_Const.GROUP_ENEMY):
		if enemy is not Node3D:
			continue
		if enemy.has_node("LT_Health") and (enemy.get_node("LT_Health") as LT_Health).is_dead:
			continue
		var distance := eye.distance_to(enemy.global_position)
		if distance > sight_range or distance >= best_distance:
			continue
		if LT_LineOfSightTester.has_line_of_sight(
				eye, enemy, body.get_world_3d(), body,
				shooter.hit_mask if shooter != null else LT_Const.LASER_HIT_MASK):
			best = enemy
			best_distance = distance
	return best

func _advance_route(_delta: float) -> void:
	if route_points.is_empty():
		return

	# Path updates happen INSIDE get_next_path_position() — call it before
	# is_navigation_finished() so the finished-check is meaningful.
	_next_path_point()

	if _route_points_dirty:
		_route_points_dirty = false
		_route_free_start = 0
		if not route_points.is_empty() and body != null:
			var first: Vector3 = route_points[0]
			var here: Vector3 = body.global_position
			# Compared flat: the marker sits on the ground and the body's
			# origin is at its feet, but a lift on either would otherwise read
			# as distance.
			if Vector2(first.x - here.x, first.z - here.z).length() <= 1.0:
				_route_free_start = 1

	if _nav_finished():
		if _seeking_cover:
			_seeking_cover = false
			_go_to_current_route_point()
			return
		_route_index += 1
		_route_reached += 1
		get_tree().call_group(LT_Const.GROUP_METRICS, "record_event",
			"RouteProgress", {
				"source": body.name,
				"reached": maxi(0, _route_reached - _route_free_start),
				"total": maxi(0, route_points.size() - _route_free_start),
			})
		if _route_index >= route_points.size():
			_completed = true
			_stop_horizontal()
			# RECORD BEFORE NOTIFYING (roadmap 128). `route_completed` is now
			# connected -- `LT_MapEvalHarness._on_route_walked` ends the run on
			# it when the guards are already down -- and a Godot signal is
			# delivered SYNCHRONOUSLY. Emitting first therefore closed the run
			# inside this line, and `record_event` returns early on a closed
			# run, so `ObjectiveReached` landed nowhere and
			# `route_completion_rate` read 0.00 on a route the crew had just
			# finished walking. Measured: `ObjectiveReached` 24 -> 0 on
			# restaurant_row_001 seed 9003 with no enemies at all.
			# A ROUTE ENDED ON A SKIP IS NOT A ROUTE WALKED (0.25.0, roadmap
			# 206): `route_walked` asks the arrivals, not the index. Said as
			# `RouteEndedShort` so the run's log shows where it fell short.
			if route_walked(_route_reached, route_points.size()):
				get_tree().call_group(LT_Const.GROUP_METRICS, "record_event",
					"ObjectiveReached", {"source": body.name})
			else:
				get_tree().call_group(LT_Const.GROUP_METRICS, "record_event",
					"RouteEndedShort", {"source": body.name,
						"reached": _route_reached, "total": route_points.size()})
			route_completed.emit()
			return
		_go_to_current_route_point()

	var flat := _next_path_point() - body.global_position
	flat.y = 0.0
	if flat.length() > 0.05:
		var direction := flat.normalized()
		body.velocity.x = direction.x * move_speed
		body.velocity.z = direction.z * move_speed
		_face_point(body.global_position + direction)
	else:
		_stop_horizontal()

## A ROUTE IS WALKED WHEN EVERY POINT ON IT WAS REACHED (0.25.0, roadmap
## 206). `_update_stuck` advances `_route_index` past a point the bot is
## jammed on, so an index that runs off the end says the route ENDED, not
## that it was walked -- and `ObjectiveReached`, which is all
## `route_completion_rate` reads, used to fire on the index. With the
## getaway van the route ends where it starts (spawn, objective, the van at
## the spawn), and a bot jammed in its first seconds was skipped to "back
## at the van" while standing beside it: a finished heist, recorded for a
## crew that never left. `_route_reached` counts real arrivals only
## (roadmap 128); this asks it.
static func route_walked(reached: int, total: int) -> bool:
	return total > 0 and reached >= total


## True once this bot's route has ended with every point reached.
func walked_whole_route() -> bool:
	return _completed and route_walked(_route_reached, route_points.size())


func _go_to_current_route_point() -> void:
	if _route_index < route_points.size():
		_set_destination(route_points[_route_index])

func _set_destination(destination: Vector3) -> void:
	if use_navigation and nav_agent != null:
		nav_agent.target_position = destination
	else:
		set_meta("lt_direct_target", destination)

func _nav_finished() -> bool:
	if use_navigation and nav_agent != null:
		return nav_agent.is_navigation_finished()
	if has_meta("lt_direct_target"):
		var target: Vector3 = get_meta("lt_direct_target")
		return body.global_position.distance_to(target) < 1.2
	return true

func _next_path_point() -> Vector3:
	if use_navigation and nav_agent != null:
		return nav_agent.get_next_path_position()
	if has_meta("lt_direct_target"):
		return get_meta("lt_direct_target")
	return body.global_position

func _face_point(point: Vector3) -> void:
	var flat := point - body.global_position
	flat.y = 0.0
	if flat.is_zero_approx():
		return
	body.rotation.y = lerp_angle(body.rotation.y, atan2(-flat.x, -flat.z), 0.3)

func _on_damaged(_current: int, _max: int) -> void:
	_recent_hits += 1
	_recent_hit_timer = 4.0
	if _recent_hits >= cover_seek_hit_threshold and not cover_points.is_empty() and not _seeking_cover:
		var nearest := Vector3.ZERO
		var best_distance := INF
		for cover in cover_points:
			var distance := body.global_position.distance_to(cover)
			if distance < best_distance:
				best_distance = distance
				nearest = cover
		# Only break off the route for cover the bot can actually reach. The
		# old code committed to the nearest point at any distance, which on a
		# map whose cover is bunched at the objective means abandoning the
		# route to cross open ground toward the enemies.
		if best_distance > cover_seek_max_distance:
			return
		_seeking_cover = true
		_recent_hits = 0
		_set_destination(nearest)

func _update_stuck(delta: float) -> void:
	if _completed or _dead or route_points.is_empty():
		return
	_stuck_timer += delta
	if _stuck_timer >= stuck_window_seconds:
		var moved := body.global_position.distance_to(_stuck_anchor)
		if moved < stuck_distance_threshold and _find_visible_enemy() == null:
			bot_stuck.emit(body.global_position)
			get_tree().call_group(LT_Const.GROUP_METRICS, "record_event", "PlayerStuck", {
				"source": body.name,
				"position": [body.global_position.x, body.global_position.y, body.global_position.z],
			})
			# Choose another route point rather than standing still forever.
			_route_index = mini(_route_index + 1, route_points.size() - 1)
			_go_to_current_route_point()
		_stuck_timer = 0.0
		_stuck_anchor = body.global_position

func _stop_horizontal() -> void:
	body.velocity.x = 0.0
	body.velocity.z = 0.0

## One-line diagnostic for --trace runs.
func debug_status() -> String:
	if body == null:
		return "bot: NO BODY"
	return "bot %s pos=%s vel=%s completed=%s route=%d/%d nav_fin=%s next=%s" % [
		body.name, _fmt(body.global_position),
		_fmt(body.velocity), _completed,
		_route_index, route_points.size(),
		_nav_finished(), _fmt(_next_path_point()),
	]

func _fmt(v: Vector3) -> String:
	return "(%.1f,%.1f,%.1f)" % [v.x, v.y, v.z]


func _align_agent_to_mesh() -> void:
	"""Lift returned path points to the walking surface (roadmap 122).

	A baked navmesh sits ONE CELL HEIGHT above the geometry it was baked from,
	and `get_next_path_position()` returns points on that mesh. The body's
	origin is at its FEET, on the geometry. So every path point is
	`cell_height` higher than the body that is walking to it, and Godot
	measures `path_desired_distance` in 3D -- the vertical error is spent out
	of the arrival budget before a single horizontal metre is counted.

	`path_height_offset` is subtracted from the y of every returned path
	point, which is exactly this correction, and the amount is READ FROM THE
	MAP rather than chosen: `map_get_cell_height` is the number the bake
	actually used, so a different bake stays correct without anyone editing a
	constant here.

	NECESSARY, NOT SUFFICIENT, and that is measured rather than hoped:
	applying this alone on `market_row_001` moved the returned point from
	y 0.25 to y 0.00 and the bot still did not walk, because it had SPAWNED
	1.797 m above the nearest navmesh point -- standing on geometry the mesh
	does not cover. No agent tuning fixes a body that is not on the mesh; that
	half is a spawn-placement defect and is filed separately.
	"""
	if nav_agent == null:
		return
	var map: RID = nav_agent.get_navigation_map()
	if not map.is_valid():
		return
	var cell_height: float = NavigationServer3D.map_get_cell_height(map)
	nav_agent.path_height_offset = cell_height

	# AND THE ARRIVAL RADIUS, DERIVED FROM THE BODY RATHER THAN AUTHORED.
	# `path_desired_distance` was 0.8 in both pill scenes: a number with no
	# stated origin, in the scene files the size contract exists to stop being
	# the source of truth (roadmap 123). It decides when a waypoint counts as
	# reached, so it is a property of the body and the bake, and both are
	# readable here.
	#
	# Three terms, and Godot measures the distance in 3D so they combine that
	# way:
	#
	#   radius        a waypoint inside the body's own footprint IS reached;
	#                 `nav_agent.radius` is set from the contract at spawn.
	#   per frame     the ground covered in one physics tick. Below this the
	#                 body can step OVER the threshold between two samples and
	#                 never register arrival -- which is the shape of the
	#                 stall in item 122, arrived at from the other side.
	#   half a cell   what `path_height_offset` above cannot remove. It
	#                 subtracts exactly one cell height; slope and rounding
	#                 leave up to half of one behind.
	#
	# On the shipped contract -- radius 0.35, speed 4.0, 60 Hz, cell 0.25 --
	# that is 0.44, against the 0.8 it replaces. A SMALLER number is the
	# direction that stalls, so this is measured rather than reasoned: see the
	# A/B in Laser Tag's changelog for the run either side.
	var ticks: float = maxf(1.0, float(Engine.physics_ticks_per_second))
	var per_frame: float = move_speed / ticks
	var horizontal: float = maxf(0.05, nav_agent.radius) + per_frame
	var vertical: float = cell_height * 0.5
	nav_agent.path_desired_distance = sqrt(
		horizontal * horizontal + vertical * vertical)
