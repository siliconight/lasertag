extends RefCounted
class_name LT_CosmeticStore
## Disk persistence for the local player's cosmetic. This is the
## "persist" half of the spike: your tracer color/style survives
## restarts, per machine, with zero backend.

const SAVE_PATH := "user://laser_tag_tool/cosmetic.json"

static func load_profile() -> Dictionary:
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		var fresh := LT_Cosmetic.default_profile()
		save_profile(fresh)
		return fresh
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return LT_Cosmetic.validate(parsed)

static func save_profile(cosmetic: Dictionary) -> void:
	var directory := SAVE_PATH.get_base_dir()
	if not DirAccess.dir_exists_absolute(directory):
		DirAccess.make_dir_recursive_absolute(directory)
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("LT_CosmeticStore: cannot write %s" % SAVE_PATH)
		return
	file.store_string(JSON.stringify(LT_Cosmetic.validate(cosmetic), "  "))
	file.close()
