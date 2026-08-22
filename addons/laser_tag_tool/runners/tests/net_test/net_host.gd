extends SceneTree
## ENet test, process 1: host = authority (peer 1).

const NetCommon := preload("res://addons/laser_tag_tool/runners/tests/net_test/net_common.gd")

var failures: int = 0
var peers_seen: Dictionary = {}

func check(condition: bool, label: String) -> void:
	if condition:
		print("  ok: " + label)
	else:
		failures += 1
		print("  FAIL: " + label)

func wait_until(predicate: Callable, timeout_s: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await create_timer(0.05).timeout
	return predicate.call()

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	var world := NetCommon.build(root)
	var adapter: LT_GodotHighLevelAdapter = world["adapter"]
	adapter.peer_joined.connect(func(id: int) -> void: peers_seen[id] = true)
	var err := adapter.host_enet(24565)
	check(err == OK, "host: ENet server up on 24565")
	var d_a: LT_Destructible = world["a"]
	var d_b: LT_Destructible = world["b"]

	var got := await wait_until(func() -> bool: return d_a.broken, 25.0)
	check(got, "host: client's request broke GlassA on the authority")

	d_b.register_hit(1, Vector3(5, 0, 0), Vector3.FORWARD)
	check(d_b.broken, "host: authority's own hit broke GlassB")

	got = await wait_until(func() -> bool: return peers_seen.size() >= 2, 25.0)
	check(got, "host: late joiner connected")
	await create_timer(5.0).timeout

	print("HOST " + ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(1 if failures > 0 else 0)
