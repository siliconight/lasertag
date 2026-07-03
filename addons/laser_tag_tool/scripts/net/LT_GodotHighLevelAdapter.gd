extends LT_NetAdapter
class_name LT_GodotHighLevelAdapter
## Default adapter: rides Godot's high-level MultiplayerAPI, which means
## it works unchanged with ANY MultiplayerPeer — ENet, WebSocketMultiplayerPeer,
## WebRTCMultiplayerPeer, GodotSteam's SteamMultiplayerPeer, etc.
##
## Two ways in:
##   1. attach() — the important one for integration: your game already
##      set `multiplayer.multiplayer_peer` however it likes; this adapter
##      just rides it. LT never opens its own connection.
##   2. host_enet() / join_enet() — convenience for the standalone LT
##      demo (what --lt-host / --lt-join use).
##
## NOTE: rpc() requires this node to exist at the same node path on all
## peers. Keep the harness/session at a stable place in the scene (it is
## a fixed-named child chain by default), or register it as an autoload
## in your game.

const DEFAULT_PORT := 24565

var _attached: bool = false
var _owns_peer: bool = false

func _ready() -> void:
	multiplayer.peer_connected.connect(func(id: int) -> void: peer_joined.emit(id))
	multiplayer.peer_disconnected.connect(func(id: int) -> void: peer_left.emit(id))
	multiplayer.server_disconnected.connect(_on_server_disconnected)

## Ride whatever MultiplayerPeer the game already configured.
## Returns false if there is nothing usable to attach to.
func attach() -> bool:
	if not _has_real_peer():
		return false
	_attached = true
	_owns_peer = false
	# Late attach into a running session: surface peers that are already here.
	for peer_id in multiplayer.get_peers():
		peer_joined.emit(peer_id)
	print("[LT net] Attached to existing multiplayer peer (%s), local id %d" % [
		multiplayer.multiplayer_peer.get_class(), local_peer_id()])
	return true

func host_enet(port: int = DEFAULT_PORT, max_clients: int = 8) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, max_clients)
	if err != OK:
		push_error("LT net: host failed on port %d (%s)" % [port, error_string(err)])
		return err
	multiplayer.multiplayer_peer = peer
	_attached = true
	_owns_peer = true
	print("[LT net] Hosting ENet on port %d as peer %d" % [port, local_peer_id()])
	return OK

func join_enet(ip: String, port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		push_error("LT net: join %s:%d failed (%s)" % [ip, port, error_string(err)])
		return err
	multiplayer.multiplayer_peer = peer
	_attached = true
	_owns_peer = true
	print("[LT net] Joining %s:%d ..." % [ip, port])
	return OK

## ---- LT_NetAdapter contract ----

func send(channel: StringName, payload: Dictionary, reliable: bool,
		target_peer: int = 0) -> void:
	if not is_session_active():
		return
	if reliable:
		if target_peer == 0:
			_msg_reliable.rpc(channel, payload)
		else:
			_msg_reliable.rpc_id(target_peer, channel, payload)
	else:
		if target_peer == 0:
			_msg_unreliable.rpc(channel, payload)
		else:
			_msg_unreliable.rpc_id(target_peer, channel, payload)

func local_peer_id() -> int:
	return multiplayer.get_unique_id()

func is_session_active() -> bool:
	if not _attached or not _has_real_peer():
		return false
	var status := multiplayer.multiplayer_peer.get_connection_status()
	return status == MultiplayerPeer.CONNECTION_CONNECTED

func describe() -> String:
	if not _attached:
		return "godot-hl (idle)"
	var mode := "own-enet" if _owns_peer else "attached"
	return "godot-hl %s (%s)" % [mode, multiplayer.multiplayer_peer.get_class()]

## ---- Wire ----

@rpc("any_peer", "reliable")
func _msg_reliable(channel: StringName, payload: Dictionary) -> void:
	message_received.emit(multiplayer.get_remote_sender_id(), channel, payload)

@rpc("any_peer", "unreliable_ordered")
func _msg_unreliable(channel: StringName, payload: Dictionary) -> void:
	message_received.emit(multiplayer.get_remote_sender_id(), channel, payload)

func _has_real_peer() -> bool:
	var peer := multiplayer.multiplayer_peer
	return peer != null and peer is not OfflineMultiplayerPeer

func _on_server_disconnected() -> void:
	# Surface as everyone leaving; session cleans up per-peer state.
	for peer_id in multiplayer.get_peers():
		peer_left.emit(peer_id)
	_attached = false
	_owns_peer = false
