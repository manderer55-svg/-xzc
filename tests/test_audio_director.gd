extends SceneTree
## Exercise the actual fixed-player mixer: batching, priority, lifecycle, and safety.
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures.append(description)


func _active(audio: AudioDirector) -> int:
	var count := 0
	for voice in audio.voices:
		count += int(voice.playing)
	return count


func _active_keys(audio: AudioDirector) -> Array[String]:
	var keys: Array[String] = []
	for index in range(audio.voices.size()):
		if audio.voices[index].playing and not audio._voice_state[index].is_empty():
			keys.append(String(audio._voice_state[index].key))
	return keys


func _run() -> void:
	var audio := AudioDirector.new()
	root.add_child(audio)
	await create_timer(0.08).timeout
	if "--preview" in OS.get_cmdline_user_args():
		var captured := await _capture_audition(audio)
		# Finish the foreground fade before retiring the streaming decoder.
		audio.set_enabled(false)
		await create_timer(0.08).timeout
		audio.queue_free()
		await create_timer(0.12).timeout
		quit(0 if captured else 1)
		return
	check(audio.voices.size() == 8 and audio.get_child_count() == 9, "one music player and eight reusable effect players")
	check(audio.streams.size() == 6 and audio.variants.size() == 6, "all canonical audio events have cached streams")
	check(audio.music.bus == "Music", "music has an independent bus")
	for voice in audio.voices:
		check(voice.bus == "SFX", "every pooled effect routes to SFX")
	check(AudioServer.get_bus_index("Music") >= 0 and AudioServer.get_bus_index("SFX") >= 0, "both mix buses exist")
	var bus_count := AudioServer.bus_count
	var master := AudioServer.get_bus_index("Master")
	var effect_count := AudioServer.get_bus_effect_count(master)
	var protected := false
	for index in range(effect_count):
		var effect := AudioServer.get_bus_effect(master, index)
		if effect is AudioEffectHardLimiter:
			protected = effect.ceiling_db <= -1.0 and effect.pre_gain_db == 0.0
	check(protected, "master has a below-zero safety ceiling without gain boost")
	check(audio.music.playing and audio.music.volume_db < -1.0, "music enters through a gentle fade")
	await create_timer(0.28).timeout
	var position := audio.music.get_playback_position()
	check(position > 0.2, "music playhead advances before app suspension")
	audio.set_paused(true)
	check(audio.music.stream_paused and audio.enabled, "background pause freezes the decoder without changing preference")
	check(absf(audio._resume_position - position) < 0.04, "pause captures the actual musical position")
	audio.play("explosion")
	check(_active(audio) == 0 and audio._pending_keys.is_empty(), "backgrounded game cannot enqueue or play explosions")
	await create_timer(0.12).timeout
	audio.set_paused(false)
	await create_timer(0.08).timeout
	check(audio.music.playing and audio.music.get_playback_position() >= position - 0.02, "foreground resumes the melody instead of its beginning")
	audio.set_enabled(false)
	var mute_position := audio._resume_position
	audio.set_paused(true)
	audio.set_paused(false)
	check(audio.music.stream_paused and not audio.enabled, "app resume respects an explicitly muted preference")
	audio.play("victory")
	check(_active(audio) == 0, "mute suppresses effects as well as music")
	audio.set_enabled(true)
	await create_timer(0.08).timeout
	check(audio.music.get_playback_position() >= mute_position - 0.02, "unmute also retains the musical position")
	audio._process(1.0)
	var first_voice := audio.next_voice
	for request in range(100):
		audio.play("match")
	check(_active(audio) == 1 and audio.next_voice == (first_voice + 1) % 8, "100 same-batch matches produce one hit")
	var first_match := audio.voices[first_voice].stream
	audio._process(2.0)
	audio.play("match")
	if audio.variants.match.size() > 1:
		check(audio.voices[(first_voice + 1) % 8].stream != first_match, "successive matches rotate real recorded variants")
	check(_active(audio) == 1, "later valid match survives the cooldown")
	audio._process(2.0)
	for key in ["tap", "match", "cascade", "lightning", "explosion"]:
		audio.play(key)
	check(_active(audio) <= 3 and audio._pending_keys.size() <= 2, "mixed event burst respects audible and pending budgets")
	audio._process(0.06)
	var keys := _active_keys(audio)
	check(_active(audio) <= 3 and "lightning" in keys and "explosion" in keys, "distinct specials replace low-priority tails smoothly")
	var cursor := audio.next_voice
	for request in range(100):
		audio.play("explosion")
		audio.play("lightning")
		audio.play("tap")
	check(audio.next_voice == cursor and _active(audio) <= 3, "special storm and button spam cannot multiply simultaneous attacks")
	audio._process(0.10)
	check(audio._music_duck <= -4.5, "heavy effects make short room in the music mix")
	var lower_ducked := true
	for state: Dictionary in audio._voice_state:
		if not state.is_empty() and int(state.priority) < 2:
			lower_ducked = lower_ducked and float(state.duck) <= -8.0
	check(lower_ducked, "special hits attenuate ordinary tails instead of piling up full gain")
	audio._process(0.65)
	var before_retrigger := audio.next_voice
	audio.play("lightning")
	audio._process(0.06)
	check(audio.next_voice != before_retrigger and _active(audio) <= 3, "a later cascade can replace a mature special tail instead of losing its hit")
	audio.play("victory")
	audio._process(0.06)
	audio._process(0.06)
	keys = _active_keys(audio)
	check(keys == ["victory"], "victory clears busy combo tails with a short release")
	audio.play("match")
	audio.play("lightning")
	check(_active_keys(audio) == ["victory"], "new low-priority hits do not collide with the victory cue")
	audio._process(4.0)
	check(_active(audio) == 0 and audio._pending_keys.is_empty(), "finished and retired voices return to the pool")
	check(audio._music_duck == 0.0 and is_equal_approx(audio.music.volume_db, AudioDirector.MUSIC_GAIN_DB), "music recovers naturally after effects")
	var child_count := audio.get_child_count()
	for request in range(200):
		audio.play("unknown_key")
	check(audio.get_child_count() == child_count and audio.voices.size() == 8, "invalid requests and cascades do not allocate audio nodes")
	audio.set_enabled(false)
	var second := AudioDirector.new()
	second.enabled = false
	root.add_child(second)
	await process_frame
	check(AudioServer.bus_count == bus_count and AudioServer.get_bus_effect_count(master) == effect_count, "reinitializing a director does not duplicate buses or limiters")
	second.queue_free()
	audio.queue_free()
	await create_timer(0.12).timeout
	if failures.is_empty():
		print("PASS: %d audio checks (bounded mixes, recorded variants, ducking, pooled players, mute and preserved music position)." % checks)
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
		quit(1)


func _capture_audition(audio: AudioDirector) -> bool:
	var master := AudioServer.get_bus_index("Master")
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 0.5
	var capture_index := AudioServer.get_bus_effect_count(master)
	AudioServer.add_bus_effect(master, capture)
	var events := [
		{"time": 0.7, "keys": ["tap"]},
		{"time": 1.3, "keys": ["match"]},
		{"time": 2.2, "keys": ["cascade"]},
		{"time": 3.0, "keys": ["lightning", "explosion", "lightning", "explosion", "lightning", "explosion", "lightning", "explosion"]},
		{"time": 3.8, "keys": ["cascade", "explosion", "lightning"]},
		{"time": 5.1, "keys": ["match"]},
		{"time": 6.0, "keys": ["victory"]},
	]
	var frames := PackedVector2Array()
	var event_index := 0
	var start := Time.get_ticks_usec()
	while float(Time.get_ticks_usec() - start) / 1000000.0 < 10.5:
		await process_frame
		var elapsed := float(Time.get_ticks_usec() - start) / 1000000.0
		while event_index < events.size() and elapsed >= float(events[event_index].time):
			for key: String in events[event_index].keys:
				audio.play(key)
			event_index += 1
		var available := capture.get_frames_available()
		if available > 0:
			frames.append_array(capture.get_buffer(available))
	var available := capture.get_frames_available()
	if available > 0:
		frames.append_array(capture.get_buffer(available))
	var discarded := capture.get_discarded_frames()
	AudioServer.remove_bus_effect(master, capture_index)
	var pcm := StreamPeerBuffer.new()
	var peak := 0.0
	for frame in frames:
		peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
		pcm.put_16(roundi(clampf(frame.x, -1.0, 1.0) * 32767.0))
		pcm.put_16(roundi(clampf(frame.y, -1.0, 1.0) * 32767.0))
	if peak <= 0.00001 or frames.is_empty():
		printerr("FAIL: Dummy backend produced no auditable mixer PCM; no preview claim.")
		return false
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = roundi(AudioServer.get_mix_rate())
	wav.stereo = true
	wav.data = pcm.data_array
	var result := wav.save_to_wav("/tmp/ashen-audio-mix.wav")
	var metrics := {"method": "Godot AudioEffectCapture on Master after the actual mix safety limiter", "mix_rate": wav.mix_rate, "frames": frames.size(), "duration": float(frames.size()) / wav.mix_rate, "peak_dbfs": linear_to_db(peak), "discarded_frames": discarded, "events": events}
	var output := FileAccess.open("/tmp/ashen-audio-mix.json", FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify(metrics, "\t"))
	if result != OK or discarded != 0:
		printerr("FAIL: Mixer preview capture returned %d and discarded %d frames" % [result, discarded])
		return false
	print("AUDIO_PREVIEW_OK: /tmp/ashen-audio-mix.wav %.2fs actual Master PCM, peak %.2fdBFS, dropped frames %d" % [metrics.duration, metrics.peak_dbfs, discarded])
	return true
