extends LT_NetAdapter
class_name LT_LoopbackAdapter
## Smallest possible LT_NetAdapter — doubles as the reference
## implementation for custom-protocol integrators and as a zero-network
## smoke test (`--lt-loopback`): every message you send is echoed back
## as if it came from a phantom peer, so you can watch the entire
## session pipeline (cosmetic exchange, remote tracers, ghost pill)
## alone in one window.
##
## Writing your own adapter is exactly this shape:
##   1. extend LT_NetAdapter
##   2. in send(): hand (channel, payload, reliable, target) to your
##      transport — payload is already JSON-safe
##   3. when your transport delivers a message: emit
##      message_received(peer_id, channel, payload)
##   4. on connect/disconnect: emit peer_joined / peer_left
##   5. return your ints from local_peer_id(), truth from
##      is_session_active()

const PHANTOM_PEER_ID := 999
const ECHO_DELAY := 0.05

var _active: bool = false

func start() -> void:
	_active = true
	print("[LT net] Loopback adapter up — phantom peer %d will mirror you" % PHANTOM_PEER_ID)
	# Simulate the phantom connecting a moment after startup.
	get_tree().create_timer(0.5).timeout.connect(
		func() -> void: peer_joined.emit(PHANTOM_PEER_ID))

func send(channel: StringName, payload: Dictionary, _reliable: bool,
		_target_peer: int = 0) -> void:
	if not _active:
		return
	# Echo back shortly, offset so the mirrored ghost isn't inside you.
	var echoed := payload.duplicate(true)
	if channel == &"transform" and echoed.has("p"):
		var p: Array = echoed["p"]
		echoed["p"] = [float(p[0]) + 2.0, p[1], float(p[2]) + 2.0]
	get_tree().create_timer(ECHO_DELAY).timeout.connect(
		func() -> void: message_received.emit(PHANTOM_PEER_ID, channel, echoed))

func local_peer_id() -> int:
	return 1

func is_session_active() -> bool:
	return _active

func describe() -> String:
	return "loopback (phantom peer %d)" % PHANTOM_PEER_ID
