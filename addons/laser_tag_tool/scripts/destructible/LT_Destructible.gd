extends Node
class_name LT_Destructible
## Replicated destructible proxy: breakable glass and other simple
## destructibles (window -> broken, crate -> destroyed, monitor -> smashed).
##
## The shards are not the glass — the STATE is the glass. The authoritative
## gameplay representation of this object is deliberately tiny: an id, hit
## points, an intact/broken flag, and a collision toggle. Everything
## expensive-looking about the break (debris, particles, sound) is a local,
## cosmetic, short-lived event that each peer plays for itself and that
## never needs to agree between machines.
##
## Node MUST be named "LT_Destructible" and sit on the CollisionObject3D it
## proxies (same name-lookup convention as LT_Health) — LT_Shooter finds it
## by name on whatever body blocked the shot.
##
## Works fully offline: with no LT_DestructibleSync in the tree, hits apply
## locally and the break is solo. With a sync node present, hits route
## through it and gameplay state follows its authority rules — this node
## then only mutates state via deduct_hit_points / apply_break /
## reset_intact.

signal broke(impact_point: Vector3, impact_direction: Vector3, break_seed: int)
signal state_changed(is_broken: bool)

## THE SEAM for game-driven fixtures (game_driven = true). A stimulus
## arrived -- a shot, a charge -- but this node decided nothing: your
## gameplay/networking layer owns the state machine (INTERACTIVES.md
## ownership table), so it hears the request, arbitrates, replicates,
## and calls apply_break()/reset_intact() on every peer when it has an
## answer. `blast` distinguishes register_blast from a bullet hit.
signal break_requested(damage: int, impact_point: Vector3,
		impact_direction: Vector3, blast: bool)

## Cosmetic break patterns, selected deterministically on every peer from
## hash(destructible_id + break_seed) % pattern_count — no per-shard
## networking. With authored debris_scenes the same index picks the scene.
const PATTERN_BURST := 0
const PATTERN_CONE := 1
const PATTERN_RAIN := 2
const PATTERN_COUNT := 3

## Shard counts per debris_quality tier (low / medium / high). Visuals may
## scale with hardware; collision and gameplay state never do.
const SHARD_COUNTS: Array[int] = [6, 12, 20]

## Debris styles: what the pieces ARE decides how they fly. Glass is thin
## plates that burst and spin; rubble is heavy chunks that tumble out low
## and drop -- a breach should never read as a glitter bomb.
const STYLE_GLASS := 0
const STYLE_RUBBLE := 1

## Stable identity used for replication and late-join snapshots. Leave
## empty to derive from the node path — stable across peers as long as the
## scene layout matches (the same constraint rpc already puts on the
## harness).
@export var destructible_id: String = ""
@export var hit_points: int = 1

## Bullets break glass; bombs break breaches. When false, bullet hits
## (register_hit, the LT_Shooter path) are ignored and only
## register_blast breaks this -- the right setting for a breach wall or
## anything else that answers to a charge rather than small arms. The
## replication path is identical either way; only the trigger differs.
@export var bullet_breakable: bool = true

## When true, this fixture's STATE belongs to the game, not the toolset
## -- doors and breach walls per INTERACTIVES.md, where the gameplay/
## networking layer replicates one state enum per interactive id.
## Stimuli are then only REPORTED (the break_requested signal); nothing
## breaks until your code calls apply_break(), and LT_DestructibleSync
## ignores this node entirely (no requests, no broadcasts, no
## snapshots), so the two authorities can never fight over one pane.
## The intact/broken presentation API is yours: apply_break(),
## reset_intact(), the broke/state_changed signals, and destructible_id
## to correlate with the gameplay.json interactive id.
@export var game_driven: bool = false

## CollisionObject3D whose collision this proxy owns. Defaults to the
## parent. On break its collision_layer is zeroed (lasers and bodies pass);
## reset_intact restores the saved layer.
@export var body_path: NodePath

## Hidden on break. Defaults to the first MeshInstance3D child of the body.
@export var intact_visual_path: NodePath

## Optional pre-authored broken-state visual (empty frame, wreck, stump).
## Hidden until the break, shown after — including for late joiners.
@export var broken_visual_path: NodePath

## Optional authored debris library: the selected pattern index picks one
## scene, instantiated locally at the break. Empty = procedural shards.
@export var debris_scenes: Array[PackedScene] = []

@export_enum("low", "medium", "high") var debris_quality: int = 1

## glass = thin plates, upward burst, fast spin. rubble = chunky blocks,
## low heavy tumble, slow spin, its own audio hook (play_breach). Pick
## rubble for breach walls and anything masonry-like.
@export_enum("glass", "rubble") var debris_style: int = STYLE_GLASS
@export var debris_lifetime: float = 4.0
@export var debris_color: Color = Color(0.62, 0.82, 0.94, 0.85)
@export var shard_size: float = 0.16

var broken: bool = false

var _hp: int = 1
var _body: CollisionObject3D
var _intact_visual: Node3D
var _broken_visual: Node3D
var _saved_collision_layer: int = 0

func _ready() -> void:
	add_to_group(LT_Const.GROUP_DESTRUCTIBLE)
	_hp = maxi(1, hit_points)

	if body_path.is_empty():
		var parent := get_parent()
		if parent is CollisionObject3D:
			_body = parent
	else:
		_body = get_node_or_null(body_path) as CollisionObject3D
	if _body == null:
		push_warning("LT_Destructible '%s': no CollisionObject3D body; collision will not toggle" % name)
	else:
		_saved_collision_layer = _body.collision_layer

	if not intact_visual_path.is_empty():
		_intact_visual = get_node_or_null(intact_visual_path) as Node3D
	if _intact_visual == null and _body != null:
		for child in _body.get_children():
			if child is MeshInstance3D:
				_intact_visual = child
				break

	if not broken_visual_path.is_empty():
		_broken_visual = get_node_or_null(broken_visual_path) as Node3D
	if _broken_visual != null and not broken:
		_broken_visual.visible = false

	if destructible_id.is_empty():
		destructible_id = str(get_path())

## Entry point for BULLET hits (LT_Shooter calls this from its blocked
## branch). Gated by bullet_breakable -- a breach wall says no to bullets
## and yes to charges. Everything else routes identically.
func register_hit(damage: int, impact_point: Vector3, impact_direction: Vector3) -> void:
	if not bullet_breakable:
		return
	if broken:
		return
	if game_driven:
		break_requested.emit(damage, impact_point, impact_direction, false)
		return
	register_blast(damage, impact_point, impact_direction)

## Trigger-agnostic entry: breach charges, explosions, scripted events.
## Never gated by bullet_breakable -- a bomb breaks anything breakable.
## Routes through the sync's authority exactly like a bullet hit, so a
## charge-triggered break replicates and snapshots the same way a
## shot-out pane does. On a game-driven fixture nothing routes: the
## stimulus is reported and the game decides.
func register_blast(damage: int, impact_point: Vector3, impact_direction: Vector3) -> void:
	if broken:
		return
	if game_driven:
		break_requested.emit(damage, impact_point, impact_direction, true)
		return
	var sync := get_tree().get_first_node_in_group(LT_Const.GROUP_DESTRUCTIBLE_SYNC)
	if sync != null and sync.has_method("route_hit"):
		sync.route_hit(self, damage, impact_point, impact_direction)
	else:
		take_local_damage(damage, impact_point, impact_direction)

## Offline / no-sync damage path: deduct and break in one place.
func take_local_damage(damage: int, impact_point: Vector3, impact_direction: Vector3) -> void:
	if not deduct_hit_points(damage):
		return
	var break_seed := randi() & 0x7FFFFFFF
	apply_break(impact_point, impact_direction, break_seed, true)

## Deduct hit points from the canonical copy (the authority's node, or the
## local one offline). Returns true when this hit is the breaking hit.
func deduct_hit_points(damage: int) -> bool:
	if broken:
		return false
	_hp -= maxi(1, damage)
	return _hp <= 0

## Flip to the broken gameplay state. Idempotent. with_effects false is the
## late-join path: persistent state without the transient event — collision
## and visuals only, no debris, no sound.
func apply_break(impact_point: Vector3, impact_direction: Vector3, break_seed: int,
		with_effects: bool = true) -> void:
	if broken:
		return
	broken = true
	_hp = 0
	_set_collision_enabled(false)
	if _intact_visual != null:
		_intact_visual.visible = false
	if _broken_visual != null:
		_broken_visual.visible = true
	if with_effects:
		_play_break_effects(impact_point, impact_direction, break_seed)
	state_changed.emit(true)
	broke.emit(impact_point, impact_direction, break_seed)

## Restore the intact gameplay state (fresh run, round reset). Local only —
## call it on every peer that needs it, or before a session starts.
func reset_intact() -> void:
	if not broken:
		return
	broken = false
	_hp = maxi(1, hit_points)
	_set_collision_enabled(true)
	if _intact_visual != null:
		_intact_visual.visible = true
	if _broken_visual != null:
		_broken_visual.visible = false
	state_changed.emit(false)

func _set_collision_enabled(enabled: bool) -> void:
	if _body == null:
		return
	if enabled:
		_body.collision_layer = _saved_collision_layer
	else:
		_saved_collision_layer = _body.collision_layer
		_body.collision_layer = 0

## ---- Cosmetic break (local per peer, never networked) ----

func _play_break_effects(impact_point: Vector3, impact_direction: Vector3, break_seed: int) -> void:
	# Rubble prefers its own hook (a breach is a thud, not a chime) and
	# falls back to the shared one, so audio stays progressive too.
	for node in get_tree().get_nodes_in_group(LT_Const.GROUP_AUDIO):
		if debris_style == STYLE_RUBBLE and node.has_method("play_breach"):
			node.call("play_breach", impact_point)
		elif node.has_method("play_break"):
			node.call("play_break", impact_point)

	var origin := impact_point
	if _body != null:
		origin = _body.global_position

	if debris_scenes.size() > 0:
		_spawn_authored_debris(origin, impact_direction, break_seed)
		return
	_spawn_procedural_shards(impact_point, impact_direction, break_seed)

## Same-formula pattern pick on every peer: hash(id + seed) % count.
func _pattern_index(break_seed: int, pattern_count: int) -> int:
	if pattern_count <= 0:
		return 0
	return absi(hash(destructible_id + ":" + str(break_seed))) % pattern_count

func _spawn_authored_debris(origin: Vector3, impact_direction: Vector3,
		break_seed: int) -> void:
	var index := _pattern_index(break_seed, debris_scenes.size())
	var scene: PackedScene = debris_scenes[index]
	if scene == null:
		return
	var instance := scene.instantiate()
	instance.add_to_group(LT_Const.GROUP_DEBRIS)
	_debris_parent().add_child(instance)
	if instance is Node3D:
		instance.global_position = origin
	# An authored set that ships its own physics animates itself. A plain
	# mesh set -- a zoo glass_shard GLB imports as MeshInstance3Ds under a
	# Node3D -- gets each mesh wrapped in a cosmetic rigid body with a
	# seeded impulse, so a shards GLB drops straight into debris_scenes
	# with no manual setup.
	if _find_rigid_bodies(instance).is_empty():
		_fling_plain_meshes(instance, impact_direction, break_seed)
	_schedule_debris_cleanup(instance, null)

func _fling_plain_meshes(container: Node, impact_direction: Vector3,
		break_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = break_seed
	var pattern := _pattern_index(break_seed, PATTERN_COUNT)
	for found in _find_meshes(container):
		var mesh_node: MeshInstance3D = found
		var aabb := AABB(Vector3.ZERO, Vector3(0.05, 0.05, 0.05))
		if mesh_node.mesh != null:
			aabb = mesh_node.mesh.get_aabb()
		var center := aabb.get_center()
		var world := mesh_node.global_transform
		mesh_node.get_parent().remove_child(mesh_node)
		var shard := RigidBody3D.new()
		# Cosmetic-only, same law as the procedural shards: on no layer,
		# colliding only WITH world so debris settles.
		shard.collision_layer = 0
		shard.collision_mask = LT_Const.LAYER_WORLD
		container.add_child(shard)
		# Body origin at the shard's own centroid, so spin reads as the
		# piece tumbling rather than orbiting the set's origin.
		shard.global_transform = world * Transform3D(Basis.IDENTITY, center)
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = aabb.size.max(Vector3(0.02, 0.02, 0.02))
		collision.shape = shape
		shard.add_child(collision)
		shard.add_child(mesh_node)
		mesh_node.transform = Transform3D(Basis.IDENTITY, -center)
		shard.linear_velocity = _shard_velocity(pattern, impact_direction, rng)
		shard.angular_velocity = Vector3(
			rng.randf_range(-6.0, 6.0), rng.randf_range(-6.0, 6.0),
			rng.randf_range(-6.0, 6.0))

func _find_rigid_bodies(root: Node) -> Array:
	var out: Array = []
	_collect_by_class(root, "RigidBody3D", out)
	return out

func _find_meshes(root: Node) -> Array:
	var out: Array = []
	_collect_by_class(root, "MeshInstance3D", out)
	return out

func _collect_by_class(node: Node, klass: String, out: Array) -> void:
	if node.is_class(klass):
		out.append(node)
	for child in node.get_children():
		_collect_by_class(child, klass, out)

func _spawn_procedural_shards(impact_point: Vector3, impact_direction: Vector3,
		break_seed: int) -> void:
	var root := Node3D.new()
	root.name = "LT_Debris"
	root.add_to_group(LT_Const.GROUP_DEBRIS)
	_debris_parent().add_child(root)

	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = debris_color

	var mesh := BoxMesh.new()
	if debris_style == STYLE_RUBBLE:
		# A chunk, not a plate: near-cubic proportions read as masonry.
		mesh.size = Vector3(shard_size, shard_size * 0.7, shard_size * 0.55)
	else:
		mesh.size = Vector3(shard_size, shard_size, shard_size * 0.25)
	mesh.material = material

	var shape := BoxShape3D.new()
	shape.size = mesh.size

	var rng := RandomNumberGenerator.new()
	rng.seed = break_seed
	var tier := clampi(debris_quality, 0, SHARD_COUNTS.size() - 1)
	var count: int = SHARD_COUNTS[tier]
	var pattern := _pattern_index(break_seed, PATTERN_COUNT)

	for i in count:
		var shard := RigidBody3D.new()
		# Cosmetic-only: on no layer (nothing scans for shards), colliding
		# only WITH world so debris settles instead of falling through.
		shard.collision_layer = 0
		shard.collision_mask = LT_Const.LAYER_WORLD
		var collision := CollisionShape3D.new()
		collision.shape = shape
		shard.add_child(collision)
		var visual := MeshInstance3D.new()
		visual.mesh = mesh
		shard.add_child(visual)
		root.add_child(shard)
		shard.global_position = impact_point + Vector3(
			rng.randf_range(-0.3, 0.3), rng.randf_range(-0.3, 0.3), rng.randf_range(-0.3, 0.3))
		shard.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
		shard.linear_velocity = _shard_velocity(pattern, impact_direction, rng)
		var spin := 3.0 if debris_style == STYLE_RUBBLE else 6.0
		shard.angular_velocity = Vector3(
			rng.randf_range(-spin, spin), rng.randf_range(-spin, spin),
			rng.randf_range(-spin, spin))

	_schedule_debris_cleanup(root, material)

func _shard_velocity(pattern: int, impact_direction: Vector3,
		rng: RandomNumberGenerator) -> Vector3:
	if debris_style == STYLE_RUBBLE:
		return _rubble_velocity(pattern, impact_direction, rng)
	var scatter := Vector3(
		rng.randf_range(-1.0, 1.0), rng.randf_range(0.0, 1.0), rng.randf_range(-1.0, 1.0))
	match pattern:
		PATTERN_CONE:
			var forward := Vector3.DOWN
			if not impact_direction.is_zero_approx():
				forward = impact_direction.normalized()
			return forward * rng.randf_range(2.5, 4.5) + scatter * 1.2
		PATTERN_RAIN:
			return Vector3(scatter.x * 0.8, rng.randf_range(-1.0, 0.5), scatter.z * 0.8)
		_:
			var out := scatter
			if out.is_zero_approx():
				out = Vector3.UP
			return out.normalized() * rng.randf_range(2.0, 5.0)

## Rubble flies like masonry: out through the hole and down, never up in
## a glitter burst. Every profile keeps the vertical component small
## (|vy| <= 0.6), which is also what the test runner asserts -- the
## difference from glass is a bound, not a vibe.
func _rubble_velocity(pattern: int, impact_direction: Vector3,
		rng: RandomNumberGenerator) -> Vector3:
	var forward := Vector3(impact_direction.x, 0.0, impact_direction.z)
	if forward.is_zero_approx():
		var angle := rng.randf() * TAU
		forward = Vector3(cos(angle), 0.0, sin(angle))
	forward = forward.normalized()
	var side := Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)) * 0.5
	match pattern:
		PATTERN_CONE:
			# kicked through: the charge's direction dominates
			return forward * rng.randf_range(1.4, 2.2) + side \
					+ Vector3(0.0, rng.randf_range(0.0, 0.45), 0.0)
		PATTERN_RAIN:
			# slump: barely clears the hole, drops at its feet
			return forward * rng.randf_range(0.4, 0.9) + side * 0.6 \
					+ Vector3(0.0, rng.randf_range(-0.6, 0.0), 0.0)
		_:
			# tumble out: default masonry spill
			return forward * rng.randf_range(0.9, 1.7) + side \
					+ Vector3(0.0, rng.randf_range(-0.2, 0.35), 0.0)

func _debris_parent() -> Node:
	if _body != null and _body.get_parent() != null:
		return _body.get_parent()
	return get_parent()

func _schedule_debris_cleanup(debris: Node, material: StandardMaterial3D) -> void:
	var fade_time := minf(1.0, maxf(0.1, debris_lifetime * 0.25))
	var solid_time := maxf(0.0, debris_lifetime - fade_time)
	get_tree().create_timer(solid_time).timeout.connect(
		_fade_and_free.bind(debris, material, fade_time))

func _fade_and_free(debris: Node, material: StandardMaterial3D, fade_time: float) -> void:
	if not is_instance_valid(debris):
		return
	if material == null:
		debris.queue_free()
		return
	var tween := debris.create_tween()
	tween.tween_property(material, "albedo_color:a", 0.0, fade_time)
	tween.tween_callback(debris.queue_free)
