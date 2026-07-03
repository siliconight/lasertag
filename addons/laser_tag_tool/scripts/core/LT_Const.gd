extends RefCounted
class_name LT_Const
## Shared constants for the Laser Tag Map Evaluation Tool.
## Collision layer plan (TDD §9):
##   Layer 1: World
##   Layer 2: Player
##   Layer 3: Enemy
##   Layer 4: Laser Blockers
##   Layer 5: Trigger Volumes
##   Layer 6: Debug Only

const LAYER_WORLD := 1 << 0
const LAYER_PLAYER := 1 << 1
const LAYER_ENEMY := 1 << 2
const LAYER_LASER_BLOCKER := 1 << 3
const LAYER_TRIGGER := 1 << 4
const LAYER_DEBUG := 1 << 5

## Laser shots hit world, players, enemies, and laser blockers (TDD §9).
const LASER_HIT_MASK := LAYER_WORLD | LAYER_PLAYER | LAYER_ENEMY | LAYER_LASER_BLOCKER

# Node groups
const GROUP_PLAYER := "lt_player"
const GROUP_ENEMY := "lt_enemy"
const GROUP_METRICS := "lt_metrics"
const GROUP_DEBUG := "lt_debug"
const GROUP_AUDIO := "lt_audio"
const GROUP_NET := "lt_net"
const GROUP_REGISTRY := "lt_player_registry"
const GROUP_HARNESS := "lt_harness"

# Map hook name prefixes (TDD §8)
const HOOK_PLAYER_SPAWN := "LT_PlayerSpawn"
const HOOK_ENEMY_SPAWNS := "LT_EnemySpawnPoints"
const HOOK_OBJECTIVE := "LT_ObjectivePoint"
const HOOK_ROUTE := "LT_PlayerRoutePoints"
const HOOK_COVER := "LT_CoverTestPoints"

# Debug laser colors (TDD §21.1)
const LASER_COLOR_PLAYER_HIT := Color(0.2, 1.0, 0.2)   # green: player hit enemy
const LASER_COLOR_ENEMY_HIT := Color(1.0, 0.15, 0.15)  # red: enemy hit player
const LASER_COLOR_MISS := Color(1.0, 1.0, 1.0)         # white: missed
const LASER_COLOR_BLOCKED := Color(0.55, 0.55, 0.55)   # gray: blocked by world
const LASER_COLOR_FRIENDLY := Color(1.0, 1.0, 0.2)     # yellow: friendly / ignored

# Default input actions, registered at runtime if missing.
const ACTION_FIRE := &"lt_fire"
const ACTION_FORWARD := &"lt_forward"
const ACTION_BACK := &"lt_back"
const ACTION_LEFT := &"lt_left"
const ACTION_RIGHT := &"lt_right"
const ACTION_JUMP := &"lt_jump"
const ACTION_RESET := &"lt_reset"
const ACTION_TOGGLE_MOUSE := &"lt_toggle_mouse"
const ACTION_COSMETIC_COLOR := &"lt_cosmetic_color"
const ACTION_COSMETIC_STYLE := &"lt_cosmetic_style"
const ACTION_TOGGLE_ENEMIES := &"lt_toggle_enemies"
const ACTION_SETTINGS := &"lt_settings"

static func ensure_input_actions() -> void:
	_ensure_key(ACTION_FORWARD, KEY_W)
	_ensure_key(ACTION_BACK, KEY_S)
	_ensure_key(ACTION_LEFT, KEY_A)
	_ensure_key(ACTION_RIGHT, KEY_D)
	_ensure_key(ACTION_JUMP, KEY_SPACE)
	_ensure_key(ACTION_RESET, KEY_R)
	_ensure_key(ACTION_TOGGLE_MOUSE, KEY_ESCAPE)
	_ensure_key(ACTION_COSMETIC_COLOR, KEY_C)
	_ensure_key(ACTION_COSMETIC_STYLE, KEY_V)
	_ensure_key(ACTION_TOGGLE_ENEMIES, KEY_N)
	_ensure_key(ACTION_SETTINGS, KEY_TAB)
	if not InputMap.has_action(ACTION_FIRE):
		InputMap.add_action(ACTION_FIRE)
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event(ACTION_FIRE, mb)

static func _ensure_key(action: StringName, keycode: Key) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	InputMap.action_add_event(action, ev)
