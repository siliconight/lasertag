extends Node
class_name LT_RunState
## Tracks the lifecycle of a single test run.

signal run_started(run_id: int)
signal run_ended(run_id: int, reason: String)

enum EndReason { NONE, TIMEOUT, TEAM_WIPE, OBJECTIVE, ENEMIES_CLEARED, MANUAL }

var run_id: int = 0
var is_running: bool = false
var elapsed_seconds: float = 0.0
var max_run_time_seconds: float = 180.0
var end_reason: EndReason = EndReason.NONE

func start_run(new_run_id: int, max_seconds: float) -> void:
	run_id = new_run_id
	max_run_time_seconds = max_seconds
	elapsed_seconds = 0.0
	end_reason = EndReason.NONE
	is_running = true
	run_started.emit(run_id)

func end_run(reason: EndReason) -> void:
	if not is_running:
		return
	is_running = false
	end_reason = reason
	run_ended.emit(run_id, end_reason_name())

func end_reason_name() -> String:
	return EndReason.keys()[end_reason]

## The run clock ticks on the PHYSICS frame, deliberately.
##
## Every combat event that reads it -- shots, deaths, line of sight -- is
## produced from `_physics_process` in LT_BotPlayerController and
## LT_EnemyBrain. When this ran on `_process` the two were different clocks:
## `elapsed_seconds` accumulated render-frame delta while the simulation
## advanced on physics ticks, and headless runs decouple the two entirely.
## `start_run()` zeroes this and spawns the pills in the same call, so a shot
## landing before the first render frame was stamped exactly 0.0 -- which is
## how a report came to claim first contact at 0.0s on a map whose nearest
## enemy stood 47.8m from a crew that acquires at 45m. The timings were not
## wrong about the ordering; they were measured with the wrong ruler.
##
## On the physics frame these numbers are simulated time: reproducible across
## machines, independent of frame rate, and directly comparable to the
## distances and speeds the map was built from. `max_run_time_seconds` becomes
## a budget of simulated seconds, which is what a deterministic evaluator
## should have been enforcing all along.
func _physics_process(delta: float) -> void:
	if not is_running:
		return
	elapsed_seconds += delta
	if elapsed_seconds >= max_run_time_seconds:
		end_run(EndReason.TIMEOUT)
