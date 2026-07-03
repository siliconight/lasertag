extends Node3D
class_name LT_ShotAudio
## Shot audio feedback. Listens on the "lt_audio" group: play_shot(shot).
##
## Two paths:
##   1. gool (preferred) — if a `Gool` autoload is present, shot events are
##      routed to it. Integration point is ONE call site (`_play_gool`);
##      adjust `gool_play_method` / event name exports to match the gool
##      API. Per gool practice, `has_sound()` is asserted at the call site
##      before playing — unknown events fall back to synth, never silence.
##   2. Synth fallback — zero-asset generated PCM blips (laser-tag pews),
##      so the tool makes sound out of the box in any project.
##
## Sounds: player shot (2D, local), enemy shot (3D at muzzle — directional
## fire audio is itself a map readability signal), hit confirm, world-
## blocked thud, player-hurt tone. Disabled in headless.

@export var enabled: bool = true
@export var volume_db: float = -8.0

@export_group("gool")
@export var use_gool: bool = true
@export var gool_autoload_name: String = "Gool"
## Method called as: gool.<method>(event_name: String, position: Vector3)
@export var gool_play_method: String = "play_event"
@export var gool_event_player_shot: String = "lt_player_shot"
@export var gool_event_enemy_shot: String = "lt_enemy_shot"
@export var gool_event_hit_confirm: String = "lt_hit_confirm"
@export var gool_event_blocked: String = "lt_blocked"
@export var gool_event_player_hurt: String = "lt_player_hurt"

var _gool: Node
var _streams: Dictionary = {}
var _local_player: AudioStreamPlayer

func _ready() -> void:
	add_to_group(LT_Const.GROUP_AUDIO)
	if DisplayServer.get_name() == "headless":
		enabled = false
		return

	if use_gool:
		_gool = get_tree().root.get_node_or_null(gool_autoload_name)
		if _gool != null and not _gool.has_method(gool_play_method):
			push_warning("LT_ShotAudio: %s found but has no %s() — using synth fallback" % [
				gool_autoload_name, gool_play_method])
			_gool = null

	# Synth fallback streams (also used when gool lacks a given event).
	_streams = {
		"player_shot": _synth_blip(1400.0, 500.0, 0.09),
		"enemy_shot": _synth_blip(900.0, 320.0, 0.11),
		"hit_confirm": _synth_blip(700.0, 1600.0, 0.08),
		"blocked": _synth_blip(220.0, 90.0, 0.07),
		"player_hurt": _synth_blip(400.0, 150.0, 0.16),
	}

	_local_player = AudioStreamPlayer.new()
	_local_player.name = "LocalShotAudio"
	_local_player.volume_db = volume_db
	add_child(_local_player)

func play_shot(shot: LT_ShotResult) -> void:
	if not enabled or shot.hit_type == "INVALID":
		return

	if shot.shooter_is_player:
		_play("player_shot", gool_event_player_shot, shot.start_position, true)
		match shot.hit_type:
			"ENEMY_HIT":
				_play("hit_confirm", gool_event_hit_confirm, shot.hit_position, true)
			"WORLD_BLOCKED":
				_play("blocked", gool_event_blocked, shot.hit_position, false)
	else:
		_play("enemy_shot", gool_event_enemy_shot, shot.start_position, false)
		if shot.hit_type == "PLAYER_HIT":
			_play("player_hurt", gool_event_player_hurt, shot.hit_position, true)

func _play(synth_key: String, gool_event: String, position: Vector3, local: bool) -> void:
	if _gool != null and _has_gool_sound(gool_event):
		# gool integration point — one line to adjust if the API differs.
		_gool.call(gool_play_method, gool_event, position)
		return

	var stream: AudioStream = _streams.get(synth_key)
	if stream == null:
		return
	if local:
		_local_player.stream = stream
		_local_player.play()
	else:
		var player_3d := AudioStreamPlayer3D.new()
		player_3d.stream = stream
		player_3d.volume_db = volume_db
		player_3d.max_distance = 60.0
		player_3d.top_level = true
		add_child(player_3d)
		player_3d.global_position = position
		player_3d.finished.connect(player_3d.queue_free)
		player_3d.play()

func _has_gool_sound(event_name: String) -> bool:
	if _gool.has_method("has_sound"):
		return _gool.has_sound(event_name)
	return true  # gool without has_sound(): trust the event names.

## Generates a short 16-bit mono PCM blip with a pitch sweep and fast
## decay — enough to feel like laser tag without shipping assets.
func _synth_blip(freq_start: float, freq_end: float, duration: float) -> AudioStreamWAV:
	const SAMPLE_RATE := 22050
	var frame_count := int(duration * SAMPLE_RATE)
	var data := PackedByteArray()
	data.resize(frame_count * 2)

	var phase := 0.0
	for i in frame_count:
		var t := float(i) / float(frame_count)
		var freq := lerpf(freq_start, freq_end, t)
		phase += TAU * freq / float(SAMPLE_RATE)
		var envelope := (1.0 - t) * (1.0 - t)
		var sample := sin(phase) * envelope * 0.6
		var value := int(clampf(sample, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, value)

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = data
	return wav
