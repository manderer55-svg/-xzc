extends SceneTree

const Generator = preload("res://scripts/level_generator.gd")
const EngineModel = preload("res://scripts/match_engine.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_test_levels()
	_test_swap_rules()
	_test_special_creation()
	_test_special_chains()
	_test_gravity()
	_test_playthroughs()
	_check(checks >= 55000, "full validation suite executed")
	if failures.is_empty():
		print("PASS: %d match engine checks (1,000 generated levels, specials, blockers, gravity, turns)." % checks)
		quit(0)
	else:
		for failure in failures:
			printerr(failure)
		quit(1)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append("FAIL: " + message)

func _connected(mask: Array) -> bool:
	var visited: Dictionary = {mask[0]: true}
	var pending: Array = [mask[0]]
	while not pending.is_empty():
		var position: Vector2i = pending.pop_front()
		for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var neighbor: Vector2i = position + direction
			if neighbor in mask and not visited.has(neighbor):
				visited[neighbor] = true
				pending.append(neighbor)
	return visited.size() == mask.size()

func _test_levels() -> void:
	var shapes: Dictionary = {}
	for level in range(1, 1001):
		var recipe: Dictionary = Generator.generate(level)
		_check(recipe == Generator.generate(level), "level %d recipe is deterministic" % level)
		_check(_connected(recipe.mask), "level %d mask is connected" % level)
		_check(recipe.mask.size() >= 20, "level %d has sufficient cells" % level)
		shapes[recipe.shape] = true
		var engine = EngineModel.new()
		engine.initialize(level)
		_check(engine.cells.size() == recipe.mask.size(), "level %d fills mask exactly" % level)
		_check(engine.find_matches().is_empty(), "level %d starts without matches" % level)
		var legal: Array = engine.legal_moves()
		_check(not legal.is_empty(), "level %d starts with legal move" % level)
		for position in engine.cells:
			_check(position in recipe.mask, "all crystals inside level %d mask" % level)
		if level <= 40 or level % 100 == 0:
			var twin = EngineModel.new()
			twin.initialize(level)
			_check(engine.snapshot() == twin.snapshot(), "level %d board deterministic" % level)
			if not legal.is_empty():
				var outcome: Dictionary = engine.try_swap(legal[0][0], legal[0][1])
				var twin_outcome: Dictionary = twin.try_swap(legal[0][0], legal[0][1])
				_check(outcome == twin_outcome, "level %d simulation deterministic" % level)
				_check(outcome.valid and outcome.score_delta > 0, "level %d legal swap resolves" % level)
				_check(engine.cells.size() == recipe.mask.size(), "level %d refill preserves mask" % level)
				_check(engine.find_matches().is_empty(), "level %d resolves all cascades" % level)
				_check(not engine.legal_moves().is_empty(), "level %d remains playable" % level)
	_check(shapes.size() == 8, "eight distinct silhouettes generated")
	var beyond: Dictionary = Generator.generate(10001)
	_check(beyond.level == 10001 and _connected(beyond.mask), "generator extends beyond 1,000 levels")

func _fixture(width: int = 7, height: int = 7):
	var engine = EngineModel.new()
	engine.initialize(1)
	engine.width = width
	engine.height = height
	engine.blockers.clear()
	engine.cells.clear()
	var mask: Array[Vector2i] = []
	for y in range(height):
		for x in range(width):
			var position := Vector2i(x, y)
			mask.append(position)
			engine.cells[position] = {"color": (x + y * 2) % 6, "special": ""}
	engine.level_data.mask = mask
	engine.level_data.target = 999999
	engine.level_data.objective = {"kind": "score", "target": 999999, "color": 0}
	return engine

func _test_swap_rules() -> void:
	var engine = _fixture()
	var before: Dictionary = engine.snapshot()
	var original_moves: int = engine.moves
	_check(not engine.try_swap(Vector2i(0, 0), Vector2i(6, 6)).valid, "non-neighbor swap rejected")
	_check(engine.snapshot() == before and engine.moves == original_moves, "invalid neighbor geometry preserves state")
	_check(not engine.try_swap(Vector2i(0, 0), Vector2i(1, 0)).valid, "non-matching swap rejected")
	_check(engine.snapshot() == before and engine.moves == original_moves, "rejected swap restored exactly")
	engine.blockers[Vector2i(0, 0)] = 2
	_check(not engine.try_swap(Vector2i(0, 0), Vector2i(1, 0)).valid, "sealed crystal cannot be swapped")
	_check(not engine.try_swap(Vector2i(-1, 0), Vector2i(0, 0)).valid, "outside board swap rejected")
	engine.moves = 0
	_check(engine.is_lost(), "zero moves loses below target")
	_check(not engine.try_swap(Vector2i(1, 0), Vector2i(2, 0)).valid, "finished level rejects input")
	engine.score = engine.level_data.target
	_check(engine.is_won() and not engine.is_lost(), "winning takes priority on final move")
	before = engine.snapshot()
	var terminal_score: int = engine.score
	var terminal_resources: Dictionary = engine.collected.duplicate(true)
	for _attempt in range(3):
		var repeated: Dictionary = engine.try_swap(Vector2i(1, 0), Vector2i(2, 0))
		_check(not repeated.valid and repeated.won and not repeated.lost, "repeated winning input remains terminal")
	_check(engine.snapshot() == before and engine.score == terminal_score and engine.collected == terminal_resources and engine.moves == 0, "terminal calls preserve board, rewards and turns")

func _test_special_creation() -> void:
	for length in [4, 5]:
		var engine = _fixture()
		for x in range(length):
			engine.cells[Vector2i(x, 3)].color = 0
		var groups: Array = engine.find_matches()
		var step: Dictionary = engine._resolve(groups, [], {}, 1, [Vector2i(1, 3)])
		var expected := "row" if length == 4 else "nova"
		var found := false
		for special in step.spawned:
			if special.special == expected:
				found = true
		_check(found, "%d line creates %s" % [length, expected])
	var engine = _fixture()
	for position in [Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2), Vector2i(3, 3), Vector2i(3, 4)]:
		engine.cells[position].color = 5
	var step: Dictionary = engine._resolve(engine.find_matches(), [], {}, 1, [Vector2i(3, 2)])
	var found := false
	for special in step.spawned:
		if special.special == "bomb":
			found = true
	_check(found, "T intersection creates explosion bomb")
	engine = _fixture()
	for y in range(1, 5):
		engine.cells[Vector2i(3, y)].color = 0
	step = engine._resolve(engine.find_matches(), [], {}, 1, [Vector2i(3, 2)])
	found = false
	for special in step.spawned:
		if special.special == "column":
			found = true
	_check(found, "vertical four creates column lightning")
	engine = _fixture()
	for x in range(4):
		engine.cells[Vector2i(x, 3)].color = 0
	engine.cells[Vector2i(1, 3)].special = "row"
	step = engine._resolve(engine.find_matches(), [], {}, 1, [Vector2i(1, 3)])
	found = false
	for special in step.spawned:
		if special.special == "row" and special.position != Vector2i(1, 3):
			found = true
	_check(found and step.activated.size() == 1, "four containing old lightning detonates it and creates new lightning")

func _test_special_chains() -> void:
	var engine = _fixture()
	engine.cells[Vector2i(1, 3)].special = "row"
	engine.cells[Vector2i(5, 3)].special = "column"
	engine.blockers[Vector2i(4, 3)] = 1
	var outcome: Dictionary = engine.try_swap(Vector2i(1, 3), Vector2i(2, 3))
	_check(outcome.valid, "special swap is legal without regular match")
	var first: Dictionary = outcome.steps[0]
	_check(first.activated.size() >= 2, "lightning triggers chained column special")
	_check(Vector2i(4, 3) in first.blocker_hits and not engine.blockers.has(Vector2i(4, 3)), "lightning destroys direct blocker")
	_check(first.removed.size() >= 10, "row and column clear extended area")
	_check(engine.moves == engine.level_data.moves - 1, "valid turn consumes one move across cascades")
	_check(outcome.score_delta == engine.score and engine.score > 0, "score delta matches aggregate scoring")
	var total := 0
	for count in engine.collected.values():
		total += count
	var destroyed := 0
	for step in outcome.steps:
		destroyed += step.removed.size()
	_check(total == destroyed, "resource counts equal destroyed crystals")
	engine = _fixture()
	engine.cells[Vector2i(0, 0)].special = "nova"
	var target_color: int = engine.cells[Vector2i(1, 0)].color
	var expected := 0
	for position in engine.cells:
		if engine.cells[position].color == target_color:
			expected += 1
	outcome = engine.try_swap(Vector2i(0, 0), Vector2i(1, 0))
	_check(outcome.steps[0].removed.size() >= expected, "nova clears swapped crystal color")
	engine = _fixture()
	engine.cells[Vector2i(0, 0)].special = "nova"
	engine.cells[Vector2i(1, 0)].special = "nova"
	outcome = engine.try_swap(Vector2i(0, 0), Vector2i(1, 0))
	_check(outcome.steps[0].removed.size() == 49, "double nova clears complete unsealed board")

func _test_gravity() -> void:
	var engine = _fixture(3, 7)
	var hole := Vector2i(1, 3)
	engine.level_data.mask.erase(hole)
	engine.cells.erase(hole)
	engine.cells[Vector2i(1, 0)].special = "row"
	engine.cells[Vector2i(1, 4)].special = "bomb"
	engine.cells.erase(Vector2i(1, 2))
	engine.cells.erase(Vector2i(1, 6))
	engine._refill()
	_check(not engine.cells.has(hole), "gravity never fills mask hole")
	_check(engine.cells[Vector2i(1, 1)].special == "row", "upper segment settles independently")
	_check(engine.cells[Vector2i(1, 5)].special == "bomb", "lower segment settles independently")
	_check(engine.cells.size() == engine.level_data.mask.size(), "segmented gravity preserves exact occupancy")
	engine = _fixture(3, 7)
	engine.blockers[Vector2i(1, 3)] = 2
	var sealed_before: Dictionary = engine.cells[Vector2i(1, 3)].duplicate(true)
	engine.cells[Vector2i(1, 0)].special = "row"
	engine.cells.erase(Vector2i(1, 2))
	engine._refill()
	_check(engine.cells[Vector2i(1, 3)] == sealed_before, "sealed crystals remain fixed during gravity")
	_check(engine.cells[Vector2i(1, 1)].special == "row", "sealed crystal separates gravity segments")
	engine = _fixture()
	_check(engine._plant_legal_move(), "deadlock repair can plant known move")
	_check(engine.find_matches().is_empty() and not engine.legal_moves().is_empty(), "planted move avoids free matches")
	engine.shuffle()
	_check(engine.find_matches().is_empty() and not engine.legal_moves().is_empty(), "shuffle preserves playable settled board")

func _test_playthroughs() -> void:
	# Exercise complete turn budgets across early and late shapes and blockers.
	for index in range(80):
		var level := 1 + index * 13
		var engine = EngineModel.new()
		engine.initialize(level)
		var previous_score := 0
		var previous_moves: int = engine.moves
		while not engine.is_won() and not engine.is_lost():
			var possible: Array = engine.legal_moves()
			_check(not possible.is_empty(), "playthrough %d never deadlocks" % level)
			if possible.is_empty():
				break
			var chosen: Array = possible[(engine.moves + level) % possible.size()]
			var outcome: Dictionary = engine.try_swap(chosen[0], chosen[1])
			_check(outcome.valid and engine.moves == previous_moves - 1, "playthrough %d accounts for turns" % level)
			_check(engine.score > previous_score and outcome.score_delta == engine.score - previous_score, "playthrough %d score monotonically increases" % level)
			_check(engine.find_matches().is_empty() and engine.cells.size() == engine.level_data.mask.size(), "playthrough %d ends settled with exact occupancy" % level)
			previous_score = engine.score
			previous_moves = engine.moves
		_check(engine.is_won() or engine.is_lost(), "playthrough %d reaches terminal state" % level)
