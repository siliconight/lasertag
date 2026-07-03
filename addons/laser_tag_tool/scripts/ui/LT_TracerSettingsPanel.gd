extends PanelContainer
class_name LT_TracerSettingsPanel
## In-game tracer settings — the "IMGUI" panel. Press [Tab] to toggle.
##
## Change your laser color (color picker), style (solid / dashed /
## rail), and display name at RUNTIME. Every change:
##   1. applies to your tracers and your pill tint instantly
##   2. persists to disk (survives restart)
##   3. replicates live — other players watch your lasers change
##
## The panel says the quiet part out loud too: cosmetics replicate,
## gameplay does not (yet). Each peer runs its own enemies and damage —
## networked gameplay state is Phase 5.

## While dragging the color wheel, broadcasts are throttled to this
## interval; the final value always commits on close/release.
const COMMIT_INTERVAL := 0.15

var session: LT_CoopSession

var _name_edit: LineEdit
var _color_button: ColorPickerButton
var _style_buttons: Dictionary = {}
var _status_label: Label
var _commit_timer: float = 0.0
var _dirty: bool = false

func _ready() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	position.x -= 20.0
	custom_minimum_size = Vector2(280, 0)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	var title := Label.new()
	title.text = "TRACER SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	root.add_child(_labeled("Name:"))
	_name_edit = LineEdit.new()
	_name_edit.max_length = LT_Cosmetic.MAX_NAME_LENGTH
	_name_edit.text_submitted.connect(func(_t: String) -> void: _commit())
	_name_edit.focus_exited.connect(_commit)
	root.add_child(_name_edit)

	root.add_child(_labeled("Laser color:"))
	_color_button = ColorPickerButton.new()
	_color_button.custom_minimum_size = Vector2(0, 36)
	_color_button.edit_alpha = false
	_color_button.color_changed.connect(func(_c: Color) -> void: _dirty = true)
	_color_button.popup_closed.connect(_commit)
	root.add_child(_color_button)

	root.add_child(_labeled("Laser style:"))
	var style_row := HBoxContainer.new()
	style_row.add_theme_constant_override("separation", 6)
	root.add_child(style_row)
	for style in LT_Cosmetic.STYLES:
		var button := Button.new()
		button.text = style
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_on_style_pressed.bind(style))
		style_row.add_child(button)
		_style_buttons[style] = button

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_size_override("font_size", 11)
	_status_label.modulate = Color(1, 1, 1, 0.7)
	root.add_child(_status_label)

	var close_hint := Label.new()
	close_hint.text = "[Tab] close"
	close_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	close_hint.add_theme_font_size_override("font_size", 11)
	close_hint.modulate = Color(1, 1, 1, 0.5)
	root.add_child(close_hint)

func _labeled(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label

func _input(event: InputEvent) -> void:
	if event.is_action_pressed(LT_Const.ACTION_SETTINGS):
		toggle()
		get_viewport().set_input_as_handled()

func toggle() -> void:
	visible = not visible
	if visible:
		_refresh_from_session()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		_commit()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _refresh_from_session() -> void:
	if session == null:
		return
	var cosmetic := session.local_cosmetic
	_name_edit.text = cosmetic.get("name", "Player")
	_color_button.color = LT_Cosmetic.color_of(cosmetic)
	var current_style := LT_Cosmetic.style_of(cosmetic)
	for style in _style_buttons:
		_style_buttons[style].button_pressed = style == current_style
	_update_status()

func _update_status() -> void:
	if session == null:
		return
	var line := "Changes save to disk and apply instantly."
	if session.is_active():
		line += " %d other player(s) see them live." % session.peer_cosmetics.size()
	else:
		line += " Not connected — they'll replicate when you are."
	line += "\nNote: only cosmetics replicate. Enemies and damage are" \
		+ " local per player (gameplay netcode is a later phase)."
	_status_label.text = line

func _on_style_pressed(style: String) -> void:
	for other in _style_buttons:
		_style_buttons[other].button_pressed = other == style
	_commit()

func _process(delta: float) -> void:
	# Live drag on the color wheel: throttle commits so the wire sees at
	# most one cosmetic update per COMMIT_INTERVAL while still feeling
	# instant on other screens.
	if not _dirty:
		return
	_commit_timer -= delta
	if _commit_timer <= 0.0:
		_commit()

func _commit() -> void:
	if session == null or not visible:
		_dirty = false
		return
	_dirty = false
	_commit_timer = COMMIT_INTERVAL

	var selected_style := LT_Cosmetic.style_of(session.local_cosmetic)
	for style in _style_buttons:
		if _style_buttons[style].button_pressed:
			selected_style = style
			break

	session.set_local_cosmetic({
		"name": _name_edit.text,
		"color": "#" + _color_button.color.to_html(false),
		"style": selected_style,
	})
	_update_status()
