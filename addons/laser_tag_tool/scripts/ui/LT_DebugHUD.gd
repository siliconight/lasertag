extends Label
class_name LT_DebugHUD
## Corner debug readout (TDD §21.2).

var harness: Node  # LT_MapEvalHarness — untyped to avoid load-order cycles.

func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2(12, 12)
	add_theme_color_override("font_color", Color.WHITE)
	add_theme_color_override("font_outline_color", Color.BLACK)
	add_theme_constant_override("outline_size", 4)

func _process(_delta: float) -> void:
	if harness == null:
		return
	text = harness.hud_text()
