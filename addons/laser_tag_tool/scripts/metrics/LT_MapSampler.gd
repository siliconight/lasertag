extends Node
class_name LT_MapSampler
## Static sightline sampler (TDD §11.1 LT_MapSampler, §17.3).
## Grid-samples the walkable space and reports, with world coordinates:
##   - PEER exposure: how much of the level can be shot from elsewhere IN the
##     level, measured between walkable positions and nothing else
##   - Long / short sightlines: max open ray distance per position
##   - Overexposed / blind zones RELATIVE TO ENEMY SPAWNS, when spawns exist
## Runs once per evaluation, before any pills spawn, so only world
## geometry (layers World + Laser Blockers) occludes the rays.
##
## THE SPAWN-RELATIVE NUMBERS ARE SECONDARY, AND THAT IS DELIBERATE. They were
## the whole instrument until 2026-09-08, which made a statement about a level
## depend on where six markers happened to be put -- and the placement of those
## markers is gameplay-layer work that is expected to move out of this
## toolchain entirely. A measure of a LEVEL has to be a property of its
## geometry, or it stops meaning anything the day somebody else owns the
## spawns.
##
## So `sample_map` no longer requires spawns. Given none, it reports the peer
## and sightline figures and OMITS the spawn-relative keys rather than
## defaulting them: with an empty eye list every sample is "visible to 0
## spawns", which reads as blind_fraction 1.0 and overexposed_fraction 0.0 --
## a wide-open arena scoring as perfectly covered. A reader that cannot find
## the field it wants has to know it is missing.

const EYE_HEIGHT := 1.5
const WORLD_MASK := LT_Const.LAYER_WORLD | LT_Const.LAYER_LASER_BLOCKER
const RAY_DIRECTIONS := 8

@export var sample_spacing: float = 2.0
@export var max_samples: int = 5000
@export var overexposed_threshold: int = 3
@export var long_sightline_meters: float = 40.0
@export var short_sightline_meters: float = 6.0
@export var bounds_margin: float = 4.0
## Peer viewpoints: walkable positions the rest of the map is tested against.
## A stratified subset, because mutual visibility is O(n^2) and a 5,000-sample
## site would be 12.5 M rays. 96 against 910 samples is ~87 K, which is one
## pass of a second or so.
## How far a sightline has to run before it counts as open. SET FROM THE
## SCENARIO's `enemy_laser_range` by the harness -- a lane only matters if
## something can shoot down it. The default here matches the shipped 35.0.
@export var sightline_limit_m: float = 35.0
@export var max_viewpoints: int = 96
## A position counts as peer-exposed when this fraction of viewpoints can see
## it. 0.25 of a spread-out viewpoint set is a position with sightlines onto
## it from a quarter of the level.
@export var peer_exposed_ratio: float = 0.25
## ...and peer-covered when at most this fraction can.
@export var peer_covered_ratio: float = 0.05
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

	var fully_open := 0
	var has_cover := 0
	var open_direction_total := 0
	var viewpoints := _viewpoints(samples)
	var peer_exposed := 0
	var peer_covered := 0
	var peer_worst: Array[Dictionary] = []
	var peer_ratio_total := 0.0

	for sample in samples:
		var eye: Vector3 = sample + Vector3.UP * EYE_HEIGHT
		var visible := 0
		for enemy_eye in enemy_eyes:
			if _ray_clear(space, eye, enemy_eye):
				visible += 1
		exposure_total += visible

		# PEER EXPOSURE -- how much of the level can shoot this spot, asked of
		# the level and not of anybody's spawn placement. A viewpoint sees
		# itself, so the self-hit is excluded rather than inflating every
		# position by one.
		var seen_by := 0
		for view_eye in viewpoints:
			if view_eye.distance_to(eye) < 0.01:
				continue
			if _ray_clear(space, eye, view_eye):
				seen_by += 1
		var denominator: int = maxi(1, viewpoints.size() - 1)
		var ratio: float = float(seen_by) / float(denominator)
		peer_ratio_total += ratio
		if ratio >= peer_exposed_ratio:
			peer_exposed += 1
			peer_worst.append({
				"position": [snappedf(sample.x, 0.1), snappedf(sample.y, 0.1),
					snappedf(sample.z, 0.1)],
				"seen_from_fraction": snappedf(ratio, 0.01),
			})
		elif ratio <= peer_covered_ratio:
			peer_covered += 1

		if visible == 0:
			blind_count += 1
		elif visible >= overexposed_threshold:
			overexposed.append({
				"position": [snappedf(sample.x, 0.1), snappedf(sample.y, 0.1), snappedf(sample.z, 0.1)],
				"visible_to": visible,
			})

		var profile := _ray_profile(space, eye)
		var max_open: float = profile["max_open"]
		var open_dirs: int = profile["open_directions"]
		open_direction_total += open_dirs
		if open_dirs >= RAY_DIRECTIONS:
			fully_open += 1
		if open_dirs <= RAY_DIRECTIONS / 2:
			has_cover += 1
		if max_open >= long_sightline_meters:
			long_sightlines += 1
		elif max_open <= short_sightline_meters:
			short_sightlines += 1

	overexposed.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return a["visible_to"] > b["visible_to"])

	peer_worst.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["seen_from_fraction"] > b["seen_from_fraction"])

	var total := samples.size()
	# THE LEVEL'S OWN FIGURES. These need no spawns and stay meaningful when
	# the gameplay layer that places them lives somewhere else entirely.
	var out := {
		"total_samples": total,
		"sample_spacing": sample_spacing,
		"long_sightline_count": long_sightlines,
		"short_sightline_count": short_sightlines,
		"long_sightline_fraction": float(long_sightlines) / float(total),
		"sightline_limit_m": sightline_limit_m,
		"fully_open_count": fully_open,
		"fully_open_fraction": float(fully_open) / float(total),
		"has_cover_count": has_cover,
		"has_cover_fraction": float(has_cover) / float(total),
		"avg_open_directions": float(open_direction_total) / float(total),
		"ray_directions": RAY_DIRECTIONS,
		"viewpoint_count": viewpoints.size(),
		"peer_exposed_count": peer_exposed,
		"peer_exposed_fraction": float(peer_exposed) / float(total),
		"peer_covered_count": peer_covered,
		"peer_covered_fraction": float(peer_covered) / float(total),
		"avg_peer_exposure": peer_ratio_total / float(total),
		"worst_peer_exposed": peer_worst.slice(0, 10),
		"peer_exposed_ratio": peer_exposed_ratio,
	}
	# SPAWN-RELATIVE, AND ONLY WHEN THERE ARE SPAWNS. Absent, these keys are
	# absent -- see the note at the top. Defaulting them would report a wide
	# open arena as 0% overexposed and 100% blind, which is a PASS and a WARN
	# describing a measurement that never happened.
	if not enemy_eyes.is_empty():
		out["blind_count"] = blind_count
		out["blind_fraction"] = float(blind_count) / float(total)
		out["overexposed_count"] = overexposed.size()
		out["overexposed_fraction"] = float(overexposed.size()) / float(total)
		out["overexposed_threshold"] = overexposed_threshold
		out["worst_overexposed"] = overexposed.slice(0, 10)
		out["avg_exposure"] = float(exposure_total) / float(total)
	return out

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
	return _ray_profile(space, eye)["max_open"]

func _ray_profile(space: PhysicsDirectSpaceState3D, eye: Vector3) -> Dictionary:
	"""Longest open ray, and how many of the 8 directions have no occluder
	inside weapon range.

	OPEN DIRECTIONS ARE THE COVER MEASURE, and the reason for it is that the
	longest ray cannot be one. `max_open` is a maximum over 8 directions, so it
	is long the moment ANY direction is open -- which on real geometry is
	nearly always. Measured on market_row_001: 98% of 3,861 positions cleared
	40 m on their best direction and NOT ONE was short on it. A number that is
	~1.0 everywhere separates no levels from each other.

	What a body actually needs is somewhere to put its back. That is the count
	of directions that ARE blocked, and it discriminates: a doorway with three
	open sides is a different place from a plaza with eight.

	`sightline_limit_m` comes from the scenario's `enemy_laser_range`, not from
	a number chosen here, because the question is whether a sightline is long
	enough to be SHOT down. A 40 m lane on a map where the weapon reaches 35 m
	is cover; the same lane at 60 m range is not.
	"""
	var longest := 0.0
	var open_directions := 0
	var reach: float = maxf(1.0, sightline_limit_m)
	# CAST PAST WEAPON RANGE, COUNT WITHIN IT. The first version of this cast
	# only to `reach`, which capped `max_open` at 35 m -- so
	# `long_sightline_fraction`, which asks whether anything clears 40 m, read
	# 0.0 on a site that had measured 0.981 an hour earlier. The metric had not
	# changed; the ray had stopped short of the question.
	var far: float = maxf(reach, long_sightline_meters * 1.5)
	for i in RAY_DIRECTIONS:
		var angle := TAU * float(i) / float(RAY_DIRECTIONS)
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var query := PhysicsRayQueryParameters3D.create(eye, eye + direction * far)
		query.collision_mask = WORLD_MASK
		var result := space.intersect_ray(query)
		var open_distance := far
		if not result.is_empty():
			open_distance = eye.distance_to(result.get("position"))
		# Open means "nothing to hide behind inside weapon range", so an
		# occluder further away than `reach` does not count as cover.
		if open_distance >= reach:
			open_directions += 1
		longest = maxf(longest, open_distance)
	return {"max_open": longest, "open_directions": open_directions}

func _viewpoints(samples: Array[Vector3]) -> Array[Vector3]:
	"""A stratified subset of the walkable samples, used as the eyes.

	Every nth sample rather than the first n: `_collect_samples` walks the grid
	in x-major order, so the first 96 of a wide site are one strip of its
	western edge and every sightline would be measured from there.
	"""
	var out: Array[Vector3] = []
	if samples.is_empty():
		return out
	var step: int = maxi(1, int(ceil(float(samples.size()) / float(max_viewpoints))))
	var i := 0
	while i < samples.size():
		out.append(samples[i] + Vector3.UP * EYE_HEIGHT)
		i += step
	return out
