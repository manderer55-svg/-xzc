class_name AudioDirector
extends Node
## Warm, bounded audio mix: fixed voices, one hit per batch, no cascade node churn.
const KEYS := ["tap", "match", "cascade", "lightning", "explosion", "victory"]
const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"
const POOL_SIZE := 8
const MAX_ACTIVE := 3
const MAX_HEAVY := 2
const VOICE_ATTACK := 0.012
const VOICE_RELEASE := 0.045
const MUSIC_GAIN_DB := 0.0
const PROFILES := {
	"tap": {"gain": -2.0, "cooldown": 0.07, "priority": 0},
	"match": {"gain": -2.0, "cooldown": 0.16, "priority": 1},
	"cascade": {"gain": -3.0, "cooldown": 0.30, "priority": 1},
	"lightning": {"gain": -4.0, "cooldown": 0.22, "priority": 2},
	"explosion": {"gain": -4.0, "cooldown": 0.22, "priority": 2},
	"victory": {"gain": -1.0, "cooldown": 2.00, "priority": 3},
}
var voices: Array[AudioStreamPlayer] = []
var streams: Dictionary = {}
var music: AudioStreamPlayer
var enabled := true
var paused := false
var next_voice := 0
var variants: Dictionary = {}
var _variant_cursor: Dictionary = {}
var _last_hit: Dictionary = {}
var _voice_state: Array[Dictionary] = []
var _pending_keys: Array[String] = []
var _clock := 0.0
var _duck_until := 0.0
var _duck_depth := 0.0
var _music_duck := 0.0
var _music_envelope := 0.0
var _resume_position := 0.0
var _mute_remaining := 0.0
var _mute_start_envelope := 0.0


func _ready() -> void:
	_configure_buses()
	for key: String in KEYS:
		var base := load("res://audio/" + key + ".wav") as AudioStream
		if base == null:
			continue
		streams[key] = base
		var choices: Array[AudioStream] = [base]
		for variant in range(2, 5):
			var path := "res://audio/%s_%d.wav" % [key, variant]
			if ResourceLoader.exists(path):
				var stream := load(path) as AudioStream
				if stream != null:
					choices.append(stream)
		variants[key] = choices
		_variant_cursor[key] = 0
	for index in range(POOL_SIZE):
		var voice := AudioStreamPlayer.new()
		voice.bus = SFX_BUS
		voice.volume_db = -80.0
		add_child(voice)
		voices.append(voice)
		_voice_state.append({})
	music = AudioStreamPlayer.new()
	var music_path := "res://audio/ambient.ogg" if ResourceLoader.exists("res://audio/ambient.ogg") else "res://audio/ambient.wav"
	music.stream = load(music_path) as AudioStream
	if music.stream is AudioStreamOggVorbis:
		(music.stream as AudioStreamOggVorbis).loop = true
	music.bus = MUSIC_BUS
	music.volume_db = -80.0
	add_child(music)
	music.finished.connect(_on_music_finished)
	set_enabled(enabled)


func _configure_buses() -> void:
	for bus_name: String in [MUSIC_BUS, SFX_BUS]:
		var index := AudioServer.get_bus_index(bus_name)
		if index < 0:
			AudioServer.add_bus()
			index = AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus_name)
			AudioServer.set_bus_send(index, "Master")
			AudioServer.set_bus_volume_db(index, -2.0)
	# Last-resort protection for unusual combos; normal assets leave ample headroom.
	var master := AudioServer.get_bus_index("Master")
	for index in range(AudioServer.get_bus_effect_count(master)):
		if AudioServer.get_bus_effect(master, index) is AudioEffectHardLimiter:
			return
	var limiter := AudioEffectHardLimiter.new()
	limiter.resource_name = "Ashen mix safety ceiling"
	limiter.ceiling_db = -1.5
	limiter.pre_gain_db = 0.0
	limiter.release = 0.12
	AudioServer.add_bus_effect(master, limiter)


func set_enabled(value: bool) -> void:
	enabled = value
	_sync_playback()


func set_paused(value: bool) -> void:
	paused = value
	_sync_playback()


func _sync_playback() -> void:
	if not is_instance_valid(music):
		return
	if enabled and not paused:
		_mute_remaining = 0.0
		if music.stream_paused or not music.playing:
			_music_envelope = 0.0
			music.volume_db = -80.0
			if music.playing:
				music.stream_paused = false
			elif music.stream != null:
				music.stream_paused = false
				music.play(_resume_position)
		return
	_pending_keys.clear()
	_duck_until = _clock
	_duck_depth = 0.0
	if music.playing:
		_resume_position = maxf(0.0, music.get_playback_position())
	if paused or music.stream_paused:
		# OS suspension can stop processing immediately: freeze the decoder itself.
		music.stream_paused = true
		_mute_remaining = 0.0
		for index in range(voices.size()):
			voices[index].stop()
			_voice_state[index] = {}
	else:
		# A foreground sound toggle has time for a short, non-clicking fade.
		_mute_remaining = VOICE_RELEASE
		_mute_start_envelope = _music_envelope
		for state: Dictionary in _voice_state:
			if not state.is_empty():
				state.release_left = VOICE_RELEASE


func _on_music_finished() -> void:
	_resume_position = 0.0
	if enabled and not paused:
		music.play()


func play(key: String) -> void:
	if not enabled or paused or not streams.has(key) or voices.is_empty():
		return
	var profile: Dictionary = PROFILES[key]
	if _clock - float(_last_hit.get(key, -100.0)) < float(profile.cooldown):
		return
	_last_hit[key] = _clock
	var priority := int(profile.priority)
	var count := 0
	var heavy := 0
	var highest := -1
	var candidate := -1
	var candidate_priority := 99
	for index in range(voices.size()):
		if not voices[index].playing or _voice_state[index].is_empty():
			continue
		count += 1
		var existing := int(_voice_state[index].priority)
		heavy += int(existing >= 2 and not _voice_state[index].has("release_left"))
		highest = maxi(highest, existing)
		if existing < candidate_priority and not _voice_state[index].has("release_left"):
			candidate = index
			candidate_priority = existing
	# Button tapping and matching cannot compete with a special or victory tail.
	if (priority == 0 and highest >= 2) or (priority < 3 and highest == 3):
		return
	for pending: String in _pending_keys:
		heavy += int(int(PROFILES[pending].priority) >= 2)
	if priority == 2 and heavy >= MAX_HEAVY:
		# A new cascade still sounds: replace a mature special tail after its attack.
		var oldest := -1
		var oldest_age := 0.35
		for index in range(voices.size()):
			var state: Dictionary = _voice_state[index]
			if voices[index].playing and not state.is_empty() and int(state.priority) == 2 and not state.has("release_left") and float(state.age) > oldest_age:
				oldest = index
				oldest_age = float(state.age)
		if oldest < 0 or _pending_keys.size() >= MAX_HEAVY:
			return
		_voice_state[oldest].release_left = VOICE_RELEASE
		_pending_keys.append(key)
		return
	if priority == 3:
		_pending_keys.clear()
	if count >= MAX_ACTIVE:
		if (candidate >= 0 and priority <= candidate_priority) or (candidate < 0 and priority <= highest):
			return
		if _pending_keys.size() >= MAX_HEAVY:
			return
		# Retire the weakest tail smoothly; pending hits use freed slots 45 ms later.
		_pending_keys.append(key)
		if candidate >= 0:
			_voice_state[candidate].release_left = VOICE_RELEASE
		return
	_start_voice(key)


func _start_voice(key: String) -> void:
	var slot := -1
	for offset in range(voices.size()):
		var index := (next_voice + offset) % voices.size()
		if not voices[index].playing:
			slot = index
			break
	if slot < 0:
		return
	next_voice = (slot + 1) % voices.size()
	var choices: Array = variants[key]
	var cursor := int(_variant_cursor[key])
	var stream := choices[cursor % choices.size()] as AudioStream
	_variant_cursor[key] = cursor + 1
	var profile: Dictionary = PROFILES[key]
	var priority := int(profile.priority)
	# Special hits lower existing ordinary tails instead of piling up loud attacks.
	if priority >= 2:
		for index in range(voices.size()):
			if not _voice_state[index].is_empty() and int(_voice_state[index].priority) < priority:
				_voice_state[index].duck_target = -8.0
		_duck_depth = maxf(_duck_depth, 7.0 if priority == 3 else 5.0)
		_duck_until = maxf(_duck_until, _clock + (2.0 if priority == 3 else 0.9))
	if priority == 3:
		for index in range(voices.size()):
			if voices[index].playing and not _voice_state[index].is_empty():
				_voice_state[index].release_left = VOICE_RELEASE
	var voice := voices[slot]
	voice.stream = stream
	voice.volume_db = -80.0
	_voice_state[slot] = {"key": key, "priority": priority, "gain": float(profile.gain), "age": 0.0, "duck": 0.0, "duck_target": 0.0, "length": stream.get_length()}
	voice.play()


func _process(delta: float) -> void:
	if paused or not enabled and _mute_remaining <= 0.0:
		return
	_clock += delta
	for index in range(voices.size()):
		var state: Dictionary = _voice_state[index]
		var voice := voices[index]
		if state.is_empty():
			continue
		state.age = float(state.age) + delta
		if not voice.playing or float(state.age) > float(state.length) + 0.08:
			voice.stop()
			_voice_state[index] = {}
			continue
		var envelope := minf(1.0, float(state.age) / VOICE_ATTACK)
		if state.has("release_left"):
			state.release_left = float(state.release_left) - delta
			if float(state.release_left) <= 0.0:
				voice.stop()
				_voice_state[index] = {}
				continue
			envelope *= float(state.release_left) / VOICE_RELEASE
		state.duck = move_toward(float(state.duck), float(state.duck_target), delta * 80.0)
		voice.volume_db = float(state.gain) + float(state.duck) + linear_to_db(maxf(0.0001, envelope))
	if enabled and not _pending_keys.is_empty():
		var active := 0
		for voice in voices:
			active += int(voice.playing)
		while active < MAX_ACTIVE and not _pending_keys.is_empty():
			var key: String = _pending_keys.pop_front()
			_start_voice(key)
			active += 1
	if not enabled:
		_mute_remaining = maxf(0.0, _mute_remaining - delta)
		_music_envelope = _mute_start_envelope * _mute_remaining / VOICE_RELEASE
		music.volume_db = MUSIC_GAIN_DB + _music_duck + linear_to_db(maxf(0.0001, _music_envelope))
		if _mute_remaining <= 0.0:
			_resume_position = maxf(0.0, music.get_playback_position())
			music.stream_paused = true
		return
	var target_duck := -_duck_depth if _clock < _duck_until else 0.0
	_music_duck = move_toward(_music_duck, target_duck, delta * (55.0 if target_duck < _music_duck else 7.0))
	if target_duck == 0.0 and _music_duck == 0.0:
		_duck_depth = 0.0
	if is_instance_valid(music) and music.playing:
		_music_envelope = minf(1.0, _music_envelope + delta / 0.8)
		music.volume_db = MUSIC_GAIN_DB + _music_duck + linear_to_db(maxf(0.0001, _music_envelope))


func _exit_tree() -> void:
	_pending_keys.clear()
	if is_instance_valid(music):
		# A paused decoder still belongs to the audio thread: resume before stopping.
		music.stream_paused = false
		music.stop()
		music.stream = null
	for voice in voices:
		voice.stop()
		voice.stream = null
	streams.clear()
	variants.clear()
