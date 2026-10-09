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
	_check_catalog()
	var store := ProgressStore.new()
	store.path = "user://colony-test-%d.json" % OS.get_process_id()
	store.data.resources = {"stone": 10000, "wood": 10000, "essence": 10000}
	var model := SettlementModel.new()
	model.configure(store)
	check(model.stage_production() and store.data.colony_mode, "activate real hauling mode")
	check(model.build(0, 0).ok and model.build(1, 0).ok, "build two mines")
	var before: Dictionary = store.data.resources.duplicate()
	store.data.last_mine_time = int(Time.get_unix_time_from_system()) - 121
	var pending := int(store.data.colony_pending.stone)
	check(model.stage_production() and store.data.resources == before and store.data.colony_pending.stone == pending + 32, "production stays unbanked until arrival")
	var world := MineColony.new()
	root.add_child(world)
	world.configure(model)
	world.set_process(false)
	_check_camera(world)
	var children := world.get_child_count()
	check(world.workers.size() == ColonyMap.SLOT_COUNT and world.site_buttons.size() == ColonyMap.SLOT_COUNT and world.frames.size() == 40, "fixed 64-site pools and generated animation frames")
	check(world.navigation.region == Rect2i(0, 0, 30, 30), "navigation uses logical map cells rather than screen pixels")
	for slot in range(ColonyMap.SLOT_COUNT):
		check(world._grid(world.feet[slot]) == ColonyMap.slot_cell(slot), "site %d stays anchored to its isometric ground footprint" % slot)
	for actor in world.workers:
		if actor.kind >= 0:
			check(not actor.path.is_empty(), "mine has a traversable route")
			for point in actor.path:
				check(not world.navigation.is_point_solid(world._grid(point)), "workers route around building footprint")
	for frame in range(40):
		world._process(0.1)
	check(store.data.resources == before, "walking out does not credit warehouse")
	var actor: Dictionary = world.workers[0]
	var saved_actor: Dictionary = actor.duplicate()
	var stranded_position: Vector2 = actor.node.position
	actor.state = "returning"
	actor.amount = 3
	actor.path = PackedVector2Array([stranded_position])
	actor.path_index = 0
	world._process(0.01)
	check(actor.node.position.is_equal_approx(stranded_position) and actor.amount == 3 and store.data.resources == before, "a completed but misplaced path cannot teleport cargo into the warehouse")
	actor.clear()
	actor.merge(saved_actor)
	for frame in range(1800):
		world._process(0.1)
		if frame % 100 == 0:
			await process_frame
	check(world.transported > 0 and store.data.resources.stone > before.stone, "animated workers actually arrive with ore")
	check(store.data.resources.stone - before.stone <= pending + 32, "shared ore reservations cannot duplicate cargo")
	check(world.get_child_count() == children, "delivery reuses nodes")
	check(model.build(ColonyMap.SLOT_COUNT - 1, 0).ok and model.production_for_slot(ColonyMap.SLOT_COUNT - 1).stone == 8, "expanded remote site contributes to real production")
	var invalid_snapshot: Dictionary = store.data.duplicate(true)
	check(not model.build(ColonyMap.SLOT_COUNT, 0).ok and store.data == invalid_snapshot, "outside construction index cannot charge the warehouse")
	check(model.upgrade(0).ok and model.production_for_slot(0).stone == 16, "upgrade increases extraction")
	world.refresh(store.data, 0)
	check(world.workers[0].tier == 2, "upgrade accelerates the existing worker")
	var restored := ProgressStore.new()
	restored.path = store.path
	check(restored.load_progress() and restored.data.colony_pending == store.data.colony_pending, "unbanked ore survives restart including in-transit reservations")
	check(restored.data.buildings.size() == ColonyMap.SLOT_COUNT and restored.data.buildings[-1] == 0, "remote construction survives a full 64-site save round trip")
	store.data.resources = {"stone": 10000, "wood": 10000, "essence": 10000}
	for stage in range(3):
		var cost := model.bunker_cost()
		var balance: Dictionary = store.data.resources.duplicate()
		check(model.build_bunker().ok and store.data.bunker_level == stage + 1, "bunker stage %d" % stage)
		for resource in SettlementModel.RESOURCE_KEYS:
			check(store.data.resources[resource] == balance[resource] - cost[resource], "bunker consumes delivered %s" % resource)
	check(not model.build_bunker().ok, "finished bunker cannot charge again")
	var cap_snapshot: Dictionary = store.data.duplicate(true)
	store.data.resources.stone = ProgressStore.MAX_RESOURCE - 2
	store.data.colony_pending.stone = 10
	var capped := model.deliver_cargo("stone", 5)
	check(capped.ok and capped.amount == 2 and store.data.resources.stone == ProgressStore.MAX_RESOURCE and store.data.colony_pending.stone == 8, "warehouse capacity preserves every undelivered unit")
	store.data = cap_snapshot
	invalid_snapshot = store.data.duplicate(true)
	check(not model.deliver_cargo("unknown", 5).ok and not model.deliver_cargo("stone", 0).ok and not model.deliver_cargo("stone", -1).ok and store.data == invalid_snapshot, "invalid cargo cannot mutate either balance")
	var snapshot: Dictionary = store.data.duplicate(true)
	var blocked := store.path + ".blocked"
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(blocked + ".tmp"))
	store.path = blocked
	store.data.colony_pending.stone = 10
	snapshot = store.data.duplicate(true)
	check(not model.deliver_cargo("stone", 3).ok and store.data == snapshot, "failed delivery save rolls back both balances")
	store.data.bunker_level = 0
	snapshot = store.data.duplicate(true)
	check(not model.build_bunker().ok and store.data == snapshot, "failed bunker save rolls back cost and stage")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(blocked + ".tmp"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(restored.path))
	world.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS: %d colony checks (isometric camera, gestures, ground routes, hauling, reservations, upgrades, bunker, atomic saves)." % checks)
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
		quit(1)


func _check_catalog() -> void:
	var store := ProgressStore.new()
	store.path = "user://colony-catalog-%d.json" % OS.get_process_id()
	store.data.resources = {"stone": 1000000, "wood": 1000000, "essence": 1000000}
	store.data.expedition_mode = true
	var model := SettlementModel.new()
	model.configure(store)
	check(SettlementModel.BUILDING_DEFS.size() == 15, "city has fifteen concrete construction choices")
	var keys: Dictionary = {}
	for kind in range(SettlementModel.BUILDING_DEFS.size()):
		var definition: Dictionary = SettlementModel.BUILDING_DEFS[kind]
		check(not keys.has(definition.key) and not model.get_building_description(kind).is_empty(), "building %d has a distinct key and useful description" % kind)
		keys[definition.key] = true
		store.data.last_mine_time = int(Time.get_unix_time_from_system()) - 86400
		var balance: Dictionary = store.data.resources.duplicate()
		var pending: Dictionary = store.data.colony_pending.duplicate()
		var cost := model.get_build_cost(kind)
		check(model.build(kind, kind).ok and store.data.buildings[kind] == kind, "building %d is constructible" % kind)
		for resource in SettlementModel.RESOURCE_KEYS:
			check(store.data.resources[resource] == balance[resource] - cost[resource], "manual city build %d consumes only delivered %s" % [kind, resource])
		check(store.data.colony_pending == pending, "manual city build %d never creates free passive ore" % kind)
	check(model.expedition_capacity() == 1, "initial castle and town hall preserve one free expedition queue")
	for tier in range(3):
		check(model.upgrade(6).ok and model.expedition_capacity() == tier + 2, "town hall improvement unlocks queue %d" % (tier + 2))
	check(model.build(16, 6).ok, "duplicate town hall can occupy a separate plot")
	for tier in range(3):
		check(model.upgrade(16).ok, "duplicate town hall can be improved")
	check(model.expedition_capacity() == 4, "multiple town halls never stack more than four queues")
	for kind in [7, 9]:
		for tier in range(3):
			check(model.upgrade(kind).ok, "new city perk building %d supports improvement" % kind)
		var bonuses := model.battle_bonuses()
		var duplicate_slot: int = 17 if kind == 7 else 18
		check(model.build(duplicate_slot, kind).ok, "duplicate perk building %d is constructible" % kind)
		for tier in range(3):
			check(model.upgrade(duplicate_slot).ok, "duplicate perk building %d supports improvement" % kind)
		check(model.battle_bonuses() == bonuses, "only the strongest building %d contributes battle perks" % kind)
	var bonuses := model.battle_bonuses()
	check(bonuses.boss_damage_bonus > 0 and bonuses.boss_damage_bonus <= 2 and bonuses.reward_percent > 0 and bonuses.reward_percent <= ProgressStore.MAX_REWARD_PERCENT, "citadel damage and market rewards stay bounded")
	for kind in [8, 14]:
		for tier in range(3):
			check(model.upgrade(kind).ok, "alliance support building %d supports improvement" % kind)
	var expedition_bonuses := model.expedition_bonuses()
	check(expedition_bonuses.yield_percent > 0 and expedition_bonuses.yield_percent <= 12 and expedition_bonuses.party_damage_percent <= 20, "city support cannot inflate finite expedition yield without bound")
	store.data.last_mine_time = int(Time.get_unix_time_from_system()) - 86400
	var balance: Dictionary = store.data.resources.duplicate()
	var pending: Dictionary = store.data.colony_pending.duplicate()
	check(model.stage_production() and store.data.resources == balance and store.data.colony_pending == pending, "new field mode never accrues passive resources while time passes")
	store.data.last_mine_time = int(Time.get_unix_time_from_system()) - 86400
	var cost := model.bunker_cost()
	check(model.build_bunker().ok and store.data.colony_pending == pending, "bunker construction creates no passive ore in field mode")
	for resource in SettlementModel.RESOURCE_KEYS:
		check(store.data.resources[resource] == balance[resource] - cost[resource], "manual bunker consumes only its %s cost" % resource)
	check(model.build(63, 14).ok, "last map site can hold a newly added building type")
	var restored := ProgressStore.new()
	restored.path = store.path
	check(restored.load_progress() and restored.data.buildings.size() == 64 and restored.data.buildings[63] == 14, "all fifteen building types and the last construction site survive normalization")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(store.path))


func _check_camera(world: MineColony) -> void:
	world.focus_slot(4)
	var original_positions: Array[Vector2] = []
	for worker in world.workers:
		original_positions.append(worker.node.position)
	var anchor := world.size * 0.5
	var ground_at_anchor := world.view_to_world(anchor)
	world.set_zoom(0.95, anchor)
	check(world.view_to_world(anchor).is_equal_approx(ground_at_anchor), "zoom preserves the ground beneath the gesture anchor")
	var ground := ColonyMap.iso(Vector2i(7, 21))
	check(world.view_to_world(world.world_to_view(ground)).is_equal_approx(ground), "screen-to-world input remains consistent after zoom")
	world.set_zoom(999.0)
	check(is_equal_approx(world.camera_zoom, MineColony.MAX_ZOOM), "zoom has a readable upper bound")
	world.set_zoom(0.0001)
	check(is_equal_approx(world.camera_zoom, MineColony.MIN_ZOOM), "zoom cannot shrink the map into a point")
	for delta in [Vector2(100000, 100000), Vector2(-200000, -200000)]:
		world.pan_camera(delta)
		var bounds := world.map_bounds()
		for axis in range(2):
			var low := bounds.position[axis] * world.camera_zoom + world.camera_offset[axis]
			var high := bounds.end[axis] * world.camera_zoom + world.camera_offset[axis]
			if bounds.size[axis] * world.camera_zoom >= world.size[axis]:
				check(low <= 0.01 and high >= world.size[axis] - 0.01, "camera stays over ground at pan boundary on axis %d" % axis)
			else:
				check(is_equal_approx((low + high) * 0.5, world.size[axis] * 0.5), "small projected map remains centered on axis %d" % axis)
	world.set_zoom(0.65)
	world.focus_home()
	var selections: Array[int] = []
	world.selected.connect(func(slot: int): selections.append(slot))
	var offset_before := world.camera_offset
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = world.size * 0.5
	world._gui_input(press)
	var motion := InputEventMouseMotion.new()
	motion.position = press.position + Vector2(100, 50)
	motion.relative = Vector2(100, 50)
	world._gui_input(motion)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = motion.position
	world._gui_input(release)
	check(selections.is_empty() and not world.camera_offset.is_equal_approx(offset_before), "drag pans the town without selecting or building a plot")
	world.focus_home()
	for index in range(2):
		var touch := InputEventScreenTouch.new()
		touch.index = index
		touch.pressed = true
		touch.position = world.size * 0.5 + Vector2(-60 if index == 0 else 60, 0)
		world._gui_input(touch)
	var pinch := InputEventScreenDrag.new()
	pinch.index = 1
	pinch.position = world.size * 0.5 + Vector2(120, 0)
	world._gui_input(pinch)
	for index in range(2):
		var touch := InputEventScreenTouch.new()
		touch.index = index
		touch.position = world.size * 0.5 + Vector2(-60 if index == 0 else 120, 0)
		world._gui_input(touch)
	check(selections.is_empty() and world.camera_zoom > 0.65, "two-finger pinch zooms without triggering a construction tap")
	world.set_interaction_enabled(false)
	offset_before = world.camera_offset
	world._gui_input(press)
	world._gui_input(motion)
	world._gui_input(release)
	check(selections.is_empty() and world.camera_offset.is_equal_approx(offset_before), "modal panels disable map gestures and taps")
	world.set_interaction_enabled(true)
	world.set_zoom(0.65)
	world.focus_home()
	for index in range(world.workers.size()):
		check(world.workers[index].node.position.is_equal_approx(original_positions[index]), "camera movement never changes worker %d ground position" % index)
