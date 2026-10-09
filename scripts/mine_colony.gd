class_name MineColony
extends Control
## Generated foundations anchor to terrain; pooled workers follow walkable ground
## to collect reserved ore and credit the warehouse only after actual arrival.
signal selected(slot: int)
signal delivery(resource: String, amount: int)
const KEYS := ["quarry", "sawmill", "shrine", "fortress", "forge", "watchtower"]
const DEPOT := Vector2(352, 632)
const BUNKER_FOOT := Vector2(602, 624)
var model: SettlementModel
var site_buttons: Array[TextureButton] = []
var workers: Array[Dictionary] = []
var frames: Array[Texture2D] = []
var feet: Array[Vector2] = []
var levels: Array[GeneratedNumber] = []
var bunker: TextureButton
var navigation := AStarGrid2D.new()
var time := 0.0
var clock := 0.0
var ordering := 0.0
var transported := 0
var last_error := ""

func configure(value: SettlementModel) -> void:
	model = value
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(720, 1280)
	navigation.region = Rect2i(2, 22, 41, 20)
	navigation.cell_size = Vector2.ONE * 16
	navigation.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	navigation.update()
	for row in range(5):
		for frame in range(8):
			frames.append(Art.texture("worker_%d_%d" % [row, frame]))
	for index in range(9):
		var foot := Vector2(126 + (index % 3) * 224, 376 + (index / 3 as int) * 90)
		feet.append(foot)
		var button := _building(Art.texture("ore_site"), foot, Vector2(156, 120), Vector2(78, 105))
		button.pressed.connect(func(): selected.emit(index))
		site_buttons.append(button)
		var number := GeneratedNumber.new()
		number.size = Vector2(24, 20)
		number.position = Vector2(112, 92)
		button.add_child(number)
		levels.append(number)
		var actor := Control.new()
		actor.mouse_filter = Control.MOUSE_FILTER_IGNORE
		actor.position = DEPOT
		actor.visible = false
		actor.set_meta("foot", DEPOT.y)
		add_child(actor)
		var body := TextureRect.new()
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		body.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		body.position = Vector2(-18, -39)
		body.size = Vector2(36, 42)
		actor.add_child(body)
		var cargo := TextureRect.new()
		cargo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cargo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		cargo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		cargo.position = Vector2(8, -29)
		cargo.size = Vector2(16, 16)
		actor.add_child(cargo)
		workers.append({"node": actor, "body": body, "cargo_sprite": cargo,
			"kind": -1, "tier": 1, "state": "outbound", "path": PackedVector2Array(),
			"path_index": 0, "wait": 0.0, "amount": 0, "resource": "stone", "left": false})
	_building(Art.texture("warehouse"), Vector2(352, 607), Vector2(164, 124), Vector2(82, 109)).mouse_filter = Control.MOUSE_FILTER_IGNORE
	bunker = _building(Art.texture("bunker_0"), BUNKER_FOOT, Vector2(138, 136), Vector2(69, 123))
	bunker.pressed.connect(func(): selected.emit(-1))
	refresh(model.store.data, 4)

func _building(texture: Texture2D, foot: Vector2, dimensions: Vector2, anchor: Vector2) -> TextureButton:
	var button := TextureButton.new()
	button.texture_normal = texture
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	button.position = foot - anchor
	button.size = dimensions
	button.set_meta("foot", foot.y)
	_mask(button)
	add_child(button)
	return button

func _mask(button: TextureButton) -> void:
	var bitmap := BitMap.new()
	bitmap.create_from_image_alpha(button.texture_normal.get_image(), 0.2)
	button.texture_click_mask = bitmap

func refresh(data: Dictionary, selected_slot: int) -> void:
	for index in range(9):
		var kind := int(data.buildings[index])
		var actor: Dictionary = workers[index]
		var button := site_buttons[index]
		var texture := Art.texture(KEYS[kind] if kind >= 0 else "ore_site")
		if button.texture_normal != texture:
			button.texture_normal = texture
			_mask(button)
		button.modulate = Color(1.16, 1.1, 0.86) if index == selected_slot else Color.WHITE
		levels[index].text = str(int(data.upgrades[index]) + 1) if kind >= 0 else ""
		actor.tier = int(data.upgrades[index]) + 1
		if actor.kind != kind:
			actor.kind = kind
			actor.amount = 0
			actor.node.position = DEPOT
			actor.node.visible = kind >= 0
			actor.state = "outbound"
			actor.wait = 0.0
			actor.cargo_sprite.visible = false
	_rebuild_paths()
	var texture := Art.texture("bunker_%d" % int(data.get("bunker_level", 0)))
	if bunker.texture_normal != texture:
		bunker.texture_normal = texture
		_mask(bunker)
	bunker.modulate = Color(1.15, 1.1, 0.86) if selected_slot == -1 else Color.WHITE
	_order()

func _rebuild_paths() -> void:
	navigation.fill_solid_region(navigation.region, false)
	for index in range(9):
		if workers[index].kind < 0:
			continue
		var foot := feet[index]
		for x in range(-2, 3):
			for y in range(-1, 1):
				var point := _grid(foot) + Vector2i(x, y)
				if navigation.region.has_point(point):
					navigation.set_point_solid(point)
	for index in range(9):
		var actor: Dictionary = workers[index]
		if actor.kind >= 0 and actor.state in ["outbound", "returning"]:
			_set_path(actor, feet[index] + Vector2(0, 28) if actor.state == "outbound" else DEPOT)

func _grid(point: Vector2) -> Vector2i:
	return Vector2i(roundi(point.x / 16), roundi(point.y / 16))

func _set_path(actor: Dictionary, destination: Vector2) -> void:
	actor.path = navigation.get_point_path(_grid(actor.node.position), _grid(destination))
	actor.path_index = 0

func _process(delta: float) -> void:
	if model == null or not is_visible_in_tree():
		return
	time += maxf(0.0, delta)
	clock += maxf(0.0, delta)
	ordering += maxf(0.0, delta)
	if clock >= 1.0:
		clock = 0.0
		if not model.stage_production():
			last_error = model.store.last_error
	for index in range(9):
		var actor: Dictionary = workers[index]
		if actor.kind < 0:
			continue
		if actor.state in ["outbound", "returning"]:
			if actor.path.is_empty():
				_set_path(actor, feet[index] + Vector2(0, 28) if actor.state == "outbound" else DEPOT)
				continue
			_move(actor, delta)
			if actor.path_index >= actor.path.size():
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
					_set_path(actor, DEPOT)
				else:
					actor.wait = 1.0
		var row := 4 if actor.state == "gathering" else (3 if actor.left else 2) if int(actor.amount) > 0 else (1 if actor.left else 0)
		actor.body.texture = frames[row * 8 + int(time * 8.0) % 8]
		actor.node.set_meta("foot", actor.node.position.y)
	if ordering >= 0.1:
		ordering = 0.0
		_order()

func _move(actor: Dictionary, delta: float) -> void:
	var budget := maxf(0.0, delta) * (42.0 + 10.0 * float(actor.tier))
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
	_set_path(actor, feet[index] + Vector2(0, 28))
	delivery.emit(String(result.resource), int(result.amount))

func dispatch() -> void:
	model.stage_production()
	for actor in workers:
		if actor.state == "gathering":
			actor.wait = 0.0

func _order() -> void:
	var items := get_children()
	items.sort_custom(func(a: Node, b: Node): return float(a.get_meta("foot", 0.0)) < float(b.get_meta("foot", 0.0)))
	for index in range(items.size()):
		move_child(items[index], index)
