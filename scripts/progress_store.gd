class_name ProgressStore
extends RefCounted
## Local campaign progress. A malformed save is preserved before new data may replace it.

const RESOURCE_KEYS := ["stone", "wood", "essence"]
const MAX_RESOURCE := 1000000000
const MAX_LEVEL := 1000000

var path: String = "user://progress.json"
var data: Dictionary = {}
var last_error: String = ""
var corrupt_backup_path: String = ""
## Award outcomes stay separate from reward amounts: zero can mean replay, locked or failed save.
var last_award_status: String = "idle"
var _save_allowed: bool = true


func _init() -> void:
	data = defaults()


func defaults() -> Dictionary:
	return {
		"version": 1,
		"level": 1,
		"best_scores": {},
		"resources": {"stone": 70, "wood": 50, "essence": 5},
		"buildings": [-1, -1, -1, -1, -1, -1, -1, -1, -1],
		"upgrades": [0, 0, 0, 0, 0, 0, 0, 0, 0],
		"banked_levels": {},
		"last_mine_time": int(Time.get_unix_time_from_system()),
	}


func load_progress() -> bool:
	data = defaults()
	last_error = ""
	corrupt_backup_path = ""
	last_award_status = "idle"
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


func award_level(level: int, score: int, won: bool, collected: Dictionary) -> Dictionary:
	var rewards := {"stone": 0, "wood": 0, "essence": 0}
	last_error = ""
	last_award_status = "invalid"
	if level < 1 or level > MAX_LEVEL:
		return rewards
	var before := data.duplicate(true)
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
		for resource in RESOURCE_KEYS:
			var previous := int(data["resources"][resource])
			var credited := mini(MAX_RESOURCE, previous + int(rewards[resource]))
			rewards[resource] = credited - previous
			data["resources"][resource] = credited
		data["banked_levels"][key] = true
		data["level"] = mini(MAX_LEVEL, maxi(int(data["level"]), level + 1))
	if not save_progress():
		data = before
		last_award_status = "save_failed"
		return {"stone": 0, "wood": 0, "essence": 0}
	return rewards


func _valid_shape(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for key in ["resources", "best_scores", "banked_levels"]:
		if value.has(key) and not value[key] is Dictionary:
			return false
	for key in ["buildings", "upgrades"]:
		if value.has(key) and (not value[key] is Array or value[key].size() != 9):
			return false
	return true


func _normalize(value: Dictionary) -> Dictionary:
	var result := defaults()
	result["level"] = _number(value.get("level", 1), 1, MAX_LEVEL, 1)
	result["last_mine_time"] = _number(value.get("last_mine_time", result["last_mine_time"]), 0, 4000000000, int(result["last_mine_time"]))
	for key in RESOURCE_KEYS:
		result["resources"][key] = _number(value.get("resources", {}).get(key, result["resources"][key]), 0, MAX_RESOURCE, int(result["resources"][key]))
	for slot in range(9):
		result["buildings"][slot] = _number(value.get("buildings", result["buildings"])[slot], -1, 3, -1)
		result["upgrades"][slot] = _number(value.get("upgrades", result["upgrades"])[slot], 0, 3, 0) if result["buildings"][slot] >= 0 else 0
	for key in value.get("best_scores", {}):
		if str(key).is_valid_int() and int(key) >= 1 and int(key) <= MAX_LEVEL:
			result["best_scores"][str(int(key))] = _number(value["best_scores"][key], 0, 10000000, 0)
	for key in value.get("banked_levels", {}):
		if str(key).is_valid_int() and int(key) >= 1 and int(key) <= MAX_LEVEL and value["banked_levels"][key] == true:
			result["banked_levels"][str(int(key))] = true
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
