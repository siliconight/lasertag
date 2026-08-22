extends Node
class_name LT_ShowcaseDriver
## Eyeball-pass driver for the destructible showcase -- and a LIVE
## example of the game-driven seam your netcode will implement.
##
## Press B: set off a "charge" against the breach wall. The wall is
## game_driven, so it only REPORTS (break_requested); this script plays
## the game's role -- hears the request, arbitrates (instantly, here),
## and orders apply_break(). A real game replicates that decision per
## INTERACTIVES.md; the loop below is the whole integration shape.
##
## Press G: hand every destructible back intact (round reset).

@export var breach_wall_path: NodePath

const ACTION_BREACH := &"lt_demo_breach"
const ACTION_RESTORE := &"lt_demo_restore"

var _wall: LT_Destructible

func _ready() -> void:
	_ensure_key(ACTION_BREACH, KEY_B)
	_ensure_key(ACTION_RESTORE, KEY_G)
	_wall = get_node_or_null(breach_wall_path) as LT_Destructible
	if _wall == null:
		push_warning("LT_ShowcaseDriver: no breach wall at breach_wall_path")
		return
	# THE SEAM, wired: stimulus in ...
	_wall.break_requested.connect(_on_break_requested)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION_BREACH):
		if _wall == null or _wall.broken:
			return
		print("[LT showcase] charge set against the game-driven wall")
		var origin := Vector3.ZERO
		var body := _wall.get_parent()
		if body is Node3D:
			origin = body.global_position
		_wall.register_blast(1, origin, Vector3(0, 0, -1))
	elif event.is_action_pressed(ACTION_RESTORE):
		for node in get_tree().get_nodes_in_group(LT_Const.GROUP_DESTRUCTIBLE):
			if node is LT_Destructible:
				node.reset_intact()
		print("[LT showcase] all destructibles restored intact")

## ... decision out. This is the game's half of the contract: arbitrate,
## replicate if online, then order the presentation to change state.
func _on_break_requested(damage: int, impact_point: Vector3,
		impact_direction: Vector3, blast: bool) -> void:
	print("[LT showcase] break_requested(dmg=%d, blast=%s) -> approved" % [
		damage, str(blast)])
	_wall.apply_break(impact_point, impact_direction,
			randi() & 0x7FFFFFFF, true)

func _ensure_key(action: StringName, keycode: Key) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	InputMap.action_add_event(action, ev)
