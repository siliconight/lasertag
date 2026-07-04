extends Node
class_name LT_Shooter
## Hitscan laser shooter (TDD §13.3).
## One call to fire() = one raycast = one potential point of damage.
## First collision hit is the only hit. World collision blocks the shot.

@export var muzzle: Marker3D
@export var laser_range: float = 60.0
@export var damage: int = 1
@export_flags_3d_physics var hit_mask: int = LT_Const.LASER_HIT_MASK

## When false (default, TDD §22.6) hits on same-team bodies are recorded
## as FRIENDLY_HIT and apply no damage.
@export var friendly_fire: bool = false

var owner_body: CollisionObject3D

func setup(body: CollisionObject3D) -> void:
	owner_body = body

func _ready() -> void:
	if owner_body == null:
		var parent := get_parent()
		if parent is CollisionObject3D:
			owner_body = parent
	# Typed @export NodePaths can load null under a version-mismatched scene
	# (see LT_EnemyBrain._ready()); re-resolve the muzzle so fire() works.
	# The muzzle sits directly under the pill (enemies) or under the camera
	# (players), so try both known layouts.
	if muzzle == null and owner_body != null:
		if owner_body.has_node("Marker3D_Muzzle"):
			muzzle = owner_body.get_node("Marker3D_Muzzle")
		elif owner_body.has_node("Camera3D/Marker3D_Muzzle"):
			muzzle = owner_body.get_node("Camera3D/Marker3D_Muzzle")

func fire(direction: Vector3) -> LT_ShotResult:
	var shot := LT_ShotResult.new()
	shot.shooter = owner_body
	shot.shooter_is_player = owner_body != null and owner_body.is_in_group(LT_Const.GROUP_PLAYER)
	if owner_body != null:
		shot.shooter_peer_id = owner_body.get_meta("lt_peer_id", 1)

	if muzzle == null or direction.is_zero_approx():
		shot.hit_type = "INVALID"
		return shot

	var start := muzzle.global_position
	var end := start + direction.normalized() * laser_range
	shot.start_position = start
	shot.end_position = end

	var query := PhysicsRayQueryParameters3D.create(start, end)
	query.collision_mask = hit_mask

	if owner_body != null:
		query.exclude = [owner_body.get_rid()]

	var space_state := muzzle.get_world_3d().direct_space_state
	var result := space_state.intersect_ray(query)

	if result.is_empty():
		shot.did_hit = false
		shot.hit_type = "MISS"
		return shot

	shot.did_hit = true
	shot.collider = result.get("collider")
	shot.hit_position = result.get("position")
	shot.hit_normal = result.get("normal")
	shot.end_position = shot.hit_position

	var hit_object := shot.collider as Node

	if hit_object != null and hit_object.has_node("LT_Health"):
		var same_team := _is_same_team(hit_object)
		if same_team and not friendly_fire:
			shot.hit_type = "FRIENDLY_HIT"
			return shot

		var health: LT_Health = hit_object.get_node("LT_Health")
		health.apply_hit(damage)
		shot.did_damage = true
		shot.damage_applied = damage

		if hit_object.is_in_group(LT_Const.GROUP_ENEMY):
			shot.hit_type = "ENEMY_HIT"
		elif hit_object.is_in_group(LT_Const.GROUP_PLAYER):
			shot.hit_type = "PLAYER_HIT"
		else:
			shot.hit_type = "CHARACTER_HIT"

		return shot

	shot.was_blocked = true
	shot.hit_type = "WORLD_BLOCKED"
	return shot

func _is_same_team(hit_object: Node) -> bool:
	if owner_body == null:
		return false
	var shooter_is_player := owner_body.is_in_group(LT_Const.GROUP_PLAYER)
	var shooter_is_enemy := owner_body.is_in_group(LT_Const.GROUP_ENEMY)
	if shooter_is_player and hit_object.is_in_group(LT_Const.GROUP_PLAYER):
		return true
	if shooter_is_enemy and hit_object.is_in_group(LT_Const.GROUP_ENEMY):
		return true
	return false
