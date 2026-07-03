extends Node
class_name LT_PlayerController
## Manual solo test controller (TDD §7.1, §13.4).
## First-person movement + mouse look + strictly manual fire:
## one press = one shot; holding fire never repeats (TDD §6.4).

@export var body: CharacterBody3D
@export var camera: Camera3D
@export var shooter: LT_Shooter
@export var fire_action: StringName = LT_Const.ACTION_FIRE

@export_group("Movement")
@export var move_speed: float = 5.0
@export var jump_velocity: float = 4.5
@export var mouse_sensitivity: float = 0.0025

var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
var _pitch: float = 0.0
var _dead: bool = false

func _ready() -> void:
	if body == null and get_parent() is CharacterBody3D:
		body = get_parent()
	if body != null and body.has_node("LT_Health"):
		var health: LT_Health = body.get_node("LT_Health")
		health.died.connect(func() -> void: _dead = true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(LT_Const.ACTION_TOGGLE_MOUSE):
		var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if captured else Input.MOUSE_MODE_CAPTURED
		return

	if _dead:
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		body.rotate_y(-event.relative.x * mouse_sensitivity)
		_pitch = clampf(_pitch - event.relative.y * mouse_sensitivity, -PI * 0.49, PI * 0.49)
		if camera != null:
			camera.rotation.x = _pitch

	# is_action_pressed on the event fires once per physical press —
	# echo/held input never reaches here as a new press.
	if event.is_action_pressed(fire_action):
		fire_once()

func fire_once() -> void:
	if camera == null or shooter == null or _dead:
		return

	var direction := -camera.global_transform.basis.z
	var shot := shooter.fire(direction)

	get_tree().call_group(LT_Const.GROUP_METRICS, "record_shot", shot)
	get_tree().call_group(LT_Const.GROUP_DEBUG, "draw_shot", shot)
	get_tree().call_group(LT_Const.GROUP_AUDIO, "play_shot", shot)
	get_tree().call_group(LT_Const.GROUP_NET, "relay_shot", shot)

func _physics_process(delta: float) -> void:
	if body == null:
		return

	if not body.is_on_floor():
		body.velocity.y -= gravity * delta

	if _dead:
		body.velocity.x = 0.0
		body.velocity.z = 0.0
		body.move_and_slide()
		return

	if Input.is_action_just_pressed(LT_Const.ACTION_JUMP) and body.is_on_floor():
		body.velocity.y = jump_velocity

	var input_dir := Input.get_vector(
		LT_Const.ACTION_LEFT, LT_Const.ACTION_RIGHT,
		LT_Const.ACTION_FORWARD, LT_Const.ACTION_BACK)
	var direction := (body.transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	if direction != Vector3.ZERO:
		body.velocity.x = direction.x * move_speed
		body.velocity.z = direction.z * move_speed
	else:
		body.velocity.x = move_toward(body.velocity.x, 0.0, move_speed)
		body.velocity.z = move_toward(body.velocity.z, 0.0, move_speed)

	body.move_and_slide()
