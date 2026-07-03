extends Control
class_name LT_HealthBar
## Mega basic life tracker: one pip per hit point, bottom-left.
## Full = green, lost = dark outline. Flashes red on damage.

@export var pip_size: float = 22.0
@export var pip_gap: float = 6.0
@export var flash_seconds: float = 0.3

const COLOR_FULL := Color(0.25, 0.95, 0.35)
const COLOR_EMPTY := Color(0.15, 0.15, 0.15, 0.8)
const COLOR_FLASH := Color(1.0, 0.2, 0.2)
const COLOR_DEAD := Color(0.6, 0.1, 0.1)

var _current: int = 0
var _max: int = 0
var _flash_timer: float = 0.0
var _dead: bool = false
var _health: LT_Health

func _ready() -> void:
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func bind(health: LT_Health) -> void:
	if _health != null:
		if _health.damaged.is_connected(_on_damaged):
			_health.damaged.disconnect(_on_damaged)
		if _health.died.is_connected(_on_died):
			_health.died.disconnect(_on_died)
	_health = health
	_dead = false
	_flash_timer = 0.0
	if _health != null:
		_current = _health.current_health
		_max = _health.max_health
		_health.damaged.connect(_on_damaged)
		_health.died.connect(_on_died)
	_layout()
	queue_redraw()

func _layout() -> void:
	var width := float(_max) * pip_size + float(maxi(_max - 1, 0)) * pip_gap
	custom_minimum_size = Vector2(width, pip_size)
	size = custom_minimum_size
	position = Vector2(16, -16 - pip_size)

func _on_damaged(current: int, max_health: int) -> void:
	_current = current
	_max = max_health
	_flash_timer = flash_seconds
	queue_redraw()

func _on_died() -> void:
	_dead = true
	queue_redraw()

func _process(delta: float) -> void:
	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			queue_redraw()

func _draw() -> void:
	if _max <= 0:
		return
	for i in _max:
		var rect := Rect2(float(i) * (pip_size + pip_gap), 0.0, pip_size, pip_size)
		var filled := i < _current
		var color := COLOR_EMPTY
		if filled:
			color = COLOR_FLASH if _flash_timer > 0.0 else COLOR_FULL
		elif _dead:
			color = COLOR_DEAD
		draw_rect(rect, color)
		draw_rect(rect, Color.BLACK, false, 2.0)
