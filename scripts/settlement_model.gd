class_name SettlementModel
extends RefCounted
## An expansive colony; production accrues in whole minutes, capped at eight offline hours.

const TITLES := ["Каменоломня", "Лесопилка", "Святилище", "Замок", "Кузница", "Башня", "Ратуша", "Цитадель", "Зал альянса", "Рынок", "Конюшня", "Казармы", "Стрельбище", "Таверна", "Склад альянса"]
const RESOURCE_KEYS := ["stone", "wood", "essence"]
const MINE_INTERVAL := 60
const OFFLINE_CAP := 8 * 60 * 60
const MAX_UPGRADE := 19
const MAX_RESOURCE := 1000000000
const SLOT_COUNT := ColonyMap.SLOT_COUNT
const BUILD_COSTS := [
	{"stone": 40, "wood": 35, "essence": 0},
	{"stone": 60, "wood": 45, "essence": 10},
	{"stone": 80, "wood": 65, "essence": 20},
	{"stone": 160, "wood": 140, "essence": 75},
	{"stone": 90, "wood": 80, "essence": 30},
	{"stone": 120, "wood": 70, "essence": 40},
	{"stone": 100, "wood": 90, "essence": 20},
	{"stone": 220, "wood": 170, "essence": 70},
	{"stone": 120, "wood": 120, "essence": 35},
	{"stone": 100, "wood": 100, "essence": 15},
	{"stone": 120, "wood": 150, "essence": 20},
	{"stone": 80, "wood": 100, "essence": 5},
	{"stone": 90, "wood": 120, "essence": 10},
	{"stone": 100, "wood": 90, "essence": 20},
	{"stone": 140, "wood": 110, "essence": 30},
]
const BUILDING_DEFS := [
	{"key": "quarry", "title": TITLES[0], "cost": BUILD_COSTS[0], "production": Vector3i(8, 0, 0), "description": "Каменоломня ускоряет добычу камня с каждым уровнем и даёт дополнительные ходы матч-3."},
	{"key": "sawmill", "title": TITLES[1], "cost": BUILD_COSTS[1], "production": Vector3i(0, 7, 0), "description": "Лесопилка ускоряет добычу дерева, даёт ход и повышает награды матч-3."},
	{"key": "shrine", "title": TITLES[2], "cost": BUILD_COSTS[2], "production": Vector3i(0, 0, 3), "description": "Святилище ускоряет добычу эссенции и даёт усилители матч-3."},
	{"key": "fortress", "title": TITLES[3], "cost": BUILD_COSTS[3], "production": Vector3i(3, 3, 2), "description": "Замок открывает до четырёх очередей; каждый следующий уровень ускоряет походы."},
	{"key": "forge", "title": TITLES[4], "cost": BUILD_COSTS[4], "production": Vector3i(5, 0, 0), "description": "Кузница ускоряет добычу инструментами, даёт бомбу матч-3 и усиливает оружие."},
	{"key": "watchtower", "title": TITLES[5], "cost": BUILD_COSTS[5], "production": Vector3i(0, 0, 2), "description": "Башня ускоряет походы разведкой, усиливает отряды и урон печатям матч-3."},
	{"key": "townhall", "title": TITLES[6], "cost": BUILD_COSTS[6], "production": Vector3i.ZERO, "description": "Ратуша открывает до четырёх очередей и сокращает время работ на 2% за уровень."},
	{"key": "citadel", "title": TITLES[7], "cost": BUILD_COSTS[7], "production": Vector3i.ZERO, "description": "Цитадель ускоряет строительство, повышает силу отрядов и урон боссам матч-3."},
	{"key": "alliance_hall", "title": TITLES[8], "cost": BUILD_COSTS[8], "production": Vector3i.ZERO, "description": "Зал альянса улучшает снабжение: отряды привозят больше ресурсов с месторождений."},
	{"key": "market", "title": TITLES[9], "cost": BUILD_COSTS[9], "production": Vector3i.ZERO, "description": "Рынок снижает цену улучшений на 1% за уровень и повышает награды матч-3."},
	{"key": "stable", "title": TITLES[10], "cost": BUILD_COSTS[10], "production": Vector3i.ZERO, "description": "Конюшня открывает конницу; каждый уровень ускоряет походы всех отрядов."},
	{"key": "barracks", "title": TITLES[11], "cost": BUILD_COSTS[11], "production": Vector3i.ZERO, "description": "Казармы открывают обучение пехоты; уровни повышают её силу и скорость добычи."},
	{"key": "archery", "title": TITLES[12], "cost": BUILD_COSTS[12], "production": Vector3i.ZERO, "description": "Стрельбище открывает стрелков; уровни повышают их силу и скорость добычи."},
	{"key": "tavern", "title": TITLES[13], "cost": BUILD_COSTS[13], "production": Vector3i.ZERO, "description": "Таверна открывает героев и сундуки; следующие уровни снижают цену сундуков."},
	{"key": "alliance_store", "title": TITLES[14], "cost": BUILD_COSTS[14], "production": Vector3i.ZERO, "description": "Склад альянса улучшает доставку и повышает количество привезённых ресурсов."},
]
const BUNKER_COSTS := [
	{"stone": 120, "wood": 80, "essence": 20},
	{"stone": 220, "wood": 130, "essence": 35},
	{"stone": 360, "wood": 180, "essence": 60},
]
const BUNKER_STAGES := ["Разметка участка", "Фундамент", "Стены и перекрытия", "Укреплённый бункер"]

var store: ProgressStore


func configure(progress_store: ProgressStore) -> void:
	store = progress_store
	sync_construction()


func get_build_cost(kind: int) -> Dictionary:
	if kind < 0 or kind >= BUILD_COSTS.size():
		return {}
	return BUILD_COSTS[kind].duplicate()


func get_building_description(kind: int) -> String:
	return str(BUILDING_DEFS[kind].description) if kind >= 0 and kind < BUILDING_DEFS.size() else ""


func highest_building_level(kind: int) -> int:
	var tiers := _strongest_tiers()
	return tiers[kind] + 1 if kind >= 0 and kind < tiers.size() else 0


func expedition_capacity() -> int:
	return clampi(maxi(highest_building_level(3), highest_building_level(6)), 1, 4)


func expedition_bonuses() -> Dictionary:
	return {
		"yield_percent": mini(60, highest_building_level(8) * 2 + highest_building_level(14)),
		"party_damage_percent": mini(100, highest_building_level(7) * 2 + highest_building_level(3) + highest_building_level(4) + highest_building_level(5)),
	}


func mining_batch(resource: String) -> int:
	var kind := RESOURCE_KEYS.find(resource)
	return 5 + maxi(0, highest_building_level(kind) - 1)


func mining_seconds(troop_type: String) -> float:
	var kind: int = {"infantry": 11, "archer": 12, "cavalry": 10}.get(troop_type, 11)
	var discipline := maxi(0, highest_building_level(kind) - 1) * 0.02
	var tools := highest_building_level(4) * 0.01
	return 5.0 * maxf(0.4, 1.0 - discipline - tools)


func march_seconds(troop_type: String) -> float:
	var reduction := highest_building_level(3) * 0.0075 + highest_building_level(10) * 0.0125 + highest_building_level(5) * 0.005
	if troop_type == "cavalry":
		reduction += 0.15
	return 1.5 * maxf(0.45, 1.0 - reduction)


func work_seconds(level: int) -> int:
	return maxi(60, ceili(construction_seconds(level) * (1.0 - highest_building_level(6) * 0.02 - highest_building_level(7) * 0.005)))


func get_upgrade_cost(slot: int) -> Dictionary:
	if not _valid_slot(slot) or int(store.data["buildings"][slot]) < 0:
		return {}
	var kind := int(store.data["buildings"][slot])
	if kind >= BUILD_COSTS.size():
		return {}
	var tier := clampi(int(store.data["upgrades"][slot]), 0, MAX_UPGRADE)
	if tier >= MAX_UPGRADE:
		return {}
	var level := tier + 2
	var multiplier := upgrade_multiplier(level)
	var discount := 1.0 - highest_building_level(9) * 0.01
	return {"stone": ceili(int(BUILD_COSTS[kind].stone) * multiplier * discount),
		"wood": ceili(int(BUILD_COSTS[kind].wood) * multiplier * discount),
		"essence": ceili((int(BUILD_COSTS[kind].essence) + 8) * multiplier * discount)}


static func upgrade_multiplier(level: int) -> int:
	var early := [1, 3, 12, 40, 100, 250]
	return early[level - 1] if level <= 6 else ceili(250.0 * pow(1.4, level - 6))


static func construction_seconds(level: int) -> int:
	var early := [120, 600, 1200, 1800, 3600, 7200]
	return early[level - 1] if level <= 6 else mini(86400, ceili(7200.0 * pow(1.35, level - 6)))


func construction_job() -> Dictionary:
	var jobs: Array = store.data.get("construction", [])
	return jobs[0] if not jobs.is_empty() else {}


func construction_remaining(now: int = -1) -> int:
	var job := construction_job()
	if job.is_empty():
		return 0
	return maxi(0, int(job.ends_at) - (int(Time.get_unix_time_from_system()) if now < 0 else now))


func sync_construction(now: int = -1) -> bool:
	var job := construction_job()
	if job.is_empty() or construction_remaining(now) > 0:
		return false
	var before := store.data.duplicate(true)
	var slot := int(job.slot)
	if slot == -1:
		store.data.bunker_level = int(job.target_level)
	elif _valid_slot(slot):
		store.data.buildings[slot] = int(job.kind)
		store.data.upgrades[slot] = int(job.target_level) - 1
	store.data.construction = []
	if not store.save_progress():
		store.data = before
		return false
	return true


func _schedule(slot: int, kind: int, target_level: int, cost: Dictionary) -> Dictionary:
	sync_construction()
	if not construction_job().is_empty():
		return _failure("Строители заняты. Дождитесь завершения текущей работы.", cost)
	if not _can_pay(cost):
		return _failure("Недостаточно ресурсов на складе.", cost)
	var before := store.data.duplicate(true)
	_pay(cost)
	var now := int(Time.get_unix_time_from_system())
	var duration := work_seconds(target_level)
	store.data.construction = [{"slot": slot, "kind": kind, "target_level": target_level, "started_at": now, "ends_at": now + duration}]
	if not store.save_progress():
		store.data = before
		return _failure(store.last_error, cost)
	return {"ok": true, "reason": "Работы начались: %d минут. Продолжаются вне игры." % (duration / 60), "cost": cost, "duration": duration}


func build(slot: int, kind: int) -> Dictionary:
	sync_construction()
	var cost := get_build_cost(kind)
	if not _valid_slot(slot) or cost.is_empty():
		return _failure("Неизвестный участок или здание.", cost)
	if int(store.data.buildings[slot]) >= 0:
		return _failure("На участке уже есть здание.", cost)
	return _schedule(slot, kind, 1, cost)


func upgrade(slot: int) -> Dictionary:
	sync_construction()
	if not _valid_slot(slot) or int(store.data.buildings[slot]) < 0:
		return _failure("Выберите построенное здание.", {})
	if int(store.data.upgrades[slot]) >= MAX_UPGRADE:
		return _failure("Достигнут максимальный уровень здания.", {})
	return _schedule(slot, int(store.data.buildings[slot]), int(store.data.upgrades[slot]) + 2, get_upgrade_cost(slot))


func production() -> Dictionary:
	var output := {"stone": 0, "wood": 0, "essence": 0}
	if store == null:
		return output
	for slot in range(_slot_capacity()):
		var site := production_for_slot(slot)
		for resource in RESOURCE_KEYS:
			output[resource] = mini(MAX_RESOURCE, int(output[resource]) + int(site[resource]))
	return output

func production_for_slot(slot: int) -> Dictionary:
	var output := {"stone": 0, "wood": 0, "essence": 0}
	if not _valid_slot(slot):
		return output
	var tier := clampi(int(store.data.upgrades[slot]), 0, MAX_UPGRADE) + 1
	var kind := int(store.data.buildings[slot])
	if kind >= 0 and kind < BUILDING_DEFS.size():
		var rates: Vector3i = BUILDING_DEFS[kind].production
		for index in range(3):
			output[RESOURCE_KEYS[index]] = rates[index] * tier
	return output

func stage_production() -> bool:
	var before := store.data.duplicate(true)
	store.data.colony_mode = true
	_accrue(int(Time.get_unix_time_from_system()))
	if store.data == before:
		return true
	if not store.save_progress():
		store.data = before
		return false
	return true

func deliver_cargo(resource: String, requested: int) -> Dictionary:
	if resource not in RESOURCE_KEYS or requested <= 0:
		return _failure("Пустой груз.", {})
	var before := store.data.duplicate(true)
	var amount := mini(requested, mini(int(store.data.colony_pending.get(resource, 0)), MAX_RESOURCE - int(store.data.resources[resource])))
	if amount <= 0:
		return _failure("Склад заполнен или руда ещё не добыта.", {})
	store.data.colony_pending[resource] -= amount
	store.data.resources[resource] += amount
	if not store.save_progress():
		store.data = before
		return _failure(store.last_error, {})
	return {"ok": true, "resource": resource, "amount": amount}

func bunker_cost() -> Dictionary:
	var level := int(store.data.get("bunker_level", 0))
	return BUNKER_COSTS[level].duplicate() if level < BUNKER_COSTS.size() else {}

func build_bunker() -> Dictionary:
	sync_construction()
	var cost := bunker_cost()
	if cost.is_empty():
		return _failure("Бункер полностью построен.", {})
	return _schedule(-1, -1, int(store.data.bunker_level) + 1, cost)


func battle_bonuses() -> Dictionary:
	var output := {
		"bonus_moves": 0,
		"starting_specials": 0,
		"boss_damage_bonus": 0,
		"reward_percent": 0,
		"essence_boost": 0,
		"forge_bomb": 0,
		"seal_damage_bonus": 0,
	}
	var tiers := _strongest_tiers()
	if tiers[0] >= 0:
		output["bonus_moves"] += 1 + int(tiers[0] >= 2)
	if tiers[1] >= 0:
		output["bonus_moves"] += 1
		output["reward_percent"] += 5 * (tiers[1] + 1)
	if tiers[2] >= 0:
		output["starting_specials"] = 1 + int(tiers[2] >= 2)
		output["essence_boost"] = tiers[2] + 1
	if tiers[3] >= 0:
		output["boss_damage_bonus"] = 1 + int(tiers[3] >= 2)
		output["reward_percent"] += 10 + tiers[3] * 5
	if tiers[4] >= 0:
		output["forge_bomb"] = 1
	if tiers[5] >= 0:
		output["seal_damage_bonus"] = 1
	if tiers[7] >= 2:
		output["boss_damage_bonus"] = mini(2, int(output["boss_damage_bonus"]) + 1)
	if tiers[9] >= 0:
		output["reward_percent"] += 2 * (tiers[9] + 1)
	output["bonus_moves"] = mini(3, int(output["bonus_moves"]))
	if int(store.data.get("bunker_level", 0)) >= 2:
		output["essence_boost"] = mini(ProgressStore.MAX_ESSENCE_BOOST, int(output["essence_boost"]) + int(store.data.bunker_level) - 1)
	output["reward_percent"] = mini(ProgressStore.MAX_REWARD_PERCENT, int(output["reward_percent"]))
	return output


func bonus_descriptions() -> Array[String]:
	var descriptions: Array[String] = []
	var tiers := _strongest_tiers()
	if tiers[0] >= 0:
		var moves := 1 + int(tiers[0] >= 2)
		descriptions.append("Каменоломня: +%d %s в каждом разломе." % [moves, "ход" if moves == 1 else "хода"])
	if tiers[1] >= 0:
		descriptions.append("Лесопилка: +1 ход и +%d%% к наградам за победу." % (5 * (tiers[1] + 1)))
	if tiers[2] >= 0:
		descriptions.append("Святилище: спецкристаллы в начале — %d; эссенция за победу +%d." % [1 + int(tiers[2] >= 2), tiers[2] + 1])
	if tiers[3] >= 0:
		descriptions.append("Замок: +%d урона боссам и +%d%% к наградам." % [1 + int(tiers[3] >= 2), 10 + tiers[3] * 5])
	if tiers[4] >= 0:
		descriptions.append("Кузница: дополнительная бомба в начале каждой попытки.")
	if tiers[5] >= 0:
		descriptions.append("Башня: +1 урон печатям от совпадений и усилителей.")
	for kind in range(6, BUILDING_DEFS.size()):
		if tiers[kind] >= 0:
			descriptions.append(TITLES[kind] + ": " + get_building_description(kind))
	if int(store.data.get("bunker_level", 0)) >= 2:
		descriptions.append("Бункер: дополнительная эссенция за первое прохождение.")
	if descriptions.is_empty():
		descriptions.append("Постройте здания, чтобы усилить походы в разломы.")
	elif tiers[1] >= 0 and tiers[3] >= 0:
		descriptions.append("Общий бонус наград: +%d%% (предел +30%%)." % int(battle_bonuses()["reward_percent"]))
	return descriptions


func mine() -> Dictionary:
	var empty := {"stone": 0, "wood": 0, "essence": 0}
	if store == null:
		return {"ok": false, "reason": "Поселение ещё не загружено.", "rewards": empty}
	if bool(store.data.get("expedition_mode", false)):
		return {"ok": false, "reason": "Отправьте свободный отряд к месторождению на карте мира.", "rewards": empty}
	if bool(store.data.get("colony_mode", false)):
		return {"ok": stage_production(), "reason": "Рабочие доставят добытую руду на склад.", "rewards": empty}
	var output := production()
	if int(output["stone"]) + int(output["wood"]) + int(output["essence"]) == 0:
		return {"ok": false, "reason": "Постройте первое добывающее здание.", "rewards": empty}
	var now := int(Time.get_unix_time_from_system())
	var before := store.data.duplicate(true)
	var rewards := _accrue(now)
	var earned := int(rewards["stone"]) + int(rewards["wood"]) + int(rewards["essence"])
	if earned == 0:
		# Persist clock repairs and consumed production even when the warehouses are full.
		if int(before["last_mine_time"]) != int(store.data["last_mine_time"]) and not store.save_progress():
			store.data = before
			return {"ok": false, "reason": store.last_error, "rewards": empty}
		if int(before["last_mine_time"]) > 0 and now - int(before["last_mine_time"]) >= MINE_INTERVAL:
			return {"ok": false, "reason": "Хранилища заполнены. Потратьте ресурсы на строительство.", "rewards": empty}
		return {"ok": false, "reason": "Добыча будет готова через %d сек." % seconds_until_mine(), "rewards": empty}
	if not store.save_progress():
		store.data = before
		return {"ok": false, "reason": store.last_error, "rewards": empty}
	return {"ok": true, "reason": "Добыча собрана.", "rewards": rewards}


func seconds_until_mine() -> int:
	if store == null:
		return MINE_INTERVAL
	var elapsed := maxi(0, int(Time.get_unix_time_from_system()) - int(store.data["last_mine_time"]))
	return maxi(0, MINE_INTERVAL - elapsed)


func _accrue(now: int) -> Dictionary:
	var rewards := {"stone": 0, "wood": 0, "essence": 0}
	var last := int(store.data["last_mine_time"])
	if bool(store.data.get("expedition_mode", false)):
		# Finite manual expeditions are the only city-resource source in the new mode.
		store.data["last_mine_time"] = now
		return rewards
	if last <= 0 or last > now:
		store.data["last_mine_time"] = now
		return rewards
	var elapsed := mini(now - last, OFFLINE_CAP)
	var cycles := elapsed / MINE_INTERVAL
	if cycles < 1:
		return rewards
	var output := production()
	for resource in RESOURCE_KEYS:
		if bool(store.data.get("colony_mode", false)):
			var pending := int(store.data.colony_pending[resource])
			var next_pending := mini(MAX_RESOURCE, pending + int(output[resource]) * cycles)
			rewards[resource] = next_pending - pending
			store.data.colony_pending[resource] = next_pending
			continue
		var previous := int(store.data["resources"][resource])
		var next := mini(MAX_RESOURCE, previous + int(output[resource]) * cycles)
		rewards[resource] = next - previous
		store.data["resources"][resource] = next
	# The cap is consumed in one collection; repeated clicks cannot claim another eight hours.
	store.data["last_mine_time"] = now - (elapsed % MINE_INTERVAL)
	return rewards


func _valid_slot(slot: int) -> bool:
	return slot >= 0 and slot < _slot_capacity()


func _slot_capacity() -> int:
	if store == null:
		return 0
	# Old in-memory fixtures and restored version-two saves remain safe during migration.
	var buildings: Variant = store.data.get("buildings", [])
	var upgrades: Variant = store.data.get("upgrades", [])
	if not buildings is Array or not upgrades is Array:
		return 0
	return mini(SLOT_COUNT, mini(buildings.size(), upgrades.size()))


func _strongest_tiers() -> Array[int]:
	# Duplicate buildings increase production, but only the strongest of each kind aids battle.
	var tiers: Array[int] = []
	tiers.resize(BUILDING_DEFS.size())
	tiers.fill(-1)
	if store == null:
		return tiers
	for slot in range(_slot_capacity()):
		var kind := int(store.data["buildings"][slot])
		if kind >= 0 and kind < tiers.size():
			tiers[kind] = maxi(tiers[kind], clampi(int(store.data["upgrades"][slot]), 0, MAX_UPGRADE))
	return tiers


func _can_pay(cost: Dictionary) -> bool:
	for resource in RESOURCE_KEYS:
		if int(store.data["resources"][resource]) < int(cost.get(resource, 0)):
			return false
	return true


func _pay(cost: Dictionary) -> void:
	for resource in RESOURCE_KEYS:
		store.data["resources"][resource] = int(store.data["resources"][resource]) - int(cost.get(resource, 0))


func _failure(reason: String, cost: Dictionary) -> Dictionary:
	return {"ok": false, "reason": reason, "cost": cost}
