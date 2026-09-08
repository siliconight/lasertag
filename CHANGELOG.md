# Changelog

Laser Tag had no changelog before 0.10.0. `CLAUDE.md` requires one per tool
change; this starts it, and does not attempt to reconstruct 0.1.0-0.9.0 from
memory.

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
