extends Node
class_name LT_DestructibleSync
## Networked authority for LT_Destructible state (breakable glass, ...).
##
## The replicated-destructible pattern, applied to LT's transport layer:
##   - ONE peer (the authority) owns the gameplay state of every
##     destructible: hit points, intact/broken, collision. Everyone else
##     asks; nobody else decides.
##   - The break EVENT is transient: one small reliable packet
##     {id, seed, impact, direction} that each peer uses to play the
##     cosmetic break locally, now. Debris never crosses the wire.
##   - The break STATE is persistent: late joiners receive a snapshot of
##     broken ids and apply it silently — collision and visuals, no
##     debris replay. They only need to know the pane is already broken.
##
## Transport: rides the same LT_NetAdapter as LT_CoopSession. Drop ONE
## LT_DestructibleSync anywhere in the level scene; it wires itself to the
## session's adapter once the session comes up (or hand it an adapter
## directly with set_adapter()). With no adapter at all, destructibles
## break purely locally — solo play needs nothing from this node. With an
## adapter that is not (yet) active — a client mid-connect — hits are
## DROPPED instead: a local break in that window would diverge from the
## authority forever, and no later packet un-breaks a pane.
##
## Authority: authority_peer_id defaults to 1 — Godot high-level
## multiplayer's server id, which is what LT_GodotHighLevelAdapter reports
## on the host. Custom adapters own their peer-id mapping (see
## LT_NetAdapter), so point this at whichever id your adapter gives the
## machine that should own destructible state.
##
## Local enemy sims may diverge between peers (that is LT's honest scope),
## so ANY locally-simulated hit — the player's or a local enemy's — routes
## through the authority. Divergent sims, one shared answer.

const CHANNEL_BREAK_REQUEST := &"dst_req"
const CHANNEL_BREAK := &"dst_break"
const CHANNEL_SNAPSHOT := &"dst_snap"
const MAX_REQUEST_DAMAGE := 100

@export var authority_peer_id: int = 1

var adapter: LT_NetAdapter

var _wire_timer: Timer

func _ready() -> void:
	add_to_group(LT_Const.GROUP_DESTRUCTIBLE_SYNC)
	# The session's adapter may not exist yet at _ready (the harness sets
	# it up at startup); poll cheaply until it does, then stop.
	_wire_timer = Timer.new()
	_wire_timer.wait_time = 1.0
	_wire_timer.timeout.connect(_try_auto_wire)
	add_child(_wire_timer)
	_wire_timer.start()
	_try_auto_wire.call_deferred()

func set_adapter(new_adapter: LT_NetAdapter) -> void:
	if new_adapter == null or adapter == new_adapter:
		return
	adapter = new_adapter
	adapter.message_received.connect(_on_message)
	adapter.peer_joined.connect(_on_peer_joined)
	if _wire_timer != null:
		_wire_timer.stop()
	print("[LT destructible] Sync riding adapter: %s" % adapter.describe())

func _try_auto_wire() -> void:
	if adapter != null:
		return
	var session := get_tree().get_first_node_in_group(LT_Const.GROUP_NET)
	if session == null:
		return
	var session_adapter := session.get("adapter") as LT_NetAdapter
	if session_adapter != null:
		set_adapter(session_adapter)

func is_networked() -> bool:
	return adapter != null and adapter.is_session_active()

## True when this machine owns destructible state: the authority peer of a
## live session, or any machine with no live session (offline = you are
## your own server).
func is_authority() -> bool:
	if not is_networked():
		return true
	return adapter.local_peer_id() == authority_peer_id

## ---- Local hits in (called by LT_Destructible.register_hit) ----

func route_hit(destructible: LT_Destructible, damage: int, impact_point: Vector3,
		impact_direction: Vector3) -> void:
	if destructible == null or destructible.broken:
		return
	# A game-driven fixture's state belongs to the game's own netcode
	# (doors, breach walls -- INTERACTIVES.md). This authority never
	# touches it, so the two replication layers cannot fight.
	if destructible.game_driven:
		return
	# No adapter at all = genuinely offline: break locally.
	if adapter == null:
		destructible.take_local_damage(damage, impact_point, impact_direction)
		return
	# A transport exists but is not up (still connecting, or torn down).
	# DROP the hit: a local break here would diverge from the authority
	# forever — no later packet un-breaks a pane. A shot that does
	# nothing during the connect window is honest; a pane that is broken
	# on one screen and intact on the rest is not.
	if not adapter.is_session_active():
		return
	if adapter.local_peer_id() == authority_peer_id:
		_authority_damage(destructible, damage, impact_point, impact_direction)
		return
	adapter.send(CHANNEL_BREAK_REQUEST, {
		"id": destructible.destructible_id,
		"dmg": damage,
		"p": _pack_v3(impact_point),
		"d": _pack_v3(impact_direction),
	}, true, authority_peer_id)

## Authority only: apply damage to the canonical state; on the breaking
## hit, replicate the persistent state change and the transient event in
## one packet, then break locally too.
func _authority_damage(destructible: LT_Destructible, damage: int, impact_point: Vector3,
		impact_direction: Vector3) -> void:
	if not destructible.deduct_hit_points(damage):
		return
	var break_seed := randi() & 0x7FFFFFFF
	# A request can arrive while the session is winding down (or in a
	# local-only setup); breaking locally still has to work then.
	if is_networked():
		adapter.send(CHANNEL_BREAK, {
			"id": destructible.destructible_id,
			"seed": break_seed,
			"p": _pack_v3(impact_point),
			"d": _pack_v3(impact_direction),
		}, true)
	destructible.apply_break(impact_point, impact_direction, break_seed, true)

## ---- Inbound (validate everything) ----

func _on_message(peer_id: int, channel: StringName, payload: Dictionary) -> void:
	match channel:
		CHANNEL_BREAK_REQUEST:
			_on_break_request(peer_id, payload)
		CHANNEL_BREAK:
			_on_break(peer_id, payload)
		CHANNEL_SNAPSHOT:
			_on_snapshot(peer_id, payload)
		_:
			pass  # Cosmetic/shot/transform traffic on the shared adapter.

func _on_break_request(_peer_id: int, payload: Dictionary) -> void:
	# Only the authority arbitrates. Requests carry a claim, not a verdict.
	if not is_authority():
		return
	var destructible := _find_destructible(str(payload.get("id", "")))
	if destructible == null or destructible.broken or destructible.game_driven:
		return
	var damage := clampi(int(payload.get("dmg", 1)), 1, MAX_REQUEST_DAMAGE)
	_authority_damage(destructible, damage,
			_unpack_v3(payload.get("p")), _unpack_v3(payload.get("d")))

func _on_break(peer_id: int, payload: Dictionary) -> void:
	# State only ever flows FROM the authority; anyone else claiming a
	# break is ignored, not honored.
	if peer_id != authority_peer_id:
		return
	var destructible := _find_destructible(str(payload.get("id", "")))
	if destructible == null or destructible.broken or destructible.game_driven:
		return
	var break_seed := int(payload.get("seed", 0))
	destructible.apply_break(
		_unpack_v3(payload.get("p")), _unpack_v3(payload.get("d")), break_seed, true)

func _on_snapshot(peer_id: int, payload: Dictionary) -> void:
	if peer_id != authority_peer_id:
		return
	var ids = payload.get("ids")
	if ids is not Array:
		return
	for raw_id in ids:
		var destructible := _find_destructible(str(raw_id))
		if destructible != null and not destructible.broken \
				and not destructible.game_driven:
			# Late join: the state without the event. Game-driven ids
			# are ignored -- their snapshot is the game's to send.
			destructible.apply_break(Vector3.ZERO, Vector3.ZERO, 0, false)

## ---- Late join (adapter emits peer_joined for already-present peers too) ----

func _on_peer_joined(peer_id: int) -> void:
	if not is_networked() or adapter.local_peer_id() != authority_peer_id:
		return
	var broken_ids: Array = []
	for node in get_tree().get_nodes_in_group(LT_Const.GROUP_DESTRUCTIBLE):
		if node is LT_Destructible and node.broken and not node.game_driven:
			broken_ids.append(node.destructible_id)
	if broken_ids.is_empty():
		return
	adapter.send(CHANNEL_SNAPSHOT, {"ids": broken_ids}, true, peer_id)

## ---- Lookup + JSON-safe vector packing (mirrors LT_CoopSession) ----

func _find_destructible(id: String) -> LT_Destructible:
	if id.is_empty():
		return null
	for node in get_tree().get_nodes_in_group(LT_Const.GROUP_DESTRUCTIBLE):
		if node is LT_Destructible and node.destructible_id == id:
			return node
	return null

func _pack_v3(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

func _unpack_v3(raw) -> Vector3:
	if raw is Array and raw.size() == 3:
		return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
	return Vector3.ZERO
