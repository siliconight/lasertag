extends Node
class_name LT_LineOfSightTester
## Shared line-of-sight raycast helper.
## A body "sees" a target when a ray from eye to target chest hits the
## target body first — anything else in the way means LOS is blocked.

const CHEST_OFFSET := Vector3.UP * 1.0

static func has_line_of_sight(
		from_position: Vector3,
		target: Node3D,
		world: World3D,
		exclude_body: CollisionObject3D = null,
		mask: int = LT_Const.LASER_HIT_MASK) -> bool:
	if target == null or world == null:
		return false

	var end := target.global_position + CHEST_OFFSET
	var query := PhysicsRayQueryParameters3D.create(from_position, end)
	query.collision_mask = mask
	if exclude_body != null:
		query.exclude = [exclude_body.get_rid()]

	var result := world.direct_space_state.intersect_ray(query)
	if result.is_empty():
		return false
	return result.get("collider") == target
