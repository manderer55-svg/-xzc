class_name ExpeditionModel
extends RefCounted
## Finite, manually assigned expeditions. Cargo is banked only after returning to the gate.

const WIDTH := 30
const HEIGHT := 30
const DEPOSIT_COUNT := 12
const FIELD_GATE_CELL := Vector2i(15, 27)
const FIELD_GATE_ACCESS := Vector2i(15, 28)
const RESOURCE_KEYS := ["stone", "wood", "essence"]
const DIRECTIONS := [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
const RESPAWN_SECONDS := 120.0
const STEP_SECONDS := 0.25
const MINING_SECONDS := 1.25
const MINING_BATCH := 5
const CHECKPOINT_SECONDS := 2.0
const OFFLINE_CAP := 8.0 * 60.0 * 60.0
const MAX_RESOURCE := 1000000000

var settlement: SettlementModel
var store: ProgressStore
var heroes: RefCounted
var navigation := AStarGrid2D.new()
var last_error := ""
var _save_elapsed := 0.0


func configure(model: SettlementModel, party_model: RefCounted = null) -> bool:
	settlement = model
	store = model.store
	heroes = party_model
	var before := store.data.duplicate(true)
	store.data["expedition_mode"] = true
	var stored: Variant = store.data.get("expedition_state", {})
	var fresh := not stored is Dictionary or int(stored.get("schema", 0)) != 1
	if fresh:
		store.data["expedition_state"] = {
			"schema": 1, "next_job_id": 1, "random_state": 7919,
			"clock": Time.get_unix_time_from_system(), "deposits": [], "jobs": [],
		}
		_rebuild_navigation()
		for index in range(DEPOSIT_COUNT):
			var deposit := {"id": index + 1, "cell": [-1, -1], "resource": RESOURCE_KEYS[index % 3],
				"remaining": 0, "initial_stock": 0, "respawn_at": 0.0, "active": false}
			_state().deposits.append(deposit)
			_spawn_deposit(deposit, true)
			_rebuild_navigation()
		# Version 1.2 pending ore remains earned, but still needs an actual return journey.
		# Moving it into finite stock and clearing the old queue share the same atomic save.
		var legacy: Variant = store.data.get("colony_pending", {})
		if legacy is Dictionary:
			for resource in RESOURCE_KEYS:
				var pending := clampi(int(legacy.get(resource, 0)), 0, MAX_RESOURCE)
				if pending <= 0:
					continue
				for deposit: Dictionary in deposits():
					if bool(deposit.active) and deposit.resource == resource:
						deposit.remaining = mini(MAX_RESOURCE, int(deposit.remaining) + pending)
						deposit.initial_stock = int(deposit.remaining)
						legacy[resource] = 0
						break
	else:
		_sanitize_state()
		_rebuild_navigation()
		# Missing optional expedition entries never leave a migrated save without resources.
		var used: Dictionary = {}
		for deposit: Dictionary in deposits():
			used[int(deposit.id)] = true
		for id in range(1, DEPOSIT_COUNT + 1):
			if not used.has(id):
				var deposit := {"id": id, "cell": [-1, -1], "resource": RESOURCE_KEYS[(id - 1) % 3],
					"remaining": 0, "initial_stock": 0, "respawn_at": 0.0, "active": false}
				deposits().append(deposit)
				_spawn_deposit(deposit, true)
	if store.data != before and not store.save_progress():
		store.data = before
		last_error = store.last_error
		return false
	return sync_elapsed().ok


func deposits() -> Array:
	return _state().get("deposits", [])


func jobs() -> Array:
	return _state().get("jobs", [])


func get_deposit(id: int) -> Dictionary:
	for deposit: Dictionary in deposits():
		if int(deposit.id) == id:
			return deposit
	return {}


func queue_status() -> Dictionary:
	var capacity := int(settlement.call("expedition_capacity")) if settlement != null and settlement.has_method("expedition_capacity") else 1
	return {"busy": jobs().size(), "capacity": capacity, "free": maxi(0, capacity - jobs().size())}


func dispatch(deposit_id: int, hero_id: String = "", troop_type: String = "") -> Dictionary:
	if store == null:
		return _failure("Карта ещё не загружена.")
	var status := queue_status()
	if status.free <= 0:
		return _failure("Все отряды заняты. Улучшайте замок и ратушу, чтобы открыть до четырёх очередей.")
	var deposit := get_deposit(deposit_id)
	if deposit.is_empty() or not bool(deposit.active) or int(deposit.remaining) <= 0:
		return _failure("Месторождение исчерпано. Новые залежи появятся на карте позже.")
	for job: Dictionary in jobs():
		if int(job.deposit_id) == deposit_id and job.phase in ["outbound", "mining"]:
			return _failure("К этому месторождению уже отправлен отряд.")
	var party := {"ok": true, "hero_id": "warden", "troop_type": "infantry", "troop_count": 3, "yield_bonus": 0, "damage_bonus": 0}
	if heroes != null:
		party = heroes.call("dispatch_validation", hero_id, troop_type, str(deposit.resource))
		if not bool(party.get("ok", false)):
			return _failure(str(party.get("reason", "Выберите свободного героя и воинов.")))
	else:
		# HeroModel already combines hero and town skills for both its UI and validation.
		# Only the standalone fallback needs to obtain town skills here.
		var city_bonuses: Dictionary = settlement.call("expedition_bonuses") if settlement.has_method("expedition_bonuses") else {}
		party["yield_bonus"] = int(city_bonuses.get("yield_percent", 0))
		party["damage_bonus"] = int(city_bonuses.get("party_damage_percent", 0))
	party["yield_bonus"] = clampi(int(party.get("yield_bonus", 0)), 0, 75)
	party["damage_bonus"] = clampi(int(party.get("damage_bonus", 0)), 0, 120)
	if not party.has("party_damage"):
		for troop: Dictionary in HeroModel.TROOPS:
			if troop.id == party.troop_type:
				var base := int(troop.damage) * int(party.troop_count)
				party["party_damage"] = base + int(base * int(party.damage_bonus) / 100)
				break
	_rebuild_navigation()
	var target := _deposit_access(deposit)
	var path := _route(FIELD_GATE_ACCESS, target)
	if path.is_empty():
		return _failure("У отряда нет прохода к выбранному месторождению.")
	var before := store.data.duplicate(true)
	var id := int(_state().next_job_id)
	_state().next_job_id = id + 1
	jobs().append({"id": id, "deposit_id": deposit_id, "phase": "outbound",
		"position": [float(FIELD_GATE_ACCESS.x), float(FIELD_GATE_ACCESS.y)], "path": path,
		"path_index": 0, "step_elapsed": 0.0, "mining_elapsed": 0.0,
		"cargo_resource": str(deposit.resource), "cargo_amount": 0, "raw_cargo": 0, "delivery_retry": 0.0,
		"hero_id": str(party.hero_id), "troop_type": str(party.troop_type), "troop_count": int(party.troop_count),
		"yield_bonus": int(party.yield_bonus), "damage_bonus": int(party.damage_bonus),
		"party_damage": maxi(0, int(party.get("party_damage", 0)))})
	if not store.save_progress():
		store.data = before
		return _failure(store.last_error)
	_save_elapsed = 0.0
	return {"ok": true, "reason": "Отряд вышел из замка к месторождению.", "job_id": id}


func advance(delta: float) -> Dictionary:
	if store == null or not is_finite(delta) or delta <= 0.0:
		return {"ok": true, "changed": false, "deliveries": []}
	var before := store.data.duplicate(true)
	var remaining := minf(delta, OFFLINE_CAP)
	var deliveries: Array = []
	var important := false
	# Small bounded steps preserve arrival/mining order even when resuming after a long pause.
	# Once all finite jobs finish, skip directly to respawns instead of simulating idle hours.
	while remaining > 0.00001:
		var step := minf(remaining, STEP_SECONDS)
		if jobs().is_empty():
			step = remaining
		_state().clock = float(_state().clock) + step
		remaining -= step
		for job: Dictionary in jobs().duplicate():
			important = _step_job(job, step, deliveries) or important
		for deposit: Dictionary in deposits():
			if not bool(deposit.active) and float(deposit.respawn_at) <= float(_state().clock):
				if _spawn_deposit(deposit, false):
					important = true
		_save_elapsed += step
	if important:
		_rebuild_navigation()
	if important or _save_elapsed >= CHECKPOINT_SECONDS:
		if not store.save_progress():
			store.data = before
			_rebuild_navigation()
			last_error = store.last_error
			return {"ok": false, "reason": last_error, "changed": false, "deliveries": []}
		_save_elapsed = 0.0
	last_error = ""
	return {"ok": true, "changed": important, "deliveries": deliveries}


func checkpoint() -> bool:
	if store == null:
		return false
	if not store.save_progress():
		last_error = store.last_error
		return false
	_save_elapsed = 0.0
	return true


func sync_elapsed() -> Dictionary:
	if store == null:
		return _failure("Карта ещё не загружена.")
	var elapsed := maxf(0.0, Time.get_unix_time_from_system() - float(_state().clock))
	if elapsed <= 0.05:
		return {"ok": true, "changed": false, "deliveries": []}
	var result := advance(elapsed)
	if result.ok and elapsed > OFFLINE_CAP:
		var previous_clock := float(_state().clock)
		_state().clock = Time.get_unix_time_from_system()
		if not checkpoint():
			_state().clock = previous_clock
			return _failure(last_error)
	return result


func job_position(job: Dictionary) -> Vector2:
	var value: Array = job.get("position", [FIELD_GATE_ACCESS.x, FIELD_GATE_ACCESS.y])
	return Vector2(float(value[0]), float(value[1]))


func job_eta(job: Dictionary) -> int:
	var travel := maxf(0, job.path.size() - 1 - int(job.path_index)) * STEP_SECONDS - float(job.step_elapsed)
	if job.phase == "mining":
		var deposit := get_deposit(int(job.deposit_id))
		var extraction := ceili(float(deposit.get("remaining", 0)) / _mining_batch(deposit)) * MINING_SECONDS
		return ceili(extraction + _return_path(job).size() * STEP_SECONDS)
	if job.phase == "outbound":
		var deposit := get_deposit(int(job.deposit_id))
		travel += ceili(float(deposit.get("remaining", 0)) / _mining_batch(deposit)) * MINING_SECONDS
		travel += maxi(0, job.path.size() - 1) * STEP_SECONDS
	return maxi(0, ceili(travel))


func _step_job(job: Dictionary, delta: float, deliveries: Array) -> bool:
	match str(job.phase):
		"outbound", "returning":
			return _move_job(job, delta, deliveries)
		"mining":
			var deposit := get_deposit(int(job.deposit_id))
			if deposit.is_empty() or not bool(deposit.active):
				_start_return(job)
				return true
			job.mining_elapsed = float(job.mining_elapsed) + delta
			if float(job.mining_elapsed) < MINING_SECONDS:
				return false
			job.mining_elapsed = float(job.mining_elapsed) - MINING_SECONDS
			var amount := mini(_mining_batch(deposit), int(deposit.remaining))
			deposit.remaining = int(deposit.remaining) - amount
			job.cargo_amount = int(job.cargo_amount) + amount
			job.raw_cargo = int(job.get("raw_cargo", 0)) + amount
			if int(deposit.remaining) == 0:
				deposit.active = false
				deposit.respawn_at = float(_state().clock) + RESPAWN_SECONDS
				_start_return(job)
			return true
		"delivery_retry":
			job.delivery_retry = float(job.get("delivery_retry", 0.0)) + delta
			if float(job.delivery_retry) >= 2.0:
				job.delivery_retry = 0.0
				return _deliver_job(job, deliveries)
	return false


func _move_job(job: Dictionary, delta: float, deliveries: Array) -> bool:
	var path: Array = job.path
	if path.is_empty():
		return _repair_route(job)
	job.step_elapsed = float(job.step_elapsed) + delta
	while float(job.step_elapsed) >= STEP_SECONDS and int(job.path_index) < path.size() - 1:
		job.step_elapsed = float(job.step_elapsed) - STEP_SECONDS
		job.path_index = int(job.path_index) + 1
	if int(job.path_index) >= path.size() - 1:
		var end: Array = path.back() if not path.is_empty() else [FIELD_GATE_ACCESS.x, FIELD_GATE_ACCESS.y]
		job.position = [float(end[0]), float(end[1])]
		job.step_elapsed = 0.0
		if job.phase == "outbound":
			var deposit := get_deposit(int(job.deposit_id))
			if deposit.is_empty() or not bool(deposit.active):
				_start_return(job)
				return true
			var destination := Vector2(float(end[0]), float(end[1]))
			var target := Vector2(_cell(deposit.cell))
			if not is_equal_approx(absf(destination.x - target.x) + absf(destination.y - target.y), 1.0):
				job.path = []
				return _repair_route(job)
			job.phase = "mining"
			return true
		return _deliver_job(job, deliveries)
	var from: Array = path[int(job.path_index)]
	var target: Array = path[int(job.path_index) + 1]
	var fraction := float(job.step_elapsed) / STEP_SECONDS
	job.position = [lerpf(float(from[0]), float(target[0]), fraction), lerpf(float(from[1]), float(target[1]), fraction)]
	return false


func _start_return(job: Dictionary) -> void:
	# A hero improves the delivered yield once; finite raw stock is never increased.
	job.cargo_amount = mini(MAX_RESOURCE, int(job.get("raw_cargo", job.cargo_amount)) + int(int(job.get("raw_cargo", job.cargo_amount)) * int(job.get("yield_bonus", 0)) / 100))
	job.phase = "returning"
	job.path = _return_path(job)
	job.path_index = 0
	job.step_elapsed = 0.0
	job.mining_elapsed = 0.0


func _return_path(job: Dictionary) -> Array:
	var point := job_position(job)
	var from := Vector2i(roundi(point.x), roundi(point.y))
	return _route(from, FIELD_GATE_ACCESS)


func _deliver_job(job: Dictionary, deliveries: Array) -> bool:
	if job_position(job).distance_squared_to(Vector2(FIELD_GATE_ACCESS)) > 0.0001:
		# A missing/stale route must never teleport a loaded squad or credit it remotely.
		job.phase = "returning"
		job.path = []
		return _repair_route(job)
	var resource := str(job.cargo_resource)
	var room := MAX_RESOURCE - int(store.data.resources.get(resource, 0))
	var amount := mini(int(job.cargo_amount), room)
	if amount > 0:
		store.data.resources[resource] = int(store.data.resources[resource]) + amount
		job.cargo_amount = int(job.cargo_amount) - amount
		deliveries.append({"job_id": int(job.id), "resource": resource, "amount": amount})
	if int(job.cargo_amount) <= 0:
		jobs().erase(job)
	else:
		job.phase = "delivery_retry"
		job.delivery_retry = 0.0
	return amount > 0 or int(job.cargo_amount) == 0


func _repair_route(job: Dictionary) -> bool:
	_rebuild_navigation()
	job.path_index = 0
	job.step_elapsed = 0.0
	if job.phase == "outbound":
		var deposit := get_deposit(int(job.deposit_id))
		if deposit.is_empty() or not bool(deposit.active):
			_start_return(job)
		else:
			var position := job_position(job)
			job.path = _route(Vector2i(roundi(position.x), roundi(position.y)), _deposit_access(deposit))
	else:
		job.path = _return_path(job)
	job["route_blocked"] = job.path.is_empty()
	return not job.path.is_empty()


func _spawn_deposit(deposit: Dictionary, initial: bool) -> bool:
	var resource: String = str(deposit.resource) if initial else str(RESOURCE_KEYS[_random(3)])
	var occupied: Dictionary = {}
	for other: Dictionary in deposits():
		if bool(other.active):
			occupied[_cell(other.cell)] = true
	for job: Dictionary in jobs():
		for value: Array in job.path:
			occupied[_cell(value)] = true
	var candidates: Array[Vector2i] = []
	var old_cell := _cell(deposit.cell)
	for y in range(2, HEIGHT - 2):
		for x in range(2, WIDTH - 2):
			var point := Vector2i(x, y)
			if point == old_cell or occupied.has(point) or field_is_road(point) or not field_walkable(point):
				continue
			if point.distance_squared_to(FIELD_GATE_ACCESS) < 36:
				continue
			if resource == "wood" and field_terrain_at(point) not in [4, 7]:
				continue
			if resource == "stone" and field_terrain_at(point) not in [2, 6]:
				continue
			if resource == "essence" and field_terrain_at(point) != 8:
				continue
			for direction in DIRECTIONS:
				var access: Vector2i = point + direction
				if field_walkable(access) and not occupied.has(access) and not _route(FIELD_GATE_ACCESS, access).is_empty():
					candidates.append(point)
					break
	if candidates.is_empty():
		deposit.respawn_at = float(_state().clock) + 10.0
		return false
	var fallback := deposit.duplicate(true)
	var stock := 60 + _random(17) * 5
	deposit.resource = resource
	deposit.initial_stock = stock
	deposit.remaining = stock
	deposit.respawn_at = 0.0
	deposit.active = true
	# An approach that was reachable before placing a deposit can be cut off by its footprint.
	# Reject that placement rather than showing an unreachable order to the player.
	var start := _random(candidates.size())
	for offset in range(candidates.size()):
		var cell := candidates[(start + offset) % candidates.size()]
		deposit.cell = [cell.x, cell.y]
		_rebuild_navigation()
		var reachable := true
		for other: Dictionary in deposits():
			if bool(other.active) and _deposit_access(other) == Vector2i(-1, -1):
				reachable = false
				break
		if reachable:
			return true
	deposit.merge(fallback, true)
	deposit.respawn_at = float(_state().clock) + 10.0
	_rebuild_navigation()
	return false


func _deposit_access(deposit: Dictionary) -> Vector2i:
	var point := _cell(deposit.cell)
	var best := Vector2i(-1, -1)
	var length := 100000
	for direction in DIRECTIONS:
		var target: Vector2i = point + direction
		var route := _route(FIELD_GATE_ACCESS, target)
		if not route.is_empty() and route.size() < length:
			best = target
			length = route.size()
	return best


func _route(from: Vector2i, to: Vector2i) -> Array:
	var result: Array = []
	if not _contains(from) or not _contains(to) or navigation.is_point_solid(from) or navigation.is_point_solid(to):
		return result
	for point: Vector2i in navigation.get_id_path(from, to):
		result.append([point.x, point.y])
	return result


func _rebuild_navigation() -> void:
	navigation.region = Rect2i(0, 0, WIDTH, HEIGHT)
	navigation.cell_size = Vector2.ONE
	navigation.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	navigation.update()
	for y in range(HEIGHT):
		for x in range(WIDTH):
			var point := Vector2i(x, y)
			navigation.set_point_solid(point, not field_walkable(point))
	for deposit: Dictionary in deposits():
		var point := _cell(deposit.cell)
		if bool(deposit.active) and _contains(point):
			navigation.set_point_solid(point)


func _sanitize_state() -> void:
	var value := _state()
	value.clock = float(value.get("clock", Time.get_unix_time_from_system()))
	value.next_job_id = maxi(1, int(value.get("next_job_id", 1)))
	value.random_state = clampi(int(value.get("random_state", 7919)), 1, 2147483647)
	if not value.get("deposits") is Array or not value.get("jobs") is Array:
		value.deposits = []
		value.jobs = []
		return
	var seen: Dictionary = {}
	var safe_deposits: Array = []
	for candidate: Variant in value.deposits:
		if not candidate is Dictionary:
			continue
		var deposit: Dictionary = candidate
		var id := int(deposit.get("id", 0))
		if id <= 0 or seen.has(id) or str(deposit.get("resource", "")) not in RESOURCE_KEYS or not _valid_cell_value(deposit.get("cell")):
			continue
		seen[id] = true
		deposit.id = id
		var cell := _cell(deposit.cell)
		deposit.cell = [cell.x, cell.y]
		deposit.remaining = clampi(int(deposit.get("remaining", 0)), 0, MAX_RESOURCE)
		deposit.initial_stock = maxi(int(deposit.remaining), int(deposit.get("initial_stock", deposit.remaining)))
		deposit.active = deposit.get("active", false) == true and int(deposit.remaining) > 0
		deposit.respawn_at = float(deposit.get("respawn_at", value.clock + RESPAWN_SECONDS))
		safe_deposits.append(deposit)
	value.deposits = safe_deposits
	seen.clear()
	var safe_jobs: Array = []
	for candidate: Variant in value.jobs:
		if not candidate is Dictionary:
			continue
		var job: Dictionary = candidate
		var id := int(job.get("id", 0))
		if id <= 0 or seen.has(id) or str(job.get("cargo_resource", "")) not in RESOURCE_KEYS:
			continue
		if job.get("phase", "") not in ["outbound", "mining", "returning", "delivery_retry"]:
			continue
		if not _valid_cell_value(job.get("position")) or not job.get("path") is Array:
			continue
		var valid_path := true
		for cell: Variant in job.path:
			valid_path = valid_path and _valid_cell_value(cell)
		if not valid_path:
			continue
		var canonical_path: Array = []
		for path_value: Array in job.path:
			var cell := _cell(path_value)
			canonical_path.append([cell.x, cell.y])
		job.path = canonical_path
		seen[id] = true
		job.id = id
		job.path_index = clampi(int(job.get("path_index", 0)), 0, job.path.size() - 1) if not job.path.is_empty() else 0
		job.step_elapsed = clampf(float(job.get("step_elapsed", 0.0)), 0.0, STEP_SECONDS)
		job.mining_elapsed = clampf(float(job.get("mining_elapsed", 0.0)), 0.0, MINING_SECONDS)
		job.delivery_retry = clampf(float(job.get("delivery_retry", 0.0)), 0.0, 2.0)
		job.cargo_amount = clampi(int(job.get("cargo_amount", 0)), 0, MAX_RESOURCE)
		job.raw_cargo = clampi(int(job.get("raw_cargo", job.cargo_amount)), 0, MAX_RESOURCE)
		job.hero_id = str(job.get("hero_id", "warden"))
		job.troop_type = str(job.get("troop_type", "infantry"))
		job.troop_count = clampi(int(job.get("troop_count", 3)), 1, 20)
		job.yield_bonus = clampi(int(job.get("yield_bonus", 0)), 0, 75)
		job.damage_bonus = clampi(int(job.get("damage_bonus", 0)), 0, 120)
		job.party_damage = maxi(0, int(job.get("party_damage", 0)))
		job.deposit_id = int(job.get("deposit_id", 0))
		safe_jobs.append(job)
		value.next_job_id = maxi(int(value.next_job_id), id + 1)
	value.jobs = safe_jobs


func _state() -> Dictionary:
	return store.data.get("expedition_state", {}) if store != null else {}


func _random(limit: int) -> int:
	_state().random_state = (int(_state().random_state) * 1103515245 + 12345) & 0x7fffffff
	return int(_state().random_state) % maxi(1, limit)


func _mining_batch(deposit: Dictionary) -> int:
	# Large migrated offline stock finishes in a reasonable expedition, rather than hours.
	return maxi(MINING_BATCH, ceili(float(deposit.get("initial_stock", MINING_BATCH)) / 32.0))


func _failure(reason: String) -> Dictionary:
	last_error = reason
	return {"ok": false, "reason": reason}


static func field_terrain_at(cell: Vector2i) -> int:
	if not _contains(cell):
		return -1
	if field_is_road(cell):
		return 5
	var variation := _hash(Vector2i(cell.x / 3, cell.y / 3), 41) % 100
	if cell.x >= 21 and cell.y <= 14:
		return 8
	if cell.x + cell.y < 14:
		return 6 if variation < 45 else 2
	if cell.x >= 19 and cell.y >= 17:
		return 3 if variation < 80 else 0
	if cell.x < 12 or cell.y < 11:
		return 7 if variation < 75 else 4
	return 4 if variation < 30 else 0


static func field_decor_at(cell: Vector2i) -> int:
	if not _contains(cell) or field_is_road(cell):
		return -1
	var terrain := field_terrain_at(cell)
	var chance := _hash(cell, 79) % 100
	match terrain:
		7:
			return (1 if chance < 12 else 0) if chance < 43 else (6 if chance < 64 else -1)
		4:
			return 0 if chance < 15 else (6 if chance < 33 else -1)
		2, 6:
			return 2 if chance < 27 else (7 if chance < 35 else -1)
		3:
			return 5 if chance < 85 else -1
		_:
			return 6 if chance < 12 else -1


static func field_walkable(cell: Vector2i) -> bool:
	if not _contains(cell):
		return false
	if cell in [FIELD_GATE_CELL, FIELD_GATE_CELL + Vector2i.LEFT, FIELD_GATE_CELL + Vector2i.UP, FIELD_GATE_CELL + Vector2i(-1, -1)]:
		return false
	return field_decor_at(cell) not in [0, 1, 2]


static func field_is_road(cell: Vector2i) -> bool:
	return cell.x in [6, 15, 24] or cell.y in [12, 20, 28]


static func _valid_cell_value(value: Variant) -> bool:
	if not value is Array or value.size() != 2:
		return false
	for part: Variant in value:
		if not (part is int or part is float) or not is_finite(float(part)):
			return false
	return float(value[0]) >= 0 and float(value[0]) < WIDTH and float(value[1]) >= 0 and float(value[1]) < HEIGHT


static func _cell(value: Array) -> Vector2i:
	return Vector2i(roundi(float(value[0])), roundi(float(value[1])))


static func _contains(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < WIDTH and cell.y < HEIGHT


static func _hash(cell: Vector2i, salt: int) -> int:
	return absi((cell.x * 73856093) ^ (cell.y * 19349663) ^ (salt * 83492791))
