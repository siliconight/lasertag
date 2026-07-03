extends Node
class_name LT_CoopSession
## Cosmetic replication session (foundation for TDD Phase 5 / §22.7) —
## now TRANSPORT-AGNOSTIC.
##
## The session owns the meaning: cosmetics persist + replicate, shot
## tracers appear on other screens, ghost pills show presence. It never
## touches the wire — all delivery goes through an LT_NetAdapter, so it
## plugs into any Godot multiplayer game regardless of protocol. Use
## LT_GodotHighLevelAdapter (rides any MultiplayerPeer your game already
## configured), LT_LoopbackAdapter (no network), or your own subclass.
##
## Channels (payloads are JSON-safe: vectors packed as [x, y, z]):
##   &"cosmetic"  reliable    {name, color, style}
##   &"shot"      reliable    {s: [x,y,z], e: [x,y,z], ht: String}
##   &"transform" unreliable  {p: [x,y,z], ry: float}   (10 Hz)
##
## Deliberately NOT shared simulation: each peer runs its own enemies
## and damage. Presence + cosmetics only; every inbound payload is
## validated. Authoritative co-op sim stays Phase 5, per TDD §29.3.

signal cosmetic_changed(peer_id: int, cosmetic: Dictionary)

const CHANNEL_COSMETIC := &"cosmetic"
const CHANNEL_SHOT := &"shot"
const CHANNEL_TRANSFORM := &"transform"
const TRANSFORM_SEND_INTERVAL := 0.1
const VALID_HIT_TYPES := ["MISS", "WORLD_BLOCKED", "ENEMY_HIT", "PLAYER_HIT", "FRIENDLY_HIT"]

var adapter: LT_NetAdapter

var local_cosmetic: Dictionary = {}
var peer_cosmetics: Dictionary = {}  # peer_id -> validated cosmetic dict

var _ghosts: Dictionary = {}  # peer_id -> LT_GhostPlayer
var _ghost_root: Node3D
var _send_timer: float = 0.0

func _ready() -> void:
	add_to_group(LT_Const.GROUP_NET)
	local_cosmetic = LT_CosmeticStore.load_profile()

	_ghost_root = Node3D.new()
	_ghost_root.name = "LT_Ghosts"
	add_child(_ghost_root)

## Give the session its transport. The adapter should be (or become) a
## child of the session or otherwise live at a stable node path if it
## needs one (the high-level adapter does, for rpc).
func set_adapter(new_adapter: LT_NetAdapter) -> void:
	adapter = new_adapter
	adapter.peer_joined.connect(_on_peer_joined)
	adapter.peer_left.connect(_on_peer_left)
	adapter.message_received.connect(_on_message)

func is_active() -> bool:
	return adapter != null and adapter.is_session_active()

func local_peer_id() -> int:
	return adapter.local_peer_id() if adapter != null else 1

func get_cosmetic_for_peer(peer_id: int) -> Dictionary:
	if peer_id == local_peer_id():
		return local_cosmetic
	return peer_cosmetics.get(peer_id, {})

func describe_transport() -> String:
	return adapter.describe() if adapter != null else "none"

## ---- Local cosmetic editing (works offline too) ----

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(LT_Const.ACTION_COSMETIC_COLOR):
		local_cosmetic = LT_Cosmetic.cycle_color(local_cosmetic)
		_local_cosmetic_updated()
	elif event.is_action_pressed(LT_Const.ACTION_COSMETIC_STYLE):
		local_cosmetic = LT_Cosmetic.cycle_style(local_cosmetic)
		_local_cosmetic_updated()

func _local_cosmetic_updated() -> void:
	LT_CosmeticStore.save_profile(local_cosmetic)  # persist
	cosmetic_changed.emit(local_peer_id(), local_cosmetic)
	print("[LT coop] Cosmetic: %s %s" % [local_cosmetic["color"], local_cosmetic["style"]])
	if is_active():
		adapter.send(CHANNEL_COSMETIC, local_cosmetic, true)  # replicate live

## Public API — used by the in-game settings panel (and anything else).
## Validates, persists, and replicates in one call.
func set_local_cosmetic(raw: Dictionary) -> void:
	local_cosmetic = LT_Cosmetic.validate(raw)
	_local_cosmetic_updated()

## ---- Peer lifecycle ----

func _on_peer_joined(peer_id: int) -> void:
	print("[LT coop] Peer %d joined" % peer_id)
	_ensure_ghost(peer_id)
	# Introduce ourselves directly to the new peer.
	adapter.send(CHANNEL_COSMETIC, local_cosmetic, true, peer_id)

func _on_peer_left(peer_id: int) -> void:
	print("[LT coop] Peer %d left" % peer_id)
	peer_cosmetics.erase(peer_id)
	if _ghosts.has(peer_id):
		_ghosts[peer_id].queue_free()
		_ghosts.erase(peer_id)

func _ensure_ghost(peer_id: int) -> LT_GhostPlayer:
	if _ghosts.has(peer_id):
		return _ghosts[peer_id]
	var ghost := LT_GhostPlayer.new()
	ghost.name = "LT_Ghost_%d" % peer_id
	ghost.peer_id = peer_id
	_ghost_root.add_child(ghost)
	_ghosts[peer_id] = ghost
	return ghost

## ---- Outbound ----

## lt_net group tap from the fire sites.
func relay_shot(shot: LT_ShotResult) -> void:
	if not is_active():
		return
	# Only the local player's own shots leave this machine — local enemy
	# sim shots stay local.
	if not shot.shooter_is_player or shot.shooter_peer_id != local_peer_id():
		return
	adapter.send(CHANNEL_SHOT, {
		"s": _pack_v3(shot.start_position),
		"e": _pack_v3(shot.end_position),
		"ht": shot.hit_type,
	}, true)

func _process(delta: float) -> void:
	if not is_active():
		return
	_send_timer -= delta
	if _send_timer > 0.0:
		return
	_send_timer = TRANSFORM_SEND_INTERVAL

	var registry := get_tree().get_first_node_in_group(LT_Const.GROUP_REGISTRY)
	if registry == null:
		return
	for player in registry.get_all_players():
		if player.get_meta("lt_peer_id", 1) == local_peer_id():
			adapter.send(CHANNEL_TRANSFORM, {
				"p": _pack_v3(player.global_position),
				"ry": player.rotation.y,
			}, false)
			return

## ---- Inbound (validate everything) ----

func _on_message(peer_id: int, channel: StringName, payload: Dictionary) -> void:
	match channel:
		CHANNEL_COSMETIC:
			var cosmetic := LT_Cosmetic.validate(payload)
			peer_cosmetics[peer_id] = cosmetic
			_ensure_ghost(peer_id).apply_cosmetic(cosmetic)
			cosmetic_changed.emit(peer_id, cosmetic)
			print("[LT coop] Cosmetic from peer %d: %s %s (%s)" % [
				peer_id, cosmetic["color"], cosmetic["style"], cosmetic["name"]])
		CHANNEL_SHOT:
			_on_remote_shot(peer_id, payload)
		CHANNEL_TRANSFORM:
			var position := _unpack_v3(payload.get("p"))
			var rotation_y := float(payload.get("ry", 0.0))
			_ensure_ghost(peer_id).set_remote_transform(position, rotation_y)
		_:
			pass  # Unknown channels are ignored, not errors — forward compat.

func _on_remote_shot(peer_id: int, payload: Dictionary) -> void:
	# Rebuild a display-only shot; never re-raycast (result authority
	# stays with the peer that simulated it).
	var shot := LT_ShotResult.new()
	shot.shooter_is_player = true
	shot.shooter_peer_id = peer_id
	shot.start_position = _unpack_v3(payload.get("s"))
	shot.end_position = _unpack_v3(payload.get("e"))
	shot.hit_position = shot.end_position
	var hit_type := str(payload.get("ht", "MISS"))
	shot.hit_type = hit_type if VALID_HIT_TYPES.has(hit_type) else "MISS"
	shot.did_hit = shot.hit_type != "MISS"

	get_tree().call_group(LT_Const.GROUP_DEBUG, "draw_shot", shot)
	get_tree().call_group(LT_Const.GROUP_AUDIO, "play_shot", shot)

## ---- JSON-safe vector packing ----

func _pack_v3(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

func _unpack_v3(raw) -> Vector3:
	if raw is Array and raw.size() == 3:
		return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
	return Vector3.ZERO
