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
const FOREST_BORDER := 6
const PARTY_OFFSETS := [Vector2(0, -22), Vector2(-38, 18), Vector2(38, 18), Vector2(0, 55)]
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
var action_frames: Array[Texture2D] = []
var mining_frames: Array[Texture2D] = []
var feet: Array[Vector2] = []
var levels: Array[GeneratedNumber] = []
var builder: Dictionary = {}
var construction_timer: Label
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
	for row in range(3):
		for frame in range(8):
			action_frames.append(Art.texture("actor_action_%d_%d" % [row, frame]))
			mining_frames.append(Art.texture("actor_mining_%d_%d" % [row, frame]))
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
	builder = _actor(city, 50.0)
	builder.node.visible = false
	construction_timer = Label.new()
	construction_timer.position = Vector2(-65, -115)
	construction_timer.size = Vector2(210, 40)
	construction_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	construction_timer.add_theme_font_size_override("font_size", 22)
	construction_timer.add_theme_color_override("font_color", Color("ffe7ab"))
	construction_timer.add_theme_color_override("font_shadow_color", Color("100b16"))
	construction_timer.add_theme_constant_override("shadow_offset_x", 2)
	construction_timer.add_theme_constant_override("shadow_offset_y", 2)
	construction_timer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	builder.node.add_child(construction_timer)

func _build_region() -> void:
	_build_decor(region, "region")
	field_castle = _building(region, Art.texture("citadel"), ColonyMap.iso(ExpeditionModel.FIELD_GATE_CELL), Vector2(230, 208), Vector2(115, 187))
	for party in range(4):
		var members: Array[Dictionary] = []
		for member in range(4):
			var actor := _actor(region, 56.0 if member == 0 else 52.0)
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
	var mount := TextureRect.new()
	mount.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mount.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mount.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mount.size = Vector2(62, 48)
	mount.position = Vector2(-31, -45)
	mount.visible = false
	var mount_node := Node2D.new()
	parent.add_child(mount_node)
	mount_node.add_child(mount)
	mount_node.visible = false
	return {"node": node, "body": body, "cargo_sprite": cargo, "mount": mount, "mount_node": mount_node}

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
	var bounds := _visible_bounds().grow(200)
	# These generated wilderness tiles are scenery beyond the 900 playable cells.
	# Batch them into the terrain canvas: no extra entities, collisions or fake sites.
	for diagonal in range(-FOREST_BORDER * 2, ColonyMap.WIDTH + ColonyMap.HEIGHT + FOREST_BORDER * 2 - 1):
		for x in range(-FOREST_BORDER, ColonyMap.WIDTH + FOREST_BORDER):
			var y := diagonal - x
			if y < -FOREST_BORDER or y >= ColonyMap.HEIGHT + FOREST_BORDER:
				continue
			var cell := Vector2i(x, y)
			var position_world := ColonyMap.iso(cell)
			var tile_rect := Rect2(position_world - Vector2(64, 32), Vector2(128, 64))
			if not bounds.intersects(tile_rect):
				continue
			var outside := x < 0 or y < 0 or x >= ColonyMap.WIDTH or y >= ColonyMap.HEIGHT
			var kind := 0 if outside else ColonyMap.terrain_at(cell) if mode == "city" else ExpeditionModel.field_terrain_at(cell)
			canvas.draw_texture_rect(tile_textures[kind], tile_rect, false, Color(0.65, 0.72, 0.68) if outside else Color.WHITE)
	var tree := Art.texture("iso_decor_0")
	for diagonal in range(-FOREST_BORDER * 2, ColonyMap.WIDTH + ColonyMap.HEIGHT + FOREST_BORDER * 2 - 1):
		for x in range(-FOREST_BORDER, ColonyMap.WIDTH + FOREST_BORDER):
			var y := diagonal - x
			if y < -FOREST_BORDER or y >= ColonyMap.HEIGHT + FOREST_BORDER or (x >= 0 and y >= 0 and x < ColonyMap.WIDTH and y < ColonyMap.HEIGHT):
				continue
			var foot := ColonyMap.iso(Vector2i(x, y))
			var tree_rect := Rect2(foot - Vector2(78, 174), Vector2(156, 195))
			if bounds.intersects(tree_rect):
				canvas.draw_texture_rect(tree, tree_rect, false, Color(0.58, 0.68, 0.64))

func refresh(data: Dictionary, selected_slot: int) -> void:
	_selected_slot = selected_slot
	for index in range(ColonyMap.SLOT_COUNT):
		var kind := int(data.buildings[index]) if index < data.buildings.size() else -1
		var actor: Dictionary = workers[index]
		var button := site_buttons[index]
		var texture := Art.texture(KEYS[kind] if kind >= 0 and kind < KEYS.size() else "bunker_1" if not model.construction_job().is_empty() and int(model.construction_job().slot) == index else "ore_site")
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
			number.position = Vector2(49, -16)
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
	_update_builder()
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
				actor.mount_node.visible = false
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
		var newly_visible_job := int(party.get("job_id", -1)) != int(job.get("id", -1))
		party["job_id"] = int(job.get("id", -1))
		var work_key := "%s:%s:%s" % [str(job.get("id", -1)), str(job.phase), str(world_position)]
		if str(job.phase) == "mining" and str(party.get("work_positions_key", "")) != work_key:
			party["work_positions_key"] = work_key
			party["work_positions"] = [world_position, _party_member_position(job, 1, world_position), _party_member_position(job, 2, world_position), _party_member_position(job, 3, world_position)]
		var mounts_key := "%s:%s:%s" % [str(job.get("id", -1)), str(job.phase), str(world_position)]
		if str(job.get("troop_type", "")) == "cavalry" and str(job.phase) == "mining" and str(party.get("mounts_key", "")) != mounts_key:
			party["mounts_key"] = mounts_key
			party["mount_positions"] = []
			var parked_cells: Array[Vector2i] = []
			for rider in range(1, 4):
				var parking := _park_mount_position(job, rider, world_position, parked_cells)
				party.mount_positions.append(parking)
				parked_cells.append(ColonyMap.cell_at(parking))
		for member in range(4):
			var actor: Dictionary = party.members[member]
			var actor_left := left
			var previous_foot: Vector2 = actor.node.position
			var target_position: Vector2 = party.work_positions[member] if str(job.phase) == "mining" else _party_member_position(job, member, world_position)
			if newly_visible_job:
				actor.node.position = target_position
				actor["work_key"] = ""
				actor["remount_done"] = true
			var approaching_work := false
			var remounting := false
			if member > 0 and str(job.phase) == "mining":
				actor["remount_done"] = false
				approaching_work = _approach_work_site(actor, target_position, job)
			elif member > 0 and str(job.phase) == "returning":
				if str(job.get("troop_type", "")) == "cavalry" and not bool(actor.get("remount_done", true)) and party.has("mount_positions"):
					remounting = _approach_work_site(actor, party.mount_positions[member - 1], job)
					actor["remount_done"] = not remounting
				else:
					_approach_work_site(actor, target_position, job)
			else:
				actor.node.position = target_position
				actor["work_key"] = ""
			if absf(actor.node.position.x - previous_foot.x) > 0.01:
				actor_left = actor.node.position.x < previous_foot.x
			actor["last_render_time"] = time
			var visual_phase := "outbound" if approaching_work else str(job.phase)
			if member > 0 and visual_phase == "mining":
				var deposit := expeditions.get_deposit(int(job.get("deposit_id", -1)))
				if not deposit.is_empty():
					var raw: Array = deposit.cell
					actor_left = ColonyMap.iso(Vector2i(int(raw[0]), int(raw[1]))).x < actor.node.position.x
			actor.node.visible = mode == "region" and _visible_bounds().grow(110).has_point(actor.node.position)
			if str(job.phase) == "returning" and float(job.get("arrival_elapsed", 0.0)) > 0.0 and actor.node.position.distance_to(world_position) < 8.0:
				actor.node.visible = false # Enters the castle; cargo waits for the tail.
			if member == 0:
				actor.body.texture = hero_frames[maxi(0, hero_index) * 4 + (int(time * 7.0) % 4 if str(job.phase) in ["outbound", "returning"] else 0)]
				actor.body.flip_h = actor_left
			else:
				var row := 4 if visual_phase == "mining" else (3 if actor_left else 2) if carrying else (1 if actor_left else 0)
				var troop_type := str(job.get("troop_type", "infantry"))
				if troop_type in ["archer", "cavalry"]:
					var action_row := 0 if troop_type == "archer" else 1
					var action_frame := int(time * 8.0 + member) % 8 if visual_phase in ["outbound", "returning"] else 0
					actor.body.texture = mining_frames[action_row * 8 + int(time * 7.0 + member) % 8] if visual_phase == "mining" else action_frames[action_row * 8 + action_frame]
					if (approaching_work or remounting) and troop_type == "cavalry":
						actor.body.texture = frames[(1 if actor_left else 0) * 8 + action_frame]
					actor.body.flip_h = actor_left and not ((approaching_work or remounting) and troop_type == "cavalry")
					actor.body.size = Vector2(64, 64) if visual_phase == "mining" else Vector2(76, 68) if troop_type == "cavalry" and not approaching_work and not remounting else Vector2(52, 52)
					var bob := sin(time * 9.0 + member) * 1.5 if visual_phase in ["outbound", "returning"] else 0.0
					actor.body.position = Vector2(-actor.body.size.x * 0.5, -actor.body.size.y + 3 + bob)
				else:
					actor.body.texture = frames[row * 8 + int(time * 8.0 + member) % 8]
					actor.body.flip_h = actor_left if visual_phase == "mining" else false
					actor.body.size = Vector2(52, 52)
					actor.body.position = Vector2(-26, -49)
				actor.body.modulate = Color.WHITE
			actor.mount.visible = member > 0 and str(job.get("troop_type", "")) == "cavalry" and (str(job.phase) == "mining" or remounting)
			actor.mount_node.visible = actor.mount.visible and actor.node.visible
			if actor.mount.visible:
				actor.mount_node.position = party.mount_positions[member - 1]
				actor.mount.texture = mining_frames[16 + int(time * 4.0) % 8]
			actor.cargo_sprite.visible = carrying and member > 0
			if carrying:
				actor.cargo_sprite.texture = Art.texture(str(job.get("cargo_resource", "stone")))

func _approach_work_site(actor: Dictionary, target: Vector2, job: Dictionary) -> bool:
	var key := "%s:%s:%s" % [str(job.get("id", -1)), str(job.phase), str(ColonyMap.cell_at(target))]
	if str(actor.get("work_key", "")) != key:
		actor["work_key"] = key
		actor["work_path"] = PackedVector2Array()
		actor["work_index"] = 0
		var start := ColonyMap.cell_at(actor.node.position)
		var finish := ColonyMap.cell_at(target)
		if expeditions.navigation.is_in_boundsv(start) and not expeditions.navigation.is_point_solid(start):
			for cell in expeditions.navigation.get_id_path(start, finish):
				actor.work_path.append(ColonyMap.iso(cell))
			if not actor.work_path.is_empty():
				actor.work_path[0] = actor.node.position # No repeated snap back to cell centers.
	var path: PackedVector2Array = actor.get("work_path", PackedVector2Array())
	if path.is_empty():
		# Never teleport through a disconnected cell. Candidate selection guarantees
		# reachability; a changed obstacle leaves the actor safely in place.
		return actor.node.position.distance_to(target) > 1.0
	if int(actor.get("work_index", 0)) >= path.size() and actor.node.position.distance_to(target) > 1.0:
		actor["work_index"] = path.size() - 1
	var elapsed := clampf(time - float(actor.get("last_render_time", time)), 0.0, 0.1)
	var budget := elapsed * 72.0 / maxf(0.25, float(job.get("step_seconds", 1.5))) * (1.5 if str(job.phase) == "returning" else 1.0)
	while budget > 0.0 and int(actor.work_index) < path.size():
		var goal := target if int(actor.work_index) == path.size() - 1 else path[int(actor.work_index)]
		var distance: float = actor.node.position.distance_to(goal)
		if distance <= budget:
			actor.node.position = goal
			actor.work_index = int(actor.work_index) + 1
			budget -= distance
		else:
			actor.node.position = actor.node.position.move_toward(goal, budget)
			budget = 0.0
	return int(actor.work_index) < path.size()

func _park_mount_position(job: Dictionary, member: int, leader: Vector2, reserved: Array[Vector2i] = []) -> Vector2:
	var occupied: Array[Vector2i] = reserved.duplicate()
	for index in range(4):
		occupied.append(ColonyMap.cell_at(_party_member_position(job, index, leader)))
	var candidates: Array[Vector2] = []
	var center := ColonyMap.cell_at(leader)
	var worker_cell := ColonyMap.cell_at(_party_member_position(job, member, leader))
	for radius in range(1, 4):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var cell := center + Vector2i(dx, dy)
				if cell not in occupied and expeditions.navigation.is_in_boundsv(cell) and not expeditions.navigation.is_point_solid(cell):
					var route := expeditions.navigation.get_id_path(worker_cell, cell)
					if not route.is_empty() and route.size() <= 4:
						candidates.append(ColonyMap.iso(cell))
	return candidates[0] if not candidates.is_empty() else leader

func _party_member_position(job: Dictionary, member: int, leader: Vector2) -> Vector2:
	if member == 0:
		return leader
	if str(job.get("phase", "")) == "mining":
		var deposit := expeditions.get_deposit(int(job.get("deposit_id", -1)))
		if not deposit.is_empty():
			var raw_cell: Array = deposit.cell
			var cell := Vector2i(int(raw_cell[0]), int(raw_cell[1]))
			var candidates: Array[Vector2] = []
			for offset in [Vector2i.DOWN, Vector2i.RIGHT, Vector2i.UP, Vector2i.LEFT, Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
				var target: Vector2i = cell + offset
				if expeditions.navigation.is_in_boundsv(target) and not expeditions.navigation.is_point_solid(target):
					var foot := ColonyMap.iso(target)
					var route := expeditions.navigation.get_id_path(ColonyMap.cell_at(leader), target)
					if foot.distance_to(leader) > 20.0 and not route.is_empty() and route.size() <= 4:
						candidates.append(foot)
			if member <= candidates.size():
				return candidates[member - 1]
			# A narrow approach can lack three separate neighboring cells. Keep
			# the extra miner at the reachable ore-facing edge of the access cell,
			# rather than swinging a pickaxe several cells away on an empty road.
			var direction := signf(ColonyMap.iso(cell).x - leader.x)
			var inset := Vector2(direction * 28.0, 14.0)
			var fallback := leader + inset
			if ColonyMap.cell_at(fallback) == ColonyMap.cell_at(leader):
				return fallback
			return leader
	# Followers sample the actual traversed route. Fixed side offsets cut corners
	# through blocking forests and make a valid central route visually incorrect.
	var path: Array = job.get("path", [])
	var cursor := leader
	var gap := float(member) * (62.0 if str(job.get("troop_type", "infantry")) == "cavalry" else 52.0)
	if str(job.get("phase", "")) == "returning" and int(job.get("path_index", 0)) >= path.size() - 1:
		var hold := maxf(0.1, 3.0 * float(job.get("step_seconds", 1.5)))
		gap *= maxf(0.0, 1.0 - float(job.get("arrival_elapsed", 0.0)) / hold)
	var index := mini(int(job.get("path_index", 0)), path.size() - 1)
	while index >= 0:
		var point: Array = path[index]
		var target := ColonyMap.iso(Vector2i(int(point[0]), int(point[1])))
		var distance := cursor.distance_to(target)
		if distance >= gap and distance > 0.001:
			return cursor.move_toward(target, gap)
		gap -= distance
		cursor = target
		index -= 1
	# Newly emerging members share the castle entrance briefly; never step into
	# unvalidated neighboring cells merely to keep a decorative formation.
	return cursor

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


func _update_builder() -> void:
	if builder.is_empty() or model == null:
		return
	var job := model.construction_job()
	builder.node.visible = mode == "city" and is_visible_in_tree() and not job.is_empty()
	if not builder.node.visible:
		return
	var slot := int(job.slot)
	var foot := ColonyMap.iso(ColonyMap.BUNKER_CELL if slot == -1 else ColonyMap.slot_cell(slot))
	builder.node.position = foot + Vector2(-40, 35)
	builder.body.texture = action_frames[16 + int(time * 8.0) % 8]
	var structure := bunker if slot == -1 else site_buttons[slot]
	construction_timer.position.y = structure.position.y - 78.0
	var seconds := model.construction_remaining()
	construction_timer.text = "%02d:%02d:%02d" % [seconds / 3600, (seconds / 60) % 60, seconds % 60]
	builder.node.visible = _visible_bounds().grow(130).has_point(builder.node.position)
