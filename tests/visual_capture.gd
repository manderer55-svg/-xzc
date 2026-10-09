extends SceneTree
## Isolated native renderer fixture. Does not alter the game's user save.
var store: ProgressStore
var model: SettlementModel
var expeditions: ExpeditionModel
var world: MineColony
var captures := 0
var canonical_dispatches := 0
var position_checks := 0
var failures: Array[String] = []
func _initialize() -> void:
	call_deferred("run")
func capture(tag: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://art/preview/audit/%s.png" % tag)
	captures += 1
func run() -> void:
	root.content_scale_size = Vector2i(720, 720)
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	root.size = Vector2i(720, 720)
	store = ProgressStore.new()
	store.path = "user://visual-audit-%d.json" % OS.get_process_id()
	store.data.resources = {"stone": 1000000, "wood": 1000000, "essence": 1000000}
	model = SettlementModel.new()
	model.configure(store)
	var heroes := HeroModel.new(store)
	expeditions = ExpeditionModel.new()
	expeditions.configure(model, heroes)
	world = MineColony.new()
	world.size = Vector2(720, 720)
	root.add_child(world)
	world.configure(model, expeditions)
	world.set_process(false)
	world.set_mode("region")
	world.camera_zoom = 1.2
	var result := expeditions.dispatch(int(expeditions.deposits()[0].id))
	if not bool(result.ok):
		push_error(str(result))
		quit(1)
		return
	var job: Dictionary = expeditions.jobs()[0]
	var original_job := job.duplicate(true)
	for deposit: Dictionary in expeditions.deposits():
		var route: Array = expeditions._route(ExpeditionModel.FIELD_GATE_ACCESS, expeditions._deposit_access(deposit))
		if route.is_empty():
			failures.append("unreachable fixture deposit")
			continue
		job.path = route
		job.phase = "outbound"
		for index in range(route.size()):
			job.path_index = index
			var raw: Array = route[index]
			var leader := ColonyMap.iso(Vector2i(int(raw[0]), int(raw[1])))
			for member in range(4):
				var actual := world._party_member_position(job, member, leader)
				var cell := ColonyMap.cell_at(actual)
				position_checks += 1
				if not expeditions.navigation.is_in_boundsv(cell) or expeditions.navigation.is_point_solid(cell):
					failures.append("party member enters blocked cell")
	job.clear()
	job.merge(original_job)
	var path: Array = job.path
	var middle := mini(10, path.size() - 1)
	for troop_definition: Dictionary in HeroModel.TROOPS:
		var troop := str(troop_definition.id)
		store.data.buildings[59] = int(troop_definition.building)
		if not bool(heroes.train(troop, 5).ok) or not bool(heroes.select_troop(troop).ok):
			failures.append("canonical troop training/selection failed: " + troop)
			continue
		expeditions._state().jobs = []
		var dispatched := expeditions.dispatch(int(expeditions.deposits()[0].id))
		if not bool(dispatched.ok):
			failures.append("canonical actual dispatch failed: " + troop)
			continue
		canonical_dispatches += 1
		job = expeditions.jobs()[0]
		if str(job.troop_type) != troop:
			failures.append("actual dispatch uses incorrect troop identity")
		path = job.path
		middle = mini(10, path.size() - 1)
		for phase in ["outbound", "mining"]:
			job.phase = phase
			job.path_index = middle if phase == "outbound" else path.size() - 1
			var cell: Array = path[int(job.path_index)]
			job.position = [float(cell[0]), float(cell[1])]
			world.focus_position(ColonyMap.iso(Vector2i(int(cell[0]), int(cell[1]))))
			if phase == "mining":
				for settling_frame in range(1000):
					world.time += 0.1
					world._update_parties()
			for frame in range(4):
				world.time = frame * 0.19
				world._update_parties()
				var texture := world.parties[0].members[1].body.texture as AtlasTexture
				var expected := "troops_cartoon" if troop == "infantry" else "actors_mining" if phase == "mining" else "actors_actions"
				if texture == null or not texture.atlas.resource_path.contains(expected):
					failures.append("canonical troop rendered with wrong illustration: " + troop + ":" + phase)
				await capture("%s-%s-%d" % [troop, phase, frame])
		job.raw_cargo = 50
		expeditions._start_return(job)
		var before_positions: Array[Vector2] = []
		for actor: Dictionary in world.parties[0].members:
			before_positions.append(actor.node.position)
		world._update_parties()
		for member in range(4):
			if world.parties[0].members[member].node.position.distance_to(before_positions[member]) > 0.01:
				failures.append("mine departure teleports member")
		for frame in range(4):
			for tick in range(10):
				expeditions.advance(0.1)
				world.time += 0.1
				world._update_parties()
			await capture("%s-return-%d" % [troop, frame])
	# A job must not disappear while visible followers are still outside the gate.
	var arrival_checks := 0
	for deposit: Dictionary in expeditions.deposits():
		var route: Array = expeditions._route(ExpeditionModel.FIELD_GATE_ACCESS, expeditions._deposit_access(deposit))
		var end: Array = route.back()
		var fixture := original_job.duplicate(true)
		fixture.id = int(deposit.id) + 100
		fixture.deposit_id = int(deposit.id)
		fixture.troop_type = "cavalry"
		fixture.phase = "mining"
		fixture.path = route
		fixture.path_index = route.size() - 1
		fixture.position = [float(end[0]), float(end[1])]
		fixture.raw_cargo = 5
		fixture.step_seconds = 1.5
		expeditions._state().jobs = [fixture]
		world._update_parties()
		expeditions._start_return(fixture)
		var gate := ColonyMap.iso(ExpeditionModel.FIELD_GATE_ACCESS)
		var previous_positions: Array[Vector2] = []
		for tick in range(1600):
			previous_positions.clear()
			for actor: Dictionary in world.parties[0].members:
				previous_positions.append(actor.node.position)
			expeditions.advance(0.1)
			world.time += 0.1
			world._update_parties()
			if expeditions.jobs().is_empty():
				for member in range(4):
					arrival_checks += 1
					if previous_positions[member].distance_to(gate) > 12.0:
						failures.append("deposit %d member %d vanishes %.1f px before gate" % [int(deposit.id), member, previous_positions[member].distance_to(gate)])
				break
	world.set_mode("city")
	model.build(6, 6)
	world.refresh(store.data, 6)
	world.camera_zoom = 1.2
	world.focus_slot(6)
	for frame in range(4):
		world.time = frame * 0.19
		world._update_builder()
		await capture("builder-%d" % frame)
	var construction := model.construction_job()
	if not construction.is_empty():
		model.sync_construction(int(construction.ends_at))
		model.upgrade(6)
		world.refresh(store.data, 6)
		for frame in range(4):
			world.time = frame * 0.19
			world._update_builder()
			await capture("upgrade-%d" % frame)
	if FileAccess.file_exists(store.path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(store.path))
	if not failures.is_empty():
		push_error(str(failures))
		quit(1)
		return
	print("VISUAL_CAPTURE_OK actual_native_frames=", captures, " canonical_dispatches=", canonical_dispatches, " collision_checks=", position_checks, " arrival_checks=", arrival_checks, " isolated_save=true")
	quit(0)
