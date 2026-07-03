extends Control
class_name LT_Crosshair
## Center-screen crosshair with hit feedback states (TDD §12).
## Drawn in _draw so it ignores lighting entirely.

enum CrosshairState { DEFAULT, ENEMY_TARGETED, BLOCKED, HIT_CONFIRMED, MISSED, PLAYER_DEAD }

const COLORS := {
	CrosshairState.DEFAULT: Color.WHITE,
	CrosshairState.ENEMY_TARGETED: Color(1.0, 0.6, 0.2),
	CrosshairState.BLOCKED: Color(0.55, 0.55, 0.55),
	CrosshairState.HIT_CONFIRMED: Color(0.2, 1.0, 0.2),
	CrosshairState.MISSED: Color(1.0, 1.0, 1.0, 0.6),
	CrosshairState.PLAYER_DEAD: Color(1.0, 0.15, 0.15),
}

@export var line_length: float = 8.0
@export var gap: float = 4.0
@export var thickness: float = 2.0
@export var feedback_seconds: float = 0.25

var state: CrosshairState = CrosshairState.DEFAULT

var _feedback_timer: float = 0.0
var _dead: bool = false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func flash(new_state: CrosshairState) -> void:
	if _dead:
		return
	state = new_state
	_feedback_timer = feedback_seconds
	queue_redraw()

func flash_for_shot(shot: LT_ShotResult) -> void:
	match shot.hit_type:
		"ENEMY_HIT":
			flash(CrosshairState.HIT_CONFIRMED)
		"WORLD_BLOCKED":
			flash(CrosshairState.BLOCKED)
		"MISS":
			flash(CrosshairState.MISSED)

func set_dead(dead: bool) -> void:
	_dead = dead
	state = CrosshairState.PLAYER_DEAD if dead else CrosshairState.DEFAULT
	queue_redraw()

func _process(delta: float) -> void:
	if _feedback_timer > 0.0:
		_feedback_timer -= delta
		if _feedback_timer <= 0.0 and not _dead:
			state = CrosshairState.DEFAULT
			queue_redraw()

func _draw() -> void:
	var center := size * 0.5
	var color: Color = COLORS[state]

	draw_circle(center, thickness * 0.75, color)
	draw_line(center + Vector2(gap, 0), center + Vector2(gap + line_length, 0), color, thickness)
	draw_line(center - Vector2(gap, 0), center - Vector2(gap + line_length, 0), color, thickness)
	draw_line(center + Vector2(0, gap), center + Vector2(0, gap + line_length), color, thickness)
	draw_line(center - Vector2(0, gap), center - Vector2(0, gap + line_length), color, thickness)
