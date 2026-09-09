extends SceneTree
## A run's pills are gone before the next run starts (roadmap 125).
##
##     godot --headless --path . \
##       -s res://addons/laser_tag_tool/runners/tests/test_run_boundary_is_clean.gd
##
## `queue_free` is DEFERRED to the end of the frame, and `_clear_pills` runs
## mid-frame: `run_ended` is emitted from a process callback, so `end_run`,
## `_clear_pills` and `start_run` all happen inside one frame. A pill therefore
## stayed in the tree, and kept processing, until after the NEXT run had begun.
##
## It could still fire -- measured with probes at the fire site and the record
## site on market_row_001 seed 7503: a shot by `LT_Enemy_04` with
## `is_queued_for_deletion()` true, at elapsed 0.000 of the FOLLOWING run,
## stamping that run's first-contact figures as zero. One corrupted run per
## boundary a team wipe crossed, dragging `avg_time_to_first_enemy_shot` to
## 0.38 s.
##
## And it kept its NAME, so the replacement collided and Godot auto-renamed it:
## 17 of 23 source names in one 8-run report came back `@CharacterBody3D@13`
## instead of `LT_Enemy_04`.
##
## [2] is the one that matters. `PROCESS_MODE_DISABLED` passes [1] and fails
## [2], and it was tried and reverted for exactly that reason.

var failures: int = 0


func check(condition: bool, label: String) -> void:
	if condition:
		print("  ok: " + label)
	else:
		failures += 1
		print("  FAIL: " + label)


func _init() -> void:
	LT_Const.ensure_input_actions()
	var host := Node3D.new()
	get_root().add_child(host)

	var first := CharacterBody3D.new()
	first.name = "LT_Enemy_01"
	host.add_child(first)
	await process_frame

	print("[1] clearing takes it out of the tree in the SAME frame")
	# The line under test, as `_clear_pills` performs it.
	var parent: Node = first.get_parent()
	parent.remove_child(first)
	first.queue_free()
	check(host.get_child_count() == 0,
		"the host has no children immediately, without waiting a frame")

	print("[2] and the name is free for the next run's pill")
	var second := CharacterBody3D.new()
	second.name = "LT_Enemy_01"
	host.add_child(second)
	check(second.name == "LT_Enemy_01",
		"the replacement keeps its name (got %s)" % second.name)
	check(not second.name.begins_with("@"),
		"it is not auto-renamed, so reports still say which enemy acted")

	print("[3] the assumption this rests on: queue_free ALONE is not enough")
	var third := CharacterBody3D.new()
	third.name = "LT_Enemy_02"
	host.add_child(third)
	third.queue_free()
	var fourth := CharacterBody3D.new()
	fourth.name = "LT_Enemy_02"
	host.add_child(fourth)
	var renamed_msg: String = ("a queue_free'd node still holds its name this "
		+ "frame, so the replacement is renamed to %s -- which is the defect")
	check(fourth.name != "LT_Enemy_02", renamed_msg % fourth.name)

	host.queue_free()
	if failures == 0:
		print("PASS: the run boundary leaves nothing behind")
		quit(0)
	else:
		print("FAIL: %d check(s)" % failures)
		quit(1)
