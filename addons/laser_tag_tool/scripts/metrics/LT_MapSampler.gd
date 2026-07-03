extends Node
class_name LT_MapSampler
## Static sightline sampler (TDD §11.1 LT_MapSampler, §17.3).
## Grid-samples the walkable space and raycasts each point against enemy
## spawn positions to find, with world coordinates:
##   - Overexposed zones: positions visible to 3+ enemy spawns
##   - Blind zones: positions no enemy spawn can ever see
##   - Long / short sightlines: max open ray distance per position
## Runs once per evaluation, before any pills spawn, so only world
## geometry (layers World + Laser Blockers) occludes the rays.

const EYE_HEIGHT := 1.5
const WORLD_MASK := LT_Const.LAYER_WORLD | LT_Const.LAYER_LASER_BLOCKER
const RAY_DIRECTIONS := 8

@export var sample_spacing: float = 2.0
@export var max_samples: int = 5000
@export var overexposed_threshold: int = 3
@export var long_sightline_meters: float = 40.0
@export var short_sightline_meters: float = 6.0
@export var bounds_margin: float = 4.0
## Snap tolerance when validating samples against the navmesh.
@export var nav_snap_tolerance: float = 1.5

func sample_map(world: World3D, navigation_available: bool,
		enemy_spawn_positions: Array[Vector3],
		bounds_anchor_positions: Array[Vector3]) -> Dictionary:
	if world == null or bounds_anchor_positions.is_empty():
		return {}

	var bounds := _bounds_from(bounds_anchor_positions)
	var samples := _collect_samples(world, navigation_available, bounds)
	if samples.is_empty():
		return {}

	var space := world.direct_space_state
	var enemy_eyes: Array[Vector3] = []
	for spawn_position in enemy_spawn_positions:
		enemy_eyes.append(spawn_position + Vector3.UP * EYE_HEIGHT)

	var blind_count := 0
	var overexposed: Array[Dictionary] = []
	var long_sightlines := 0
	var short_sightlines := 0
	var exposure_total := 0

	for sample in samples:
		var eye: Vector3 = sample + Vector3.UP * EYE_HEIGHT
		var visible := 0
		for enemy_eye in enemy_eyes:
			if _ray_clear(space, eye, enemy_eye):
				visible += 1
		exposure_total += visible

		if visible == 0:
			blind_count += 1
		elif visible >= overexposed_threshold:
			overexposed.append({
				"position": [snappedf(sample.x, 0.1), snappedf(sample.y, 0.1), snappedf(sample.z, 0.1)],
				"visible_to": visible,
			})

		var max_open := _max_open_ray(space, eye)
		if max_open >= long_sightline_meters:
			long_sightlines += 1
		elif max_open <= short_sightline_meters:
			short_sightlines += 1

	overexposed.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return a["visible_to"] > b["visible_to"])

	var total := samples.size()
	return {
		"total_samples": total,
		"sample_spacing": sample_spacing,
		"blind_count": blind_count,
		"blind_fraction": float(blind_count) / float(total),
		"overexposed_count": overexposed.size(),
		"overexposed_fraction": float(overexposed.size()) / float(total),
		"overexposed_threshold": overexposed_threshold,
		"worst_overexposed": overexposed.slice(0, 10),
		"avg_exposure": float(exposure_total) / float(total),
		"long_sightline_count": long_sightlines,
		"short_sightline_count": short_sightlines,
		"long_sightline_fraction": float(long_sightlines) / float(total),
	}

func _bounds_from(anchor_positions: Array[Vector3]) -> AABB:
	var bounds := AABB(anchor_positions[0], Vector3.ZERO)
	for anchor in anchor_positions:
		bounds = bounds.expand(anchor)
	return bounds.grow(bounds_margin)

func _collect_samples(world: World3D, navigation_available: bool, bounds: AABB) -> Array[Vector3]:
	var samples: Array[Vector3] = []
	var space := world.direct_space_state
	var map_rid := world.navigation_map

	var spacing := sample_spacing
	# Widen spacing if the grid would exceed the sample budget.
	var estimated := (bounds.size.x / spacing) * (bounds.size.z / spacing)
	while estimated > float(max_samples):
		spacing *= 1.5
		estimated = (bounds.size.x / spacing) * (bounds.size.z / spacing)

	var x := bounds.position.x
	while x <= bounds.end.x:
		var z := bounds.position.z
		while z <= bounds.end.z:
			var probe := Vector3(x, bounds.end.y + 5.0, z)
			var floor_point := _floor_below(space, probe, bounds.size.y + 15.0)
			if floor_point != Vector3.INF:
				if navigation_available:
					var snapped_point := NavigationServer3D.map_get_closest_point(map_rid, floor_point)
					if snapped_point.distance_to(floor_point) <= nav_snap_tolerance:
						samples.append(snapped_point)
				else:
					samples.append(floor_point)
			z += spacing
		x += spacing

	return samples

func _floor_below(space: PhysicsDirectSpaceState3D, from_point: Vector3, depth: float) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(
		from_point, from_point + Vector3.DOWN * depth)
	query.collision_mask = WORLD_MASK
	var result := space.intersect_ray(query)
	if result.is_empty():
		return Vector3.INF
	return result.get("position")

func _ray_clear(space: PhysicsDirectSpaceState3D, from_point: Vector3, to_point: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from_point, to_point)
	query.collision_mask = WORLD_MASK
	return space.intersect_ray(query).is_empty()

func _max_open_ray(space: PhysicsDirectSpaceState3D, eye: Vector3) -> float:
	var longest := 0.0
	for i in RAY_DIRECTIONS:
		var angle := TAU * float(i) / float(RAY_DIRECTIONS)
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var query := PhysicsRayQueryParameters3D.create(
			eye, eye + direction * long_sightline_meters * 1.5)
		query.collision_mask = WORLD_MASK
		var result := space.intersect_ray(query)
		var open_distance := long_sightline_meters * 1.5
		if not result.is_empty():
			open_distance = eye.distance_to(result.get("position"))
		longest = maxf(longest, open_distance)
	return longest
