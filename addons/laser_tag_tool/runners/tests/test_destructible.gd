extends SceneTree
## Headless functional test for the replicated destructible proxy.
##
##     godot --headless --path . \
##       -s res://addons/laser_tag_tool/runners/test_destructible.gd
##
## Exit code 0 = all checks passed, 1 = failures (wire into CI like
## run_map_eval). Runs on the first process frame so node _ready and
## group membership are live.

var failures: int = 0

func check(condition: bool, label: String) -> void:
	if condition:
		print("  ok: " + label)
	else:
		failures += 1
		print("  FAIL: " + label)

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	print("[1] offline break via register_hit (no sync in tree)")
	var scene: PackedScene = load("res://addons/laser_tag_tool/scenes/LT_BreakableGlass.tscn")
	var glass: StaticBody3D = scene.instantiate()
	glass.name = "GlassA"
	root.add_child(glass)
	var d: LT_Destructible = glass.get_node("LT_Destructible")
	check(d != null, "LT_Destructible child found by name")
	check(glass.collision_layer == 1, "intact pane on layer 1")
	check(glass.get_node("GlassPane").visible, "intact visual shown")
	check(not glass.get_node("BrokenFrame").visible, "broken visual hidden")
	d.register_hit(1, Vector3.ZERO, Vector3.FORWARD)
	check(d.broken, "one hit breaks a 1 HP pane")
	check(glass.collision_layer == 0, "collision dropped on break")
	check(not glass.get_node("GlassPane").visible, "intact visual hidden")
	check(glass.get_node("BrokenFrame").visible, "broken visual shown")
	check(_count_debris() == 1, "cosmetic debris spawned locally")

	print("[2] reset_intact restores gameplay state")
	d.reset_intact()
	check(not d.broken, "broken flag cleared")
	check(glass.collision_layer == 1, "collision layer restored")
	check(glass.get_node("GlassPane").visible, "intact visual restored")
	check(not glass.get_node("BrokenFrame").visible, "broken visual hidden again")

	print("[3] multi-hit pane honors hit_points")
	var glass_b: StaticBody3D = scene.instantiate()
	glass_b.name = "GlassB"
	var d_b: LT_Destructible = glass_b.get_node("LT_Destructible")
	d_b.hit_points = 3  # before add_child so _ready initializes hp from it
	root.add_child(glass_b)
	d_b.take_local_damage(1, Vector3.ZERO, Vector3.FORWARD)
	d_b.take_local_damage(1, Vector3.ZERO, Vector3.FORWARD)
	check(not d_b.broken, "two of three hits leave it standing")
	d_b.take_local_damage(1, Vector3.ZERO, Vector3.FORWARD)
	check(d_b.broken, "third hit breaks it")

	print("[4] sync: authority break packet accepted, imposter ignored")
	var sync := LT_DestructibleSync.new()
	root.add_child(sync)
	var glass_c: StaticBody3D = scene.instantiate()
	glass_c.name = "GlassC"
	root.add_child(glass_c)
	var d_c: LT_Destructible = glass_c.get_node("LT_Destructible")
	sync._on_break(2, {"id": d_c.destructible_id, "seed": 42, "p": [0, 0, 0], "d": [0, 0, 1]})
	check(not d_c.broken, "break from non-authority peer ignored")
	sync._on_break(1, {"id": d_c.destructible_id, "seed": 42, "p": [0, 0, 0], "d": [0, 0, 1]})
	check(d_c.broken, "break from authority peer applied")

	print("[5] late-join snapshot applies state silently")
	var glass_d: StaticBody3D = scene.instantiate()
	glass_d.name = "GlassD"
	root.add_child(glass_d)
	var d_d: LT_Destructible = glass_d.get_node("LT_Destructible")
	var debris_before := _count_debris()
	sync._on_snapshot(1, {"ids": [d_d.destructible_id]})
	check(d_d.broken, "snapshot broke the pane")
	check(glass_d.collision_layer == 0, "snapshot dropped collision")
	check(_count_debris() == debris_before, "no debris for late-join state")
	sync._on_snapshot(1, {"ids": "garbage"})
	check(true, "malformed snapshot did not crash")

	print("[6] hits routed through an offline sync still break locally")
	var glass_e: StaticBody3D = scene.instantiate()
	glass_e.name = "GlassE"
	root.add_child(glass_e)
	var d_e: LT_Destructible = glass_e.get_node("LT_Destructible")
	d_e.register_hit(1, Vector3.ZERO, Vector3.FORWARD)
	check(d_e.broken, "sync present but unnetworked falls back to local")

	print("[7] pattern selection is deterministic per (id, seed)")
	var p1 := d_e._pattern_index(12345, 3)
	var p2 := d_e._pattern_index(12345, 3)
	check(p1 == p2, "same id + seed -> same pattern")
	check(p1 >= 0 and p1 < 3, "pattern index in range")

	print("[8] request validation clamps damage and ignores unknown ids")
	sync._on_break_request(7, {"id": "no_such_pane", "dmg": 1, "p": [0, 0, 0], "d": [0, 0, 1]})
	check(true, "unknown id ignored without crash")
	var glass_f: StaticBody3D = scene.instantiate()
	glass_f.name = "GlassF"
	var d_f: LT_Destructible = glass_f.get_node("LT_Destructible")
	d_f.hit_points = 50
	root.add_child(glass_f)
	sync._on_break_request(7, {"id": d_f.destructible_id, "dmg": 999999, "p": [0, 0, 0],
			"d": [0, 0, 1]})
	check(d_f.broken, "clamped 100-damage request still breaks a 50 HP pane")

	print("[9] real hitscan: fire() blocks on intact glass, passes once broken")
	# Muzzle at z=+5 aiming -Z: glass pane at origin, wall 2m behind it.
	# This exercises the LT_Shooter blocked-branch integration against a
	# LIVE physics space, not a direct method call.
	var rig := Node3D.new()
	rig.name = "HitscanRig"
	# Far from the origin, where the panes of earlier sections (GlassA is
	# intact again after [2]) would otherwise sit exactly on this ray.
	rig.position = Vector3(100, 0, 0)
	root.add_child(rig)
	var glass_g: StaticBody3D = scene.instantiate()
	glass_g.name = "GlassG"
	rig.add_child(glass_g)
	var wall := StaticBody3D.new()
	wall.name = "BackWall"
	wall.collision_layer = LT_Const.LAYER_WORLD
	wall.collision_mask = 0
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(4, 4, 0.5)
	wall_shape.shape = wall_box
	wall.add_child(wall_shape)
	rig.add_child(wall)
	wall.position = Vector3(0, 0, -2)
	var muzzle := Marker3D.new()
	rig.add_child(muzzle)
	muzzle.position = Vector3(0, 0, 5)
	var shooter := LT_Shooter.new()
	shooter.muzzle = muzzle
	rig.add_child(shooter)
	# Collision shapes register on the physics tick after they enter the
	# tree; shoot only once the space knows about the pane.
	await physics_frame
	await physics_frame
	var d_g: LT_Destructible = glass_g.get_node("LT_Destructible")
	var first := shooter.fire(Vector3(0, 0, -1))
	check(first.hit_type == "WORLD_BLOCKED", "intact pane blocks the beam")
	check(first.collider == glass_g, "first shot hit the pane, not the wall")
	check(d_g.broken, "the blocked shot registered and broke the pane")
	await physics_frame
	await physics_frame
	var second := shooter.fire(Vector3(0, 0, -1))
	check(second.hit_type == "WORLD_BLOCKED", "second shot still blocked (wall)")
	check(second.collider == wall, "second shot passed the broken pane to the wall")
	check(second.hit_position.z < -1.0, "second hit is behind the pane plane")

	print("[10] connect window: adapter present but inactive drops the hit")
	# A local break here would diverge from the authority forever, so the
	# hit must do nothing — unlike [6], where no adapter exists at all.
	var idle_adapter := LT_NetAdapter.new()
	root.add_child(idle_adapter)
	sync.set_adapter(idle_adapter)
	var glass_h: StaticBody3D = scene.instantiate()
	glass_h.name = "GlassH"
	root.add_child(glass_h)
	var d_h: LT_Destructible = glass_h.get_node("LT_Destructible")
	d_h.register_hit(1, Vector3.ZERO, Vector3.FORWARD)
	check(not d_h.broken, "hit during connect window dropped, pane intact")
	check(glass_h.collision_layer == 1, "pane still blocks after dropped hit")

	print("[11] authored debris: a plain-mesh scene gets flung as shard bodies")
	# A zoo glass_shard GLB imports as MeshInstance3Ds under a Node3D; the
	# destructible must wrap each in a cosmetic rigid body with a seeded
	# impulse. Modeled here with a synthetic packed scene of 3 meshes.
	# take_local_damage (not register_hit): the sync from [10] holds an
	# inactive adapter, which correctly drops routed hits.
	var authored_root := Node3D.new()
	authored_root.name = "AuthoredShards"
	for i in 3:
		var m := MeshInstance3D.new()
		m.name = "Shard%d" % i
		var box := BoxMesh.new()
		box.size = Vector3(0.1, 0.1, 0.02)
		m.mesh = box
		m.position = Vector3(0.2 * i, 0.1, 0.0)
		authored_root.add_child(m)
		m.owner = authored_root
	var packed := PackedScene.new()
	packed.pack(authored_root)
	var glass_i: StaticBody3D = scene.instantiate()
	glass_i.name = "GlassI"
	glass_i.position = Vector3(-100, 0, 0)
	root.add_child(glass_i)
	var d_i: LT_Destructible = glass_i.get_node("LT_Destructible")
	d_i.debris_scenes = [packed]
	d_i.take_local_damage(1, Vector3(-100, 0, 0), Vector3(0, 0, -1))
	check(d_i.broken, "authored-debris pane broke")
	var spawned := root.get_node_or_null("AuthoredShards")
	check(spawned != null, "authored debris scene instanced at the pane")
	if spawned != null:
		var bodies: Array = []
		var meshes: Array = []
		for child in spawned.get_children():
			if child is RigidBody3D:
				bodies.append(child)
				for sub in child.get_children():
					if sub is MeshInstance3D:
						meshes.append(sub)
		check(bodies.size() == 3, "each plain mesh wrapped in a rigid body")
		check(meshes.size() == 3, "every shard kept its visual mesh")
		var moving := 0
		for body in bodies:
			if body.linear_velocity.length() > 0.1:
				moving += 1
		check(moving == 3, "every shard body carries a seeded impulse")

	print("[12] bullets break glass, bombs break breaches")
	# bullet_breakable=false models a breach wall: LT_Shooter's path
	# (register_hit) must do nothing; register_blast must break it. The
	# sync leaves the group for a moment so the blast takes the local
	# path rather than being dropped by [10]'s inactive adapter.
	var glass_j: StaticBody3D = scene.instantiate()
	glass_j.name = "GlassJ"
	var d_j: LT_Destructible = glass_j.get_node("LT_Destructible")
	d_j.bullet_breakable = false
	root.add_child(glass_j)
	d_j.register_hit(99, Vector3.ZERO, Vector3.FORWARD)
	check(not d_j.broken, "bullet hit ignored on a charge-only destructible")
	check(glass_j.collision_layer == 1, "still standing after small arms")
	sync.remove_from_group(LT_Const.GROUP_DESTRUCTIBLE_SYNC)
	d_j.register_blast(1, Vector3.ZERO, Vector3.FORWARD)
	sync.add_to_group(LT_Const.GROUP_DESTRUCTIBLE_SYNC)
	check(d_j.broken, "blast broke it through the same pipeline")
	check(glass_j.collision_layer == 0, "collision dropped on breach")

	print("[13] game-driven seam: the breach wall reports, the game decides")
	# LT_BreachWall ships game_driven = true: like a door, its state
	# lives on the gameplay/networking layer (INTERACTIVES.md). The
	# toolset only reports stimuli (break_requested) and presents
	# whatever state the game applies (apply_break / reset_intact).
	var breach_scene: PackedScene = load(
		"res://addons/laser_tag_tool/scenes/LT_BreachWall.tscn")
	var wall_k: StaticBody3D = breach_scene.instantiate()
	wall_k.name = "BreachK"
	root.add_child(wall_k)
	var d_k: LT_Destructible = wall_k.get_node("LT_Destructible")
	var requests: Array = []
	d_k.break_requested.connect(
		func(dmg: int, _p: Vector3, _dir: Vector3, blast: bool) -> void:
			requests.append([dmg, blast]))
	d_k.register_hit(99, Vector3.ZERO, Vector3.FORWARD)
	check(not d_k.broken and requests.is_empty(),
			"bullets are a non-event for masonry: no break, no report")
	d_k.register_blast(3, Vector3.ZERO, Vector3.FORWARD)
	check(not d_k.broken, "a charge does not breach it either -- not ours to decide")
	check(requests == [[3, true]], "the charge was REPORTED as a blast request")
	sync._on_snapshot(1, {"ids": [d_k.destructible_id]})
	check(not d_k.broken, "toolset snapshots ignore a game-driven fixture")
	d_k.apply_break(Vector3.ZERO, Vector3(0, 0, 1), 77, true)
	check(d_k.broken, "the game's own call is what breaches it")
	check(wall_k.get_node("BreachedFrame").visible, "breached frame shown")
	check(wall_k.collision_layer == 0, "collision dropped on the game's order")
	d_k.reset_intact()
	check(not d_k.broken and wall_k.collision_layer == 1,
			"and the game can hand it back intact (round reset)")

	print("[14] rubble reacts differently from glass: low, heavy, chunky")
	var wall_l: StaticBody3D = breach_scene.instantiate()
	wall_l.name = "BreachL"
	root.add_child(wall_l)
	var d_l: LT_Destructible = wall_l.get_node("LT_Destructible")
	d_l.game_driven = false      # toolset-driven for this physics check
	sync.remove_from_group(LT_Const.GROUP_DESTRUCTIBLE_SYNC)
	var debris_before_nodes := get_nodes_in_group(LT_Const.GROUP_DEBRIS)
	d_l.register_blast(1, wall_l.global_position, Vector3(0, 0, 1))
	sync.add_to_group(LT_Const.GROUP_DESTRUCTIBLE_SYNC)
	check(d_l.broken, "toolset-mode blast breaches it")
	var rubble_root: Node = null
	for node in get_nodes_in_group(LT_Const.GROUP_DEBRIS):
		if not debris_before_nodes.has(node):
			rubble_root = node
	check(rubble_root != null, "rubble debris spawned")
	if rubble_root != null:
		var chunks: Array = []
		for child in rubble_root.get_children():
			if child is RigidBody3D:
				chunks.append(child)
		check(chunks.size() > 0, "rubble chunks exist")
		var low := true
		var moving := true
		for chunk in chunks:
			var v: Vector3 = chunk.linear_velocity
			if absf(v.y) > 0.8:
				low = false
			if Vector2(v.x, v.z).length() < 0.2:
				moving = false
		check(low, "every chunk stays low (|vy| <= 0.8; glass bursts to 5.0)")
		check(moving, "every chunk still tumbles outward")
		var visual: MeshInstance3D = null
		for sub in chunks[0].get_children():
			if sub is MeshInstance3D:
				visual = sub
		var box: BoxMesh = visual.mesh if visual != null else null
		check(box != null and box.size.z / box.size.x > 0.4,
				"chunk proportions, not glass-plate proportions")

	print("[15] eyeball showcase scene loads with its overrides intact")
	var showcase: PackedScene = load(
		"res://addons/laser_tag_tool/scenes/demo/LT_DestructibleShowcase.tscn")
	check(showcase != null and showcase.can_instantiate(), "showcase loads")
	if showcase != null:
		var stage := showcase.instantiate()
		var three: LT_Destructible = stage.get_node(
			"Exhibits/GlassThreeHits/LT_Destructible")
		var high: LT_Destructible = stage.get_node(
			"Exhibits/GlassHighDebris/LT_Destructible")
		var breach: LT_Destructible = stage.get_node(
			"Exhibits/BreachWall/LT_Destructible")
		check(three.hit_points == 3, "3-hit pane override applied")
		check(high.debris_quality == 2, "high-debris override applied")
		check(breach.game_driven and not breach.bullet_breakable,
				"breach exhibit ships game-driven and bullet-proof")
		check(stage.get_node("Driver") != null, "seam driver present")
		stage.free()

	print("[16] manual fire path: controller re-resolves camera and shooter")
	# 4.7 regression: typed @export node refs loaded null on the spawned
	# pill, so fire_once() null-checked camera/shooter and silently dropped
	# every human click (HUD forever read Shots: 0). Bots, enemies, and CI
	# never caught it -- they fire through paths that already re-resolve.
	# Simulate the null load and prove _ready() heals it and a click fires.
	var pill_scene: PackedScene = load("res://addons/laser_tag_tool/scenes/LT_PlayerPill.tscn")
	var pill: CharacterBody3D = pill_scene.instantiate()
	pill.position = Vector3(200, 1, 0)  # clear of every other test rig
	var pc: LT_PlayerController = pill.get_node("LT_PlayerController")
	pc.body = null
	pc.camera = null
	pc.shooter = null
	LT_Const.ensure_input_actions()  # the live pill polls movement actions
	root.add_child(pill)  # _ready must re-resolve all three
	check(pc.body == pill, "body re-resolved from parent")
	check(pc.camera != null, "camera re-resolved (loaded null on 4.7)")
	check(pc.shooter != null, "shooter re-resolved (loaded null on 4.7)")
	var counter := ShotCounter.new()
	root.add_child(counter)
	counter.add_to_group(LT_Const.GROUP_METRICS)
	pc.fire_once()
	counter.remove_from_group(LT_Const.GROUP_METRICS)
	check(counter.shots.size() == 1, "one click = one recorded shot")
	if counter.shots.size() == 1:
		var fired: LT_ShotResult = counter.shots[0]
		check(fired.hit_type != "INVALID", "shot raycast ran (muzzle wired)")
	pill.free()
	counter.free()

	print("")
	if failures == 0:
		print("ALL CHECKS PASSED")
	else:
		print("%d CHECKS FAILED" % failures)
	quit(1 if failures > 0 else 0)

## Captures record_shot broadcasts like the metrics collector would.
class ShotCounter:
	extends Node
	var shots: Array = []

	func record_shot(shot: LT_ShotResult) -> void:
		shots.append(shot)

func _count_debris() -> int:
	# By GROUP, never by name: a sibling name collision renames the new
	# node to "@<Class>@<id>" (measured), so name-counting sees only the
	# first debris root ever spawned and every later check goes vacuous.
	return get_nodes_in_group(LT_Const.GROUP_DEBRIS).size()
