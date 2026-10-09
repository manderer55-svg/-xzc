class_name MineColony
extends Control
## Two actual isometric maps. Generated tiles and sprites remain separate objects;
## the camera moves across 900 cells, and foot positions determine depth.
signal selected(slot: int)
signal deposit_selected(id: int)
signal delivery(resource: String, amount: int)
const KEYS := ["quarry", "sawmill", "shrine", "fortress", "forge", "watchtower", "townhall", "citadel", "alliance_hall", "market", "stable", "barracks", "archery", "tavern", "alliance_store"]
const MIN_ZOOM := 0.16
const MAX_ZOOM := 1.2
const DRAG_THRESHOLD := 12.0
const PARTY_OFFSETS := [Vector2(0, -8), Vector2(-23, 12), Vector2(23, 13), Vector2(0, 31)]
const DEPOT := Vector2(-384, 1088)
const BUNKER_FOOT := Vector2(0, 1216)
class TerrainCanvas:
	extends Node2D
	var world: Control
	func _draw() -> void:
		world._draw_terrain(self)
var model: SettlementModel
var expeditions: ExpeditionModel
var mode := "city"
var interaction_enabled := true:
	set(value):
		interaction_enabled = value
		if not value:
			cancel_gestures()
var camera_zoom := 0.65
var camera_offset := Vector2.ZERO
var site_buttons: Array[TextureButton] = []
var workers: Array[Dictionary] = []
var frames: Array[Texture2D] = []
var hero_frames: Array[Texture2D] = []
var troop_bodies: Array[Texture2D] = []
var feet: Array[Vector2] = []
var levels: Array[GeneratedNumber] = []
var bunker: TextureButton
var field_castle: TextureButton
var navigation := AStarGrid2D.new()
var time := 0.0
var clock := 0.0
var ordering := 0.0
var transported := 0
var last_error := ""
var content: Node2D
var terrain: TerrainCanvas
var city: Node2D
var region: Node2D
var decorations: Array[Node2D] = []
var deposits: Dictionary = {}
var parties: Array[Dictionary] = []
var tile_textures: Array[Texture2D] = []
var _dragging := false
var _drag_moved := false
var _drag_origin := Vector2.ZERO
var _last_pointer := Vector2.ZERO
var _touches: Dictionary = {}
var _pinched := false
var _camera_initialized := false
var _selected_slot := 4
var _selected_deposit := -1
var _refresh_elapsed := 0.0

func configure(value: SettlementModel, expedition_model: ExpeditionModel = null) -> void:
	model = value
	expeditions = expedition_model
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	if size.x <= 0.0 or size.y <= 0.0:
		size = Vector2(720, 668)
	content = Node2D.new()
	add_child(content)
	terrain = TerrainCanvas.new()
	terrain.world = self
	terrain.z_index = -100
	content.add_child(terrain)
	city = Node2D.new()
	city.y_sort_enabled = true
	content.add_child(city)
	region = Node2D.new()
	region.y_sort_enabled = true
	content.add_child(region)
	for index in range(9):
		tile_textures.append(Art.texture("iso_tile_%d" % index))
	for row in range(5):
		for frame in range(8):
			frames.append(Art.texture("worker_%d_%d" % [row, frame]))
	for hero in range(4):
		for frame in range(4):
			hero_frames.append(Art.texture("hero_world_%d_%d" % [hero, frame]))
	for troop in range(3):
		troop_bodies.append(Art.texture("troop_%d" % troop))
	_build_city()
	_build_region()
	_rebuild_paths()
	resized.connect(_resized)
	visibility_changed.connect(func():
		if not visible:
			cancel_gestures())
	refresh(model.store.data, 4)
	set_mode("region" if expeditions != null else "city")

func _building(parent: Node2D, texture: Texture2D, foot: Vector2, dimensions: Vector2, anchor: Vector2) -> TextureButton:
	var base := Node2D.new()
	base.position = foot
	parent.add_child(base)
	var button := TextureButton.new()
	button.texture_normal = texture
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.position = -anchor
	button.size = dimensions
	button.set_meta("base", base)
	_mask(button)
	base.add_child(button)
	return button

func _mask(button: TextureButton) -> void:
	if button.texture_normal == null:
		return
	# A narrow tower and a broad foundation share their ground contact, even
	# though KEEP_ASPECT_CENTERED gives them different vertical letterboxing.
	var texture_size := button.texture_normal.get_size()
	var fit := minf(button.size.x / texture_size.x, button.size.y / texture_size.y)
	var fitted_bottom := (button.size.y + texture_size.y * fit) * 0.5
	button.position = Vector2(-button.size.x * 0.5, -fitted_bottom + 18.0)
	var bitmap := BitMap.new()
	bitmap.create_from_image_alpha(button.texture_normal.get_image(), 0.15)
	button.texture_click_mask = bitmap

func _build_city() -> void:
	_build_decor(city, "city")
	for index in range(ColonyMap.SLOT_COUNT):
		var foot := ColonyMap.iso(ColonyMap.slot_cell(index))
		feet.append(foot)
		var button := _building(city, Art.texture("ore_site"), foot, Vector2(166, 136), Vector2(83, 116))
		button.pressed.connect(func(): selected.emit(index))
		site_buttons.append(button)
		var number := GeneratedNumber.new()
		number.mouse_filter = Control.MOUSE_FILTER_IGNORE
		number.size = Vector2(26, 23)
		number.position = Vector2(126, 101)
		button.add_child(number)
		levels.append(number)
		var actor := _actor(city, 43.0)
		actor.node.position = ColonyMap.iso(ColonyMap.DEPOT_ACCESS)
		actor.node.visible = false
		actor.merge({"kind": -1, "tier": 1, "state": "outbound", "path": PackedVector2Array(), "path_index": 0, "wait": 0.0, "amount": 0, "resource": "stone", "left": false})
		workers.append(actor)
	_building(city, Art.texture("warehouse"), ColonyMap.iso(ColonyMap.DEPOT_CELL), Vector2(205, 165), Vector2(102, 145))
	bunker = _building(city, Art.texture("bunker_0"), ColonyMap.iso(ColonyMap.BUNKER_CELL), Vector2(212, 183), Vector2(106, 163))
	bunker.pressed.connect(func(): selected.emit(-1))

func _build_region() -> void:
	_build_decor(region, "region")
	field_castle = _building(region, Art.texture("citadel"), ColonyMap.iso(ExpeditionModel.FIELD_GATE_CELL), Vector2(230, 208), Vector2(115, 187))
	for party in range(4):
		var members: Array[Dictionary] = []
		for member in range(4):
			var actor := _actor(region, 64.0 if member == 0 else 48.0)
			actor.node.visible = false
			members.append(actor)
		parties.append({"members": members, "job_id": -1})

func _actor(parent: Node2D, height: float) -> Dictionary:
	var node := Node2D.new()
	parent.add_child(node)
	var body := TextureRect.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	body.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	body.position = Vector2(-height * 0.5, -height + 3)
	body.size = Vector2(height, height)
	node.add_child(body)
	var cargo := TextureRect.new()
	cargo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cargo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cargo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	cargo.position = Vector2(height * 0.1, -height * 0.6)
	cargo.size = Vector2(18, 18)
	cargo.visible = false
	node.add_child(cargo)
	return {"node": node, "body": body, "cargo_sprite": cargo}

func _build_decor(parent: Node2D, map_mode: String) -> void:
	for y in range(ColonyMap.HEIGHT):
		for x in range(ColonyMap.WIDTH):
			var cell := Vector2i(x, y)
			var kind := ColonyMap.decor_at(cell) if map_mode == "city" else ExpeditionModel.field_decor_at(cell)
			if kind < 0:
				continue
			var base := Node2D.new()
			base.position = ColonyMap.iso(cell)
			base.set_meta("mode", map_mode)
			parent.add_child(base)
			var sprite := TextureRect.new()
			sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
			sprite.texture = Art.texture("iso_decor_%d" % kind)
			sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			var dimensions: Vector2 = [Vector2(132, 165), Vector2(162, 175), Vector2(112, 91), Vector2(109, 92), Vector2(101, 132), Vector2(122, 82), Vector2(92, 87), Vector2(91, 77)][kind]
			sprite.size = dimensions
			sprite.position = Vector2(-dimensions.x * 0.5, -dimensions.y + 21)
			base.add_child(sprite)
			decorations.append(base)

func _draw_terrain(canvas: Node2D) -> void:
	var bounds := _visible_bounds().grow(80)
	for diagonal in range(ColonyMap.WIDTH + ColonyMap.HEIGHT - 1):
		for x in range(ColonyMap.WIDTH):
			var y := diagonal - x
			if y < 0 or y >= ColonyMap.HEIGHT:
				continue
			var cell := Vector2i(x, y)
			var position_world := ColonyMap.iso(cell)
			var tile_rect := Rect2(position_world - Vector2(64, 32), Vector2(128, 64))
			if not bounds.intersects(tile_rect):
				continue
			var kind := ColonyMap.terrain_at(cell) if mode == "city" else ExpeditionModel.field_terrain_at(cell)
			canvas.draw_texture_rect(tile_textures[kind], tile_rect, false)

func refresh(data: Dictionary, selected_slot: int) -> void:
	_selected_slot = selected_slot
	for index in range(ColonyMap.SLOT_COUNT):
		var kind := int(data.buildings[index]) if index < data.buildings.size() else -1
		var actor: Dictionary = workers[index]
		var button := site_buttons[index]
		var texture := Art.texture(KEYS[kind] if kind >= 0 and kind < KEYS.size() else "ore_site")
		if button.texture_normal != texture:
			button.texture_normal = texture
			_mask(button)
		button.modulate = Color(1.2, 1.13, 0.84) if index == selected_slot else Color.WHITE
		levels[index].text = str(int(data.upgrades[index]) + 1) if kind >= 0 else ""
		actor.tier = int(data.upgrades[index]) + 1 if index < data.upgrades.size() else 1
		if actor.kind != kind:
			actor.kind = kind
			actor.amount = 0
			actor.node.position = ColonyMap.iso(ColonyMap.DEPOT_ACCESS)
			actor.state = "outbound"
			actor.wait = 0.0
			actor.cargo_sprite.visible = false
		actor.node.visible = kind >= 0 and expeditions == null
	var bunker_texture := Art.texture("bunker_%d" % int(data.get("bunker_level", 0)))
	if bunker.texture_normal != bunker_texture:
		bunker.texture_normal = bunker_texture
		_mask(bunker)
	bunker.modulate = Color(1.2, 1.13, 0.84) if selected_slot == -1 else Color.WHITE
	if expeditions == null:
		_rebuild_paths()
	_refresh_deposits()
	_cull()

func _refresh_deposits() -> void:
	if expeditions == null:
		return
	for deposit: Dictionary in expeditions.deposits():
		var id := int(deposit.id)
		if not deposits.has(id):
			var resource := str(deposit.resource)
			var kind := 1 if resource == "wood" else 3 if resource == "stone" else 4
			var button := _building(region, Art.texture("iso_decor_%d" % kind), Vector2.ZERO, Vector2(162, 170), Vector2(81, 151))
			var number := GeneratedNumber.new()
			number.mouse_filter = Control.MOUSE_FILTER_IGNORE
			number.size = Vector2(64, 25)
			number.position = Vector2(52, 137)
			button.add_child(number)
			deposits[id] = {"button": button, "number": number, "cell": Vector2i.ZERO, "active": false}
		var entry: Dictionary = deposits[id]
		entry.cell = Vector2i(int(deposit.cell[0]), int(deposit.cell[1]))
		entry.active = bool(deposit.active) and int(deposit.remaining) > 0
		entry.button.get_parent().position = ColonyMap.iso(entry.cell)
		entry.button.get_parent().visible = entry.active
		entry.number.text = str(int(deposit.remaining))
		entry.button.modulate = Color(1.25, 1.17, 0.77) if id == _selected_deposit else Color.WHITE

func set_mode(value: String) -> void:
	var next_mode := "region" if value == "region" and expeditions != null else "city"
	var changed := next_mode != mode
	mode = next_mode
	cancel_gestures()
	if content == null:
		return
	city.visible = mode == "city"
	region.visible = mode == "region"
	if changed or not _camera_initialized:
		camera_zoom = 0.65
		focus_home()
	else:
		_update_camera()
	_refresh_deposits()
	terrain.queue_redraw()

func world_to_view(point: Vector2) -> Vector2:
	return point * camera_zoom + camera_offset

func view_to_world(point: Vector2) -> Vector2:
	return (point - camera_offset) / camera_zoom

func map_bounds() -> Rect2:
	return Rect2(Vector2(-1920, -32), Vector2(3840, 1920))

func set_zoom(value: float, local_anchor: Variant = null) -> void:
	var anchor: Vector2 = size * 0.5 if local_anchor == null else local_anchor
	var world_point := view_to_world(anchor)
	camera_zoom = clampf(value, MIN_ZOOM, MAX_ZOOM)
	camera_offset = anchor - world_point * camera_zoom
	_update_camera()

func pan_camera(delta: Vector2) -> void:
	camera_offset += delta
	_update_camera()

func focus_home() -> void:
	var center := ColonyMap.iso(Vector2i(14, 15)) if mode == "city" else ColonyMap.iso(Vector2i(15, 23))
	_camera_initialized = true
	focus_position(center)

func focus_position(world_point: Vector2) -> void:
	camera_offset = size * 0.5 - world_point * camera_zoom
	_update_camera()

func focus_slot(slot: int) -> void:
	var cell := ColonyMap.BUNKER_CELL if slot == -1 else ColonyMap.slot_cell(slot)
	camera_offset = size * 0.5 - (ColonyMap.iso(cell) - Vector2(0, 42)) * camera_zoom
	_update_camera()

func focus_deposit(id: int) -> void:
	_selected_deposit = id
	if expeditions == null:
		return
	var deposit := expeditions.get_deposit(id)
	if deposit.is_empty():
		return
	var cell := Vector2i(int(deposit.cell[0]), int(deposit.cell[1]))
	camera_offset = size * 0.5 - ColonyMap.iso(cell) * camera_zoom
	_update_camera()
	_refresh_deposits()

func _update_camera() -> void:
	var bounds := map_bounds()
	for axis in range(2):
		var lower := size[axis] - bounds.end[axis] * camera_zoom
		var upper := -bounds.position[axis] * camera_zoom
		camera_offset[axis] = clampf(camera_offset[axis], lower, upper) if lower <= upper else size[axis] * 0.5 - bounds.get_center()[axis] * camera_zoom
	if content == null:
		return
	content.position = camera_offset
	content.scale = Vector2.ONE * camera_zoom
	terrain.queue_redraw()
	_cull()

func _resized() -> void:
	if _camera_initialized:
		_update_camera()

func _visible_bounds() -> Rect2:
	return Rect2(view_to_world(Vector2.ZERO), size / camera_zoom)

func _cull() -> void:
	if content == null:
		return
	var bounds := _visible_bounds().grow(240)
	for decor in decorations:
		decor.visible = bounds.has_point(decor.position)
	for button in site_buttons:
		button.get_parent().visible = bounds.has_point(button.get_parent().position)
	if bunker != null:
		bunker.get_parent().visible = bounds.has_point(bunker.get_parent().position)
	for entry: Dictionary in deposits.values():
		entry.button.get_parent().visible = entry.active and bounds.has_point(entry.button.get_parent().position)

func cancel_gestures() -> void:
	_dragging = false
	_drag_moved = false
	_pinched = false
	_touches.clear()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_WINDOW_FOCUS_OUT]:
		cancel_gestures()

func _gui_input(event: InputEvent) -> void:
	if not interaction_enabled:
		return
	# The ordinary HUD uses Godot's touch-to-mouse emulation. The map consumes
	# native touch itself, so its emulated second event must not move/select twice.
	if (event is InputEventMouseButton or event is InputEventMouseMotion) and event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			set_zoom(camera_zoom * (1.12 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.12), event.position)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_dragging = true
				_drag_moved = false
				_drag_origin = event.position
				_last_pointer = event.position
			else:
				if _dragging and not _drag_moved:
					_select_at(event.position)
				_dragging = false
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		if event.position.distance_to(_drag_origin) >= DRAG_THRESHOLD:
			_drag_moved = true
		if _drag_moved:
			pan_camera(event.position - _last_pointer)
		_last_pointer = event.position
		accept_event()
	elif event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
			if _touches.size() == 1:
				_drag_origin = event.position
				_last_pointer = event.position
				_drag_moved = false
				_pinched = false
			else:
				_pinched = true
				_drag_moved = true
		else:
			if _touches.has(event.index) and _touches.size() == 1 and not _drag_moved and not _pinched:
				_select_at(event.position)
			_touches.erase(event.index)
			if _touches.size() == 1:
				_last_pointer = _touches.values()[0]
		accept_event()
	elif event is InputEventScreenDrag and _touches.has(event.index):
		if _touches.size() >= 2:
			var old_points := _touches.values()
			var old_midpoint: Vector2 = (old_points[0] + old_points[1]) * 0.5
			var old_distance: float = old_points[0].distance_to(old_points[1])
			_touches[event.index] = event.position
			var new_points := _touches.values()
			var new_midpoint: Vector2 = (new_points[0] + new_points[1]) * 0.5
			var new_distance: float = new_points[0].distance_to(new_points[1])
			if old_distance > 1:
				set_zoom(camera_zoom * new_distance / old_distance, old_midpoint)
			pan_camera(new_midpoint - old_midpoint)
			_pinched = true
			_drag_moved = true
		else:
			_touches[event.index] = event.position
			if event.position.distance_to(_drag_origin) >= DRAG_THRESHOLD:
				_drag_moved = true
			if _drag_moved:
				pan_camera(event.position - _last_pointer)
			_last_pointer = event.position
		accept_event()

func _select_at(point: Vector2) -> void:
	if not Rect2(Vector2.ZERO, size).has_point(point):
		return
	var world_point := view_to_world(point)
	if mode == "region":
		if _hit(field_castle, world_point):
			selected.emit(-2)
			return
		var candidates: Array = deposits.values()
		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.button.get_parent().position.y > b.button.get_parent().position.y)
		for entry: Dictionary in candidates:
			if entry.active and _hit(entry.button, world_point):
				for id in deposits:
					if deposits[id] == entry:
						_selected_deposit = int(id)
						_refresh_deposits()
						deposit_selected.emit(int(id))
						return
		return
	if _hit(bunker, world_point):
		selected.emit(-1)
		return
	var indices: Array[int] = []
	for index in range(site_buttons.size()):
		indices.append(index)
	indices.sort_custom(func(a: int, b: int) -> bool: return feet[a].y > feet[b].y)
	for index in indices:
		if _hit(site_buttons[index], world_point):
			selected.emit(index)
			return

func _hit(button: TextureButton, point: Vector2) -> bool:
	if not button.get_parent().visible:
		return false
	var local: Vector2 = point - button.get_parent().position - button.position
	var texture_size := button.texture_normal.get_size()
	var ratio := minf(button.size.x / texture_size.x, button.size.y / texture_size.y)
	var bounds := Rect2((button.size - texture_size * ratio) * 0.5, texture_size * ratio)
	if not bounds.has_point(local):
		return false
	var pixel := Vector2i((local - bounds.position) / ratio)
	return button.texture_click_mask == null or button.texture_click_mask.get_bitv(pixel)

func _rebuild_paths() -> void:
	navigation.region = Rect2i(0, 0, ColonyMap.WIDTH, ColonyMap.HEIGHT)
	navigation.cell_size = Vector2.ONE
	navigation.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	navigation.update()
	for y in range(ColonyMap.HEIGHT):
		for x in range(ColonyMap.WIDTH):
			var cell := Vector2i(x, y)
			navigation.set_point_solid(cell, not ColonyMap.is_walkable(cell))
	for index in range(workers.size()):
		var actor: Dictionary = workers[index]
		if actor.kind >= 0 and actor.state in ["outbound", "returning"]:
			_set_path(actor, ColonyMap.iso(ColonyMap.slot_access(index)) if actor.state == "outbound" else ColonyMap.iso(ColonyMap.DEPOT_ACCESS))

func _grid(point: Vector2) -> Vector2i:
	return ColonyMap.cell_at(point)

func _set_path(actor: Dictionary, destination: Vector2) -> void:
	var path := PackedVector2Array()
	var start := _grid(actor.node.position)
	var end := _grid(destination)
	if navigation.is_in_boundsv(start) and navigation.is_in_boundsv(end) and not navigation.is_point_solid(start) and not navigation.is_point_solid(end):
		for cell in navigation.get_id_path(start, end):
			path.append(ColonyMap.iso(cell))
	actor.path = path
	actor.path_index = 0
	actor["destination"] = destination

func _process(delta: float) -> void:
	if model == null or not is_visible_in_tree():
		return
	time += maxf(0.0, delta)
	if expeditions != null:
		_update_parties()
		_refresh_elapsed += maxf(0.0, delta)
		if _refresh_elapsed >= 0.2:
			_refresh_elapsed = 0.0
			_refresh_deposits()
			_cull()
		return
	clock += maxf(0.0, delta)
	if clock >= 1.0:
		clock = 0.0
		if not model.stage_production():
			last_error = model.store.last_error
	for index in range(workers.size()):
		var actor: Dictionary = workers[index]
		if actor.kind < 0:
			continue
		var destination := ColonyMap.iso(ColonyMap.slot_access(index)) if actor.state == "outbound" else ColonyMap.iso(ColonyMap.DEPOT_ACCESS)
		if actor.state in ["outbound", "returning"]:
			if actor.path.is_empty():
				_set_path(actor, destination)
				continue
			_move(actor, delta)
			if actor.path_index >= actor.path.size():
				if actor.node.position.distance_to(destination) > 1.0:
					_set_path(actor, destination)
					continue
				if actor.state == "returning":
					_deliver(actor, index)
				else:
					actor.state = "gathering"
					actor.wait = 5.0 / float(actor.tier)
		else:
			actor.wait -= maxf(0.0, delta)
			if actor.wait <= 0.0:
				if actor.state == "delivery_retry":
					_deliver(actor, index)
				elif _pickup(actor, index):
					actor.state = "returning"
					_set_path(actor, ColonyMap.iso(ColonyMap.DEPOT_ACCESS))
				else:
					actor.wait = 1.0
		var row: int = 4 if actor.state == "gathering" else (3 if actor.left else 2) if int(actor.amount) > 0 else (1 if actor.left else 0)
		actor.body.texture = frames[row * 8 + int(time * 8.0) % 8]
		actor.node.visible = _visible_bounds().grow(80).has_point(actor.node.position)

func _update_parties() -> void:
	var jobs := expeditions.jobs()
	for index in range(parties.size()):
		var party: Dictionary = parties[index]
		if index >= jobs.size():
			for actor: Dictionary in party.members:
				actor.node.visible = false
			continue
		var job: Dictionary = jobs[index]
		var logical := expeditions.job_position(job)
		var world_position := Vector2((logical.x - logical.y) * 64, (logical.x + logical.y) * 32)
		var previous: Vector2 = party.get("previous", world_position)
		var left := world_position.x < previous.x - 0.01
		if world_position.x == previous.x:
			left = bool(party.get("left", false))
		party["left"] = left
		party["previous"] = world_position
		var hero_index := ["warden", "ranger", "seer", "marshal"].find(str(job.get("hero_id", "warden")))
		var carrying := int(job.get("cargo_amount", 0)) > 0
		for member in range(4):
			var actor: Dictionary = party.members[member]
			actor.node.position = world_position + PARTY_OFFSETS[member]
			actor.node.visible = mode == "region" and _visible_bounds().grow(110).has_point(actor.node.position)
			if member == 0:
				actor.body.texture = hero_frames[maxi(0, hero_index) * 4 + int(time * 7.0) % 4]
				actor.body.flip_h = left
			else:
				var row := 4 if str(job.phase) == "mining" else (3 if left else 2) if carrying else (1 if left else 0)
				var troop_type := str(job.get("troop_type", "infantry"))
				if troop_type in ["archers", "cavalry"]:
					actor.body.texture = troop_bodies[1 if troop_type == "archers" else 2]
					actor.body.flip_h = left
					actor.body.size = Vector2(64, 57) if troop_type == "cavalry" else Vector2(48, 48)
					var bob := sin(time * 9.0 + member) * 1.5 if str(job.phase) in ["outbound", "returning"] else 0.0
					actor.body.position = Vector2(-actor.body.size.x * 0.5, -actor.body.size.y + 3 + bob)
				else:
					actor.body.texture = frames[row * 8 + int(time * 8.0 + member) % 8]
					actor.body.flip_h = false
					actor.body.size = Vector2(48, 48)
					actor.body.position = Vector2(-24, -45)
				actor.body.modulate = Color.WHITE
			actor.cargo_sprite.visible = carrying and member > 0
			if carrying:
				actor.cargo_sprite.texture = Art.texture(str(job.get("cargo_resource", "stone")))

func _move(actor: Dictionary, delta: float) -> void:
	var budget := maxf(0.0, delta) * (110.0 + 16.0 * float(actor.tier))
	while budget > 0 and int(actor.path_index) < actor.path.size():
		var target: Vector2 = actor.path[int(actor.path_index)]
		var direction: Vector2 = target - actor.node.position
		var distance := direction.length()
		if distance < 0.01:
			actor.path_index += 1
			continue
		actor.left = direction.x < 0 if absf(direction.x) > 0.01 else actor.left
		var step := minf(distance, budget)
		actor.node.position += direction / distance * step
		budget -= step
		if step >= distance:
			actor.path_index += 1

func _pickup(actor: Dictionary, index: int) -> bool:
	var production := model.production_for_slot(index)
	for resource in SettlementModel.RESOURCE_KEYS:
		if int(production[resource]) <= 0:
			continue
		var reserved := 0
		for colleague in workers:
			if colleague.resource == resource:
				reserved += int(colleague.amount)
		var available := maxi(0, int(model.store.data.colony_pending[resource]) - reserved)
		if available <= 0:
			continue
		actor.resource = resource
		actor.amount = mini(available, maxi(3 * int(actor.tier), available / 4))
		actor.cargo_sprite.texture = Art.texture(resource)
		actor.cargo_sprite.visible = true
		return true
	return false

func _deliver(actor: Dictionary, index: int) -> void:
	if actor.node.position.distance_to(ColonyMap.iso(ColonyMap.DEPOT_ACCESS)) > 1.0:
		_set_path(actor, ColonyMap.iso(ColonyMap.DEPOT_ACCESS))
		return
	var result := model.deliver_cargo(String(actor.resource), int(actor.amount))
	if not result.ok:
		last_error = String(result.reason)
		actor.state = "delivery_retry"
		actor.wait = 2.0
		return
	transported += int(result.amount)
	actor.amount = 0
	actor.cargo_sprite.visible = false
	actor.state = "outbound"
	_set_path(actor, ColonyMap.iso(ColonyMap.slot_access(index)))
	delivery.emit(String(result.resource), int(result.amount))

func dispatch() -> void:
	if expeditions != null:
		return
	model.stage_production()
	for actor in workers:
		if actor.state == "gathering":
			actor.wait = 0.0

func set_interaction_enabled(value: bool) -> void:
	interaction_enabled = value

func _order() -> void:
	# Node2D y_sort handles sprite feet without reallocating or reparenting them.
	pass
