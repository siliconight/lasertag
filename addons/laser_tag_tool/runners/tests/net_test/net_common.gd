extends RefCounted
## Shared world for the 3-process ENet destructible test. Every process
## builds the SAME tree — rpc needs matching node paths on all peers.

static func build(root: Node) -> Dictionary:
	var session := LT_CoopSession.new()
	session.name = "LT_Session"
	root.add_child(session)
	var adapter := LT_GodotHighLevelAdapter.new()
	adapter.name = "LT_Adapter"
	session.add_child(adapter)
	session.set_adapter(adapter)
	var sync := LT_DestructibleSync.new()
	sync.name = "LT_Sync"
	root.add_child(sync)
	var scene: PackedScene = load("res://addons/laser_tag_tool/scenes/LT_BreakableGlass.tscn")
	var glass_a: StaticBody3D = scene.instantiate()
	glass_a.name = "GlassA"
	root.add_child(glass_a)
	var glass_b: StaticBody3D = scene.instantiate()
	glass_b.name = "GlassB"
	root.add_child(glass_b)
	glass_b.position = Vector3(5, 0, 0)
	return {
		"session": session,
		"adapter": adapter,
		"sync": sync,
		"glass_a": glass_a,
		"glass_b": glass_b,
		"a": glass_a.get_node("LT_Destructible"),
		"b": glass_b.get_node("LT_Destructible"),
	}
