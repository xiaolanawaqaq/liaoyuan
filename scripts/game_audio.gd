extends Node
## Original offline-synthesized audio. Instantiate with preload(...).new(),
## then add_child(); no autoload, class_name, custom bus, or input hooks needed.
## Public API: set_muted(bool), play_cue(String), set_fire_intensity(int).
## Calls before ready retain mute/fire state; early or unknown cues are ignored.

const CUES := {
	"select": preload("res://assets/audio/select.wav"),
	"dig": preload("res://assets/audio/dig.wav"),
	"axe": preload("res://assets/audio/axe.wav"),
	"water": preload("res://assets/audio/water.wav"),
	"turn": preload("res://assets/audio/turn.wav"),
	"wind": preload("res://assets/audio/wind.wav"),
	"win": preload("res://assets/audio/win.wav"),
	"lose": preload("res://assets/audio/lose.wav"),
	"undo": preload("res://assets/audio/undo.wav"),
}
const FOREST_LOOP: AudioStreamWAV = preload("res://assets/audio/forest_loop.wav")
const FIRE_LOOP: AudioStreamWAV = preload("res://assets/audio/fire_loop.wav")
const CUE_VOICES := 4
const CUE_VOLUME_DB := -10.0
const FOREST_VOLUME_DB := -27.0
const MAX_FIRE_INTENSITY := 24
const CUE_COOLDOWN_MS := {
	"select": 100, "dig": 120, "axe": 120, "water": 180,
	"turn": 220, "wind": 750, "win": 1150, "lose": 800, "undo": 180,
}

var _muted := false
var _fire_intensity := 0
var _background_ready := false
var _cue_players: Array[AudioStreamPlayer] = []
var _result_player: AudioStreamPlayer
var _forest_player: AudioStreamPlayer
var _fire_player: AudioStreamPlayer
var _last_cue_ms := {
	"select": -10000, "dig": -10000, "axe": -10000, "water": -10000,
	"turn": -10000, "wind": -10000, "win": -10000, "lose": -10000, "undo": -10000,
}


func _ready() -> void:
	# Exactly seven players for this node's lifetime: four normal cues,
	# one reserved outcome voice, and two very quiet looping beds.
	for i in range(CUE_VOICES):
		_cue_players.append(_make_player("Cue%d" % i, CUE_VOLUME_DB))
	_result_player = _make_player("Result", -9.0)
	_forest_player = _make_player("Forest", FOREST_VOLUME_DB)
	_forest_player.stream = _loop_copy(FOREST_LOOP)
	_fire_player = _make_player("Fire", -43.0)
	_fire_player.stream = _loop_copy(FIRE_LOOP)
	# Let the parent apply saved mute state before any background playback.
	_start_background.call_deferred()


func _exit_tree() -> void:
	_background_ready = false
	for player in get_children():
		if player is AudioStreamPlayer:
			player.stop()
			player.stream = null


func set_muted(muted: bool) -> void:
	if _muted == muted:
		return
	_muted = muted
	if muted:
		# Do not resume stale action sounds when the user unmutes.
		for player in _cue_players:
			player.stop()
		if is_instance_valid(_result_player):
			_result_player.stop()
	_sync_background()


func play_cue(cue_name: String) -> void:
	if _muted or _cue_players.is_empty() or not is_inside_tree() or not CUES.has(cue_name):
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_cue_ms[cue_name]) < int(CUE_COOLDOWN_MS[cue_name]):
		return
	var voice: AudioStreamPlayer = null
	if cue_name == "win" or cue_name == "lose":
		# UI/action spam cannot occupy the reserved melodic result voice.
		if _result_player.playing:
			return
		voice = _result_player
		voice.volume_db = -9.0 if cue_name == "win" else -12.0
	else:
		for player in _cue_players:
			if not player.playing:
				voice = player
				break
		# Drop excess requests instead of allocating players or cutting tails.
		if voice == null:
			return
		voice.volume_db = CUE_VOLUME_DB
		if cue_name == "select":
			voice.volume_db -= 2.0
		elif cue_name == "wind":
			voice.volume_db -= 3.0
	_last_cue_ms[cue_name] = now
	voice.stream = CUES[cue_name]
	voice.play()


func set_fire_intensity(n: int) -> void:
	# Pass the number of burning cells, or zero for an empty/menu/finished board.
	# Safe to call repeatedly: unchanged values do nothing. Never triggers cues,
	# crackles, timers, or per-frame synth work; only adjusts a persistent loop.
	var intensity := clampi(n, 0, MAX_FIRE_INTENSITY)
	if intensity == _fire_intensity:
		return
	_fire_intensity = intensity
	_sync_fire()


func _make_player(player_name: String, gain_db: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.bus = &"Master"
	player.max_polyphony = 1
	player.volume_db = gain_db
	add_child(player)
	return player


func _loop_copy(source: AudioStreamWAV) -> AudioStreamWAV:
	# Keep shared/preloaded resources immutable; no special import flags needed.
	var stream := source.duplicate() as AudioStreamWAV
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = roundi(stream.get_length() * float(stream.mix_rate))
	return stream


func _start_background() -> void:
	if not is_inside_tree():
		return
	_background_ready = true
	_sync_background()


func _sync_background() -> void:
	if not _background_ready:
		return
	# Pause only our own beds; never mute or change any AudioServer bus.
	_forest_player.stream_paused = _muted
	_fire_player.stream_paused = _muted
	if _muted:
		return
	if not _forest_player.playing:
		_forest_player.play()
	_sync_fire()


func _sync_fire() -> void:
	if not _background_ready:
		return
	if _fire_intensity == 0:
		_fire_player.stop()
		return
	var weight := float(_fire_intensity - 1) / float(MAX_FIRE_INTENSITY - 1)
	_fire_player.volume_db = lerpf(-43.0, -32.0, weight)
	if _muted:
		return
	_fire_player.stream_paused = false
	if not _fire_player.playing:
		_fire_player.play()
