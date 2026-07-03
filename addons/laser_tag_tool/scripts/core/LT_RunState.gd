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

func _process(delta: float) -> void:
	if not is_running:
		return
	elapsed_seconds += delta
	if elapsed_seconds >= max_run_time_seconds:
		end_run(EndReason.TIMEOUT)
