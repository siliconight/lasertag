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
