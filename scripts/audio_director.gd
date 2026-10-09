class_name AudioDirector
extends Node
## Fixed voice pool; original WAV streams, no new audio nodes during cascades.
const KEYS := ["tap", "match", "cascade", "lightning", "explosion", "victory"]
var voices: Array[AudioStreamPlayer] = []
var streams: Dictionary = {}
var music: AudioStreamPlayer
var enabled := true
var paused := false
var next_voice := 0

func _ready() -> void:
	for key in KEYS:
		streams[key] = load("res://audio/" + key + ".wav")
	for index in range(8):
		var voice := AudioStreamPlayer.new()
		voice.volume_db = -10.0
		add_child(voice)
		voices.append(voice)
	music = AudioStreamPlayer.new()
	music.stream = load("res://audio/ambient.wav")
	music.volume_db = -19.0
	add_child(music)
	music.finished.connect(func(): if enabled and not paused: music.play())
	set_enabled(enabled)

func set_enabled(value: bool) -> void:
	enabled = value
	if not is_instance_valid(music):
		return
	if enabled and not paused:
		if not music.playing:
			music.play()
	else:
		music.stop()
		for voice in voices:
			voice.stop()

func play(key: String) -> void:
	if not enabled or paused or not streams.has(key) or voices.is_empty():
		return
	var voice := voices[next_voice]
	next_voice = (next_voice + 1) % voices.size()
	voice.stream = streams[key]
	voice.play()

func set_paused(value: bool) -> void:
	paused = value
	set_enabled(enabled)

func _exit_tree() -> void:
	set_enabled(false)
