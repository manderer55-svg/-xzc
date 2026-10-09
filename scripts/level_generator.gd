extends RefCounted
class_name LevelGenerator

## A level number is its complete recipe. No level files or finite level cap.
const SHAPES := ["citadel", "diamond", "cross", "hourglass", "heart", "ring", "wings", "rune"]
const REGION := "Проклятый лес"

static func generate(level: int) -> Dictionary:
	level = maxi(1, level)
	var seed_value: int = 73939133 + level * 104729
	var random := RandomNumberGenerator.new()
	random.seed = seed_value
	var width: int = 7 + ((level - 1) / SHAPES.size() as int) % 3
	var height: int = 7 + ((level - 1) / (SHAPES.size() * 3) as int) % 3
	var shape: String = SHAPES[(level - 1) % SHAPES.size()]
	var chapter_stage: int = (level - 1) % 10
	var kind: String = "boss" if chapter_stage == 9 else ["score", "collect", "seals", "altars"][chapter_stage % 4]
	var mask: Array[Vector2i] = []
	var center := Vector2((width - 1) / 2.0, (height - 1) / 2.0)
	for y in range(height):
		for x in range(width):
			var include := true
			match shape:
				"diamond":
					include = absf(x - center.x) / (center.x + 0.5) + absf(y - center.y) / (center.y + 0.5) <= 1.18
				"cross":
					include = absf(x - center.x) <= 1.5 or absf(y - center.y) <= 1.5
				"hourglass":
					var margin: int = floori(mini(y, height - 1 - y) * 0.7)
					include = x >= margin and x < width - margin
				"heart":
					if y == 0:
						include = x > 0 and x < width - 1 and absf(x - center.x) >= 0.6
					elif y >= height / 2:
						var margin: int = maxi(0, y - height / 2 + 1)
						include = x >= margin and x < width - margin
				"ring":
					include = not (absf(x - center.x) <= 1.0 and absf(y - center.y) <= 1.0)
				"wings":
					include = absf(x - center.x) <= 1.0 or (y >= absi(x - floori(center.x)) / 2 and y < height - absi(x - floori(center.x)) / 2)
				"rune":
					include = absf(x - center.x) <= 1.5 or y < 2 or y >= height - 2 or (x < 2 and y < height / 2) or (x >= width - 2 and y >= height / 2)
			if include:
				mask.append(Vector2i(x, y))
	# Later levels add sealed crystals, which can be broken by neighboring matches.
	var blockers: Dictionary = {}
	var candidate_cells: Array[Vector2i] = []
	for position in mask:
		if position.y > 1 and position.y < height - 1:
			candidate_cells.append(position)
	var blocker_count: int = mini(mask.size() / 8, maxi(0, (level - 4) / 3))
	if kind == "seals":
		blocker_count = 3 + mini(3, (level - 1) / 30)
	elif kind == "boss":
		blocker_count = mini(3, blocker_count)
	for _index in range(blocker_count):
		if candidate_cells.is_empty():
			break
		var chosen: int = random.randi_range(0, candidate_cells.size() - 1)
		var position: Vector2i = candidate_cells.pop_at(chosen)
		blockers[position] = 2 if level >= 35 and random.randf() < 0.35 else 1
	var altar_positions: Array[Vector2i] = []
	if kind == "altars":
		var altar_candidates: Array[Vector2i] = []
		for position in mask:
			if not blockers.has(position) and position.y > 0 and position.y < height - 1:
				altar_candidates.append(position)
		while altar_positions.size() < 3 and not altar_candidates.is_empty():
			var chosen: int = random.randi_range(0, altar_candidates.size() - 1)
			var position: Vector2i = altar_candidates.pop_at(chosen)
			var separated := true
			for existing in altar_positions:
				if absi(existing.x - position.x) + absi(existing.y - position.y) < 3:
					separated = false
			if separated:
				altar_positions.append(position)
		# The masks always offer three separated slots; retain a safe fallback.
		if altar_positions.size() < 3:
			for position in mask:
				if not blockers.has(position) and position not in altar_positions:
					altar_positions.append(position)
				if altar_positions.size() == 3:
					break
	var score_target: int = 650 if level == 1 else 750 + mini(level * 23, 1250) + (mask.size() - 25) * 8
	var objective_target := score_target
	var objective_color: int = random.randi_range(0, 5)
	var boss: Dictionary = {}
	match kind:
		"collect": objective_target = 18 + mini(8, (level - 1) / 30)
		"seals": objective_target = blockers.size()
		"altars": objective_target = altar_positions.size()
		"boss":
			objective_target = 32 + mini(18, level / 20)
			boss = {"name": "Страж корней", "hp": objective_target, "weak_color": objective_color, "attack_every": 3}
	return {
		"level": level,
		"width": width,
		"height": height,
		"mask": mask,
		"moves": 26 + mini(10, mask.size() / 12),
		"target": score_target,
		"seed": seed_value,
		"shape": shape,
		"blockers": blockers,
		"region": REGION,
		"objective": {"kind": kind, "target": objective_target, "color": objective_color},
		"altars": altar_positions,
		"boss": boss,
	}
