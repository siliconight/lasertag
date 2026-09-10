extends Node
class_name LT_LineOfSightTester
## Shared line-of-sight raycast helper.
## A body "sees" a target when a ray from eye to target chest hits the
## target body first — anything else in the way means LOS is blocked.

## The ratified aim height, and the fallback when nothing sets one.
const CHEST_OFFSET := Vector3.UP * 1.0

## Where a shot is aimed on the target, in metres above its feet.
##
## A static var rather than a const because the scenario has to be able to
## move it: it is half the geometry that decides how tall a solid must be to
## break a mutual sightline, so a consumer whose characters are not 1.8 m
## tall cannot be left aiming at OUR chest. `LT_MapEvalHarness` sets it once
## from `scenario.aim_height_m`; nothing else writes it.
static var aim_height: float = CHEST_OFFSET.y

## The offset the two callers used to read directly. Kept as the single way
## to ask, so a reader cannot pick up the const by habit and miss the value
## the run is actually using.
static func chest_offset() -> Vector3:
	return Vector3.UP * aim_height

## Where a body sights FROM. Roadmap 131, and the whole point of this item.
##
## Six call sites used to answer this question and no two agreed: the crew
## bot's probe said 1.4, its camera said `player_eye_height_m`, its muzzle
## said camera - 0.05, the enemy pill's marker said 1.5, the enemy's muzzle
## said 1.3, and `LT_PlayerRegistry` said 1.4 again while picking which crew
## member to shoot at. `LT_MapSampler` had a seventh in its own const.
##
## So a body's eye is now a NODE, positioned once by
## `LT_MapEvalHarness._apply_body` / `_configure_enemy` from the scenario,
## and this is the only way to ask where it is. A number cannot drift from
## itself.
##
## The fallback for a body with neither marker nor camera is the height it
## would be AIMED at, which is the one other stated point on a body. It is
## deliberately not the origin: the origin is at the feet, and a body that
## sights along the floor sees nothing and reports the map as covered.
static func eye_position(body: Node3D) -> Vector3:
	if body == null:
		return Vector3.ZERO
	var eye := body.get_node_or_null("Marker3D_Eye")
	if eye == null:
		eye = body.get_node_or_null("Camera3D")
	if eye is Node3D:
		return (eye as Node3D).global_position
	return body.global_position + chest_offset()

static func has_line_of_sight(
		from_position: Vector3,
		target: Node3D,
		world: World3D,
		exclude_body: CollisionObject3D = null,
		mask: int = LT_Const.LASER_HIT_MASK) -> bool:
	if target == null or world == null:
		return false

	var end := target.global_position + chest_offset()
	var query := PhysicsRayQueryParameters3D.create(from_position, end)
	query.collision_mask = mask
	if exclude_body != null:
		query.exclude = [exclude_body.get_rid()]

	var result := world.direct_space_state.intersect_ray(query)
	if result.is_empty():
		return false
	return result.get("collider") == target
