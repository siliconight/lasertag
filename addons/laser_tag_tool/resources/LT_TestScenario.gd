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
## The CREW bot's sight range. Was an `@export` default on
## `LT_BotPlayerController` that the harness never assigned, so the scenario
## could not set it -- while `enemy_sight_range` below, which looks like its
## pair, could. The pipeline raised that as LT_ENGAGEMENT_NOT_CONFIGURABLE on
## every candidate of every cold run. A route metric gated on "can I see an
## enemy" cannot be tuned while the seeing range is unreachable from here.
##
## 45.0 keeps the shipped behaviour exactly: Lot places enemies to the
## 45-vs-35 difference so the crew acquires first, and `OPENING_RANGE` is
## built to it. Changing this changes that contract.
@export var player_sight_range: float = 45.0
@export var enemy_sight_range: float = 35.0
@export var enemy_preferred_distance: float = 14.0

## TRAVERSAL UNDER FIRE (roadmap 121). Default FALSE, which is the shipped
## bot exactly: it stops dead when it sees a guard and only advances the route
## in the `else`, so route progress and enemy presence are mutually exclusive
## and `route_completion_rate` is structurally zero on any map with live
## guards. That makes the metric a statement about the encounter rather than
## the level, which `level_factory`'s `lasertag_report.py` already documents.
##
## Set TRUE and the bot advances while engaging, at
## `engaged_move_speed_scale` of its normal speed, facing and firing at what
## it sees. Then `route_completion_rate` answers the question the name implies
## -- can a crew get through this level while being shot at -- which today is
## measured by NOTHING: `walktest_navqa` walks the same spine with no combat
## in it, and Laser Tag runs the combat with a bot that cannot move.
##
## OPT-IN ON PURPOSE. Every historical Laser Tag number was produced with this
## off; flipping the default would invalidate 33 reports of comparison history
## in one commit.
@export var advance_while_engaging: bool = false
## How much of `move_speed` the bot keeps while engaging. Only read when
## `advance_while_engaging` is true.
@export var engaged_move_speed_scale: float = 0.5

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
