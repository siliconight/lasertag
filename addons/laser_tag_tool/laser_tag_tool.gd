@tool
extends EditorPlugin
## Laser Tag Map Evaluation Tool — editor plugin entry point.
##
## The plugin is intentionally thin. Everything runs at game time via
## LT_MapEvalHarness. The plugin only registers custom node types so the
## harness and markers show up in the Create Node dialog.

const HARNESS_SCRIPT := preload("scripts/core/LT_MapEvalHarness.gd")
const SPAWN_SCRIPT := preload("scripts/core/LT_SpawnMarker.gd")

func _enter_tree() -> void:
	add_custom_type(
		"LT_MapEvalHarness", "Node3D", HARNESS_SCRIPT,
		null)
	add_custom_type(
		"LT_SpawnMarker", "Marker3D", SPAWN_SCRIPT,
		null)

func _exit_tree() -> void:
	remove_custom_type("LT_MapEvalHarness")
	remove_custom_type("LT_SpawnMarker")
