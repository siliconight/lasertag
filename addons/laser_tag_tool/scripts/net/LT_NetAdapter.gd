extends Node
class_name LT_NetAdapter
## Transport abstraction for the cosmetic replication layer.
##
## LT_CoopSession never touches a socket, a MultiplayerPeer, or an @rpc —
## it only talks to this contract. To run LT cosmetics over YOUR game's
## networking (Steam sockets, WebRTC, Nakama, custom UDP, rollback, ...),
## subclass this, implement the 3 methods, emit the 3 signals. That's the
## whole integration surface (~30 lines; see LT_LoopbackAdapter for the
## smallest possible reference).
##
## CONTRACT
## - Peer ids are ints, stable for the life of a peer's connection, and
##   unique within the session. 0 as a send target means broadcast.
##   Your adapter owns the mapping from your protocol's identity
##   (SteamID, session token, ...) to these ints.
## - Payloads are JSON-SAFE Dictionaries: numbers, strings, bools,
##   arrays, nested dicts only. No Vector3, no Objects — the session
##   packs vectors as [x, y, z] before they reach you, so
##   `JSON.stringify(payload)` is always a valid encoding if your
##   transport wants text.
## - `reliable = false` messages are high-frequency and loss-tolerant
##   (ghost transforms at 10 Hz). Deliver them however is cheap; drops
##   and reordering are fine. `reliable = true` messages (cosmetics,
##   shot tracers) must arrive.
## - Emit peer_joined for every peer that is ALREADY present when the
##   adapter comes up mid-session (late join into a running game).

signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
signal message_received(peer_id: int, channel: StringName, payload: Dictionary)

## Send payload on a channel. target_peer 0 broadcasts to all other
## peers; a specific id sends to that peer only.
func send(_channel: StringName, _payload: Dictionary, _reliable: bool,
		_target_peer: int = 0) -> void:
	push_error("LT_NetAdapter.send() not implemented")

## This machine's stable peer id within the session.
func local_peer_id() -> int:
	return 1

## True while the transport can deliver messages to at least the session
## infrastructure (server up / client connected).
func is_session_active() -> bool:
	return false

## Short human string for the HUD ("enet host :24565", "steam lobby", ...).
func describe() -> String:
	return "none"
