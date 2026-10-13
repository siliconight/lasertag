extends Node
class_name LT_EnemyMovement
## Moves an enemy pill CharacterBody3D via NavigationAgent3D, with a
## direct-movement fallback when navigation is missing (TDD §29.1) and
## simple stuck detection.

signal stuck_detected(position: Vector3)
## Held by another bot's body and by nothing of the level (0.30.0, factory roadmap 242). Every guard
## in SEEK paths to the same crew member through the same corners and none steers round another,
## so a guard behind a guard stood still and was `stuck_detected` -- 74 of 75 such events traced on
## the factory's lots had another body among their contacts -- and NPC Pathing charged the map for
## the bots' own crowding.
signal blocked_detected(position: Vector3)

@export var body: CharacterBody3D
@export var nav_agent: NavigationAgent3D
@export var move_speed: float = 4.0
@export var use_navigation: bool = true

## THE GUARD WALKS AS THE CREW DOES (0.31.0, factory roadmap 242): `LT_Steering`, the crew bot's
## own copy. `agent_contract.json` says npc_standard shares the player's metrics until a distinct
## class ships, so the harness sets this from the scenario's `player_max_step_up_m` (0.5), as it
## sets the crew's. 0 turns step-up off.
@export var max_step_up: float = 0.5
## Keep each step on the mesh the guard plans on, as the crew has since 0.29.0. Off, the guard steers
## straight at its next path point, as it did before 0.31.0.
@export var keep_to_mesh: bool = true
## Step-ups taken: what the step-up did, for a reader of a run.
var steps_taken: int = 0

## Considered stuck when displacement over the window is below threshold
## while actively trying to move.
@export var stuck_window_seconds: float = 3.0
@export var stuck_distance_threshold: float = 0.5

var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))

var _wants_to_move: bool = false
var _stuck_timer: float = 0.0
var _stuck_anchor: Vector3 = Vector3.ZERO
var _stuck_reported: bool = false
## Set once the agent has its arrival radius and path height offset (0.26.0).
var _aligned: bool = false

func _ready() -> void:
	if body == null and get_parent() is CharacterBody3D:
		body = get_parent()
	if nav_agent == null and body != null and body.has_node("NavigationAgent3D"):
		nav_agent = body.get_node("NavigationAgent3D")
	if body != null:
		_stuck_anchor = body.global_position

func set_destination(destination: Vector3) -> void:
	_wants_to_move = true
	if use_navigation and nav_agent != null:
		_align_agent_to_mesh()
		nav_agent.target_position = destination
	else:
		set_meta("lt_direct_target", destination)

## Steer the enemy as the crew is steered (0.26.0, roadmap 197): the arrival
## radius from the body and the bake, and every returned path point lowered
## by the bake's cell height to the feet that walk to it -- what
## `LT_BotPlayerController._align_agent_to_mesh` has done for the crew since
## 0.18.0. The pill scene's `path_desired_distance` 0.8 counts a waypoint
## reached from 0.8 m away, so at a door the body turns for the next one
## before it is through and walks into the jamb; 0.18.0 measured exactly
## that for the crew. Read from the MAP once one is known, so a different
## bake stays right without an edit here; `nav_agent.radius` is the body's,
## set by the harness from the scenario.
func _align_agent_to_mesh() -> void:
	if _aligned or nav_agent == null:
		return
	var map: RID = nav_agent.get_navigation_map()
	if not map.is_valid():
		return
	var cell_height: float = NavigationServer3D.map_get_cell_height(map)
	nav_agent.path_height_offset = cell_height
	nav_agent.path_desired_distance = LT_Const.arrival_radius(
		nav_agent.radius, move_speed,
		float(Engine.physics_ticks_per_second), cell_height)
	_aligned = true

func stop() -> void:
	_wants_to_move = false
	if body != null:
		body.velocity.x = 0.0
		body.velocity.z = 0.0

func is_navigation_finished() -> bool:
	if use_navigation and nav_agent != null:
		return nav_agent.is_navigation_finished()
	if has_meta("lt_direct_target") and body != null:
		var target: Vector3 = get_meta("lt_direct_target")
		return body.global_position.distance_to(target) < 1.0
	return true

func _physics_process(delta: float) -> void:
	if body == null:
		return

	if not body.is_on_floor():
		body.velocity.y -= gravity * delta

	if _wants_to_move:
		var next_point := _next_point()
		var flat := next_point - body.global_position
		flat.y = 0.0
		if flat.length() > 0.05:
			var direction := flat.normalized()
			var v: Vector3 = direction * move_speed
			if keep_to_mesh and use_navigation:
				v = LT_Steering.velocity_on_mesh(body, nav_agent, v, delta)
			body.velocity.x = v.x
			body.velocity.z = v.z
			_face(direction)
		else:
			body.velocity.x = 0.0
			body.velocity.z = 0.0
	else:
		body.velocity.x = move_toward(body.velocity.x, 0.0, move_speed)
		body.velocity.z = move_toward(body.velocity.z, 0.0, move_speed)

	# the way the guard MEANT to go, before the slide turns it along whatever it hit: the step-up
	# asks about that wall, not about the slide (0.31.0, the crew's since 0.24.0)
	var intended := Vector3(body.velocity.x, 0.0, body.velocity.z)
	body.move_and_slide()
	if LT_Steering.try_step_up(body, nav_agent, intended, max_step_up):
		steps_taken += 1
	_update_stuck(delta)

func _next_point() -> Vector3:
	if use_navigation and nav_agent != null:
		return nav_agent.get_next_path_position()
	if has_meta("lt_direct_target"):
		return get_meta("lt_direct_target")
	return body.global_position

func _face(direction: Vector3) -> void:
	if direction.is_zero_approx():
		return
	var target_angle := atan2(-direction.x, -direction.z)
	body.rotation.y = lerp_angle(body.rotation.y, target_angle, 0.2)

func _update_stuck(delta: float) -> void:
	if not _wants_to_move or is_navigation_finished():
		_stuck_timer = 0.0
		_stuck_anchor = body.global_position
		_stuck_reported = false
		return

	_stuck_timer += delta
	if _stuck_timer >= stuck_window_seconds:
		var moved := body.global_position.distance_to(_stuck_anchor)
		if moved < stuck_distance_threshold and not _stuck_reported:
			_stuck_reported = true
			if _held_by_a_body():
				blocked_detected.emit(body.global_position)
			else:
				stuck_detected.emit(body.global_position)
		_stuck_timer = 0.0
		_stuck_anchor = body.global_position
		if moved >= stuck_distance_threshold:
			_stuck_reported = false

## Whether this frame's move was held by another bot's body and by nothing of the level (0.30.0).
## `_update_stuck` runs right after `move_and_slide`, so these are the closing frame's contacts. A
## contact under the feet is the floor, not a hold; any other contact that is not a body -- a wall,
## a prop -- is the level's, and the guard is stuck as before.
func _held_by_a_body() -> bool:
	var by_body := false
	for i in range(body.get_slide_collision_count()):
		var c: KinematicCollision3D = body.get_slide_collision(i)
		if c.get_normal().angle_to(Vector3.UP) <= body.floor_max_angle:
			continue
		if c.get_collider() is CharacterBody3D:
			by_body = true
		else:
			return false
	return by_body
