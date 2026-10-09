class_name ColonyMap
extends RefCounted
## Deterministic, navigable terrain for the expansive colony. Art is rendered separately.

const WIDTH := 30
const HEIGHT := 30
const SLOT_COUNT := 64
const TILE_SIZE := Vector2(128.0, 64.0)
const DEPOT_CELL := Vector2i(14, 19)
const BUNKER_CELL := Vector2i(19, 19)
const DEPOT_ACCESS := Vector2i(14, 20)
const BUNKER_ACCESS := Vector2i(19, 20)
const DIRECTIONS := [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]
const TERRAIN_NAMES := ["grass", "dirt", "rock", "wheatfield", "darkgrass", "road", "stonepatch", "forestground", "crystalground"]
const DECOR_NAMES := ["tree", "cluster", "rock", "ore", "crystal", "fieldcrops", "bush", "stump"]

static var _slots: Array[Vector2i] = []
static var _terrain := PackedInt32Array()
static var _decor := PackedInt32Array()
static var _reserved: Dictionary = {}
static var _roads: Dictionary = {}


static func iso(cell: Vector2i) -> Vector2:
	return Vector2((cell.x - cell.y) * 64.0, (cell.x + cell.y) * 32.0)


static func cell_at(world: Vector2) -> Vector2i:
	return Vector2i(roundi(world.x / 128.0 + world.y / 64.0), roundi(world.y / 64.0 - world.x / 128.0))


static func contains(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < WIDTH and cell.y < HEIGHT


static func slot_cell(index: int) -> Vector2i:
	_ensure_slots()
	return _slots[index] if index >= 0 and index < SLOT_COUNT else Vector2i(-1, -1)


static func slot_access(index: int) -> Vector2i:
	return slot_cell(index) + Vector2i(0, 1) if index >= 0 and index < SLOT_COUNT else Vector2i(-1, -1)


static func footprint_cells(index: int) -> Array[Vector2i]:
	if index < 0 or index >= SLOT_COUNT:
		return []
	return _footprint(slot_cell(index))


static func terrain_at(cell: Vector2i) -> int:
	if not contains(cell):
		return -1
	_ensure_map()
	return _terrain[_index(cell)]


static func decor_at(cell: Vector2i) -> int:
	if not contains(cell):
		return -1
	_ensure_map()
	return _decor[_index(cell)]


static func is_walkable(cell: Vector2i) -> bool:
	if not contains(cell):
		return false
	_ensure_map()
	# Reserved mine foundations and all visible solid trees/rocks share navigation data.
	if _reserved.has(cell):
		return false
	return _decor[_index(cell)] not in [0, 1, 2, 3, 4]


static func is_road(cell: Vector2i) -> bool:
	_ensure_map()
	return _roads.has(cell)


static func _ensure_slots() -> void:
	if not _slots.is_empty():
		return
	# These nine indices preserve saves from the compact colony.
	for y in [10, 13, 16]:
		for x in [11, 14, 17]:
			_slots.append(Vector2i(x, y))
	var candidates: Array[Vector2i] = []
	for y in range(2, 27, 3):
		for x in range(2, 27, 3):
			var cell := Vector2i(x, y)
			var available := true
			for existing in _slots:
				if absi(cell.x - existing.x) <= 2 and absi(cell.y - existing.y) <= 2:
					available = false
			for landmark in [DEPOT_CELL, BUNKER_CELL]:
				if absi(cell.x - landmark.x) <= 2 and absi(cell.y - landmark.y) <= 2:
					available = false
			if available:
				candidates.append(cell)
	# Fixed distribution spreads construction across every quadrant, never depending on load order.
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var order_a := _hash(a, 113)
		var order_b := _hash(b, 113)
		return order_a < order_b if order_a != order_b else _index(a) < _index(b)
	)
	for cell in candidates:
		if _slots.size() == SLOT_COUNT:
			break
		_slots.append(cell)
	assert(_slots.size() == SLOT_COUNT, "The colony requires exactly 64 construction sites.")


static func _ensure_map() -> void:
	if not _terrain.is_empty():
		return
	_ensure_slots()
	var clearances: Dictionary = {}
	for foot in _slots + [DEPOT_CELL, BUNKER_CELL]:
		for cell in _footprint(foot):
			_reserved[cell] = true
			clearances[cell] = true
		clearances[foot + Vector2i(0, 1)] = true
	_connect_roads()
	_terrain.resize(WIDTH * HEIGHT)
	_decor.resize(WIDTH * HEIGHT)
	for y in range(HEIGHT):
		for x in range(WIDTH):
			var cell := Vector2i(x, y)
			var terrain := _natural_terrain(cell)
			var decoration := _natural_decor(cell, terrain)
			if clearances.has(cell):
				terrain = 1
				decoration = -1
			if _roads.has(cell):
				terrain = 5
				decoration = -1
			_terrain[_index(cell)] = terrain
			_decor[_index(cell)] = decoration


static func _connect_roads() -> void:
	# One breadth-first tree gives every site an actual route around all construction footprints.
	var parents: Dictionary = {DEPOT_ACCESS: DEPOT_ACCESS}
	var queue: Array[Vector2i] = [DEPOT_ACCESS]
	var cursor := 0
	while cursor < queue.size():
		var current := queue[cursor]
		cursor += 1
		for direction in DIRECTIONS:
			var next: Vector2i = current + direction
			if contains(next) and not _reserved.has(next) and not parents.has(next):
				parents[next] = current
				queue.append(next)
	var destinations: Array[Vector2i] = [BUNKER_ACCESS]
	for slot in range(SLOT_COUNT):
		destinations.append(slot_access(slot))
	for destination in destinations:
		assert(parents.has(destination), "Every mine approach must connect to the warehouse.")
		var current := destination
		while current != DEPOT_ACCESS:
			_roads[current] = true
			current = parents[current]
		_roads[DEPOT_ACCESS] = true


static func _natural_terrain(cell: Vector2i) -> int:
	var patch := Vector2i(cell.x / 3, cell.y / 3)
	var variation := _hash(patch, 41) % 100
	if cell.x >= 21 and cell.y <= 12:
		return 8 if (cell - Vector2i(25, 7)).length_squared() < 28 else (6 if variation < 38 else 2)
	if cell.x + cell.y < 11:
		return 6 if variation < 40 else 2
	if cell.x >= 20 and cell.y >= 16:
		return 3 if variation < 76 else 0
	if cell.x < 10 or cell.y < 8:
		return 7 if variation < 74 else 4
	return 4 if variation < 30 else 0


static func _natural_decor(cell: Vector2i, terrain: int) -> int:
	var chance := _hash(cell, 79) % 100
	match terrain:
		7:
			return (1 if chance < 15 else 0) if chance < 60 else (6 if chance < 75 else -1)
		4:
			return 0 if chance < 15 else (6 if chance < 35 else -1)
		2:
			return 2 if chance < 29 else (7 if chance < 36 else -1)
		6:
			return 3 if chance < 39 else (2 if chance < 55 else -1)
		8:
			return 4 if chance < 45 else -1
		3:
			return 5 if chance < 86 else -1
		_:
			return 6 if chance < 10 else (7 if chance < 13 else -1)


static func _footprint(foot: Vector2i) -> Array[Vector2i]:
	return [foot, foot + Vector2i(-1, 0), foot + Vector2i(0, -1), foot + Vector2i(-1, -1)]


static func _index(cell: Vector2i) -> int:
	return cell.y * WIDTH + cell.x


static func _hash(cell: Vector2i, salt: int) -> int:
	return absi((cell.x * 73856093) ^ (cell.y * 19349663) ^ (salt * 83492791))
