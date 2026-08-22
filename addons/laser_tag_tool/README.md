# Laser Tag Map Evaluation Tool

Lightweight Godot 4.x add-on for testing whether a greybox 3D level supports
basic PvE firefights. Pill players, pill enemies, strictly manual hitscan
laser shots, collision-blocked fire, and machine-readable map reports.

This is not final combat. This is a map testing tool — a level truth machine.

## Install

1. Copy `addons/laser_tag_tool/` into your project.
2. Enable **Laser Tag Map Evaluation Tool** in Project Settings → Plugins
   (optional — only needed for the Create Node entries; the harness works
   without the plugin enabled).

## Collision layers (required)

| Layer | Use |
|---|---|
| 1 | World (all level geometry that should block bullets) |
| 2 | Player |
| 3 | Enemy |
| 4 | Laser Blockers (extra props that block fire) |
| 5 | Trigger Volumes (ignored by lasers) |
| 6 | Debug Only (ignored by lasers) |

**The rule:** if it should block bullets in the real game, it must be on a
laser-blocking layer here. That is the whole point of the harness.

## Level hooks

Required:
- `LT_PlayerSpawn` (add `LT_PlayerSpawn_02`..`_04` for more players)
- `LT_EnemySpawnPoints` with child markers (`LT_EnemySpawn_01`, ...)
- World collision on Layer 1

Strongly recommended:
- `NavigationRegion3D` with a baked `NavigationMesh` — without it the tool
  falls back to direct movement and reports `NAVIGATION_MISSING`.

Optional:
- `LT_ObjectivePoint`, `LT_PlayerRoutePoints` (children = bot route),
  `LT_CoverTestPoints` (children = bot cover positions)

Markers are discovered by **name prefix**; plain `Marker3D`/`Node3D` nodes
work fine.

## Mode A — Manual solo test

**Drop `scenes/LT_MapEvalHarness.tscn` into your level scene and press Play.**

Controls (registered automatically if missing): WASD move, mouse look,
Space jump, **Left Mouse fires — one press = one shot, holding does
nothing**, **Tab opens tracer settings**, R resets the run, **N toggles
enemies on/off**, Esc toggles mouse capture.

### Tracer settings panel (Tab)

In-game runtime cosmetic editor: color picker for your laser, style
buttons (`solid` / `dashed` / `rail`), display name. Changes apply to
your tracers and pill tint instantly, save to disk, and replicate live —
while you drag the color wheel, connected players watch your lasers
change (broadcasts throttled to ~6/s during drags). The panel states the
scope plainly: cosmetics replicate; enemies and damage are simulated
locally per player until gameplay netcode lands in Phase 5. `C`/`V`
still work as quick-cycle hotkeys without opening the panel.

### Enemy toggle (free-roam mode)

Enemies default **ON**. Press `N` (or set `enemies_enabled = false` on
the scenario) to switch to free-roam: all enemies despawn instantly and
none respawn — running around a gym with friends online just to show off
tracer colors, no orange pills interrupting. Press `N` again to bring
them back at the spawn points. In coop each peer toggles independently
(enemy sim is local per peer). Headless: `--no-enemies` for
traversal-only runs — combat categories will score 0, by design.

You get: crosshair with hit/blocked/miss feedback, a health pip bar
(bottom-left, one pip per HP, red flash on damage), debug HUD, fading laser
lines (green = you hit an enemy, red = enemy hit you, white = miss,
gray = blocked by world), enemy overhead labels with HP/state/target/LOS,
and shot audio.

### Shot audio (gool bridge)

Every shot broadcasts to the `lt_audio` group. `LT_ShotAudio` handles it
with two paths:

- **gool:** if a `Gool` autoload exists, events are routed as
  `Gool.play_event(event_name, position)` — event names
  (`lt_player_shot`, `lt_enemy_shot`, `lt_hit_confirm`, `lt_blocked`,
  `lt_player_hurt`) and the method name are exported vars on
  `LT_ShotAudio`, and `has_sound()` is asserted at the call site before
  playing. If gool's API differs, the integration point is one line in
  `_play()`.
- **Fallback:** zero-asset synthesized PCM blips, so the tool makes sound
  in any project. Enemy shots play positionally (3D at the muzzle) —
  directional incoming-fire audio is itself a map readability signal.

Disable via `enable_shot_audio = false` on the scenario. Audio is off in
headless mode automatically.

## Mode B — Headless evaluation

```
godot --headless --path . \
  -s res://addons/laser_tag_tool/runners/run_map_eval.gd -- \
  --map res://levels/gas_station_test.tscn \
  --scenario res://addons/laser_tag_tool/resources/default_laser_tag_scenario.tres \
  --runs 25 \
  --output user://reports/gas_station_eval.json
```

Extra flags: `--enemies N`, `--players N`, `--max-run-time SECONDS`,
`--time-scale X` (default 4.0 — sim runs faster than real time),
`--seed N` (deterministic runs: run *i* seeds with N+i — repeatable on the
same engine version), `--baseline old_report.json` (prints and embeds a
score/metric diff against a previous report — compare map versions in CI),
`--bake-nav` (runtime-bakes any `NavigationRegion3D` before evaluating —
useful for CI and greyboxes shipped without a baked navmesh).

Outputs:
- JSON report (score, grade, category breakdown, findings, per-run summary,
  sampled sightline data, optional baseline diff)
- CSV next to it (one row per run)
- Human summary printed to stdout

Exit code: `0` = PASS, `1` = WARN, `2` = FAIL/BROKEN — wire it straight
into CI. A ready-made GitHub Actions workflow is included at
`.github/workflows/map-eval.yml`: lints, runs a seeded eval on the demo
greybox, validates the report shape with `jq`, and checks determinism.

## Sightline sampling

Before the runs start, `LT_MapSampler` grid-samples the walkable space
(navmesh-snapped when navigation exists, floor-raycast otherwise) and
raycasts every position against every enemy spawn. The report gains:

- **Overexposed zones** — positions visible to 3+ enemy spawns, with world
  coordinates of the worst offenders (`sightlines.worst_overexposed`)
- **Blind zones** — positions no enemy spawn can ever see
- **Long/short sightline counts** per §17.3

Sightline scoring uses this real exposure data when available instead of
inferring from engagement stats. Tune via the scenario
(`sample_spacing`, `overexposed_threshold`) or disable with
`enable_map_sampling = false`.

## Scoring (100 pts)

Traversal 25 · NPC Pathing 20 · Sightlines 20 · Cover 20 · Combat Pacing 15

| Score | Grade |
|---|---|
| 90–100 | PASS — strong combat map |
| 75–89 | PASS_WITH_TUNING |
| 50–74 | WARN — needs design review |
| 25–49 | FAIL — major level issues |
| 0–24 | BROKEN for this combat model |

A passing laser tag test is a **combat readiness signal**, not "map is
done." Pair the report with manual review.

## Mode C — Co-op (future)

The architecture is player-plural from day one (`LT_PlayerRegistry`, plural
spawns, multi-player enemy targeting per TDD §15.3), but authoritative
networked simulation is deliberately not built yet. Server-authoritative
model per TDD §22 when it lands.

### Cosmetic replication spike (in now)

**Transport-agnostic:** the session (`LT_CoopSession`) never touches the
wire. All delivery goes through an `LT_NetAdapter`, so the cosmetic layer
plugs into any Godot multiplayer game regardless of protocol.

**Integrating into YOUR multiplayer game:**

1. **You use Godot high-level multiplayer** (any `MultiplayerPeer`:
   ENet, WebSocket, WebRTC, GodotSteam's SteamMultiplayerPeer, ...):
   nothing to write. Drop the harness in; on startup the default
   `LT_GodotHighLevelAdapter` detects your already-configured
   `multiplayer.multiplayer_peer` and **attaches** to it — LT opens no
   connection of its own, exchanges cosmetics with peers already
   present, and rides your session. (Keep the harness at the same scene
   path on all peers, or register the session as an autoload — rpc
   needs matching node paths.)

2. **You use a custom protocol** (Nakama, raw UDP, rollback netcode,
   your own sockets): subclass `LT_NetAdapter` (~30 lines) and hand it
   to the session with `set_adapter()`. The whole contract:
   - implement `send(channel, payload, reliable, target_peer)` —
     payloads are already JSON-safe dictionaries (vectors packed as
     `[x, y, z]`), so `JSON.stringify(payload)` is always a valid
     encoding for your wire
   - emit `message_received(peer_id, channel, payload)` when your
     transport delivers
   - emit `peer_joined` / `peer_left` (including joins for peers
     already present when you attach mid-session)
   - return stable ints from `local_peer_id()` — your adapter owns the
     mapping from SteamIDs/tokens/whatever to ints
   `LT_LoopbackAdapter` is the reference implementation.

   Channels: `cosmetic` (reliable), `shot` (reliable, small
   start/end/hit-type packets), `transform` (unreliable, 10 Hz,
   loss-tolerant). Unknown channels are ignored on receive — safe to
   extend.

3. **No network at all:** run with `-- --lt-loopback` — a phantom peer
   mirrors everything you send (offset 2 m), so the full pipeline
   (cosmetic exchange, remote tracers, ghost pill) is visible solo in
   one window. Smoke-tests the session without touching a socket.

What replicates — per-player tracer cosmetic, color + style
(`solid` / `dashed` / `rail`), that:

- **Persists** to `user://laser_tag_tool/cosmetic.json` (fresh installs
  get a random hue, so two test instances differ with zero config)
- **Replicates**: exchanged on connect and live on change; your shots
  render on every peer's screen in *your* color and style, and your pill
  appears to others as a translucent ghost tinted with your cosmetic,
  name overhead, position streamed at 10 Hz
- **Edits live**: `C` cycles color, `V` cycles style — saved immediately,
  rebroadcast immediately

Try it in one editor: **Debug → Customize Run Instances…**, 2 instances,
give instance 1 the arguments `-- --lt-host` and instance 2
`-- --lt-join 127.0.0.1`, then Play the demo level. Shoot; watch your
tracer show up in the other window; press `C`; restart — your color is
still yours. (Or set `coop_mode` on the harness node directly.)

Scope honesty: this is presence + cosmetics only. Each peer still runs
its own enemies and its own damage — nothing gameplay-authoritative
crosses the wire. Shot tracer events are replicated as small
start/end/hit-type packets and are never re-raycast on the receiving
side (result authority stays with the simulating peer). All inbound
payloads are validated (`LT_Cosmetic.validate`) — color parsed, style
whitelisted, name length clamped.

### Replicated destructibles — breakable glass (in now)

The shards are not the glass; **the state is the glass.** A destructible
keeps a deliberately tiny authoritative gameplay state — id, hit points,
intact/broken, a collision toggle — and everything expensive-looking
about the break (debris, particles, sound) is a local, cosmetic,
short-lived event each peer plays for itself.

**Drop-in:** place `scenes/LT_BreakableGlass.tscn` in your level — it
blocks lasers and movement on Layer 1 while intact, and neither once
broken. Any other body works the same way: put a `Node` named
`LT_Destructible` (script `scripts/destructible/LT_Destructible.gd`) on
the CollisionObject3D — same name-lookup convention as `LT_Health` —
point it at the intact visual and an optional pre-authored broken visual
(empty frame, wreck, stump), set `hit_points`, done. Window → broken,
crate → destroyed, monitor → smashed: one system, art decides how
dramatic the transition looks.

**Solo:** no networking required. A hit applies damage locally; at 0 HP
the pane swaps visuals, drops collision, and plays debris.

**Coop:** add ONE `LT_DestructibleSync` node to the level. It rides the
same `LT_NetAdapter` as the cosmetic session (auto-wires when the
session comes up, or hand it one via `set_adapter()`). One peer —
`authority_peer_id`, default 1, Godot high-level multiplayer's server
id — owns the state. Every locally-simulated hit, yours or your local
enemies', routes to the authority as a request; the authority applies
damage to the canonical copy and, on the breaking hit, broadcasts one
small reliable packet `{id, seed, impact, direction}`. Persistent state
and transient event stay separate concepts: late joiners receive a
snapshot of broken ids and apply it silently — collision and visuals,
no debris replay. They only need to know the pane is already broken.

**Debris never crosses the wire.** Each peer picks the same break
pattern from `hash(id + seed) % pattern_count` — authored
`debris_scenes` if you provide them, three built-in procedural shard
patterns otherwise — then simulates its own short-lived cosmetic
shards. An authored scene made of plain meshes (a zoo `glass_shard`
GLB imports as exactly that) is flung automatically: every mesh is
wrapped in a cosmetic rigid body with a seeded impulse, so a shards
GLB skinned by the same Pixelcoat glass pack as the pane drops
straight into `debris_scenes` with no manual setup. A scene that
ships its own physics animates itself. `debris_quality` scales shard count per machine (low / medium /
high) while collision, traversal, and sightlines stay identical for
everyone; `debris_lifetime` fades and frees the pieces. Nobody needs to
agree where shards bounce; everybody agrees the pane is broken.

**Bullets break glass; bombs break breaches.** `bullet_breakable`
(default on) gates the LT_Shooter path: set it off for a breach wall or
anything that answers to a charge rather than small arms, and trigger
the break from your explosive's code via `register_blast()` — same
authority routing, same replication, same late-join snapshot, only the
trigger differs. This pairs with Deli Counter's interactive kinds: a
`window` machine transitions on `break`, a `breach_wall` on `breach` —
the game maps weapons to events; the proxy doesn't care which weapon.
Debris differs with the material: `debris_style = rubble` throws chunky
low-flying masonry (|vy| ≤ 0.6, slow tumble, `play_breach` audio hook)
where glass bursts and glitters — a breach is a thud, not a chime.

**THE SEAM — breach walls and doors belong to YOUR netcode.**
`scenes/LT_BreachWall.tscn` ships `game_driven = true`: like a door,
its state machine lives on the gameplay/networking layer per
INTERACTIVES.md, and this toolset only reports and presents. The
integration surface your engineers hook up later, in full: stimuli
arrive on the `break_requested(damage, impact, direction, blast)`
signal (nothing breaks on its own — a charge against a game-driven
wall emits a request and stops); your replicated state machine decides
and then calls `apply_break(impact, direction, seed, with_effects)` on
every peer (pass `with_effects = false` for late-join state) and
`reset_intact()` on round reset; `broke` / `state_changed` fire for
anything listening; `destructible_id` is yours to set to the
`gameplay.json` interactive id (`cr_deli:if:...`) so the fixture and
the contract entry correlate. `LT_DestructibleSync` ignores
game-driven fixtures completely — no requests, no broadcasts, no
snapshot entries — so the toolset's cosmetic-layer authority and your
gameplay authority can never fight over one wall. Glass panes stay
toolset-driven by default; flip `game_driven` on when your netcode is
ready to own them too, and the presentation layer doesn't change.

Validation mirrors the cosmetic layer: break state is accepted only
from the authority peer, request damage is clamped, unknown ids are
ignored. `reset_intact()` restores a pane locally (fresh run) — state
is otherwise permanent for the session, which is exactly what late
joiners need it to be. A hit that lands while a client is still
connecting is dropped, not applied locally — a local break in that
window would diverge from the authority forever. Gameplay stays
intentionally simple; art is allowed to be complicated.

**Upgrading the break art — the visuals ship primitive on purpose.**
The procedural shards and the bar-frame broken state are the
zero-asset floor; better-looking breaks plug into three independent
sockets without touching state, netcode, or a single test. (1) Drop
authored shatter scenes into `debris_scenes` — the seeded pattern
index picks one per break on every peer, plain-mesh GLBs are wrapped
and flung automatically, and the zoo `glass_shard` species (skinned by
the pane's own Pixelcoat pack, so the pieces look like the pane)
builds exactly those. (2) Point `broken_visual_path` at a real broken
state — the zoo `window_broken` species builds a glazed remnant whose
void matches the intact `window` by construction. (3) Hook
`broke(impact_point, impact_direction, break_seed)` for particles,
decals, and sound — cosmetic, local, deterministic per seed. Swap any
socket independently, ship them in any order; the proxy's contract
does not move.

**Seeing it.** `scenes/demo/LT_DestructibleShowcase.tscn` is the
eyeball pass: the demo greybox plus four labelled exhibits at the
player spawn — a one-shot pane, a 3-hit pane, a high-tier-debris pane,
and a game-driven breach wall. Shoot the glass; press **B** to set a
charge against the wall (its driver script is a live, printing example
of the break_requested → apply_break seam); press **G** to restore
everything. Run it solo, or as the host instance in the two-instance
coop setup to watch breaks replicate.

**Proving it.** Two instruments ship with the system. Single-process
(state machine, validation, and a real physics raycast that blocks on
intact glass and passes once broken):

```
godot --headless --path . \
  -s res://addons/laser_tag_tool/runners/tests/test_destructible.gd
```

Three-process, over a real ENet session on localhost — client hit
routes to the authority and round-trips, host break replicates live
with debris, late joiner gets both panes by snapshot with none:

```
addons\laser_tag_tool\runners\tests\net_test\run_net_test.bat
```

(or run `net_host.gd`, `net_client.gd`, `net_late.gd` with `-s` in
three terminals, host first). Expect `HOST PASS`, `CLIENT PASS`,
`LATE PASS`. Exit codes are CI-friendly: 0 pass, 1 fail.

### debug-shot-tracers bridge

If the `debug-shot-tracers` addon is installed (ShotDebugBus /
DebugTracerManager autoloads), every LT shot — local and remote — is
also forwarded via `ShotDebugBus.report(...)` with
`metadata.shooter_peer_id` and `metadata.cosmetic`, so its visualizer
renders alongside or instead of LT's. Disable with
`forward_to_shot_debug_bus = false` on `LT_DebugLaser`. No hard
dependency either way.

## Rules recap

Player HP 5 · Enemy HP 2 · Damage 1 · Hitscan only · First hit only ·
No automatic fire · No shooting through collision · Friendly fire off.
