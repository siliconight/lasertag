extends SceneTree
## ENet test, process 2: client — hits route to the authority; the break
## only lands here when the authority says so.

const NetCommon := preload("res://addons/laser_tag_tool/runners/tests/net_test/net_common.gd")

var failures: int = 0

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

func _debris_count() -> int:
	# By group, never by name: sibling collisions rename debris roots to
	# "@<Class>@<id>", so name-counting undercounts (measured on 4.3).
	return get_nodes_in_group(LT_Const.GROUP_DEBRIS).size()

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	var world := NetCommon.build(root)
	var adapter: LT_GodotHighLevelAdapter = world["adapter"]
	var sync: LT_DestructibleSync = world["sync"]
	var err := adapter.join_enet("127.0.0.1", 24565)
	check(err == OK, "client: join initiated")
	var ok := await wait_until(func() -> bool: return adapter.is_session_active(), 20.0)
	check(ok, "client: connected")
	ok = await wait_until(func() -> bool: return sync.adapter != null, 10.0)
	check(ok, "client: sync auto-wired to the session's adapter")

	var d_a: LT_Destructible = world["a"]
	var d_b: LT_Destructible = world["b"]
	d_a.register_hit(1, Vector3.ZERO, Vector3(0, 0, -1))
	check(not d_a.broken, "client: no local break before the authority verdict")
	ok = await wait_until(func() -> bool: return d_a.broken, 20.0)
	check(ok, "client: authority verdict broke GlassA here")
	ok = await wait_until(func() -> bool: return d_b.broken, 20.0)
	check(ok, "client: host-initiated GlassB break replicated here")
	check(_debris_count() >= 1, "client: live breaks played cosmetic debris")
	var glass_a: StaticBody3D = world["glass_a"]
	check(glass_a.collision_layer == 0, "client: broken pane no longer collides")

	print("CLIENT " + ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(1 if failures > 0 else 0)
