class_name HeroModel
extends RefCounted
## Heroes lead finite expeditions; soldiers and heroes are reserved by saved active jobs.

const MAX_LEVEL := 5
const MAX_ARMY := 10000
const MAX_CARDS := 1000000
const PARTY_SIZE := 3
const UNLOCK_CARDS := 3
const CHEST_COST := {"stone": 60, "wood": 40, "essence": 15}
const RESOURCE_KEYS := ["stone", "wood", "essence"]
const ACTIVE_PHASES := ["outbound", "mining", "returning", "delivery_retry"]
const HEROES := [
	{"id": "warden", "name": "Бран", "role": "Страж камня", "resource": "stone", "portrait": "hero_0", "yield": 20, "damage": 10, "recruit_cost": {}},
	{"id": "ranger", "name": "Эйра", "role": "Следопыт лесов", "resource": "wood", "portrait": "hero_1", "yield": 25, "damage": 8, "recruit_cost": {}},
	{"id": "seer", "name": "Морвен", "role": "Хранительница эссенции", "resource": "essence", "portrait": "hero_2", "yield": 25, "damage": 12, "recruit_cost": {}},
	{"id": "marshal", "name": "Каэл", "role": "Воевода", "resource": "all", "portrait": "hero_3", "yield": 12, "damage": 25, "recruit_cost": {}},
]
const TROOPS := [
	{"id": "infantry", "name": "Пехота", "portrait": "troop_0", "building": 11, "damage": 10, "cost_per_unit": {"stone": 6, "wood": 4, "essence": 0}},
	{"id": "archer", "name": "Стрелки", "portrait": "troop_1", "building": 12, "damage": 13, "cost_per_unit": {"stone": 4, "wood": 7, "essence": 0}},
	{"id": "cavalry", "name": "Конница", "portrait": "troop_2", "building": 10, "damage": 18, "cost_per_unit": {"stone": 9, "wood": 6, "essence": 1}},
]

var store: ProgressStore
var _town: SettlementModel
var last_error := ""


func _init(progress_store: ProgressStore = null) -> void:
	if progress_store != null:
		configure(progress_store)


func configure(progress_store: ProgressStore) -> void:
	store = progress_store
	_town = SettlementModel.new()
	_town.configure(store)
	# New saves are initialized by ProgressStore. This also keeps migrated in-memory fixtures safe.
	if not store.data.get("heroes") is Dictionary:
		store.data["heroes"] = {"warden": 1}
	if store.data.heroes.is_empty():
		store.data.heroes["warden"] = 1
	if not store.data.get("army") is Dictionary:
		store.data["army"] = {"infantry": 20, "archer": 0, "cavalry": 0}
	for troop: Dictionary in TROOPS:
		if not store.data.army.has(troop.id):
			store.data.army[troop.id] = 0
	if not store.data.heroes.has(str(store.data.get("selected_hero", ""))):
		store.data["selected_hero"] = str(store.data.heroes.keys()[0])
	if _troop(str(store.data.get("selected_troop", ""))).is_empty():
		store.data["selected_troop"] = "infantry"
	if not store.data.get("hero_state") is Dictionary:
		store.data["hero_state"] = {"cards": {}, "chests": 0}
	if not store.data.hero_state.get("cards") is Dictionary:
		store.data.hero_state["cards"] = {}
	for hero: Dictionary in HEROES:
		if not store.data.hero_state.cards.has(hero.id):
			store.data.hero_state.cards[hero.id] = 0
	if not store.data.hero_state.has("chests"):
		store.data.hero_state["chests"] = 0


func catalog() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var city_bonuses := _town.expedition_bonuses() if _town != null else {}
	for hero: Dictionary in HEROES:
		var entry := hero.duplicate(true)
		var level := hero_level(str(hero.id))
		entry["level"] = level
		entry["cards"] = card_count(str(hero.id))
		entry["unlock_cards"] = 0 if hero.id == "warden" else UNLOCK_CARDS
		entry["upgrade_cards"] = level * 2 if level > 0 and level < MAX_LEVEL else 0
		entry["busy"] = hero_busy(str(hero.id))
		entry["damage_bonus"] = damage_bonus(str(hero.id)) if level > 0 else mini(150, int(hero.damage) + int(city_bonuses.get("party_damage_percent", 0)))
		entry["yield_bonuses"] = {}
		for resource in RESOURCE_KEYS:
			var base := int(hero["yield"]) if hero.resource in [resource, "all"] else 5
			entry.yield_bonuses[resource] = yield_bonus(str(hero.id), resource) if level > 0 else mini(100, base + int(city_bonuses.get("yield_percent", 0)))
		result.append(entry)
	return result


func owned() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if store == null:
		return result
	for hero: Dictionary in catalog():
		if not store.data.heroes.has(hero.id):
			continue
		var entry := hero.duplicate(true)
		entry["level"] = hero_level(str(hero.id))
		entry["busy"] = hero_busy(str(hero.id))
		entry["damage_bonus"] = damage_bonus(str(hero.id))
		entry["yield_bonuses"] = {}
		for resource in RESOURCE_KEYS:
			entry.yield_bonuses[resource] = yield_bonus(str(hero.id), resource)
		entry["upgrade_cost"] = {}
		result.append(entry)
	return result


func recruit(id: String) -> Dictionary:
	var hero := _hero(id)
	if store == null or hero.is_empty():
		return _failure("Неизвестный герой.")
	if store.data.heroes.has(id):
		return _failure("Этот герой уже в замке.")
	if _building_level(13) < 1:
		return _failure("Постройте таверну, чтобы приглашать героев.")
	if card_count(id) < UNLOCK_CARDS:
		return _failure("Для открытия героя нужны три его карты. Получайте их за уровни и из сундуков таверны.")
	var before := store.data.duplicate(true)
	store.data.hero_state.cards[id] = card_count(id) - UNLOCK_CARDS
	store.data.heroes[id] = 1
	store.data.selected_hero = id
	if not store.save_progress():
		store.data = before
		return _failure(store.last_error)
	last_error = ""
	return {"ok": true, "reason": "%s открыт за три карты и прибыл в таверну." % str(hero.name), "cost": {}, "cards_spent": UNLOCK_CARDS}


func upgrade_cost(_id: String) -> Dictionary:
	return {}


func upgrade(id: String) -> Dictionary:
	var level := hero_level(id)
	if level <= 0:
		return _failure("Сначала пригласите этого героя.")
	if level >= MAX_LEVEL:
		return _failure("Герой достиг пятого уровня.")
	if hero_busy(id):
		return _failure("Герой в походе. Улучшение доступно после возвращения отряда.")
	var needed := level * 2
	if card_count(id) < needed:
		return _failure("Для следующего уровня нужны %d карт этого героя." % needed)
	var before := store.data.duplicate(true)
	store.data.hero_state.cards[id] = card_count(id) - needed
	store.data.heroes[id] = level + 1
	if not store.save_progress():
		store.data = before
		return _failure(store.last_error)
	last_error = ""
	return {"ok": true, "reason": "%s: уровень %d. Навыки добычи и командования усилены." % [str(_hero(id).name), level + 1], "cost": {}, "cards_spent": needed}


func card_count(id: String) -> int:
	if store == null or _hero(id).is_empty():
		return 0
	return clampi(int(store.data.get("hero_state", {}).get("cards", {}).get(id, 0)), 0, MAX_CARDS)


func chest_cost() -> Dictionary:
	var discount := maxi(0, _building_level(13) - 1)
	var cost: Dictionary = {}
	for resource in RESOURCE_KEYS:
		cost[resource] = maxi(1, floori(int(CHEST_COST[resource]) * (100.0 - discount) / 100.0))
	return cost


func buy_chest() -> Dictionary:
	var cost := chest_cost()
	if store == null or _building_level(13) < 1:
		return _failure("Постройте таверну, чтобы открывать сундуки героев.")
	if not _can_pay(cost):
		return _failure("Недостаточно ресурсов на складе для сундука.", cost)
	if int(store.data.hero_state.chests) >= MAX_CARDS:
		return _failure("Достигнут предел сундуков этого сохранения.")
	var before := store.data.duplicate(true)
	_pay(cost)
	var counter := int(store.data.hero_state.chests) + 1
	var seed := (counter * 104729 + 7919) & 0x7fffffff
	var rewards: Dictionary = {}
	for index in range(3):
		seed = (seed * 1103515245 + 12345) & 0x7fffffff
		var id := str(HEROES[(seed >> 16) % HEROES.size()].id)
		var previous := card_count(id)
		if previous >= MAX_CARDS:
			store.data = before
			return _failure("Достигнут предел карт. Сундук не оплачен.")
		store.data.hero_state.cards[id] = previous + 1
		rewards[id] = int(rewards.get(id, 0)) + 1
	store.data.hero_state.chests = counter
	if not store.save_progress():
		store.data = before
		return _failure(store.last_error, cost)
	last_error = ""
	return {"ok": true, "reason": "Сундук открыт: три карты героев.", "cost": cost.duplicate(), "cards": rewards}


static func level_card_reward(level: int) -> Dictionary:
	if level <= 0 or (level % 3 != 0 and level % 10 != 0):
		return {}
	var hero: Dictionary = HEROES[(level / 3) % HEROES.size()]
	return {"hero_id": str(hero.id), "name": str(hero.name), "portrait": str(hero.portrait), "amount": 1}


static func grant_level_cards(data: Dictionary, level: int) -> Dictionary:
	var reward := level_card_reward(level)
	if reward.is_empty():
		return {}
	if not data.get("hero_state") is Dictionary:
		data["hero_state"] = {"cards": {}, "chests": 0}
	if not data.hero_state.get("cards") is Dictionary:
		data.hero_state["cards"] = {}
	var previous := clampi(int(data.hero_state.cards.get(reward.hero_id, 0)), 0, MAX_CARDS)
	if previous >= MAX_CARDS:
		return {}
	data.hero_state.cards[reward.hero_id] = previous + 1
	return reward


func select(id: String) -> Dictionary:
	if hero_level(id) <= 0:
		return _failure("Этот герой ещё не приглашён.")
	var before := store.data.duplicate(true)
	store.data.selected_hero = id
	if not store.save_progress():
		store.data = before
		return _failure(store.last_error)
	last_error = ""
	return {"ok": true, "reason": "%s выбран командиром следующего отряда." % str(_hero(id).name)}


func select_troop(type: String) -> Dictionary:
	if not troop_unlocked(type):
		return _failure("Постройте казарму, стрельбище или конюшню для этого рода войск.")
	var before := store.data.duplicate(true)
	store.data.selected_troop = type
	if not store.save_progress():
		store.data = before
		return _failure(store.last_error)
	last_error = ""
	return {"ok": true, "reason": "%s выбраны для следующего отряда." % str(_troop(type).name)}


func train(type: String, amount: int = 5) -> Dictionary:
	var troop := _troop(type)
	if store == null or troop.is_empty() or amount <= 0 or amount > 100:
		return _failure("Выберите от 1 до 100 воинов для обучения.")
	if _building_level(int(troop.building)) < 1:
		return _failure("Для обучения нужно построить соответствующее военное здание.")
	if int(store.data.army.get(type, 0)) + amount > MAX_ARMY:
		return _failure("Этот род войск достиг предела армии.")
	var cost: Dictionary = {}
	for resource in RESOURCE_KEYS:
		cost[resource] = int(troop.cost_per_unit.get(resource, 0)) * amount
	if not _can_pay(cost):
		return _failure("Недостаточно ресурсов на складе для обучения воинов.", cost)
	var before := store.data.duplicate(true)
	_pay(cost)
	store.data.army[type] = int(store.data.army.get(type, 0)) + amount
	if not store.save_progress():
		store.data = before
		return _failure(store.last_error, cost)
	last_error = ""
	return {"ok": true, "reason": "%s: обучено %d." % [str(troop.name), amount], "cost": cost, "amount": amount}


func hero_level(id: String) -> int:
	if store == null or _hero(id).is_empty():
		return 0
	return clampi(int(store.data.heroes.get(id, 0)), 0, MAX_LEVEL)


func hero_busy(id: String) -> bool:
	for job: Dictionary in _active_jobs():
		if str(job.get("hero_id", "")) == id:
			return true
	return false


func troop_unlocked(type: String) -> bool:
	var troop := _troop(type)
	if store == null or troop.is_empty():
		return false
	# The starting garrison can leave immediately; new infantry still require a barracks.
	return type == "infantry" or _building_level(int(troop.building)) >= 1


func available_troops(type: String) -> int:
	if store == null or _troop(type).is_empty():
		return 0
	var count := clampi(int(store.data.army.get(type, 0)), 0, MAX_ARMY)
	for job: Dictionary in _active_jobs():
		if str(job.get("troop_type", "")) == type:
			count -= maxi(0, int(job.get("troop_count", 0)))
	return maxi(0, count)


func yield_bonus(id: String, resource: String) -> int:
	var level := hero_level(id)
	var hero := _hero(id)
	if level <= 0 or resource not in RESOURCE_KEYS:
		return 0
	var base := int(hero["yield"]) if hero.resource in [resource, "all"] else 5
	return mini(100, base + (level - 1) * 5 + int(_town.expedition_bonuses().get("yield_percent", 0)))


func damage_bonus(id: String) -> int:
	var level := hero_level(id)
	return 0 if level <= 0 else mini(150, int(_hero(id).damage) + (level - 1) * 5 + int(_town.expedition_bonuses().get("party_damage_percent", 0)))


func extraction_cargo(id: String, resource: String, raw: int) -> int:
	# The raw stock is decremented by the expedition. The bonus is applied once to its cargo.
	var safe_raw := clampi(raw, 0, ProgressStore.MAX_RESOURCE)
	return mini(ProgressStore.MAX_RESOURCE, safe_raw + int(safe_raw * yield_bonus(id, resource) / 100))


func party_damage(id: String, type: String, count: int = PARTY_SIZE) -> int:
	var troop := _troop(type)
	if troop.is_empty() or hero_level(id) <= 0:
		return 0
	var veteran := 1.0 + maxi(0, _building_level(int(troop.building)) - 1) * 0.02
	var base := floori(int(troop.damage) * clampi(count, 0, MAX_ARMY) * veteran)
	return base + int(base * damage_bonus(id) / 100)


func dispatch_validation(id: String = "", type: String = "", resource: String = "") -> Dictionary:
	if store == null:
		return _failure("Замок ещё не загружен.")
	if id.is_empty():
		id = str(store.data.selected_hero)
	if type.is_empty():
		type = str(store.data.selected_troop)
	if hero_level(id) <= 0:
		return _failure("Выберите приглашённого героя.")
	if hero_busy(id):
		return _failure("Этот герой уже ведёт отряд. Выберите другого героя в таверне.")
	if not troop_unlocked(type):
		return _failure("Этот род войск ещё не открыт.")
	if available_troops(type) < PARTY_SIZE:
		return _failure("Нужно три свободных воина. Обучите их или дождитесь возвращения отряда.")
	last_error = ""
	return {"ok": true, "reason": "Герой и три воина готовы к походу.", "hero_id": id, "troop_type": type,
		"troop_count": PARTY_SIZE, "yield_bonus": yield_bonus(id, resource), "damage_bonus": damage_bonus(id),
		"party_damage": party_damage(id, type)}


func party_for_job(job_id: int) -> Dictionary:
	for job: Dictionary in _active_jobs():
		if int(job.get("id", -1)) != job_id:
			continue
		var hero_id := str(job.get("hero_id", "warden"))
		var type := str(job.get("troop_type", "infantry"))
		var count := int(job.get("troop_count", PARTY_SIZE))
		var result := {"hero_id": hero_id, "hero_name": str(_hero(hero_id).get("name", hero_id)), "troop_type": type,
			"troop_count": count, "yield_bonus": int(job.get("yield_bonus", 0)), "damage_bonus": int(job.get("damage_bonus", 0))}
		var base := int(_troop(type).get("damage", 0)) * count
		result["party_damage"] = int(job.get("party_damage", base + int(base * int(result.damage_bonus) / 100)))
		return result
	return {}


func info() -> Dictionary:
	if store == null:
		return {}
	var troops: Array[Dictionary] = []
	var available: Dictionary = {}
	for troop: Dictionary in TROOPS:
		var entry := troop.duplicate(true)
		var type := str(troop.id)
		entry["unlocked"] = troop_unlocked(type)
		entry["training_unlocked"] = _building_level(int(troop.building)) >= 1
		entry["count"] = int(store.data.army.get(type, 0))
		entry["available"] = available_troops(type)
		entry["party_damage"] = party_damage(str(store.data.selected_hero), type)
		troops.append(entry)
		available[type] = int(entry.available)
	return {"heroes": owned(), "selected_hero": str(store.data.selected_hero), "selected_troop": str(store.data.selected_troop),
		"army": store.data.army.duplicate(), "available_army": available, "troops": troops,
		"recruit_unlocked": _building_level(13) >= 1, "tavern_level": _building_level(13), "party_size": PARTY_SIZE,
		"chest_cost": chest_cost(), "chest_count": int(store.data.hero_state.chests),
		"card_chances": "25% каждому герою", "cards": store.data.hero_state.cards.duplicate()}


func _building_level(kind: int) -> int:
	if store == null:
		return 0
	var buildings: Array = store.data.get("buildings", [])
	var upgrades: Array = store.data.get("upgrades", [])
	var level := 0
	for slot in range(mini(buildings.size(), upgrades.size())):
		if int(buildings[slot]) == kind:
			level = maxi(level, clampi(int(upgrades[slot]), 0, SettlementModel.MAX_UPGRADE) + 1)
	return level


func _active_jobs() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if store == null:
		return result
	var state: Variant = store.data.get("expedition_state", {})
	if not state is Dictionary or not state.get("jobs") is Array:
		return result
	for candidate: Variant in state.jobs:
		if candidate is Dictionary and str(candidate.get("phase", "")) in ACTIVE_PHASES:
			result.append(candidate)
	return result


func _hero(id: String) -> Dictionary:
	for hero: Dictionary in HEROES:
		if str(hero.id) == id:
			return hero
	return {}


func _troop(id: String) -> Dictionary:
	for troop: Dictionary in TROOPS:
		if str(troop.id) == id:
			return troop
	return {}


func _can_pay(cost: Dictionary) -> bool:
	for resource in RESOURCE_KEYS:
		if int(store.data.resources.get(resource, 0)) < int(cost.get(resource, 0)):
			return false
	return true


func _pay(cost: Dictionary) -> void:
	for resource in RESOURCE_KEYS:
		store.data.resources[resource] = int(store.data.resources[resource]) - int(cost.get(resource, 0))


func _failure(reason: String, cost: Dictionary = {}) -> Dictionary:
	last_error = reason
	return {"ok": false, "reason": reason, "cost": cost}
