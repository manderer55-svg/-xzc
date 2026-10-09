class_name SettlementModel
extends RefCounted
## Nine-slot outpost; production accrues in whole minutes, capped at eight offline hours.

const TITLES := ["Каменоломня", "Лесопилка", "Святилище", "Крепость"]
const RESOURCE_KEYS := ["stone", "wood", "essence"]
const MINE_INTERVAL := 60
const OFFLINE_CAP := 8 * 60 * 60
const MAX_UPGRADE := 3
const MAX_RESOURCE := 1000000000
const BUILD_COSTS := [
	{"stone": 40, "wood": 35, "essence": 0},
	{"stone": 60, "wood": 45, "essence": 10},
	{"stone": 80, "wood": 65, "essence": 20},
	{"stone": 160, "wood": 140, "essence": 75},
]

var store: ProgressStore


func configure(progress_store: ProgressStore) -> void:
	store = progress_store


func get_build_cost(kind: int) -> Dictionary:
	if kind < 0 or kind >= BUILD_COSTS.size():
		return {}
	return BUILD_COSTS[kind].duplicate()


func get_upgrade_cost(slot: int) -> Dictionary:
	if not _valid_slot(slot) or int(store.data["buildings"][slot]) < 0:
		return {}
	var kind := int(store.data["buildings"][slot])
	var tier := int(store.data["upgrades"][slot])
	if tier >= MAX_UPGRADE:
		return {}
	var multiplier := tier + 2
	return {
		"stone": int(BUILD_COSTS[kind]["stone"]) * multiplier,
		"wood": int(BUILD_COSTS[kind]["wood"]) * multiplier,
		"essence": (int(BUILD_COSTS[kind]["essence"]) + 8) * multiplier,
	}


func build(slot: int, kind: int) -> Dictionary:
	var cost := get_build_cost(kind)
	if not _valid_slot(slot) or cost.is_empty():
		return _failure("Неизвестный участок или здание.", cost)
	if int(store.data["buildings"][slot]) >= 0:
		return _failure("На участке уже есть здание.", cost)
	var before := store.data.duplicate(true)
	var now := int(Time.get_unix_time_from_system())
	_accrue(now)
	if not _can_pay(cost):
		store.data = before
		return _failure("Недостаточно ресурсов. Пройдите уровни или соберите добычу.", cost)
	_pay(cost)
	store.data["buildings"][slot] = kind
	store.data["upgrades"][slot] = 0
	# New capacity starts now, never retroactively producing before construction.
	store.data["last_mine_time"] = now
	if not store.save_progress():
		store.data = before
		return _failure(store.last_error, cost)
	return {"ok": true, "reason": TITLES[kind] + " построена.", "cost": cost}


func upgrade(slot: int) -> Dictionary:
	if not _valid_slot(slot) or int(store.data["buildings"][slot]) < 0:
		return _failure("Выберите построенное здание.", {})
	if int(store.data["upgrades"][slot]) >= MAX_UPGRADE:
		return _failure("Достигнут максимальный уровень здания.", {})
	var cost := get_upgrade_cost(slot)
	var before := store.data.duplicate(true)
	var now := int(Time.get_unix_time_from_system())
	_accrue(now)
	if not _can_pay(cost):
		store.data = before
		return _failure("Недостаточно ресурсов для улучшения.", cost)
	_pay(cost)
	store.data["upgrades"][slot] = int(store.data["upgrades"][slot]) + 1
	store.data["last_mine_time"] = now
	if not store.save_progress():
		store.data = before
		return _failure(store.last_error, cost)
	return {"ok": true, "reason": "Здание улучшено. Добыча увеличена.", "cost": cost}


func production() -> Dictionary:
	var output := {"stone": 0, "wood": 0, "essence": 0}
	if store == null:
		return output
	for slot in range(9):
		var tier := int(store.data["upgrades"][slot]) + 1
		match int(store.data["buildings"][slot]):
			0:
				output["stone"] += 8 * tier
			1:
				output["wood"] += 7 * tier
			2:
				output["essence"] += 3 * tier
			3:
				output["stone"] += 3 * tier
				output["wood"] += 3 * tier
				output["essence"] += 2 * tier
	return output


func battle_bonuses() -> Dictionary:
	var output := {
		"bonus_moves": 0,
		"starting_specials": 0,
		"boss_damage_bonus": 0,
		"reward_percent": 0,
		"essence_boost": 0,
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
	output["bonus_moves"] = mini(3, int(output["bonus_moves"]))
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
		descriptions.append("Крепость: +%d урона боссам и +%d%% к наградам." % [1 + int(tiers[3] >= 2), 10 + tiers[3] * 5])
	if descriptions.is_empty():
		descriptions.append("Постройте здания, чтобы усилить походы в разломы.")
	elif tiers[1] >= 0 and tiers[3] >= 0:
		descriptions.append("Общий бонус наград: +%d%% (предел +30%%)." % int(battle_bonuses()["reward_percent"]))
	return descriptions


func mine() -> Dictionary:
	var empty := {"stone": 0, "wood": 0, "essence": 0}
	if store == null:
		return {"ok": false, "reason": "Поселение ещё не загружено.", "rewards": empty}
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
	if last <= 0 or last > now:
		store.data["last_mine_time"] = now
		return rewards
	var elapsed := mini(now - last, OFFLINE_CAP)
	var cycles := elapsed / MINE_INTERVAL
	if cycles < 1:
		return rewards
	var output := production()
	for resource in RESOURCE_KEYS:
		var previous := int(store.data["resources"][resource])
		var next := mini(MAX_RESOURCE, previous + int(output[resource]) * cycles)
		rewards[resource] = next - previous
		store.data["resources"][resource] = next
	# The cap is consumed in one collection; repeated clicks cannot claim another eight hours.
	store.data["last_mine_time"] = now - (elapsed % MINE_INTERVAL)
	return rewards


func _valid_slot(slot: int) -> bool:
	return store != null and slot >= 0 and slot < 9


func _strongest_tiers() -> Array[int]:
	# Duplicate buildings increase production, but only the strongest of each kind aids battle.
	var tiers: Array[int] = [-1, -1, -1, -1]
	if store == null:
		return tiers
	for slot in range(9):
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
