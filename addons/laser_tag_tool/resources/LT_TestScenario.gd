extends Resource
class_name LT_TestScenario
## Test scenario configuration (TDD §20).

@export var map_scene: PackedScene
@export var run_count: int = 25
@export var max_run_time_seconds: float = 180.0

@export_group("Health")
@export var player_health: int = 5
@export var enemy_health: int = 2

@export_group("Counts")
@export var player_count: int = 1
@export var enemy_count: int = 6
## Free-roam switch: false = no enemies spawn (hangout / cosmetic
## show-off mode). Toggle live in manual mode with [N]. Default ON.
@export var enemies_enabled: bool = true

@export_group("Combat Tuning")
@export var player_laser_range: float = 60.0
@export var enemy_laser_range: float = 35.0
@export var enemy_fire_cooldown: float = 1.25
@export var enemy_reaction_delay_min: float = 0.25
@export var enemy_reaction_delay_max: float = 0.5
@export var enemy_sight_range: float = 35.0
@export var enemy_preferred_distance: float = 14.0

@export_group("Pacing Targets")
## First contact inside this window scores full pacing points (TDD §18.2).
@export var first_contact_min_seconds: float = 3.0
@export var first_contact_max_seconds: float = 30.0
## Player dying before this counts as "no reasonable reaction time".
@export var min_reasonable_survival_seconds: float = 10.0

@export_group("Options")
@export var use_random_spawn_permutations: bool = true
@export var use_bot_players: bool = true
@export var enable_debug_lasers: bool = true
@export var enable_shot_audio: bool = true
@export var record_debug_events: bool = true
## 0 = unseeded. Non-zero: run N uses seed random_seed + N, making
## evaluations repeatable (same engine version; physics is not bit-exact
## across versions).
@export var random_seed: int = 0

@export_group("Sightline Sampling")
@export var enable_map_sampling: bool = true
@export var sample_spacing: float = 2.0
@export var overexposed_threshold: int = 3

@export_group("Validation")
@export var fail_on_missing_player_spawn: bool = true
@export var fail_on_missing_enemy_spawns: bool = true
@export var fail_on_unreachable_spawns: bool = true
@export var require_navigation: bool = false
