extends SceneTree

const Map = preload("res://scripts/colony_map.gd")
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	check(Map.WIDTH == 30 and Map.HEIGHT == 30 and Map.SLOT_COUNT == 64, "expansive 30 by 30 map with 64 buildable sites")
	var terrains: Dictionary = {}
	var decorations: Dictionary = {}
	var navigation := AStarGrid2D.new()
	navigation.region = Rect2i(0, 0, Map.WIDTH, Map.HEIGHT)
	navigation.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	navigation.update()
	for y in range(Map.HEIGHT):
		for x in range(Map.WIDTH):
			var cell := Vector2i(x, y)
			var projected: Vector2 = Map.iso(cell)
			check(Map.cell_at(projected) == cell, "isometric round trip at %s" % cell)
			check(Map.cell_at(projected + Vector2(20, 4)) == cell, "interior tap belongs to its ground tile at %s" % cell)
			var terrain: int = Map.terrain_at(cell)
			var decor: int = Map.decor_at(cell)
			check(terrain >= 0 and terrain < Map.TERRAIN_NAMES.size(), "generated terrain index at %s" % cell)
			check(decor >= -1 and decor < Map.DECOR_NAMES.size(), "generated decoration index at %s" % cell)
			terrains[terrain] = int(terrains.get(terrain, 0)) + 1
			decorations[decor] = int(decorations.get(decor, 0)) + 1
			var walkable: bool = Map.is_walkable(cell)
			navigation.set_point_solid(cell, not walkable)
			if Map.is_road(cell):
				check(walkable and decor == -1, "roads never intersect blocking scenery at %s" % cell)
			if decor in [0, 1, 2, 3, 4]:
				check(not walkable, "visible tree, rock or deposit blocks walking at %s" % cell)
	check(int(terrains.get(7, 0)) >= 8 and int(decorations.get(0, 0)) + int(decorations.get(1, 0)) >= 8, "forest has actual ground and solid trees")
	check(int(terrains.get(3, 0)) >= 8 and int(decorations.get(5, 0)) >= 5, "fields contain crops beyond construction plots")
	check(int(terrains.get(6, 0)) >= 8 and int(decorations.get(3, 0)) >= 4, "stone deposits have visible ore")
	check(int(terrains.get(8, 0)) >= 8 and int(decorations.get(4, 0)) >= 4, "crystal deposit region remains populated")
	check(terrains.size() >= 8, "landscape contains varied ground")
	var sites: Dictionary = {}
	var footprints: Dictionary = {}
	var quadrants: Dictionary = {}
	for slot in range(Map.SLOT_COUNT):
		var cell: Vector2i = Map.slot_cell(slot)
		check(Map.contains(cell) and not sites.has(cell), "site %d is a distinct map cell" % slot)
		sites[cell] = true
		quadrants[Vector2i(int(cell.x >= 15), int(cell.y >= 15))] = true
		if slot < 9:
			check(cell == Vector2i(11 + (slot % 3) * 3, 10 + (slot / 3) * 3), "legacy site %d keeps a stable position" % slot)
		var footprint: Array[Vector2i] = Map.footprint_cells(slot)
		check(footprint.size() == 4, "building %d occupies a real two by two footprint" % slot)
		for occupied in footprint:
			check(Map.contains(occupied) and not footprints.has(occupied), "site %d foundation cannot overlap another building" % slot)
			check(not Map.is_walkable(occupied) and Map.decor_at(occupied) == -1, "site %d foundation stays clear of scenery and walking" % slot)
			footprints[occupied] = true
		var access: Vector2i = Map.slot_access(slot)
		check(Map.is_walkable(access), "site %d has a walkable entrance" % slot)
		var route: Array[Vector2i] = navigation.get_id_path(Map.DEPOT_ACCESS, access)
		check(not route.is_empty() and route[0] == Map.DEPOT_ACCESS and route[-1] == access, "site %d has an actual warehouse route" % slot)
		for index in range(route.size()):
			check(Map.is_walkable(route[index]), "site %d route stays on navigable ground" % slot)
			if index > 0:
				check((route[index] - route[index - 1]).length_squared() == 1, "site %d route cannot jump over an obstacle" % slot)
	check(quadrants.size() == 4, "construction sites span every quarter of the map")
	check(not navigation.get_id_path(Map.DEPOT_ACCESS, Map.BUNKER_ACCESS).is_empty(), "bunker approach remains reachable")
	for cell in [Vector2i(-1, 0), Vector2i(0, -1), Vector2i(30, 29), Vector2i(29, 30)]:
		check(not Map.contains(cell) and not Map.is_walkable(cell) and Map.terrain_at(cell) == -1, "outside ground rejects navigation at %s" % cell)
	check(Map.slot_cell(-1) == Vector2i(-1, -1) and Map.slot_access(64) == Vector2i(-1, -1), "invalid construction indices have no map position")
	if failures.is_empty():
		print("PASS: %d colony map checks (30x30 projection, forest, fields, deposits, 64 disjoint foundations and reachable approaches)." % checks)
		print("COLONY_MAP_TERRAINS: %s; DECORATIONS: %s" % [terrains, decorations])
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
		quit(1)


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
