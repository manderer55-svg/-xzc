extends RefCounted
class_name MatchEngine

const Generator = preload("res://scripts/level_generator.gd")
const COLOR_COUNT := 6
const DIRECTIONS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const MAX_CASCADES := 64

var level_data: Dictionary = {}
var width := 0
var height := 0
var cells: Dictionary = {}
var blockers: Dictionary = {}
var score := 0
var moves := 0
var collected: Dictionary = {}
var rng := RandomNumberGenerator.new()

func initialize(level: int) -> void:
	level_data = Generator.generate(level)
	width = level_data.width
	height = level_data.height
	blockers = level_data.blockers.duplicate(true)
	moves = level_data.moves
	score = 0
	collected.clear()
	for color in range(COLOR_COUNT):
		collected[color] = 0
	rng.seed = level_data.seed
	_randomize_board(false)

func is_won() -> bool:
	return not level_data.is_empty() and score >= int(level_data.target)

func is_lost() -> bool:
	return moves <= 0 and not is_won()

func snapshot() -> Dictionary:
	return cells.duplicate(true)

func _open(position: Vector2i) -> bool:
	return cells.has(position) and not blockers.has(position)

func _same_color(position: Vector2i, color: int) -> bool:
	return _open(position) and int(cells[position].color) == color

func _has_match_at(position: Vector2i) -> bool:
	if not _open(position):
		return false
	var color: int = cells[position].color
	for axis in [Vector2i.RIGHT, Vector2i.DOWN]:
		var count := 1
		for direction in [axis, -axis]:
			var neighbor: Vector2i = position + direction
			while _same_color(neighbor, color):
				count += 1
				neighbor += direction
		if count >= 3:
			return true
	return false

## Connected horizontal/vertical runs of the same color form one group.
func find_matches() -> Array:
	var runs: Array = []
	for y in range(height):
		var x := 0
		while x < width:
			var position := Vector2i(x, y)
			if not _open(position):
				x += 1
				continue
			var color: int = cells[position].color
			var run: Array[Vector2i] = []
			while x < width and _same_color(Vector2i(x, y), color):
				run.append(Vector2i(x, y))
				x += 1
			if run.size() >= 3:
				runs.append({"cells": run, "color": color, "axes": ["row"]})
	for x in range(width):
		var y := 0
		while y < height:
			var position := Vector2i(x, y)
			if not _open(position):
				y += 1
				continue
			var color: int = cells[position].color
			var run: Array[Vector2i] = []
			while y < height and _same_color(Vector2i(x, y), color):
				run.append(Vector2i(x, y))
				y += 1
			if run.size() >= 3:
				runs.append({"cells": run, "color": color, "axes": ["column"]})
	var merged := true
	while merged:
		merged = false
		for first in range(runs.size()):
			for second in range(first + 1, runs.size()):
				if int(runs[first].color) != int(runs[second].color):
					continue
				var overlaps := false
				for position in runs[first].cells:
					if position in runs[second].cells:
						overlaps = true
						break
				if overlaps:
					for position in runs[second].cells:
						if position not in runs[first].cells:
							runs[first].cells.append(position)
					for axis in runs[second].axes:
						if axis not in runs[first].axes:
							runs[first].axes.append(axis)
					runs.remove_at(second)
					merged = true
					break
			if merged:
				break
	return runs

func legal_moves() -> Array:
	var result: Array = []
	for y in range(height):
		for x in range(width):
			var first := Vector2i(x, y)
			if not _open(first):
				continue
			for direction in [Vector2i.RIGHT, Vector2i.DOWN]:
				var second: Vector2i = first + direction
				if not _open(second):
					continue
				if cells[first].special != "" or cells[second].special != "":
					result.append([first, second])
					continue
				_exchange(first, second)
				var valid := _has_match_at(first) or _has_match_at(second)
				_exchange(first, second)
				if valid:
					result.append([first, second])
	return result

func _exchange(first: Vector2i, second: Vector2i) -> void:
	var tile: Dictionary = cells[first]
	cells[first] = cells[second]
	cells[second] = tile

func try_swap(first: Vector2i, second: Vector2i) -> Dictionary:
	var result := {"valid": false, "steps": [], "score_delta": 0, "won": is_won(), "lost": is_lost(), "shuffled": false}
	if is_won() or is_lost() or not _open(first) or not _open(second):
		return result
	if absi(first.x - second.x) + absi(first.y - second.y) != 1:
		return result
	_exchange(first, second)
	var groups: Array = find_matches()
	var special_positions: Array = []
	for position in [first, second]:
		if cells[position].special != "":
			special_positions.append(position)
	if groups.is_empty() and special_positions.is_empty():
		_exchange(first, second)
		return result
	result.valid = true
	moves -= 1
	var previous_score := score
	var nova_targets: Dictionary = {}
	if cells[first].special == "nova":
		nova_targets[first] = -1 if cells[second].special == "nova" else cells[second].color
	if cells[second].special == "nova":
		nova_targets[second] = -1 if cells[first].special == "nova" else cells[first].color
	var combo := 1
	while (not groups.is_empty() or not special_positions.is_empty()) and combo <= MAX_CASCADES:
		var step: Dictionary = _resolve(groups, special_positions, nova_targets, combo, [second, first] if combo == 1 else [])
		result.steps.append(step)
		groups = find_matches()
		special_positions = []
		nova_targets = {}
		combo += 1
	# Extremely unlikely repeated random cascades have a deterministic safe exit.
	if not groups.is_empty() or legal_moves().is_empty():
		shuffle()
		result.shuffled = true
		result.shuffle_board = snapshot()
	result.score_delta = score - previous_score
	result.won = is_won()
	result.lost = is_lost()
	return result

func _special_for(group: Dictionary) -> String:
	if group.axes.size() > 1:
		return "bomb"
	if group.cells.size() >= 5:
		return "nova"
	if group.cells.size() == 4:
		return "row" if group.axes[0] == "row" else "column"
	return ""

func _resolve(groups: Array, special_positions: Array, nova_targets: Dictionary, combo: int, preferred: Array) -> Dictionary:
	var removed: Dictionary = {}
	var pending: Array = special_positions.duplicate()
	var spawned: Array = []
	var protected: Dictionary = {}
	for group in groups:
		var new_special: String = _special_for(group)
		var pivot: Vector2i = group.cells[group.cells.size() / 2]
		var pivot_found: bool = cells[pivot].special == ""
		for choice in preferred:
			if choice in group.cells and cells[choice].special == "":
				pivot = choice
				pivot_found = true
				break
		if not pivot_found:
			for choice in group.cells:
				if cells[choice].special == "":
					pivot = choice
					pivot_found = true
					break
		# An old special detonates, while a different ordinary crystal becomes
		# the new special earned by this match. It survives this same clear.
		if new_special != "" and pivot_found:
			protected[pivot] = true
			spawned.append({"position": pivot, "special": new_special, "color": group.color})
		for position in group.cells:
			if not protected.has(position):
				removed[position] = true
				if cells[position].special != "":
					pending.append(position)
	var activated: Array = []
	var seen: Dictionary = {}
	var direct_blockers: Dictionary = {}
	while not pending.is_empty():
		var position: Vector2i = pending.pop_front()
		if seen.has(position) or not _open(position):
			continue
		seen[position] = true
		var special: String = cells[position].special
		if special == "":
			continue
		activated.append({"position": position, "special": special})
		removed[position] = true
		var affected: Array = []
		match special:
			"row":
				for x in range(width):
					affected.append(Vector2i(x, position.y))
			"column":
				for y in range(height):
					affected.append(Vector2i(position.x, y))
			"bomb":
				for y in range(position.y - 1, position.y + 2):
					for x in range(position.x - 1, position.x + 2):
						affected.append(Vector2i(x, y))
			"nova":
				var target: int = int(nova_targets.get(position, cells[position].color))
				for tile_position in cells:
					if target < 0 or int(cells[tile_position].color) == target:
						affected.append(tile_position)
		for target_position in affected:
			if blockers.has(target_position):
				direct_blockers[target_position] = true
			elif cells.has(target_position) and not protected.has(target_position):
				removed[target_position] = true
				if cells[target_position].special != "" and not seen.has(target_position):
					pending.append(target_position)
	var damaged: Dictionary = direct_blockers.duplicate()
	for position in removed:
		for direction in DIRECTIONS:
			var neighbor: Vector2i = position + direction
			if blockers.has(neighbor):
				damaged[neighbor] = true
	var blocker_hits: Array = []
	for position in damaged:
		blockers[position] -= 1
		blocker_hits.append(position)
		if blockers[position] <= 0:
			blockers.erase(position)
			score += 30 * combo
	var details: Array = []
	for position in removed:
		var tile: Dictionary = cells[position]
		details.append({"position": position, "color": tile.color, "special": tile.special})
		collected[tile.color] = int(collected.get(tile.color, 0)) + 1
		cells.erase(position)
		score += 10 * combo
	for entry in spawned:
		cells[entry.position] = {"color": entry.color, "special": entry.special}
		score += 20 * combo
	_refill()
	return {
		"removed": removed.keys(), "removed_details": details,
		"activated": activated, "spawned": spawned,
		"blocker_hits": blocker_hits, "board": snapshot(),
		"blockers": blockers.duplicate(true), "score": score, "combo": combo,
	}

## Holes and sealed crystals divide columns into independent gravity segments.
func _refill() -> void:
	var mask: Dictionary = {}
	for position in level_data.mask:
		mask[position] = true
	for x in range(width):
		var y := 0
		while y < height:
			var position := Vector2i(x, y)
			if not mask.has(position) or blockers.has(position):
				y += 1
				continue
			var segment: Array = []
			while y < height and mask.has(Vector2i(x, y)) and not blockers.has(Vector2i(x, y)):
				segment.append(Vector2i(x, y))
				y += 1
			var survivors: Array = []
			for slot in segment:
				if cells.has(slot):
					survivors.append(cells[slot])
			for slot in segment:
				cells.erase(slot)
			for index in range(segment.size() - 1, -1, -1):
				cells[segment[index]] = survivors.pop_back() if not survivors.is_empty() else {"color": rng.randi_range(0, COLOR_COUNT - 1), "special": ""}

func shuffle() -> void:
	_randomize_board(true)

func _randomize_board(preserve_specials: bool) -> void:
	var specials: Dictionary = {}
	if preserve_specials:
		for position in cells:
			if cells[position].special != "":
				specials[position] = cells[position].special
	for _attempt in range(128):
		cells.clear()
		for position in level_data.mask:
			var available: Array = range(COLOR_COUNT)
			for axis in [Vector2i.LEFT, Vector2i.UP]:
				var previous: Vector2i = position + axis
				var earlier: Vector2i = position + axis * 2
				if _open(previous) and _open(earlier) and cells[previous].color == cells[earlier].color:
					available.erase(int(cells[previous].color))
			var color: int = available[rng.randi_range(0, available.size() - 1)]
			cells[position] = {"color": color, "special": specials.get(position, "")}
		if find_matches().is_empty() and not legal_moves().is_empty():
			return
	# Every generated shape has an unsealed 3x2 window in its upper half.
	# Force A-B-A / ?-A-? without introducing a match in the current board.
	if not _plant_legal_move():
		push_error("Level mask cannot support a match-free playable board.")

func _plant_legal_move() -> bool:
	for y in range(height - 1):
		for x in range(width - 2):
			var slots: Array = [Vector2i(x, y), Vector2i(x + 1, y), Vector2i(x + 2, y), Vector2i(x + 1, y + 1)]
			var usable := true
			for position in slots:
				if not _open(position):
					usable = false
			if not usable:
				continue
			var before: Array = []
			for position in slots:
				before.append(cells[position].color)
			for primary in range(COLOR_COUNT):
				for alternate in range(COLOR_COUNT):
					if primary == alternate:
						continue
					cells[slots[0]].color = primary
					cells[slots[1]].color = alternate
					cells[slots[2]].color = primary
					cells[slots[3]].color = primary
					if find_matches().is_empty():
						return true
			for index in range(slots.size()):
				cells[slots[index]].color = before[index]
	return false
