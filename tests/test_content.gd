extends SceneTree
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures.append(description)

func _run() -> void:
	var regions := {}
	var relic_levels := 0
	for level in range(1, 1001):
		var recipe := LevelGenerator.generate(level)
		regions[recipe.region_index] = true
		check(recipe.region == LevelGenerator.REGIONS[recipe.region_index], "consistent regional recipe %d" % level)
		if recipe.objective.kind != "relic":
			continue
		relic_levels += 1
		var engine := MatchEngine.new()
		engine.initialize(level)
		check(recipe.relics.size() == recipe.objective.target and recipe.relics.size() > 0, "relic target %d" % level)
		for index in range(recipe.relics.size()):
			var start: Vector2i = recipe.relics[index]
			var finish: Vector2i = recipe.relic_exits[index]
			check(start.x == finish.x and finish.y - start.y >= 3, "actual gravity lane %d" % level)
			for y in range(start.y, finish.y + 1):
				check(Vector2i(start.x, y) in recipe.mask and not recipe.blockers.has(Vector2i(start.x, y)), "unblocked connected exit lane %d" % level)
			for move in engine.legal_moves():
				check(start not in move, "relic cannot be swapped as a gem %d" % level)
		var before := engine.snapshot()
		engine.shuffle()
		for start: Vector2i in recipe.relics:
			check(bool(engine.cells[start].get("relic", false)), "shuffle preserves relic %d" % level)
		check(not engine.find_matches().size() and not engine.legal_moves().is_empty(), "relic shuffle remains settled and playable %d" % level)
		var copy := engine.clone_model() as MatchEngine
		check(copy.snapshot() == engine.snapshot() and copy.relics_delivered == 0, "relic clone %d" % level)
	check(regions.size() == 3 and relic_levels == 100, "all three regions and 100 relic missions exercised")
	var model := MatchEngine.new()
	model.initialize(5)
	var start: Vector2i = model.level_data.relics[0]
	var charge := start + Vector2i.DOWN
	model.cells[charge].special = "column"
	var step := model._resolve([], [charge], {}, 1, [])
	check(model.relics_delivered == 1 and model.is_won() and step.objective.complete, "lightning clears below relic and gravity delivers it")
	for entry in step.removed_details:
		check(entry.position != start, "lightning does not destroy or count the relic as a gem")
	var progress := ProgressStore.new()
	progress.path = "user://content-private-test.json"
	progress.data.resources = {"stone": 100000, "wood": 100000, "essence": 100000}
	var city := SettlementModel.new()
	city.configure(progress)
	check(_complete_build(city, 0, 4).ok and _complete_build(city, 1, 5).ok, "forge and tower can be built")
	check(city.battle_bonuses().forge_bomb == 1 and city.battle_bonuses().seal_damage_bonus == 1, "new buildings have useful battle effects")
	model.initialize(30, city.battle_bonuses())
	var bombs := 0
	for tile in model.cells.values():
		bombs += int(tile.special == "bomb")
	check(bombs == 1, "forge seeds exactly one bomb")
	var seal := Vector2i(1, 2)
	model.blockers[seal] = 2
	model.cells[Vector2i(1, 1)].special = "column"
	model._resolve([], [Vector2i(1, 1)], {}, 1, [])
	check(not model.blockers.has(seal), "tower breaks a two-HP seal in one hit")
	check(progress.update_setting("sound", false), "sound setting saves")
	var restored := ProgressStore.new()
	restored.path = progress.path
	check(restored.load_progress() and restored.data.buildings[0] == 4 and restored.data.buildings[1] == 5 and not restored.data.settings.sound, "new buildings and audio preference survive reload")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(progress.path))
	var pool := EffectPool.new()
	root.add_child(pool)
	pool.configure(false)
	for color in range(6):
		check(pool.play("fx_shards_%d" % color, Vector2.ZERO, Vector2(90, 40)), "generated shards available for color %d" % color)
	pool._process(0.26)
	check(pool.stats().active == 0 and pool.stats().created == 24, "calm shard bursts retire without growing pool")
	pool.queue_free()
	var audio := AudioDirector.new()
	root.add_child(audio)
	await create_timer(0.05).timeout
	check(audio.voices.size() == 8 and audio.music.stream != null, "audio initialized with fixed voices and music")
	audio.set_enabled(false)
	await create_timer(0.05).timeout
	audio.play("explosion")
	check(audio.music.stream_paused or not audio.music.playing, "mute silences music and suppresses effects")
	audio.set_enabled(true)
	await create_timer(0.05).timeout
	audio.set_paused(true)
	await create_timer(0.05).timeout
	check(audio.music.stream_paused, "app pause freezes music playback")
	audio.set_paused(false)
	await create_timer(0.05).timeout
	check(audio.music.playing and not audio.music.stream_paused and audio.voices.size() == 8, "resume reuses voices and preserves music playback")
	audio.set_enabled(false)
	await create_timer(0.08).timeout
	audio.queue_free()
	await create_timer(0.15).timeout
	if failures.is_empty():
		print("PASS: %d content checks (relic lanes/delivery, 3 regions, forge/tower, audio lifecycle, colored VFX)." % checks)
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
		quit(1)


func _complete_build(model: SettlementModel, slot: int, kind: int) -> Dictionary:
	var result := model.build(slot, kind)
	if result.ok:
		model.sync_construction(int(model.construction_job().ends_at))
	return result


func _complete_upgrade(model: SettlementModel, slot: int) -> Dictionary:
	var result := model.upgrade(slot)
	if result.ok:
		model.sync_construction(int(model.construction_job().ends_at))
	return result


func _complete_build_bunker(model: SettlementModel) -> Dictionary:
	var result := model.build_bunker()
	if result.ok:
		model.sync_construction(int(model.construction_job().ends_at))
	return result
