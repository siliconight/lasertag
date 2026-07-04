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
@export var use_navigation: bool = true

@export var stuck_window_seconds: float = 4.0
@export var stuck_distance_threshold: float = 0.5

var route_points: Array[Vector3] = []
var cover_points: Array[Vector3] = []

var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))

var _route_index: int = 0
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
	if body != null:
		_stuck_anchor = body.global_position
		if body.has_node("LT_Health"):
			var health: LT_Health = body.get_node("LT_Health")
			health.damaged.connect(_on_damaged)
			health.died.connect(func() -> void: _dead = true)

func start_route(points: Array[Vector3], covers: Array[Vector3] = []) -> void:
	route_points = points
	cover_points = covers
	_route_index = 0
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
		# DIAGNOSTIC (temporary): fires once if the bot thinks it sees a target.
		if not has_meta("_lt_bot_saw_enemy"):
			set_meta("_lt_bot_saw_enemy", true)
			print("[LT bot] %s SEES ENEMY %s — stopping to fire (not advancing route)" % [
				body.name, enemy.name])
		_stop_horizontal()
		_face_point(enemy.global_position)
		if _fire_timer <= 0.0:
			_fire_at(enemy)
	else:
		_advance_route(delta)

	if not body.is_on_floor():
		body.velocity.y -= gravity * delta
	body.move_and_slide()
	_update_stuck(delta)

func _fire_at(enemy: Node3D) -> void:
	if shooter == null or shooter.muzzle == null:
		return
	var aim_point := enemy.global_position + LT_LineOfSightTester.CHEST_OFFSET
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
	var eye := body.global_position + Vector3.UP * 1.4
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

	if _nav_finished():
		if _seeking_cover:
			_seeking_cover = false
			_go_to_current_route_point()
			return
		_route_index += 1
		if _route_index >= route_points.size():
			_completed = true
			_stop_horizontal()
			route_completed.emit()
			get_tree().call_group(LT_Const.GROUP_METRICS, "record_event",
				"ObjectiveReached", {"source": body.name})
			return
		_go_to_current_route_point()

	var flat := _next_path_point() - body.global_position
	flat.y = 0.0
	# DIAGNOSTIC (temporary): fires once on first route-advance frame.
	if not has_meta("_lt_bot_logged"):
		set_meta("_lt_bot_logged", true)
		print("[LT bot] %s advance use_nav=%s has_target=%s next=%s pos=%s flat_len=%.2f route=%d/%d" % [
			body.name, use_navigation, has_meta("lt_direct_target"),
			_next_path_point(), body.global_position, flat.length(),
			_route_index, route_points.size()])
	if flat.length() > 0.05:
		var direction := flat.normalized()
		body.velocity.x = direction.x * move_speed
		body.velocity.z = direction.z * move_speed
		_face_point(body.global_position + direction)
	else:
		_stop_horizontal()

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
		_seeking_cover = true
		_recent_hits = 0
		var nearest := cover_points[0]
		var best_distance := INF
		for cover in cover_points:
			var distance := body.global_position.distance_to(cover)
			if distance < best_distance:
				best_distance = distance
				nearest = cover
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
