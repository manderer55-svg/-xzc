extends SceneTree

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func _run() -> void:
	for level in range(1, 1001):
		var recipe: Dictionary = LevelGenerator.generate(level)
		_test_geometry(recipe.mask, "level %d" % level)
	var ring := BoardContour.geometry(LevelGenerator.generate(6).mask)
	_check(ring.loops.size() == 2, "ring outlines both outside and its central hole")
	_check(ring.loops.filter(func(loop: Dictionary): return int(loop.area_twice) < 0).size() == 1, "ring has one oppositely oriented hole boundary")
	var inner: Dictionary = ring.loops.filter(func(loop: Dictionary): return int(loop.area_twice) < 0)[0]
	_check(inner.edges.size() == 12, "ring's three-by-three hole has all twelve inner edges")
	_test_geometry([Vector2i(0, 0), Vector2i(1, 1)], "diagonally touching cells")
	var diagonals := BoardContour.geometry([Vector2i(0, 0), Vector2i(1, 1)])
	_check(diagonals.loops.size() == 2, "diagonal contacts keep both boundary strands closed")
	_test_geometry([], "empty mask")
	_test_render_nodes()
	await process_frame
	if failures.is_empty():
		print("PASS: %d board-contour checks (1,000 masks, all exposed edges, holes, closed loops, stable artwork thickness)." % checks)
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
		quit(1)


func _test_geometry(mask: Array, label: String) -> void:
	var occupied: Dictionary = {}
	for cell: Vector2i in mask:
		occupied[cell] = true
	var expected: Dictionary = {}
	for cell: Vector2i in occupied:
		for side in range(4):
			if not occupied.has(cell + [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT][side]):
				expected[Vector3i(cell.x, cell.y, side)] = true
	var shape := BoardContour.geometry(mask)
	_check(bool(shape.valid), label + ": every outline strand closes")
	var reversed: Array = mask.duplicate()
	reversed.reverse()
	_check(shape == BoardContour.geometry(reversed), label + ": outline is independent of mask insertion order")
	var found: Dictionary = {}
	for edge: Dictionary in shape.edges:
		var cell: Vector2i = edge.cell
		var key := Vector3i(cell.x, cell.y, int(edge.side))
		_check(expected.has(key), label + ": no internal edge drawn")
		_check(not found.has(key), label + ": exposed edge drawn exactly once")
		found[key] = true
	_check(found == expected, label + ": all exposed edges included")
	var visited: Dictionary = {}
	var area := 0
	for loop: Dictionary in shape.loops:
		_check(bool(loop.closed), label + ": closed boundary path")
		area += int(loop.area_twice)
		for index in range(loop.edges.size()):
			var edge_index: int = loop.edges[index]
			var next_index: int = loop.edges[(index + 1) % loop.edges.size()]
			_check(shape.edges[edge_index].to == shape.edges[next_index].from, label + ": consecutive pieces meet at a vertex")
			_check(not visited.has(edge_index), label + ": edge belongs to exactly one loop")
			visited[edge_index] = true
	_check(visited.size() == expected.size(), label + ": loops cover whole contour")
	_check(area == occupied.size() * 2, label + ": signed outline area matches occupied cells including holes")


func _test_render_nodes() -> void:
	var contour := BoardContour.new()
	root.add_child(contour)
	var mask: Array = LevelGenerator.generate(6).mask
	var spec: Dictionary = Art.contour_spec()
	contour.configure(mask, Vector2(30, 40), 62)
	_check(contour.mouse_filter == Control.MOUSE_FILTER_IGNORE, "contour container never intercepts gestures")
	_check(contour.edge_nodes.size() == contour.topology.edges.size(), "one generated strip per exposed edge")
	_check(contour.corner_nodes.size() == contour.topology.corners.size(), "every turn uses generated corner artwork")
	for node: TextureRect in contour.edge_nodes.values():
		_check(_same_artwork(node.texture, spec.edge) and is_equal_approx(node.size.y, float(spec.edge_height)), "straight strip uses original artwork at fixed thickness")
		_check(node.mouse_filter == Control.MOUSE_FILTER_IGNORE, "straight strips do not intercept gestures")
	for node in contour.corner_nodes:
		_check(_same_artwork(node.texture, spec.convex) or _same_artwork(node.texture, spec.concave), "corner uses original generated artwork")
		_check(node.size == Vector2.ONE * float(spec.corner_size), "corner size stays independent of cell size")
	var shape := contour.topology.duplicate(true)
	contour.configure(mask, Vector2(30, 40), 78)
	_check(contour.topology == shape, "changing display cell size retains the exact mask outline")
	for node: TextureRect in contour.edge_nodes.values():
		_check(is_equal_approx(node.size.y, float(spec.edge_height)), "larger cells preserve rim thickness")
	for node in contour.corner_nodes:
		_check(node.size == Vector2.ONE * float(spec.corner_size), "larger cells preserve corner dimensions")
	contour.queue_free()


func _same_artwork(first: Texture2D, second: Texture2D) -> bool:
	return first is AtlasTexture and second is AtlasTexture and first.atlas == second.atlas and first.region == second.region
