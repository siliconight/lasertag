# Changelog

## [0.20.0] - one eye per body

Roadmap 131. Seven heights described one firefight and no two of them agreed:

```
crew   sees from   1.40   hardcoded in LT_BotPlayerController
crew   camera      1.60   scenario.player_eye_height_m, since 0.11.0
crew   shoots from 1.55   Marker3D_Muzzle, a child of that camera, 0.3 m fwd
enemy  sees from   1.50   LT_EnemyPill.tscn Marker3D_Eye
enemy  shoots from 1.30   LT_EnemyPill.tscn Marker3D_Muzzle, 0.4 m fwd
enemy  targeted at 1.40   LT_PlayerRegistry.get_best_target_for_enemy
map    sampled at  1.50   LT_MapSampler's own const EYE_HEIGHT
```

Two of those are defects standing alone. **A body that sights 0.15 m below its
own barrel can decline a shot it has** -- and take one it does not. An enemy
that sights 0.2 m *above* its barrel fires into the cover it is looking over.
The forward offsets make it worse in the direction that matters: a muzzle
0.4 m in front of the eye can be through the wall the body is standing behind.

The registry's 1.4 only went live when crews grew past one member (roadmap
129): `get_best_target_for_enemy` returns early at `alive.size() == 1`. So
target SELECTION and target ENGAGEMENT have disagreed on every multi-member
run this project has done, which is all of them since 2026-09-09.

`LT_MapSampler`'s is the quietest and the worst, because it is the number that
decides what the report says about the MAP rather than about one run. Cover
was being measured 0.1 m below the eye that plays the level.

### Changed
- A body's eye is a NODE, positioned once by the harness, and
  `LT_LineOfSightTester.eye_position(body)` is the only way to ask where it
  is. A number cannot drift from itself. All three sight call sites read it.
- The muzzle sits AT the eye for both sides, with no forward offset, so the
  firing ray is the same ray the visibility test just proved clear. The
  offset was never load-bearing: `LT_Shooter.fire` already excludes
  `owner_body` from its query, so a muzzle at the eye cannot hit the shooter.
- `LT_MapSampler.EYE_HEIGHT` becomes an `@export`, assigned from
  `player_eye_height_m` -- the same field that places the crew camera.

### Added
- `enemy_eye_height_m` and `aim_height_m` on `LT_TestScenario`. Three of the
  seven heights were unreachable from a scenario, and how tall a solid must be
  to break a MUTUAL sightline is decided by the two eyes and the aim height
  together: `h = a - (a - c)^2 / (a + b - 2c)`. A consumer stating a body
  could reach one third of that geometry. The default enemy eye is the
  player's, because `agent_contract.json` says npc_standard shares the
  player's metrics until a distinct class ships -- not the 1.5 the pill
  happened to carry.
- `LT_LineOfSightTester.aim_height`, a static var the harness sets once from
  the scenario. `CHEST_OFFSET` stays as the ratified default and the fallback.
- `runners/tests/test_one_eye_per_body.gd`. It guards the literals as well as
  the behaviour, because the defect WAS six literals and no run-level
  assertion catches a reintroduced one on a map with no geometry in the band
  that moved -- which, as below, is most maps.

### Measured
warehouse_yard_001, crew 4, 25 runs, three maps, the addon the only difference.

**The firefight is indifferent on this map.** `route_progress_rate`,
`route_completion_rate`, `team_wipe_count` and `avg_enemy_deaths_per_run` are
identical on all three seeds. The whole run-level residue is stuck counts, and
they move in both directions (+4 player on 9004, -3 on 9105); seed 9004 crosses
WARN -> FAIL on a two-point score move, which is a band boundary rather than a
finding.

That is expected rather than reassuring: the shipped corpus has no geometry
between 1.10 m and 1.20 m (roadmap 130), so raising an eye from 1.4 to 1.6
crosses nothing on it. A three-run smoke returned figures identical to four
significant figures on both arms, which looked like a wiring failure and was
not -- a probe printing the live positions showed eye 2.600 and muzzle 2.600
against a body at 1.000. That is why `test_one_eye_per_body` guards the
LITERALS as well as the behaviour.

**The map-level figures are where it lands, and they move the same way on every
seed** -- these come from the sampler, whose eye rose 1.5 -> 1.6:

```
                          seed 9004         seed 9105         seed 9206
avg_exposure          1.5664 -> 1.5858  1.4352 -> 1.4592  1.6308 -> 1.6552
avg_open_directions   3.8555 -> 3.8619  3.9405 -> 3.9657  3.7769 -> 3.7929
peer_exposed_fraction 0.7300 -> 0.7342  0.7662 -> 0.7742  0.7639 -> 0.7704
overexposed_fraction  0.2662 -> 0.2677  0.2883 -> 0.2941  0.2586 -> 0.2624
blind_fraction        0.6526 -> 0.6526  0.5496 -> 0.5492  0.4245 -> 0.4150
```

Nine of ten move, all in the same direction, on three different maps: every map
reads as more open and more exposed than it was being reported. Not noise the
way the stuck counts are -- a systematic correction the size of the 10 cm the
sampler was measuring below the eye that plays the level.

### What this does to the derived cover height
With every side sighting from 1.6 at a 1.0 chest, the crossing rises from
1.2222 m to **1.3000 m**. `deli_counter/agent_contract.json`'s `sightlines`
block is re-derived to match. It flags the same 39 of 91 combat rooms in the
shipped presets, because that corpus has nothing between 1.20 m and 1.40 m --
the same clustering roadmap 130 measured.

## [0.19.0] - how far the crew got, not merely whether it finished

Roadmap 128. `route_completion_rate` is a boolean averaged, so it reports 0.0
whether the crew was wiped on the spawn or reached the objective and then
cleared the map. Those are not the same level.

### Added
- `route_progress_rate` in the summary, `route_points_reached` and
  `route_points_total` per run in the CSV, and the traversal finding now says
  the number out loud: "It reached 50% of the route's points on average, so
  the zero above is how often it FINISHED, not how far it got."

  MEASURED on `market_row_001`, three runs per enemy count -- every row scored
  `route_completion_rate` 0.00:

        enemies 0    progress 1.00    2 of 2 legs    TIMEOUT
        enemies 1    progress 0.50    1 of 2 legs    ENEMIES_CLEARED
        enemies 2    progress 0.50    1 of 2 legs    ENEMIES_CLEARED
        enemies 4    progress 0.17    mostly 0 of 2  TEAM_WIPE

  The crew reaches the objective and THEN clears the enemies, which the
  boolean recorded as identical to being wiped on the spawn.

  On `restaurant_row_001` it reads 0.00 at every enemy count above zero, and
  that is also true rather than a failure of the measure: there the crew is in
  contact before it walks a single leg.

### Two traps, both hit before this was right
- `_route_index` IS NOT PROGRESS. `_update_stuck` advances it to move a jammed
  bot along, so it counts points SKIPPED as well as reached. Progress comes
  from a separate counter that only increments on a genuine arrival, and the
  test asserts `_update_stuck` never touches it.
- THE ROUTE'S FIRST POINT IS THE SPAWN. Lot emits `Route_0` at the crew spawn
  exactly -- measured 0.00 m apart on restaurant_row_001 -- so counting points
  reached gave every run 1 of 3 for standing still, including a crew wiped at
  3.4 seconds. Progress is counted in LEGS WALKED, detected by comparing the
  first point to the body's position rather than assumed, so a route that
  genuinely starts away from the spawn still counts its first leg.

### Not changed
- The SCORE. `route_completion_rate` still drives the traversal category
  exactly as before, and no threshold reads the new figure. This adds a
  reading; deciding what it should be worth is roadmap 128's remaining half.

## [0.18.0] - the arrival radius is a property of the body, not of a scene file

Roadmap 123's last arm.

### Fixed
- `path_desired_distance` is derived in `_align_agent_to_mesh` from the body
  and the bake, beside the `path_height_offset` that item 122 already derived
  there. It was 0.8 in both pill scenes -- a number with no stated origin, in
  the scene files the size contract exists to stop being the source of truth.

        radius        a waypoint inside the body's own footprint IS reached
                      (`nav_agent.radius`, set from the contract at spawn)
        per frame     move_speed / physics_ticks_per_second; below this the
                      body steps OVER the threshold between two samples
        half a cell   what path_height_offset cannot remove -- it subtracts
                      exactly one cell height, slope and rounding leave up to
                      half of one

  Combined in 3D, because that is how Godot measures the distance. On the
  shipped contract -- radius 0.35, speed 4.0, 60 Hz, cell 0.25 -- that is
  0.435.

### Measured, and it is not a tidying change
  `restaurant_row_001` seed 9003, no enemies, 180 s, four runs either side,
  the constant the only difference:

        0.8 authored     route_completion 0.0 x4     player_stuck 38 x4
        0.435 derived    route_completion 1.0 x4     player_stuck  0 x4

  Three further seeds on the derived value completed 1.0 with 0 stuck. At 0.8
  the agent counts a waypoint reached from 0.8 m away, cuts the corner and
  jams. That is the OPPOSITE failure to item 122, where the distance was too
  small to register arrival at all -- and 0.8 had worked on `market_row_001`,
  which is exactly what a constant that survives one map looks like.

  Under fire the two are indistinguishable, checked rather than assumed: 20
  runs at 4 enemies gave 0 stuck events and within 3% on survival and shots
  either way. The crew dies before path-following precision matters, which is
  why the traversal case is the one that shows it.

### Note
- The 0.8 in `LT_PlayerPill.tscn` and `LT_EnemyPill.tscn` is left as the
  authored fallback for a pill spawned without the controller's derivation.
  Nothing in this repo's own evaluation path uses it any more.

## [0.17.0] - the navigation wait is a clock, and ZERO is not a coordinate

Roadmap 126: `validate_map` reported NAVIGATION_MISSING on about 7% of
evaluations, immediately after logging a successful bake. Two causes, and the
first hid the second.

### Fixed
- `_await_navigation_sync` is bounded in MILLISECONDS (`NAV_SYNC_MAX_MSEC`,
  2000) rather than by a frame count. `await get_tree().physics_frame` in a
  headless SceneTree does not pace to 60 Hz -- it spins.

        30 physics frames, inside run_map_eval        1 ms
        30 physics frames, in a bare SceneTree      ~490 ms
        the navigation server's own sync           14-28 ms

  So the original flat 3-frame wait was about 0.1 ms and 0.15.0's 30-frame
  replacement about 1 ms; neither was a wait. Whether the map read as ready
  came down to how much wall time happened to pass doing other work, which is
  the coin flip the 7% was. The frame cap survives at 3000 purely as a
  runaway guard.

- `_navigation_ready` refuses a closest point of exactly `Vector3.ZERO` while
  the probe is not itself at the origin. Before its first sync
  `map_get_closest_point` returns ZERO, which is a plausible-looking
  coordinate rather than an error: measured on restaurant_row_001, iteration 1
  answered (0,0,0) against a spawn at (0, 1, -23) and the probe read it as
  "the navmesh is 23 m away".

  IT CUTS BOTH WAYS, which is why it is tested rather than left to the
  distance. On a map whose crew spawn sits near the world origin the same
  unsynced ZERO measures ~1 m and would have reported READY on a navigation
  map that had not been built.

### Measured
        NAVIGATION_MISSING   2 of 30 before   ->   0 of 20 after
        wait budget exhausted     16 of 20    ->   0 of 20
        observed wait times                        14-28 ms

  The 16-of-20 figure is 0.15.0's own warning firing on runs that were fine --
  a fix that cried wolf four times in five, which is how the millisecond
  measurement got taken at all.

### Added
- `runners/tests/test_nav_wait_is_a_clock.gd`. It pins the PREMISE rather than
  the fix: if a future Godot paces `physics_frame`, a frame count becomes a
  clock again and this analysis changes. Its first version asserted "30 frames
  < 100 ms" and failed at 480 ms in a bare SceneTree -- the spread IS the
  finding, so the timing is now printed and the assertions are on the things
  that hold: that the wait reads a millisecond clock, and the ZERO arithmetic.

## [0.16.0] - the sampled region is the level, not the marker spread

### Fixed
- The sample bounds are the level's geometry ALONE when there is any; the
  markers are a fallback for a scene with no meshes. 0.12.0 replaced a
  marker-derived region with a geometry-derived one, said so in the comment,
  and then appended the markers anyway -- so they could still EXTEND it.

  IT IS REACHABLE BECAUSE THE TWO HALVES READ DIFFERENT THINGS.
  `_collect_samples` finds a floor by raycasting COLLISION;
  `_geometry_anchors` bounds the grid by MESHES. Wherever collision runs past
  the visual geometry there is samplable ground outside the level's own box,
  and a marker out there dragged the region onto it.

  MEASURED WHEN LOT 0.53.0 MOVED ONLY WHERE ENEMIES STAND on
  restaurant_row_001 seed 9003 -- byte-identical buildings:

        total_samples          3876 -> 2904
        has_cover_fraction    0.764 -> 0.729
        fully_open_fraction   0.211 -> 0.269

  A denominator that moves when the level does not makes every figure over it
  a statement about somebody's marker placement. With geometry-only bounds
  both placements sample 2904 and agree to three decimals; what is left is
  real, and attributable -- Lot placed 6 cover nodes in the new arrangement
  against 5 in the old.

### Retracted
- LOT 0.53.0's CHANGELOG AND ROADMAP 127 BOTH CLAIM THAT CHANGE CAUSED A NEW
  `BLIND_MAP` WARNING AT 52%, AND IT DID NOT. That reading compared a 2904-
  sample region against a 3876-sample one. Re-measured over the same
  geometry-only region, `blind_fraction` is 0.5272 for the OLD placement and
  0.5210 for the new -- above the 0.5 threshold either way, and slightly
  BETTER after. The warning is a property of the site that the inflated region
  had been hiding, because the extra ground it sampled lay near the distant
  enemy spawns and was visible to them. There was no trade.

### Added
- `runners/tests/test_sample_bounds_are_the_level.gd` -- a slab whose collision
  is wider than its mesh, so the defect is reproducible: 169 samples on
  geometry bounds, 900 when a marker 90 m out is passed alongside them.

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
