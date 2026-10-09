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
	var children := world.get_child_count()
	check(world.workers.size() == 9 and world.frames.size() == 40, "fixed workers and generated animation frames")
	for actor in world.workers:
		if actor.kind >= 0:
			check(not actor.path.is_empty(), "mine has a traversable route")
			for point in actor.path:
				check(not world.navigation.is_point_solid(world._grid(point)), "workers route around building footprint")
	for frame in range(40):
		world._process(0.1)
	check(store.data.resources == before, "walking out does not credit warehouse")
	for frame in range(900):
		world._process(0.1)
		if frame % 100 == 0:
			await process_frame
	check(world.transported > 0 and store.data.resources.stone > before.stone, "animated workers actually arrive with ore")
	check(store.data.resources.stone - before.stone <= pending + 32, "shared ore reservations cannot duplicate cargo")
	check(world.get_child_count() == children, "delivery reuses nodes")
	check(model.upgrade(0).ok and model.production_for_slot(0).stone == 16, "upgrade increases extraction")
	world.refresh(store.data, 0)
	check(world.workers[0].tier == 2, "upgrade accelerates the existing worker")
	var restored := ProgressStore.new()
	restored.path = store.path
	check(restored.load_progress() and restored.data.colony_pending == store.data.colony_pending, "unbanked ore survives restart including in-transit reservations")
	store.data.resources = {"stone": 10000, "wood": 10000, "essence": 10000}
	for stage in range(3):
		var cost := model.bunker_cost()
		var balance: Dictionary = store.data.resources.duplicate()
		check(model.build_bunker().ok and store.data.bunker_level == stage + 1, "bunker stage %d" % stage)
		for resource in SettlementModel.RESOURCE_KEYS:
			check(store.data.resources[resource] == balance[resource] - cost[resource], "bunker consumes delivered %s" % resource)
	check(not model.build_bunker().ok, "finished bunker cannot charge again")
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
		print("PASS: %d colony checks (ground routes, hauling, reservations, upgrades, bunker, atomic saves)." % checks)
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
		quit(1)
