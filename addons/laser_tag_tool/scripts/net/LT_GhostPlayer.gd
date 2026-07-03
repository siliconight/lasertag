extends Node3D
class_name LT_GhostPlayer
## Visual-only representation of a remote peer: a translucent pill tinted
## with their cosmetic color, name label overhead. No collision, no
## health, no simulation — presence only.

var peer_id: int = 0

var _mesh: MeshInstance3D
var _material: StandardMaterial3D
var _label: Label3D
var _target_position: Vector3
var _target_rotation_y: float = 0.0
var _has_target: bool = false

func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.albedo_color = Color(1, 1, 1, 0.55)

	var capsule := CapsuleMesh.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	capsule.material = _material

	_mesh = MeshInstance3D.new()
	_mesh.mesh = capsule
	_mesh.position = Vector3.UP * 0.9
	add_child(_mesh)

	_label = Label3D.new()
	_label.position = Vector3.UP * 2.2
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = true
	_label.pixel_size = 0.004
	_label.outline_modulate = Color.BLACK
	add_child(_label)

func apply_cosmetic(cosmetic: Dictionary) -> void:
	var color := LT_Cosmetic.color_of(cosmetic)
	color.a = 0.55
	_material.albedo_color = color
	_label.text = "%s (#%d)" % [cosmetic.get("name", "Player"), peer_id]
	_label.modulate = LT_Cosmetic.color_of(cosmetic)

func set_remote_transform(position: Vector3, rotation_y: float) -> void:
	_target_position = position
	_target_rotation_y = rotation_y
	if not _has_target:
		global_position = position
		rotation.y = rotation_y
		_has_target = true

func _process(delta: float) -> void:
	if not _has_target:
		return
	# Cheap smoothing between 10 Hz updates.
	global_position = global_position.lerp(_target_position, minf(delta * 12.0, 1.0))
	rotation.y = lerp_angle(rotation.y, _target_rotation_y, minf(delta * 12.0, 1.0))
