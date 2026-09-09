# Changelog

## [0.15.0] - wait for navigation to be ready, not for three frames

### Changed
- `_await_navigation_sync` waits for `_navigation_ready()` to be true, up to
  `NAV_SYNC_MAX_FRAMES` (30), instead of awaiting a flat 3 physics frames. It
  prints how many extra frames it needed when that is more than zero, and
  warns if the budget runs out.

  `_navigation_ready` already forces a synchronous server update and its
  comment says readiness "doesn't depend on how many frames happened to elapse
  since the bake" -- but the WAIT in front of it was still a frame count, so
  the guarantee stopped at the door.

- `discover_hooks` now runs BEFORE that wait. `_navigation_ready` probes the
  navmesh near the player spawn, so it could only ask its real question after
  the hooks were known, and it was being called first with no spawns to probe.

### Known
- WHAT THIS DOES NOT CLAIM. The failure it targets -- `NAVIGATION_MISSING`
  immediately after a successful 477-polygon bake -- was NOT reproduced in 16
  consecutive attempts, all of which passed with `iter=2 regions=1` and a
  spawn-probe distance of 0.750 against a 3.0 limit. It appeared in 2 of 30
  reports across one session, and a run that loses navigation falls back to
  direct movement and reports 240 stuck events, zero shots and NO_ENGAGEMENT,
  which reads as a catastrophic level rather than a race. So this is a
  robustness change against a failure mode that is real and measured but whose
  trigger is not identified, and it cannot be said to have fixed it.

- Polling the condition gives 0, 1 or 2 frames in most runs and up to 26 in
  others, which is the variance the flat 3 was assuming away. The figures move
  when the poll prints -- printing each frame changes the timing -- so treat
  the exact counts as an order of magnitude and not a measurement.

## [0.14.0] - a run's pills are gone before the next run starts

Roadmap 125, which 0.13.0 named as known and unexplained.

### Fixed
- `_clear_pills` removes each pill from the tree before freeing it.
  `queue_free` is deferred to the end of the frame, and this runs mid-frame --
  `run_ended` is emitted from a process callback, so `end_run`,
  `_clear_pills` and `start_run` all happen inside one frame. A pill stayed in
  the tree, and kept processing, until after the next run had already begun.

  IT COULD STILL FIRE. With probes at the fire site and the record site on
  market_row_001 seed 7503: a shot by `LT_Enemy_04` with
  `is_queued_for_deletion()` true, at `run_state.elapsed_seconds` of 0.000 of
  the FOLLOWING run. That stamped that run's `time_to_first_contact` and
  `time_to_first_enemy_shot` as zero, one corrupted run per boundary a team
  wipe crossed. Over 4 runs:

        time_to_first_contact   2.93, 0.00, 0.00, 0.00  ->  2.93 x 4
        avg_time_to_first_contact          0.37  ->  2.93
        avg_time_to_first_enemy_shot       0.38  ->  3.07

  Run outcomes are unchanged (11.1, 8.1, 8.4, 10.0 s either side), so this
  moves the measurement and not the game.

  AND IT KEPT ITS NAME, which is the second defect and was not noticed until
  the fix removed it. `spawn_enemies` sets `pill.name = "LT_Enemy_%02d"`, that
  collided with the pill still in the tree, and Godot auto-renamed the new
  one. Every run after the first reported its sources as
  `@CharacterBody3D@13`: 17 of 23 source names in one 8-run report, now 0. Any
  finding naming a shooter was unusable after run 1.

  `process_mode = PROCESS_MODE_DISABLED` fixes NEITHER -- the node is already
  scheduled for the frame in progress and keeps its name regardless. That was
  tried first, measured to change nothing, and reverted.

### Added
- `runners/tests/test_run_boundary_is_clean.gd`, including a check that pins
  the engine assumption the fix rests on: a `queue_free`d node still holds its
  name for the rest of the frame, so the replacement is auto-renamed.

## [0.13.0] - a corpse is not a wall

Roadmap 124, and the collision rules stated plainly: players do not collide
with each other or with corpses; players do collide with enemies, while those
enemies are alive.

### Fixed
- `LT_EnemyBrain._on_died` takes the body off every collision layer. It stopped
  the movement component and left the collider on `LAYER_ENEMY` forever, so a
  dead enemy stayed solid to everything that masks against it. The evaluation
  bot walked into one 0.8 m from its next path point and stood there for the
  rest of the run.

  Three symptoms, one cause, because `LASER_HIT_MASK` includes `LAYER_ENEMY`
  and both line of sight and shooting use it: bodies collided with corpses,
  `LT_LineOfSightTester` treated them as occluders, and `LT_Shooter` recorded a
  ray that stopped on one as `did_damage = true` / `ENEMY_HIT` -- a corpse
  still carries an `LT_Health`, so rounds absorbed by a body were counted as
  hits while `apply_hit` early-returned on `is_dead`.

  Measured on market_row_001 seed 7503, 8 runs, identical seed either side:

        player_stuck_events    79  ->  0
        enemy_stuck_events     33  ->  0

  Both to zero, which is what says corpses owned all of them.

- `LT_PlayerPill` no longer masks `LAYER_PLAYER`: mask 7 -> 5, so players pass
  through each other. Crew members were solid to one another, which is what
  `LT_Const.spawn_ring_offset` exists to work around -- coincident pills
  "elevator each other forever".

### Added
- `runners/tests/test_body_collision_rules.gd` -- asserts the player mask
  excludes PLAYER and includes ENEMY and WORLD, that a live enemy is on
  `LAYER_ENEMY`, and that a killed one leaves every layer.

### Known
- THE CREW NOW DIES FAST, and this is the honest consequence rather than a
  regression to hide: survival 53.67 s -> 8.95 s, 1 team wipe -> 8, over the
  same 8 runs. Corpses had been acting as cover and as sight blockers, which
  was never a decision -- it fell out of them keeping their layer. Whether a
  body should stop a laser is a design question this does not answer.

- `route_completion_rate` is still 0.0. Removing the blocker did not produce a
  completed route; see roadmap 121 for what else gates it.

- Metrics leak across the run boundary, and it is NOT caused by this change.
  A shot from the end of one run is recorded against the next at `_now()` of
  0.0, stamping its `time_to_first_contact` and `time_to_first_enemy_shot` as
  zero. The count tracks team wipes exactly: 1 wipe gave 1 corrupted run
  before this change, 8 wipes gave 7 after -- one per boundary a wipe crossed,
  run 1 having no predecessor. It drags `avg_time_to_first_enemy_shot` from
  2.70 s to 0.38 s and reads as "enemies open fire instantly". Disabling the
  pill's process mode before `queue_free` does NOT fix it, so the recording is
  arriving late rather than the pill firing late; the mechanism is not
  established and that attempt was reverted rather than shipped.

## [0.12.0] - the cover measure stops depending on where the spawns are

`LT_MapSampler` answered "is there cover here" by raycasting every walkable
position against ENEMY SPAWN POSITIONS. That made a statement about a level
depend on where six markers happened to be put -- and spawn placement is
gameplay-layer work that is expected to live outside this toolchain entirely.
A measure of a level has to be a property of its geometry, or it stops meaning
anything the day somebody else owns the spawns.

### Fixed
- `VERSION` and `plugin.cfg` agree again. `plugin.cfg` was last bumped at
  0.9.0; 0.10.0 and 0.11.0 both moved `VERSION` alone, so the lint job's
  version check -- whose own error says "the factory certifies a version Godot
  does not load" -- has been failing for two releases.

- The ray profile casts past weapon range and counts within it. An
  intermediate version of this change cast only to `sightline_limit_m`, which
  capped `max_open` at 35 m, so `long_sightline_fraction` read 0.0 on a site
  that had measured 0.981 an hour earlier. The metric had not changed; the ray
  had stopped short of the question. Restored to 0.981 on the same site.

### Changed
- Sampling no longer requires enemy spawns. It used to be gated on
  `not enemy_spawns.is_empty()`, so a map with none produced NO sightline data
  at all -- including the figures that never needed spawns.

- The sample region comes from the level's geometry, not from gameplay
  markers. The anchor list was player spawns + enemy spawns + route points
  plus 4 m, so the grid covered the bounding box of somebody's placement and
  nothing outside it. Measured on `market_row_001`: 910 sampled positions
  before, 3,861 after. The old box was about a quarter of the walkable space,
  which is also why the spawn-relative figures moved so far when it widened
  (11% blind / 72% overexposed on the box, 39% / 42% on the level).

- Cover is scored from `has_cover_fraction` and `fully_open_fraction` -- how
  many of a position's eight approaches have an occluder inside weapon range.
  `sightline_limit_m` is set from the scenario's `enemy_laser_range` rather
  than chosen here, because a lane only matters if something can shoot down
  it. The spawn-relative `overexposed_fraction` and `blind_fraction` are still
  reported and no longer deduct.

  THIS CHANGES SCORES, and comparison history with it. On `market_row_001` the
  same map and seed moved 45/FAIL to 65/WARN. The old deduction is not
  recoverable by tuning because it was measuring a different subject.

  Why the longest ray could not be the measure: `max_open` is a maximum over
  eight directions, so it is long the moment ANY direction is open, which on
  real geometry is nearly always -- 98% of 3,861 positions cleared 40 m on
  their best direction and not one was short on it. A number that is ~1.0
  everywhere separates no levels. What a body needs is somewhere to put its
  back, which is the count of directions that are BLOCKED.

- Spawn-relative keys are OMITTED, not defaulted, when there are no spawns.
  With an empty eye list every sample is visible to zero spawns, which reads
  as `blind_fraction` 1.0 and `overexposed_fraction` 0.0 -- a bare plane
  reporting as perfectly covered and scoring a PASS on exposure.

### Added
- `runners/tests/test_sampler_without_spawns.gd` -- builds a bare 40 x 40
  plane, samples it with no spawns, and asserts the spawn keys are absent and
  that the plane reads as open (1.00 fully open, 0.00 cover) rather than
  covered.

- A CI step that runs every runner test. Only `test_report_findings.gd` ran;
  `test_pill_wiring.gd` and everything under `runners/tests` -- including the
  traversal-under-fire guard added for roadmap 121 -- existed without ever
  being executed.

### Known
- `NAVIGATION_MISSING` is intermittent. One run in six reported no usable
  NavigationRegion3D immediately after logging a successful 477-polygon bake,
  and graded BROKEN; three consecutive re-runs of the identical command were
  clean. Not caused by this change and not diagnosed.


Laser Tag had no changelog before 0.10.0. `CLAUDE.md` requires one per tool
change; this starts it, and does not attempt to reconstruct 0.1.0-0.9.0 from
memory.

## [0.11.0] - the pill is built from the size contract

Nobody ships a floating capsule. The pill exists so the toolchain can prove
that a body of a STATED size fits the doors, stairs and headroom this factory
generates -- and a studio using these tools has characters of their own size.
`deli_counter/agent_contract.json` calls itself "THE single source of truth
for character/agent dimensions and every clearance derived from them", and
Laser Tag read neither it nor `docs/AGENT_CONTRACT.md`. The pill's capsule,
camera, speed and navigation agent were hardcoded in `LT_PlayerPill.tscn`, so
changing the contract moved every clearance in Deli Counter and left the body
that TESTS them untouched. Roadmap 123.

### Added
- `LT_TestScenario` gains a **Body** group: `player_radius_m` (0.35),
  `player_height_m` (1.8), `player_eye_height_m` (1.6),
  `player_walk_speed_mps` (4.0) -- the contract's `characters.player`.
  `LT_MapEvalHarness._apply_body` builds the pill from them at spawn: capsule
  radius and height, the shape and mesh offsets that keep the origin at the
  FEET, the camera's eye height, the bot's speed, and the navigation agent's
  radius and height.

  The capsule and mesh resources are DUPLICATED before being written. The
  `.tscn` declares them as sub-resources, so every pill in a scene shares one
  instance and the last write would otherwise win.

### Changed — this moves numbers
- The pill was **0.40 m** wide and walked at **4.5 m/s**. The contract says
  0.35 and 4.0, and those are now the defaults. The 0.40 was
  `nav_bake.agent_radius_m`, whose own note reads "fattest navigating
  character + 0.05 safety" -- the BAKE's safety margin had been built into the
  BODY, so every door-width and corridor test ran against a proxy 14% fatter
  than the character it stood for. That direction hides defects rather than
  inventing them, but it spends the margin twice and leaves nobody able to say
  how much is left.

### Fixed
- `LT_BotPlayerController` sets `path_height_offset` from the navigation map's
  own cell height (roadmap 122). A baked navmesh sits one cell height above
  the geometry it was baked from and `get_next_path_position()` returns points
  on that mesh, while the body's origin is at its feet on the geometry --
  so every path point was `cell_height` higher than the body walking to it,
  and Godot spends that out of `path_desired_distance` (0.8, measured in 3D)
  before counting a single horizontal metre. The value is READ FROM THE MAP,
  so a different bake stays correct without editing a constant.

  NECESSARY, NOT SUFFICIENT, and measured rather than hoped: applying it alone
  on `market_row_001` moved the returned point from y 0.25 to y 0.00 and the
  bot still did not walk, because it had SPAWNED 1.797 m above the nearest
  navmesh point -- standing on geometry the mesh does not cover. No agent
  tuning fixes a body that is not on the mesh. That half is a spawn-placement
  defect and stays open in 122.

## [0.10.0] - the bot can advance under fire, if you ask it to

### Added
- `LT_TestScenario.advance_while_engaging` (default **false**) and
  `engaged_move_speed_scale` (0.5). With the flag on, `LT_BotPlayerController`
  advances its route while engaging -- at that fraction of `move_speed`,
  facing and firing at what it sees -- instead of stopping dead.

  WHY. `route_completion_rate` is 0.0 in 31 of the 33 Laser Tag reports on
  disk: every workspace, every cold run this project has done, highest ever
  recorded 0.16. The cause is four lines here -- `_stop_horizontal()` in the
  "can I see an enemy" branch and `_advance_route()` only in the `else` -- so
  route progress and enemy presence are mutually exclusive by construction and
  the metric reports zero on a perfect map.
  `level_factory/packages/validation/lasertag_report.py` already documents
  this and classes `traversal` as an ENCOUNTER category rather than a MAP one.

  WHAT IT BUYS. Nothing currently measures whether a level can be traversed
  UNDER FIRE. `walktest_navqa` walks the mission spine with no combat and
  passes; Laser Tag runs the combat with a bot that cannot move. For a heist
  game that gap is the question, and a route that walks empty and is
  impassable under fire passes every gate in the toolchain today. Roadmap 121.

  OFF BY DEFAULT, DELIBERATELY. Every historical number was produced with the
  stand-and-fight bot; flipping the default would invalidate 33 reports of
  comparison history in one commit. `engaged_move_speed_scale: 0.0` reproduces
  the old behaviour exactly, so the original is reachable from the scenario
  rather than only from git.

- `LT_TestScenario.player_sight_range` (45.0). The crew bot's sight range was
  an `@export` default the harness NEVER assigned, so the scenario could not
  set it -- while `enemy_sight_range`, which looks like its pair, could. The
  pipeline raised that as `LT_ENGAGEMENT_NOT_CONFIGURABLE` on every candidate
  of every cold run. A route metric gated on "can I see an enemy" cannot be
  tuned while the seeing range is unreachable. 45.0 is the shipped default, so
  exposing it changes no behaviour: Lot places enemies to the 45-vs-35
  difference and `OPENING_RANGE` is built to it.

- `runners/tests/test_advance_while_engaging.gd`, pinning that the defaults
  are the shipped behaviour and that the scale is read rather than ignored.

### Fixed
- `LT_MapEvalHarness` assigns all three from the scenario. It previously wired
  the enemy's ranges and left the crew bot's on their `@export` defaults.

### Known, unchanged
- `runners/test_pill_wiring.gd` emits 18 `InputMap action doesn't exist`
  errors. Pre-existing and unrelated: verified by stashing this change and
  re-running, which produces the same 18.
