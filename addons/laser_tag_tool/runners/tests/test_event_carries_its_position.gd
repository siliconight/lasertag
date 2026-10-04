extends SceneTree
## A named event is logged at the position it carries (0.23.2).
##
## `record_event` logged every named event -- PlayerStuck, EnemyStuck,
## RouteProgress -- with a top-level `position` of `Vector3.ZERO`, while both
## stuck emitters put the real position in `metadata.position`. Every reader
## took the top-level field: Level Factory's cold-run notes for 9140 and 9141
## said seed 9181's stuck events "carry no position", and two attributions
## were left open on that. They were all at one spot -- 1,354 of 1,378 at
## Godot (55.3, 6.0, 13.1), six metres up.

var failures: int = 0


func check(condition: bool, label: String) -> void:
	if condition:
		print("  ok: " + label)
	else:
		failures += 1
		print("  FAIL: " + label)


func _init() -> void:
	var m := LT_MetricsCollector.new()
	m.record_debug_events = true
	m.begin_run(1, 4, 6)
	print("[1] a stuck event is logged where it happened")
	m.record_event("PlayerStuck", {"source": "LT_Player_01", "position": [55.33, 6.0, 13.1]})
	var e: Dictionary = m.events[m.events.size() - 1]
	check(e["event"] == "PlayerStuck", "the event is the one recorded")
	check(e["position"] == [55.33, 6.0, 13.1], "its top-level position is the metadata's: %s" % [e["position"]])
	print("[2] an event that carries no position still logs zero, as before")
	m.record_event("RouteProgress", {"reached": 2, "total": 5})
	e = m.events[m.events.size() - 1]
	check(e["position"] == [0.0, 0.0, 0.0], "no position, the origin: %s" % [e["position"]])
	print("[3] the control: the counters still count")
	check(int(m.current["player_stuck_events"]) == 1, "one PlayerStuck counted")
	m.free()
	print("EVENT_POSITION %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(1 if failures else 0)
