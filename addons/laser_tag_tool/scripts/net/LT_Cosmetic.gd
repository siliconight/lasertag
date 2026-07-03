extends RefCounted
class_name LT_Cosmetic
## Tracer cosmetic profile — the payload of the persistence/replication
## spike. Everything is plain primitives so it serializes to JSON on disk
## and travels over RPC untouched.
##
## Schema (all optional, validated on every ingest path):
##   { "name": String, "color": "#rrggbb", "style": "solid|dashed|rail" }
##
## validate() is applied to BOTH disk loads and network payloads — never
## trust either.

const STYLES: Array[String] = ["solid", "dashed", "rail"]
const MAX_NAME_LENGTH := 24

static func default_profile() -> Dictionary:
	# Fresh installs get a random hue so two local test instances differ
	# without any configuration — instant visual proof in coop.
	var color := Color.from_hsv(randf(), 0.85, 1.0)
	return {
		"name": "Player",
		"color": "#" + color.to_html(false),
		"style": STYLES[randi() % STYLES.size()],
	}

static func validate(raw) -> Dictionary:
	var out := default_profile()
	if raw is not Dictionary:
		return out

	var name = raw.get("name", out["name"])
	if name is String and not name.is_empty():
		out["name"] = name.substr(0, MAX_NAME_LENGTH)

	var color = raw.get("color", out["color"])
	if color is String and Color.html_is_valid(color):
		out["color"] = "#" + Color.html(color).to_html(false)

	var style = raw.get("style", out["style"])
	if style is String and STYLES.has(style):
		out["style"] = style

	return out

static func color_of(cosmetic: Dictionary) -> Color:
	return Color.html(cosmetic.get("color", "#ffffff"))

static func style_of(cosmetic: Dictionary) -> String:
	var style: String = cosmetic.get("style", "solid")
	return style if STYLES.has(style) else "solid"

static func cycle_color(cosmetic: Dictionary) -> Dictionary:
	var current := color_of(cosmetic)
	var hue := fmod(current.h + 0.11, 1.0)
	cosmetic["color"] = "#" + Color.from_hsv(hue, 0.85, 1.0).to_html(false)
	return cosmetic

static func cycle_style(cosmetic: Dictionary) -> Dictionary:
	var index := STYLES.find(style_of(cosmetic))
	cosmetic["style"] = STYLES[(index + 1) % STYLES.size()]
	return cosmetic
