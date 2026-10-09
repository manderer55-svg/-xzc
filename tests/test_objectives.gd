extends SceneTree

const Generator = preload("res://scripts/level_generator.gd")
const EngineModel = preload("res://scripts/match_engine.gd")
var checks := 0
var completed_sections := 0
var failures: Array[String] = []

func _initialize() -> void:
	_test_recipes()
	_test_counters()
	_test_boss()
	_test_bonuses()
	_test_cloning()
	_test_balance()
	_check(completed_sections == 6, "all objective test sections executed")
	if failures.is_empty():
		print("PASS: %d objective checks (missions, boss cadence, bonuses, deterministic previews)." % checks)
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
		quit(1)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func _test_recipes() -> void:
	var kinds: Dictionary = {}
	var target_colors: Dictionary = {"collect": {}, "boss": {}}
	for level in range(1, 1001):
		var recipe: Dictionary = Generator.generate(level)
		var objective: Dictionary = recipe.objective
		kinds[objective.kind] = true
		if target_colors.has(objective.kind):
			var histogram: Dictionary = target_colors[objective.kind]
			histogram[objective.color] = int(histogram.get(objective.color, 0)) + 1
		_check(recipe.region in Generator.REGIONS, "region is included in level %d" % level)
		_check(int(objective.target) > 0, "level %d objective requires actual work" % level)
		_check((objective.kind == "boss") == (level % 10 == 0), "boss appears every tenth level %d" % level)
		if objective.kind == "seals":
			_check(recipe.blockers.size() >= 3 and objective.target == recipe.blockers.size(), "seal objective tracks all original seals at level %d" % level)
		if objective.kind == "altars":
			_check(recipe.altars.size() == 3, "three altars placed at level %d" % level)
			for altar in recipe.altars:
				_check(altar in recipe.mask and not recipe.blockers.has(altar), "altar occupies usable slot at level %d" % level)
		if objective.kind == "boss":
			_check(recipe.boss.hp == objective.target and recipe.boss.attack_every == 3, "boss recipe has consistent health and cadence")
	_check(kinds.size() == 6, "six genuinely different mission kinds")
	_check(target_colors.collect.size() == 6 and target_colors.boss.size() == 6, "collection and boss missions vary across all six gem colors")
	print("MISSION COLORS (first 1,000 levels): ", target_colors)
	completed_sections += 1

func _fixture(kind: String, target: int = 999999, color: int = 5):
	var engine = EngineModel.new()
	engine.initialize(1)
	engine.level_data.objective = {"kind": kind, "target": target, "color": color}
	engine.level_data.boss = {"name": "Страж корней", "hp": target, "weak_color": color, "attack_every": 3} if kind == "boss" else {}
	engine.boss_hp = target if kind == "boss" else 0
	engine.boss_max_hp = engine.boss_hp
	engine.cells.clear()
	engine.blockers.clear()
	engine._original_seals.clear()
	engine._seals_destroyed = 0
	engine.altars.clear()
	for position in engine.level_data.mask:
		engine.cells[position] = {"color": (position.x + position.y * 2) % 6, "special": ""}
	return engine

func _make_row(engine, y: int, color: int) -> void:
	for x in range(3):
		engine.cells[Vector2i(x, y)].color = color

func _test_counters() -> void:
	var engine = _fixture("collect", 3)
	engine.score = 999999
	engine.collected[0] = 99
	_check(not engine.is_won(), "high score and wrong crystals cannot win collection mission")
	_make_row(engine, 3, 5)
	var step: Dictionary = engine._resolve(engine.find_matches(), [], {}, 1, [])
	_check(engine.objective_state().current == 3 and engine.is_won(), "removed requested crystals complete collection")
	_check(step.objective.complete and step.objective.kind == "collect", "step carries current mission state")
	engine = _fixture("seals", 1)
	engine.blockers[Vector2i(3, 3)] = 2
	engine.blockers[Vector2i(3, 5)] = 1
	engine._original_seals[Vector2i(3, 3)] = 2
	engine.cells[Vector2i(1, 5)].special = "row"
	step = engine._resolve([], [Vector2i(1, 5)], {}, 1, [])
	_check(engine.objective_state().current == 0, "new non-objective seals do not count as original seals")
	_make_row(engine, 3, 5)
	step = engine._resolve(engine.find_matches(), [], {}, 1, [])
	_check(engine.blockers[Vector2i(3, 3)] == 1 and not engine.is_won(), "damaging a seal is not destroying it")
	_make_row(engine, 3, 5)
	step = engine._resolve(engine.find_matches(), [], {}, 1, [])
	_check(engine.objective_state().current == 1 and engine.is_won(), "original seal destruction completes mission")
	engine = _fixture("altars", 2)
	engine.altars = {Vector2i(2, 3): false, Vector2i(2, 4): false}
	engine.score = 999999
	_make_row(engine, 3, 5)
	step = engine._resolve(engine.find_matches(), [], {}, 1, [])
	_check(engine.altars[Vector2i(2, 3)] and not engine.altars[Vector2i(2, 4)] and not engine.is_won(), "match charges its own altar and no adjacent altar")
	engine.cells[Vector2i(2, 0)].special = "column"
	step = engine._resolve([], [Vector2i(2, 0)], {}, 1, [])
	_check(engine.objective_state().current == 2 and engine.is_won(), "lightning hit charges remaining altar")
	var state: Dictionary = engine.objective_state()
	state.altars[Vector2i(2, 4)] = false
	_check(engine.altars[Vector2i(2, 4)], "returned altar state is independent snapshot")
	engine.cells[Vector2i(2, 0)].special = "column"
	engine._resolve([], [Vector2i(2, 0)], {}, 1, [])
	_check(engine.objective_state().current == 2, "charged altars are counted once")
	engine = _fixture("altars", 1)
	var pivot := Vector2i(1, 3)
	engine.altars[pivot] = false
	for x in range(4):
		engine.cells[Vector2i(x, 3)].color = 5
	step = engine._resolve(engine.find_matches(), [], {}, 1, [pivot])
	_check(pivot not in step.removed and engine.cells[pivot].special == "row", "new lightning pivot survives four-match removal")
	_check(engine.altars[pivot] and engine.is_won() and step.altars[pivot], "match participation charges altar even when protected pivot becomes special")
	engine = _fixture("score", 30)
	engine.moves = 1
	engine._plant_legal_move()
	var legal: Array = engine.legal_moves()
	var outcome: Dictionary = engine.try_swap(legal[0][0], legal[0][1])
	_check(outcome.valid and outcome.won and not outcome.lost and engine.moves == 0, "score objective completed on final move wins before loss")
	completed_sections += 1

func _test_boss() -> void:
	var engine = _fixture("boss", 200)
	engine.score = 999999
	_check(not engine.is_won(), "score alone cannot defeat boss")
	_make_row(engine, 3, 5)
	var step: Dictionary = engine._resolve(engine.find_matches(), [], {}, 1, [])
	_check(step.boss_damage == 3 and engine.boss_hp == 197, "weak-color crystals each cause one damage")
	engine = _fixture("boss", 200)
	_make_row(engine, 3, 0)
	step = engine._resolve(engine.find_matches(), [], {}, 1, [])
	_check(step.boss_damage == 0 and engine.boss_hp == 200, "non-weak ordinary match earns score without boss damage")
	engine = _fixture("boss", 200)
	engine.bonuses.boss_damage_bonus = 2
	engine.cells[Vector2i(1, 3)].special = "row"
	engine.cells[Vector2i(5, 3)].special = "column"
	step = engine._resolve([], [Vector2i(1, 3)], {}, 1, [])
	var weak_removed := 0
	for removed in step.removed_details:
		if removed.color == 5:
			weak_removed += 1
	var expected_damage: int = weak_removed + step.activated.size() * 4 + 2
	_check(step.activated.size() == 2 and step.boss_damage == expected_damage and engine.boss_hp == 200 - expected_damage, "chains contribute damage and fortress bonus once per damaging cascade")
	engine = _fixture("boss", 500)
	engine._plant_legal_move()
	for turn in range(1, 7):
		var legal: Array = engine.legal_moves()
		_check(not legal.is_empty(), "boss always offers a legal turn")
		if legal.is_empty():
			break
		var outcome: Dictionary = engine.try_swap(legal[0][0], legal[0][1])
		var attacks := 0
		for resolution in outcome.steps:
			if resolution.combo == 0:
				attacks += 1
				_check(resolution.boss_attack.size() >= 1 and resolution.boss_attack.size() <= 2, "retaliation casts one or two seals")
		_check(attacks == (1 if turn % 3 == 0 else 0), "boss retaliation occurs every third valid turn")
		_check(engine.objective_state().attack_in == 3 - turn % 3, "boss countdown reflects successful player turns")
		_check(not engine.legal_moves().is_empty() and engine.find_matches().is_empty(), "retaliation preserves playable settled board")
	var turns_before: int = engine.valid_turns
	engine.try_swap(Vector2i(0, 0), Vector2i(6, 6))
	_check(engine.valid_turns == turns_before, "invalid input cannot advance boss cadence")
	engine.cells[Vector2i(0, 0)].special = "row"
	engine.blockers.erase(Vector2i(0, 0))
	var snapshot_before: Dictionary = engine.blockers.duplicate(true)
	var projected_attack = engine.clone_model()
	var attack_step: Dictionary = projected_attack._boss_attack()
	_check(engine.blockers == snapshot_before, "boss attack preview cannot mutate original seals")
	var actual_attack: Dictionary = engine._boss_attack()
	_check(actual_attack == attack_step and engine.blockers == projected_attack.blockers, "boss retaliation clone preserves exact RNG and blocker snapshots")
	for _attack in range(40):
		engine._boss_attack()
	_check(engine.blockers.size() <= engine.level_data.mask.size() / 5 and not engine.legal_moves().is_empty(), "repeated retaliation obeys seal cap and cannot softlock board")
	_check(not engine.blockers.has(Vector2i(0, 0)), "boss never seals existing special")
	engine = _fixture("boss", 1)
	engine.valid_turns = 2
	engine.cells[Vector2i(0, 0)].special = "nova"
	var outcome: Dictionary = engine.try_swap(Vector2i(0, 0), Vector2i(1, 0))
	var attacks := 0
	for resolution in outcome.steps:
		if resolution.combo == 0:
			attacks += 1
	_check(outcome.won and engine.boss_hp == 0 and attacks == 0, "boss defeated on attack turn cannot retaliate")
	var before: Dictionary = engine.snapshot()
	var repeated: Dictionary = engine.try_swap(Vector2i(1, 0), Vector2i(2, 0))
	_check(not repeated.valid and repeated.won and engine.snapshot() == before and engine.valid_turns == 3, "defeated boss remains terminal on repeated input")
	engine = _fixture("boss", 500)
	engine.valid_turns = 2
	engine.moves = 1
	engine._plant_legal_move()
	var legal: Array = engine.legal_moves()
	outcome = engine.try_swap(legal[0][0], legal[0][1])
	attacks = 0
	for resolution in outcome.steps:
		if resolution.combo == 0:
			attacks += 1
	_check(outcome.lost and not outcome.won and engine.boss_hp > 0 and attacks == 0, "boss skips futile retaliation after final-move loss")
	engine.initialize(10)
	_check(engine.boss_hp == engine.boss_max_hp and engine.valid_turns == 0 and engine.score == 0 and engine.objective_state().attack_in == 3, "retry fully resets boss health and attack cadence")
	engine.initialize(4)
	_check(engine.boss_hp == 0 and engine.boss_max_hp == 0 and engine.valid_turns == 0 and engine.objective_state().current == 0, "switching from boss resets combat and altar state")
	completed_sections += 1

func _test_bonuses() -> void:
	var supplied: Dictionary = {"bonus_moves": 50, "starting_specials": 20, "boss_damage_bonus": 99, "essence_boost": 4}
	var original: Dictionary = supplied.duplicate(true)
	var engine = EngineModel.new()
	engine.initialize(10, supplied)
	_check(supplied == original, "engine does not mutate settlement bonuses")
	_check(engine.moves == int(engine.level_data.moves) + 3 and engine.bonuses.boss_damage_bonus == 2, "bonuses clamp to documented caps")
	var specials := 0
	for position in engine.cells:
		if engine.cells[position].special != "":
			specials += 1
			_check(not engine.blockers.has(position), "starting special placed in usable slot")
	_check(specials == 2 and engine.find_matches().is_empty(), "two seeded starting specials preserve settled initial board")
	var twin = EngineModel.new()
	twin.initialize(10, supplied)
	_check(engine.snapshot() == twin.snapshot() and engine.objective_state() == twin.objective_state(), "bonused board deterministic")
	engine.initialize(1, {"bonus_moves": -9, "starting_specials": "invalid", "boss_damage_bonus": NAN})
	_check(engine.moves == engine.level_data.moves and engine.bonuses == {"bonus_moves": 0, "starting_specials": 0, "boss_damage_bonus": 0, "forge_bomb": 0, "seal_damage_bonus": 0}, "invalid or negative bonuses are harmless")
	completed_sections += 1

func _test_cloning() -> void:
	for level in range(1, 41):
		var engine = EngineModel.new()
		engine.initialize(level, {"bonus_moves": 1, "starting_specials": 1, "boss_damage_bonus": 1})
		var clone = engine.clone_model()
		_check(clone.snapshot() == engine.snapshot() and clone.objective_state() == engine.objective_state(), "clone copies mission %d" % level)
		var before: Dictionary = engine.snapshot()
		var legal: Array = engine.legal_moves()
		var projected: Dictionary = clone.try_swap(legal[0][0], legal[0][1])
		_check(engine.snapshot() == before and engine.valid_turns == 0, "tactical preview cannot mutate live board")
		var actual: Dictionary = engine.try_swap(legal[0][0], legal[0][1])
		_check(actual == projected and clone.objective_state() == engine.objective_state(), "preview uses exact RNG and mission state at level %d" % level)
	completed_sections += 1

func _fitness(before, projected, outcome: Dictionary) -> float:
	var old_state: Dictionary = before.objective_state()
	var new_state: Dictionary = projected.objective_state()
	var fitness := float(int(new_state.current) - int(old_state.current)) * 1000.0
	if old_state.kind == "relic":
		for position in projected.cells:
			if bool(projected.cells[position].get("relic", false)):
				fitness += position.y * 100.0
	if new_state.complete:
		fitness += 1000000.0
	if old_state.kind == "seals":
		for position in before._original_seals:
			fitness += (int(before.blockers.get(position, 0)) - int(projected.blockers.get(position, 0))) * 150.0
	for position in projected.cells:
		var special: String = projected.cells[position].special
		if special != "":
			fitness += 80 if special == "nova" else 50 if special == "bomb" else 30
	fitness += float(outcome.score_delta) * 0.03
	return fitness

func _test_balance() -> void:
	# One-step objective-aware deterministic lookahead; a sample, not a solver proof.
	var wins := 0
	var by_kind: Dictionary = {}
	var failed_runs: Array = []
	for level in range(1, 61):
		var engine = EngineModel.new()
		engine.initialize(level)
		var kind: String = engine.level_data.objective.kind
		if not by_kind.has(kind):
			by_kind[kind] = {"wins": 0, "total": 0}
		by_kind[kind].total += 1
		var budget: int = engine.moves
		var turns := 0
		while not engine.is_won() and not engine.is_lost() and turns < budget:
			var legal: Array = engine.legal_moves()
			_check(not legal.is_empty(), "balance run %d remains playable" % level)
			if legal.is_empty():
				break
			var best_move: Array = legal[0]
			var best_fitness := -INF
			for move in legal:
				var projection = engine.clone_model()
				var outcome: Dictionary = projection.try_swap(move[0], move[1])
				var fitness: float = _fitness(engine, projection, outcome)
				if fitness > best_fitness:
					best_fitness = fitness
					best_move = move
			var outcome: Dictionary = engine.try_swap(best_move[0], best_move[1])
			_check(outcome.valid and engine.find_matches().is_empty(), "balance run %d settles every chosen move" % level)
			turns += 1
		_check(engine.is_won() or engine.is_lost(), "balance run %d reaches real objective terminal state" % level)
		if engine.is_won():
			wins += 1
			by_kind[kind].wins += 1
		else:
			var uncharged: Array = []
			for position in engine.altars:
				if not engine.altars[position]:
					uncharged.append(position)
			var state: Dictionary = engine.objective_state()
			failed_runs.append({"level": level, "kind": kind, "current": state.current, "target": state.target, "moves": engine.moves, "uncharged_altars": uncharged, "original_seals": engine.level_data.blockers, "remaining_seals": engine.blockers})
	print("BALANCE first 60 levels: %d/60 wins (%.1f%%), one-step objective lookahead, no building bonuses. %s Failed runs: %s" % [wins, wins * 100.0 / 60.0, str(by_kind), str(failed_runs)])
	completed_sections += 1
