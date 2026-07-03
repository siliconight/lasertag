extends Node3D
class_name LT_DebugLaser
## Draws fading 3D laser tracers for every shot (TDD §21.1), now
## cosmetic-aware:
##   - Player-fired tracers use the shooter's COSMETIC color + style
##     (solid / dashed / rail) when an LT_CoopSession knows that peer —
##     including remote peers' shots, so everyone sees your look.
##   - Enemy shots and un-cosmeticed shooters keep the semantic palette
##     (red = enemy hit you, gray = blocked, white = miss).
##   - The hit MARKER always stays semantic (green/red/gray), so eval
##     readability survives any cosmetic choice.
## Also bridges to the debug-shot-tracers addon: if a ShotDebugBus
## autoload exists, every shot is forwarded with cosmetic metadata so
## DebugTracerManager renders it too.
## Listens on the "lt_debug" group: draw_shot(shot).

const DASH_LENGTH := 0.5
const RAIL_OFFSET := 0.05

@export var enabled: bool = true
@export var laser_lifetime: float = 0.6
@export var forward_to_shot_debug_bus: bool = true

var crosshair: LT_Crosshair

var _bus: Node

func _ready() -> void:
	add_to_group(LT_Const.GROUP_DEBUG)
	if DisplayServer.get_name() == "headless":
		enabled = false
		return
	if forward_to_shot_debug_bus:
		_bus = get_tree().root.get_node_or_null("ShotDebugBus")
		if _bus != null and not _bus.has_method("report"):
			_bus = null

func draw_shot(shot: LT_ShotResult) -> void:
	var is_local_player_shot := shot.shooter_is_player \
		and shot.shooter_peer_id == multiplayer.get_unique_id()
	if crosshair != null and is_local_player_shot:
		crosshair.flash_for_shot(shot)

	if shot.hit_type == "INVALID":
		return

	_forward_to_bus(shot)

	if not enabled:
		return

	var cosmetic := _cosmetic_for(shot)
	var color := _semantic_color(shot)
	var style := "solid"
	if shot.shooter_is_player and not cosmetic.is_empty():
		color = LT_Cosmetic.color_of(cosmetic)
		style = LT_Cosmetic.style_of(cosmetic)

	match style:
		"dashed":
			_draw_dashed(shot.start_position, shot.end_position, color)
		"rail":
			_draw_rail(shot.start_position, shot.end_position, color)
		_:
			_draw_segments([[shot.start_position, shot.end_position]], color)

	if shot.did_hit:
		_spawn_hit_marker(shot.hit_position, _semantic_color(shot))

func _cosmetic_for(shot: LT_ShotResult) -> Dictionary:
	var session := get_tree().get_first_node_in_group(LT_Const.GROUP_NET)
	if session == null or not session.has_method("get_cosmetic_for_peer"):
		return {}
	return session.get_cosmetic_for_peer(shot.shooter_peer_id)

## ---- Line drawing ----

func _draw_dashed(start_position: Vector3, end_position: Vector3, color: Color) -> void:
	var segments: Array = []
	var total := start_position.distance_to(end_position)
	var direction := (end_position - start_position).normalized()
	var travelled := 0.0
	while travelled < total:
		var dash_end := minf(travelled + DASH_LENGTH, total)
		segments.append([
			start_position + direction * travelled,
			start_position + direction * dash_end,
		])
		travelled += DASH_LENGTH * 2.0
	_draw_segments(segments, color)

func _draw_rail(start_position: Vector3, end_position: Vector3, color: Color) -> void:
	var direction := (end_position - start_position).normalized()
	var side := direction.cross(Vector3.UP).normalized()
	if side.is_zero_approx():
		side = Vector3.RIGHT
	var offset := side * RAIL_OFFSET
	_draw_segments([
		[start_position + offset, end_position + offset],
		[start_position - offset, end_position - offset],
	], color)

func _draw_segments(segments: Array, color: Color) -> void:
	if segments.is_empty():
		return
	var mesh_instance := MeshInstance3D.new()
	var immediate := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	immediate.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for segment in segments:
		immediate.surface_add_vertex(segment[0])
		immediate.surface_add_vertex(segment[1])
	immediate.surface_end()

	mesh_instance.mesh = immediate
	mesh_instance.top_level = true
	add_child(mesh_instance)

	var tween := mesh_instance.create_tween()
	tween.tween_property(material, "albedo_color:a", 0.0, laser_lifetime)
	tween.tween_callback(mesh_instance.queue_free)

func _spawn_hit_marker(position: Vector3, color: Color) -> void:
	var marker := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.06
	sphere.height = 0.12
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	sphere.material = material
	marker.mesh = sphere
	marker.top_level = true
	add_child(marker)
	marker.global_position = position

	var tween := marker.create_tween()
	tween.tween_interval(laser_lifetime)
	tween.tween_callback(marker.queue_free)

func _semantic_color(shot: LT_ShotResult) -> Color:
	match shot.hit_type:
		"ENEMY_HIT":
			return LT_Const.LASER_COLOR_PLAYER_HIT
		"PLAYER_HIT":
			return LT_Const.LASER_COLOR_ENEMY_HIT
		"WORLD_BLOCKED":
			return LT_Const.LASER_COLOR_BLOCKED
		"FRIENDLY_HIT":
			return LT_Const.LASER_COLOR_FRIENDLY
		_:
			return LT_Const.LASER_COLOR_MISS

## ---- debug-shot-tracers bridge ----

func _forward_to_bus(shot: LT_ShotResult) -> void:
	if _bus == null:
		return
	var cosmetic := _cosmetic_for(shot)
	_bus.report({
		"origin": shot.start_position,
		"end_position": shot.end_position,
		"shooter_type": StringName("player") if shot.shooter_is_player else StringName("enemy"),
		"hit_type": _bus_hit_type(shot),
		"weapon_id": StringName("lt_laser"),
		"metadata": {
			"shooter_peer_id": shot.shooter_peer_id,
			"cosmetic": cosmetic,
		},
	})

func _bus_hit_type(shot: LT_ShotResult) -> StringName:
	match shot.hit_type:
		"ENEMY_HIT":
			return &"enemy"
		"PLAYER_HIT", "FRIENDLY_HIT":
			return &"friendly"
		"WORLD_BLOCKED":
			return &"blocked"
		_:
			return &"miss"
