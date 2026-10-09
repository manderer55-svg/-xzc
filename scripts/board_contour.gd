class_name BoardContour
extends Control
## Exposed cell edges arrange generated strips and corner sprites. The mask,
## including holes, determines the outline; no lines or replacement art are drawn.

const DIRECTIONS := [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
const NEIGHBORS := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
const OFFSETS := [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.ONE, Vector2i.DOWN]

var topology: Dictionary = {}
var edge_nodes: Dictionary = {}
var corner_nodes: Array[TextureRect] = []
var rebuild_count := 0
var tile_width := 0.0


static func geometry(mask: Array) -> Dictionary:
	var occupied: Dictionary = {}
	for cell: Vector2i in mask:
		occupied[cell] = true
	var ordered: Array = occupied.keys()
	ordered.sort_custom(func(a: Vector2i, b: Vector2i): return a.y < b.y or (a.y == b.y and a.x < b.x))
	var edges: Array[Dictionary] = []
	var outgoing: Dictionary = {}
	for cell: Vector2i in ordered:
		for side in range(4):
			if occupied.has(cell + NEIGHBORS[side]):
				continue
			var start: Vector2i = cell + OFFSETS[side]
			var finish: Vector2i = start + DIRECTIONS[side]
			var index := edges.size()
			edges.append({"from": start, "to": finish, "cell": cell, "side": side,
				"direction": side, "start_corner": false, "end_corner": false})
			if not outgoing.has(start):
				outgoing[start] = []
			outgoing[start].append(index)
	var visited: Dictionary = {}
	var loops: Array[Dictionary] = []
	var corners: Array[Dictionary] = []
	var valid := true
	for initial in range(edges.size()):
		if visited.has(initial):
			continue
		var path: Array[int] = []
		var current := initial
		var closed := false
		var area_twice := 0
		while current >= 0:
			if visited.has(current):
				closed = current == initial
				break
			visited[current] = true
			path.append(current)
			var edge: Dictionary = edges[current]
			var start: Vector2i = edge.from
			var finish: Vector2i = edge.to
			area_twice += start.x * finish.y - finish.x * start.y
			var next := -1
			# At diagonal contacts the right turn keeps separate boundary strands
			# attached to their own occupied cells instead of joining across a hole.
			for turn in [1, 0, 3, 2]:
				for candidate: int in outgoing.get(finish, []):
					if visited.has(candidate) and candidate != initial:
						continue
					if (int(edges[candidate].direction) - int(edge.direction) + 4) % 4 == turn:
						next = candidate
						break
				if next >= 0:
					break
			current = next
		valid = valid and closed
		var loop_index := loops.size()
		loops.append({"edges": path, "closed": closed, "area_twice": area_twice})
		if not closed:
			continue
		for index in range(path.size()):
			var before := path[(index - 1 + path.size()) % path.size()]
			var after := path[index]
			var turn := (int(edges[after].direction) - int(edges[before].direction) + 4) % 4
			if turn == 0:
				continue
			valid = valid and turn != 2
			edges[before].end_corner = true
			edges[after].start_corner = true
			corners.append({"vertex": edges[after].from, "turn": turn,
				"incoming": edges[before].direction, "outgoing": edges[after].direction,
				"before": before, "after": after, "loop": loop_index})
	return {"edges": edges, "loops": loops, "corners": corners, "valid": valid}


func configure(mask: Array, origin: Vector2, cell_width: float) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	edge_nodes.clear()
	corner_nodes.clear()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = origin
	tile_width = cell_width
	topology = geometry(mask)
	rebuild_count += 1
	var spec: Dictionary = Art.contour_spec()
	var thickness := float(spec.edge_height)
	var corner_width := float(spec.corner_size)
	var radius := corner_width * 0.5
	var trim := maxf(0.0, radius - float(spec.get("edge_overlap", 0.0)))
	for index in range(topology.edges.size()):
		var edge: Dictionary = topology.edges[index]
		var direction := Vector2(DIRECTIONS[int(edge.direction)])
		var angle := int(edge.direction) * PI * 0.5
		var start := Vector2(edge.from) * cell_width
		var length := cell_width
		if bool(edge.start_corner):
			start += direction * trim
			length -= trim
		if bool(edge.end_corner):
			length -= trim
		var node := _piece(spec.edge, Vector2(maxf(0.0, length), thickness))
		node.position = start + Vector2(0, -thickness * 0.5).rotated(angle)
		node.rotation = angle
		edge_nodes[index] = node
	for corner: Dictionary in topology.corners:
		var texture: Texture2D = spec.convex if int(corner.turn) == 1 else spec.concave
		var node := _piece(texture, Vector2.ONE * corner_width)
		node.pivot_offset = Vector2.ONE * radius
		node.position = Vector2(corner.vertex) * cell_width - Vector2.ONE * radius
		node.rotation = int(corner.incoming) * PI * 0.5
		corner_nodes.append(node)


func _piece(texture: Texture2D, dimensions: Vector2) -> TextureRect:
	var node := TextureRect.new()
	node.texture = texture
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_SCALE
	node.size = dimensions
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(node)
	return node
