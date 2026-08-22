extends SceneTree
## ENet test, process 3: late joiner — both panes were broken before this
## process connected; the snapshot must apply state silently.

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
	var err := adapter.join_enet("127.0.0.1", 24565)
	check(err == OK, "late: join initiated")
	var ok := await wait_until(func() -> bool: return adapter.is_session_active(), 20.0)
	check(ok, "late: connected")

	var d_a: LT_Destructible = world["a"]
	var d_b: LT_Destructible = world["b"]
	ok = await wait_until(func() -> bool: return d_a.broken and d_b.broken, 20.0)
	check(ok, "late: snapshot broke both panes")
	var glass_a: StaticBody3D = world["glass_a"]
	var glass_b: StaticBody3D = world["glass_b"]
	check(glass_a.collision_layer == 0, "late: GlassA collision dropped")
	check(glass_b.collision_layer == 0, "late: GlassB collision dropped")
	check(glass_a.get_node("BrokenFrame").visible, "late: GlassA shows broken visual")
	check(_debris_count() == 0, "late: state applied silently — no debris replay")

	print("LATE " + ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(1 if failures > 0 else 0)
