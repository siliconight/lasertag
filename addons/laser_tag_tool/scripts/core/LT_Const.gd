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
const GROUP_DESTRUCTIBLE := "lt_destructible"
const GROUP_DESTRUCTIBLE_SYNC := "lt_destructible_sync"
# Every cosmetic debris root (procedural shards or an instanced authored
# set) joins this group. Membership is the ONLY reliable handle: node
# names are not one, because a sibling name collision renames the
# newcomer to "@<Class>@<id>" and discards the authored name entirely --
# measured on 4.3, and it silently blinded a test that counted by name.
const GROUP_DEBRIS := "lt_debris"

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

## Deterministic lateral offset for the Nth reuse of one spawn point.
## Spawning two CharacterBody3Ds at the same position feeds Godot's
## overlap recovery every physics frame: each treats the other as
## floor, gravity never engages, and the stack ratchets skyward
## forever (measured 160 m up after 1.5 s). Golden-angle spiral, so
## every reuse gets its own level spot with no randomness and the
## radius grows as a point gets more crowded. reuse_index 0 is the
## first use: the point itself, no offset.
static func spawn_ring_offset(reuse_index: int) -> Vector3:
	if reuse_index <= 0:
		return Vector3.ZERO
	var angle := float(reuse_index) * 2.399963  # golden angle in radians
	var radius := 1.0 + 0.25 * float(reuse_index)
	return Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)

## How near a waypoint must be before a body counts it reached -- ONE
## definition for every body (0.26.0). Three terms, combined in 3D because
## Godot measures `path_desired_distance` that way: the body's radius (a
## waypoint inside its own footprint IS reached), one physics tick of travel
## (below it the body steps over the threshold between two samples), and half
## a cell height (what `path_height_offset` cannot remove). The crew's
## controller derived this inline from 0.18.0; the enemy took the pill
## scene's 0.8 until 0.26.0 -- the value 0.18.0 measured cutting corners.
static func arrival_radius(radius: float, speed: float, ticks: float,
		cell_height: float) -> float:
	var horizontal: float = maxf(0.05, radius) + speed / maxf(1.0, ticks)
	var vertical: float = cell_height * 0.5
	return sqrt(horizontal * horizontal + vertical * vertical)

## THE NAVIGATION MAP UPDATES ON THE CALLER'S THREAD (0.27.0, factory roadmap
## 239). Godot 4.7 runs a map's and a region's iterations on worker threads
## unless told otherwise, so WHEN a navigation update lands is wall time, and
## an evaluation that reads it repeats only as far as the machine is idle:
## three evaluations at once moved a few event positions by 0.01 m, and the
## engine's `--fixed-fps` clock moved a crew's stuck count 9 -> 21 with the
## physics step unchanged. Synchronous, every report measured read the same
## under either clock and any load. This sets the world's map, every region
## under `scene_root` and each region's own map, and returns how many regions
## it set. The setters are server COMMANDS that land at the next sync -- read
## straight back they still say asynchronous (measured) -- so a caller lets a
## physics frame pass before it asks `navigation_is_synchronous`.
static func synchronous_navigation(scene_root: Node) -> int:
	var count := 0
	var viewport: Viewport = scene_root.get_viewport()
	if viewport != null and viewport.get_world_3d() != null:
		NavigationServer3D.map_set_use_async_iterations(
			viewport.get_world_3d().navigation_map, false)
	for node in scene_root.find_children("*", "NavigationRegion3D", true, false):
		var region: NavigationRegion3D = node as NavigationRegion3D
		if region.get_navigation_map().is_valid():
			NavigationServer3D.map_set_use_async_iterations(region.get_navigation_map(), false)
		NavigationServer3D.region_set_use_async_iterations(region.get_rid(), false)
		count += 1
	return count

## Whether the world's map and every region under `scene_root` (and its map)
## update synchronously: the dial read back, once the commands have landed.
static func navigation_is_synchronous(scene_root: Node) -> bool:
	var viewport: Viewport = scene_root.get_viewport()
	if viewport != null and viewport.get_world_3d() != null:
		if NavigationServer3D.map_get_use_async_iterations(viewport.get_world_3d().navigation_map):
			return false
	for node in scene_root.find_children("*", "NavigationRegion3D", true, false):
		var region: NavigationRegion3D = node as NavigationRegion3D
		if NavigationServer3D.region_get_use_async_iterations(region.get_rid()):
			return false
		if region.get_navigation_map().is_valid() \
				and NavigationServer3D.map_get_use_async_iterations(region.get_navigation_map()):
			return false
	return true

static func _ensure_key(action: StringName, keycode: Key) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	InputMap.action_add_event(action, ev)
