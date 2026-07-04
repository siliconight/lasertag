extends Node
class_name LT_EnemyBrain
## Enemy AI state machine (TDD §13.5, §15).
## Deliberately dumb: if results are bad, the map is usually the problem.

enum State {
	IDLE,
	SEEK,
	LINE_OF_SIGHT,
	SHOOT,
	REPOSITION,
	STUCK,
	DEAD,
}

@export var shooter: LT_Shooter
@export var movement: LT_EnemyMovement
@export var eye: Marker3D
@export var fire_cooldown: float = 1.25
@export var sight_range: float = 35.0
@export var preferred_distance: float = 14.0
@export var reaction_delay_min: float = 0.25
@export var reaction_delay_max: float = 0.5

var state: State = State.IDLE
var target: Node3D
var fire_timer: float = 0.0
var reaction_timer: float = 0.0
var had_los_last_frame: bool = false
var stuck_count: int = 0

var _body: CharacterBody3D

func _ready() -> void:
	_body = get_parent() as CharacterBody3D
	if movement != null:
		movement.stuck_detected.connect(_on_stuck)
	if _body != null and _body.has_node("LT_Health"):
		var health: LT_Health = _body.get_node("LT_Health")
		health.died.connect(_on_died)

func state_name() -> String:
	return State.keys()[state]

func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return

	fire_timer -= delta
	target = _find_target()

	if target == null:
		state = State.IDLE
		if movement != null:
			movement.stop()
		had_los_last_frame = false
		return

	var has_los := _has_line_of_sight(target)
	var distance := _body.global_position.distance_to(target.global_position) if _body != null else INF

	if has_los and distance <= sight_range:
		if not had_los_last_frame:
			# Fresh sighting: apply humanizing reaction delay before firing.
			reaction_timer = randf_range(reaction_delay_min, reaction_delay_max)
			get_tree().call_group(LT_Const.GROUP_METRICS, "record_event",
				"LineOfSightGained", {"source": _source_name(), "target": target.name})

		reaction_timer -= delta
		state = State.SHOOT

		if distance < preferred_distance * 0.6:
			# Too close — back off slightly while shooting is on cooldown.
			state = State.REPOSITION
			_back_away()
		else:
			if movement != null:
				movement.stop()

		if reaction_timer <= 0.0:
			_try_fire_at_target(target)
	else:
		if had_los_last_frame:
			get_tree().call_group(LT_Const.GROUP_METRICS, "record_event",
				"LineOfSightLost", {"source": _source_name(), "target": target.name})
		state = State.SEEK
		if movement != null:
			movement.set_destination(target.global_position)

	had_los_last_frame = has_los and distance <= sight_range

func _try_fire_at_target(target_node: Node3D) -> void:
	if fire_timer > 0.0 or shooter == null or shooter.muzzle == null:
		return

	var aim_point := target_node.global_position + LT_LineOfSightTester.CHEST_OFFSET
	var direction := (aim_point - shooter.muzzle.global_position).normalized()
	var shot := shooter.fire(direction)

	fire_timer = fire_cooldown

	get_tree().call_group(LT_Const.GROUP_METRICS, "record_shot", shot)
	get_tree().call_group(LT_Const.GROUP_DEBUG, "draw_shot", shot)
	get_tree().call_group(LT_Const.GROUP_AUDIO, "play_shot", shot)
	get_tree().call_group(LT_Const.GROUP_NET, "relay_shot", shot)

func _find_target() -> Node3D:
	var registry := get_tree().get_first_node_in_group(LT_Const.GROUP_REGISTRY)
	if registry == null:
		return null
	return registry.get_best_target_for_enemy(_body)

func _has_line_of_sight(target_node: Node3D) -> bool:
	if eye == null or _body == null:
		return false
	return LT_LineOfSightTester.has_line_of_sight(
		eye.global_position, target_node, eye.get_world_3d(), _body,
		shooter.hit_mask if shooter != null else LT_Const.LASER_HIT_MASK)

func _back_away() -> void:
	if movement == null or _body == null or target == null:
		return
	var away := (_body.global_position - target.global_position)
	away.y = 0.0
	if away.is_zero_approx():
		return
	movement.set_destination(_body.global_position + away.normalized() * 4.0)

func _on_stuck(position: Vector3) -> void:
	stuck_count += 1
	state = State.STUCK
	get_tree().call_group(LT_Const.GROUP_METRICS, "record_event", "EnemyStuck", {
		"source": _source_name(),
		"position": [position.x, position.y, position.z],
		"stuck_count": stuck_count,
	})
	# Try an alternate nearby point to unstick (TDD §15.2).
	if movement != null and _body != null:
		var jitter := Vector3(randf_range(-3.0, 3.0), 0.0, randf_range(-3.0, 3.0))
		movement.set_destination(_body.global_position + jitter)

func _on_died() -> void:
	state = State.DEAD
	if movement != null:
		movement.stop()
		movement.set_physics_process(false)
	get_tree().call_group(LT_Const.GROUP_METRICS, "record_event", "EnemyKilled", {
		"source": _source_name(),
	})

func _source_name() -> String:
	return _body.name if _body != null else name

## One-line diagnostic for --trace runs.
func debug_status() -> String:
	if _body == null:
		return "enemy %s: NO BODY" % name
	var target_name := target.name if target != null else "none"
	var dist := _body.global_position.distance_to(target.global_position) if target != null else -1.0
	return "enemy %s pos=(%.1f,%.1f,%.1f) state=%s target=%s dist=%.1f los=%s fire_t=%.2f" % [
		_body.name, _body.global_position.x, _body.global_position.y, _body.global_position.z,
		state_name(), target_name, dist, had_los_last_frame, fire_timer,
	]
