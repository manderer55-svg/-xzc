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
