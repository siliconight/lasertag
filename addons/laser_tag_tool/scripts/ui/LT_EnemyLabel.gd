extends Label3D
class_name LT_EnemyLabel
## Overhead enemy debug label (TDD §21.3): name, HP, state, target, LOS.

@export var brain: LT_EnemyBrain
@export var health: LT_Health

var _body: Node3D

func _ready() -> void:
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	no_depth_test = true
	fixed_size = true
	pixel_size = 0.004
	modulate = Color.WHITE
	outline_modulate = Color.BLACK
	_body = get_parent() as Node3D
	if DisplayServer.get_name() == "headless":
		set_process(false)
		visible = false

func _process(_delta: float) -> void:
	if brain == null or health == null or _body == null:
		return
	var target_name := brain.target.name if brain.target != null else "-"
	var los := "CLEAR" if brain.had_los_last_frame else "BLOCKED"
	text = "%s\nHP: %d / %d\nSTATE: %s\nTARGET: %s\nLOS: %s" % [
		_body.name, health.current_health, health.max_health,
		brain.state_name(), target_name, los,
	]
