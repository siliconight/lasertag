# Changelog

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
