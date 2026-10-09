class_name ProgressStore
extends RefCounted
## Local campaign progress. A malformed save is preserved before new data may replace it.

const RESOURCE_KEYS := ["stone", "wood", "essence"]
const MAX_RESOURCE := 1000000000
const MAX_LEVEL := 1000000
const MAX_REWARD_PERCENT := 30
const MAX_ESSENCE_BOOST := 4
const SETTING_KEYS := ["reduced_effects", "haptics", "sound"]
const LEGACY_SLOT_COUNT := 9
const SLOT_COUNT := ColonyMap.SLOT_COUNT
const HERO_IDS := ["warden", "ranger", "seer", "marshal"]
const TROOP_IDS := ["infantry", "archer", "cavalry"]

var path: String = "user://progress.json"
var data: Dictionary = {}
var last_error: String = ""
var corrupt_backup_path: String = ""
## Award outcomes stay separate from reward amounts: zero can mean replay, locked or failed save.
var last_award_status: String = "idle"
var last_hero_reward: Dictionary = {}
var _save_allowed: bool = true


func _init() -> void:
	data = defaults()


func defaults() -> Dictionary:
	var buildings: Array = []
	buildings.resize(SLOT_COUNT)
	buildings.fill(-1)
	var upgrades: Array = []
	upgrades.resize(SLOT_COUNT)
	upgrades.fill(0)
	return {
		"version": 2,
		"level": 1,
		"best_scores": {},
		"resources": {"stone": 70, "wood": 50, "essence": 5},
		"buildings": buildings,
		"upgrades": upgrades,
		"construction": [],
		"banked_levels": {},
		"last_mine_time": int(Time.get_unix_time_from_system()),
		"settings": {"reduced_effects": false, "haptics": true, "sound": true},
		"colony_mode": false,
		"colony_pending": {"stone": 0, "wood": 0, "essence": 0},
		"bunker_level": 0,
		"expedition_mode": false,
		"expedition_state": {},
		"heroes": {"warden": 1},
		"hero_state": {"cards": {"warden": 0, "ranger": 0, "seer": 0, "marshal": 0}, "chests": 0},
		"selected_hero": "warden",
		"selected_troop": "infantry",
		"army": {"infantry": 20, "archer": 0, "cavalry": 0},
	}


func load_progress() -> bool:
	data = defaults()
	last_error = ""
	corrupt_backup_path = ""
	last_award_status = "idle"
	last_hero_reward = {}
	_save_allowed = true
	if not FileAccess.file_exists(path):
		return true
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		last_error = "Не удалось прочитать сохранение. Исходный файл сохранён."
		_save_allowed = false
		return false
	var contents := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(contents) != OK or not _valid_shape(json.data):
		return _preserve_corrupt_save()
	data = _normalize(json.data)
	return true


func save_progress() -> bool:
	last_error = ""
	if not _save_allowed:
		last_error = "Сохранение защищено: сначала восстановите доступ к исходному файлу."
		return false
	var absolute := ProjectSettings.globalize_path(path)
	var dir_error := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if dir_error != OK:
		last_error = "Не удалось создать папку сохранения."
		return false
	var temporary := absolute + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		last_error = "Не удалось записать временное сохранение."
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		last_error = "Запись сохранения не завершена."
		DirAccess.remove_absolute(temporary)
		return false
	if DirAccess.rename_absolute(temporary, absolute) != OK:
		last_error = "Не удалось заменить сохранение. Исходный файл сохранён."
		DirAccess.remove_absolute(temporary)
		return false
	return true


func award_level(level: int, score: int, won: bool, collected: Dictionary, bonuses: Dictionary = {}) -> Dictionary:
	var rewards := {"stone": 0, "wood": 0, "essence": 0}
	last_error = ""
	last_award_status = "invalid"
	last_hero_reward = {}
	if level < 1 or level > MAX_LEVEL:
		return rewards
	var before := data.duplicate(true)
	var hero_reward: Dictionary = {}
	var key := str(level)
	var safe_score := clampi(score, 0, 10000000)
	data["best_scores"][key] = maxi(int(data["best_scores"].get(key, 0)), safe_score)
	last_award_status = "lost"
	if won:
		last_award_status = "locked" if level > int(data["level"]) else "replay"
	# Only unlocked levels can advance the campaign or receive a first-clear reward.
	if won and level <= int(data["level"]) and not data["banked_levels"].has(key):
		last_award_status = "awarded"
		var count := 0
		for value in collected.values():
			if value is int or value is float:
				count += clampi(int(value), 0, 250)
		count = mini(count, 1000)
		rewards = {
			"stone": 8 + mini(safe_score / 180, 100) + count / 6,
			"wood": 6 + mini(safe_score / 250, 80) + count / 8,
			"essence": 3 + mini(safe_score / 500, 40) + count / 14,
		}
		var reward_percent := _number(bonuses.get("reward_percent", 0), 0, MAX_REWARD_PERCENT, 0)
		var essence_boost := _number(bonuses.get("essence_boost", 0), 0, MAX_ESSENCE_BOOST, 0)
		# A boss first clear pays eight extra essence; it uses the same anti-replay bank.
		rewards["essence"] = int(rewards["essence"]) + essence_boost + (8 if level % 10 == 0 else 0)
		for resource in RESOURCE_KEYS:
			var previous := int(data["resources"][resource])
			var scaled := int(rewards[resource]) * (100 + reward_percent) / 100
			var credited := mini(MAX_RESOURCE, previous + scaled)
			rewards[resource] = credited - previous
			data["resources"][resource] = credited
		data["banked_levels"][key] = true
		data["level"] = mini(MAX_LEVEL, maxi(int(data["level"]), level + 1))
		hero_reward = HeroModel.grant_level_cards(data, level)
	if not save_progress():
		data = before
		last_award_status = "save_failed"
		return {"stone": 0, "wood": 0, "essence": 0}
	last_hero_reward = hero_reward
	return rewards


func update_setting(name: String, value: bool) -> bool:
	if not name in SETTING_KEYS:
		last_error = "Неизвестная настройка."
		return false
	var before := data.duplicate(true)
	data["settings"][name] = value
	if not save_progress():
		data = before
		return false
	return true


func _valid_shape(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for key in ["resources", "best_scores", "banked_levels"]:
		if value.has(key) and not value[key] is Dictionary:
			return false
	for key in ["buildings", "upgrades"]:
		if value.has(key) and (not value[key] is Array or value[key].size() not in [LEGACY_SLOT_COUNT, SLOT_COUNT]):
			return false
	return true


func _normalize(value: Dictionary) -> Dictionary:
	var result := defaults()
	result["colony_mode"] = value.get("colony_mode", false) == true
	result["expedition_mode"] = value.get("expedition_mode", false) == true
	var expedition_state: Variant = value.get("expedition_state", {})
	if expedition_state is Dictionary:
		# ExpeditionModel owns its versioned finite-deposit/job validation.
		result["expedition_state"] = expedition_state.duplicate(true)
	result["bunker_level"] = _number(value.get("bunker_level", 0), 0, 3, 0)
	var pending: Variant = value.get("colony_pending", {})
	if pending is Dictionary:
		for resource in RESOURCE_KEYS:
			result["colony_pending"][resource] = _number(pending.get(resource, 0), 0, MAX_RESOURCE, 0)
	result["level"] = _number(value.get("level", 1), 1, MAX_LEVEL, 1)
	result["last_mine_time"] = _number(value.get("last_mine_time", result["last_mine_time"]), 0, 4000000000, int(result["last_mine_time"]))
	for key in RESOURCE_KEYS:
		result["resources"][key] = _number(value.get("resources", {}).get(key, result["resources"][key]), 0, MAX_RESOURCE, int(result["resources"][key]))
	var buildings: Array = value.get("buildings", [])
	var upgrades: Array = value.get("upgrades", [])
	for slot in range(mini(SLOT_COUNT, buildings.size())):
		result["buildings"][slot] = _number(buildings[slot], -1, 14, -1)
		var tier: Variant = upgrades[slot] if slot < upgrades.size() else 0
		result["upgrades"][slot] = _number(tier, 0, 19, 0) if result["buildings"][slot] >= 0 else 0
	var construction: Variant = value.get("construction", [])
	if construction is Array and construction.size() == 1 and construction[0] is Dictionary:
		var job: Dictionary = construction[0]
		var slot := _number(job.get("slot", -2), -2, SLOT_COUNT - 1, -2)
		var kind := _number(job.get("kind", -2), -2, 14, -2)
		var level := _number(job.get("target_level", 0), 0, 20, 0)
		var started := _number(job.get("started_at", 0), 0, 4000000000, 0)
		var ends := _number(job.get("ends_at", 0), 0, 4000000000, 0)
		var valid := slot == -1 and kind == -1 and level == int(result.bunker_level) + 1 and level <= 3
		if slot >= 0:
			valid = kind >= 0 and ((result.buildings[slot] == -1 and level == 1) or (result.buildings[slot] == kind and level == int(result.upgrades[slot]) + 2))
		if valid and ends > started and ends - started <= 86400:
			result.construction = [{"slot": slot, "kind": kind, "target_level": level, "started_at": started, "ends_at": ends}]

	for key in value.get("best_scores", {}):
		if str(key).is_valid_int() and int(key) >= 1 and int(key) <= MAX_LEVEL:
			result["best_scores"][str(int(key))] = _number(value["best_scores"][key], 0, 10000000, 0)
	for key in value.get("banked_levels", {}):
		if str(key).is_valid_int() and int(key) >= 1 and int(key) <= MAX_LEVEL and value["banked_levels"][key] == true:
			result["banked_levels"][str(int(key))] = true
	# Version-one saves have no settings. Malformed preferences never erase campaign data.
	var settings: Variant = value.get("settings", {})
	if settings is Dictionary:
		for key in SETTING_KEYS:
			if settings.get(key) is bool:
				result["settings"][key] = settings[key]
	var heroes: Variant = value.get("heroes", {})
	if heroes is Dictionary:
		for id in HERO_IDS:
			if heroes.has(id):
				var level := _number(heroes[id], 0, 5, 0)
				if level > 0:
					result["heroes"][id] = level
	var selected_hero := str(value.get("selected_hero", "warden"))
	result["selected_hero"] = selected_hero if result["heroes"].has(selected_hero) else "warden"
	var selected_troop := str(value.get("selected_troop", "infantry"))
	result["selected_troop"] = selected_troop if selected_troop in TROOP_IDS else "infantry"
	var army: Variant = value.get("army", {})
	if army is Dictionary:
		for id in TROOP_IDS:
			result["army"][id] = _number(army.get(id, result["army"][id]), 0, 10000, int(result["army"][id]))
	var hero_state: Variant = value.get("hero_state", {})
	if hero_state is Dictionary:
		result["hero_state"]["chests"] = _number(hero_state.get("chests", 0), 0, 1000000, 0)
		var cards: Variant = hero_state.get("cards", {})
		if cards is Dictionary:
			for id in HERO_IDS:
				result["hero_state"]["cards"][id] = _number(cards.get(id, 0), 0, 1000000, 0)
	return result


func _number(value: Variant, minimum: int, maximum: int, fallback: int) -> int:
	if value is int or value is float:
		if is_finite(float(value)):
			return clampi(int(value), minimum, maximum)
	return fallback


func _preserve_corrupt_save() -> bool:
	var absolute := ProjectSettings.globalize_path(path)
	var backup := absolute + ".corrupt." + str(int(Time.get_unix_time_from_system()))
	var suffix := 0
	while FileAccess.file_exists(backup):
		suffix += 1
		backup = absolute + ".corrupt." + str(int(Time.get_unix_time_from_system())) + "." + str(suffix)
	if DirAccess.copy_absolute(absolute, backup) == OK:
		corrupt_backup_path = backup
		last_error = "Повреждённое сохранение сохранено отдельно. Начат новый поход."
	else:
		_save_allowed = false
		last_error = "Сохранение повреждено. Исходный файл защищён от перезаписи."
	return false
