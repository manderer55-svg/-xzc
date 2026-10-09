extends SceneTree

const Progress = preload("res://scripts/progress_store.gd")
const Settlement = preload("res://scripts/settlement_model.gd")
var failures: int = 0
var save_path := "user://test_progress_%d.json" % OS.get_process_id()


func _initialize() -> void:
	var store = Progress.new()
	store.path = save_path
	_check(store.load_progress(), "missing save starts a campaign")
	_check(store.data["level"] == 1, "campaign starts at level one")
	var rewards: Dictionary = store.award_level(1, 2400, true, {0: 24, 1: 30})
	_check(rewards["stone"] > 0 and store.data["level"] == 2 and store.last_award_status == "awarded", "winning advances and rewards")
	var balance: Dictionary = store.data["resources"].duplicate()
	var second: Dictionary = store.award_level(1, 3000, true, {0: 60})
	_check(second["stone"] == 0 and balance == store.data["resources"] and store.last_award_status == "replay", "replaying cannot farm completion rewards")
	_check(store.data["best_scores"]["1"] == 3000, "replay still records best score")
	store.award_level(2, 10000, false, {0: 120})
	_check(balance == store.data["resources"] and store.data["level"] == 2 and store.last_award_status == "lost", "a loss never yields spendable rewards")
	store.award_level(50, 10000, true, {0: 120})
	_check(balance == store.data["resources"] and store.data["level"] == 2 and store.last_award_status == "locked", "locked levels cannot advance or reward")
	var restored = Progress.new()
	restored.path = save_path
	_check(restored.load_progress(), "written progress parses")
	_check(restored.data == store.data, "JSON roundtrip preserves progression and balances")
	_check(not FileAccess.file_exists(save_path + ".tmp"), "successful save leaves no temporary file")

	var model = Settlement.new()
	model.configure(restored)
	_check(model.build(0, 0)["ok"], "a modest starting campaign can build one quarry")
	_check(model.production()["stone"] == 8, "quarry has minute production")
	_check(model.battle_bonuses()["bonus_moves"] == 1, "building a quarry helps the next battle")
	_check(not model.build(0, 1)["ok"], "occupied plot is protected")
	_check(not model.build(-1, 0)["ok"], "invalid plot is protected")
	var built: Dictionary = restored.data.duplicate(true)
	_check(not model.build(1, 3)["ok"], "unaffordable construction is rejected")
	_check(built == restored.data, "failed construction changes no resources")
	_check(not model.mine()["ok"], "immediate collection is on cooldown")
	restored.data["last_mine_time"] = int(Time.get_unix_time_from_system()) - 121
	var mined: Dictionary = model.mine()
	_check(mined["ok"] and mined["rewards"]["stone"] == 16, "only whole elapsed minutes accrue")
	_check(not model.mine()["ok"], "a repeated click earns nothing")
	restored.data["last_mine_time"] = int(Time.get_unix_time_from_system()) - 7 * 24 * 3600
	mined = model.mine()
	_check(mined["rewards"]["stone"] == 8 * 480, "offline production is capped to eight hours")
	_check(not model.mine()["ok"], "offline cap cannot be claimed twice")
	var blocked_path := save_path + ".blocked"
	var blocked_directory := ProjectSettings.globalize_path(blocked_path + ".tmp")
	DirAccess.make_dir_absolute(blocked_directory)
	restored.path = blocked_path
	var before_failed_save: Dictionary = restored.data.duplicate(true)
	_check(not restored.update_setting("reduced_effects", true) and restored.data == before_failed_save, "setting changes roll back when persistence fails")
	_check(not model.build(1, 0)["ok"], "construction reports failed persistence")
	_check(restored.data == before_failed_save, "construction rolls back when saving fails")
	var failed_reward: Dictionary = restored.award_level(2, 4000, true, {0: 50})
	_check(failed_reward["stone"] == 0 and restored.data == before_failed_save and restored.last_award_status == "save_failed", "level rewards roll back when saving fails")
	restored.data["last_mine_time"] = int(Time.get_unix_time_from_system()) + 10000
	before_failed_save = restored.data.duplicate(true)
	var failed_mine: Dictionary = model.mine()
	_check(not failed_mine["ok"] and failed_mine["reason"] == restored.last_error and restored.data == before_failed_save, "clock-repair persistence failure is reported without mutating progress")
	restored.path = save_path
	DirAccess.remove_absolute(blocked_directory)
	restored.data["resources"] = {"stone": 10000, "wood": 10000, "essence": 10000}
	for index in range(3):
		_check(model.upgrade(0)["ok"], "upgrade tier %d is available" % (index + 1))
	_check(model.production()["stone"] == 32, "upgrades improve production")
	_check(not model.upgrade(0)["ok"], "building upgrades stop at tier three")
	restored.data["last_mine_time"] = int(Time.get_unix_time_from_system()) + 10000
	_check(not model.mine()["ok"], "future clock creates no production")
	_check(model.seconds_until_mine() <= 60, "future clock is repaired")
	restored.data["resources"] = {"stone": Progress.MAX_RESOURCE, "wood": Progress.MAX_RESOURCE, "essence": Progress.MAX_RESOURCE}
	var capped_award: Dictionary = restored.award_level(2, 4000, true, {0: 50})
	_check(capped_award["stone"] == 0 and restored.last_award_status == "awarded" and restored.data["level"] == 3, "full warehouses report actual credits while banking first completion")
	restored.data["last_mine_time"] = int(Time.get_unix_time_from_system()) - 120
	var capped_mine: Dictionary = model.mine()
	_check(not capped_mine["ok"] and "Хранилища" in capped_mine["reason"] and model.seconds_until_mine() > 0, "full warehouses consume elapsed production and explain capacity")

	var broken_path := save_path + ".broken"
	var broken := FileAccess.open(broken_path, FileAccess.WRITE)
	broken.store_string("{broken-json")
	broken.close()
	var recovery = Progress.new()
	recovery.path = broken_path
	_check(not recovery.load_progress(), "malformed saves are detected")
	_check(FileAccess.file_exists(recovery.corrupt_backup_path), "corrupt save is preserved separately")
	_check(FileAccess.get_file_as_string(broken_path) == "{broken-json", "loading does not overwrite original corrupt file")
	_check(recovery.data["level"] == 1, "corrupt save has safe runtime defaults")
	_check(recovery.save_progress(), "recovery can save once original is backed up")
	_check(FileAccess.get_file_as_string(recovery.corrupt_backup_path) == "{broken-json", "backup retains original bytes after save")
	_test_migration_and_settings()
	_test_bonuses()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(recovery.corrupt_backup_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(broken_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	if failures == 0:
		print("PASS: progress persistence, first-clear rewards, settlement bonuses, version-one migration, settings, mining and recovery")
	quit(0 if failures == 0 else 1)


func _check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + description)


func _test_migration_and_settings() -> void:
	var legacy = Progress.new()
	var legacy_data: Dictionary = legacy.defaults()
	legacy_data["version"] = 1
	legacy_data.erase("settings")
	legacy_data["level"] = 27
	legacy_data["resources"] = {"stone": 324, "wood": 235, "essence": 88}
	legacy_data["buildings"] = [0, 1, 2, 3, -1, -1, -1, -1, -1]
	legacy_data["upgrades"] = [1, 2, 3, 0, 0, 0, 0, 0, 0]
	legacy_data["best_scores"] = {"26": 6000}
	legacy_data["banked_levels"] = {"26": true}
	var legacy_path := save_path + ".legacy"
	var file := FileAccess.open(legacy_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy_data))
	file.close()
	legacy.path = legacy_path
	_check(legacy.load_progress() and legacy.data["version"] == 2, "version-one progress upgrades to current schema")
	for key in ["level", "resources", "buildings", "upgrades", "best_scores", "banked_levels", "last_mine_time"]:
		_check(legacy.data[key] == legacy_data[key], "migration preserves " + key)
	_check(legacy.data["settings"] == {"reduced_effects": false, "haptics": true}, "old saves receive safe default settings")
	_check(legacy.update_setting("reduced_effects", true) and legacy.update_setting("haptics", false), "known settings are saved")
	var reloaded = Progress.new()
	reloaded.path = legacy_path
	_check(reloaded.load_progress() and reloaded.data["settings"] == {"reduced_effects": true, "haptics": false}, "settings survive a save roundtrip")
	var before: Dictionary = reloaded.data.duplicate(true)
	_check(not reloaded.update_setting("unknown", true) and reloaded.data == before, "unknown settings cannot mutate campaign data")
	file = FileAccess.open(legacy_path, FileAccess.WRITE)
	legacy_data["settings"] = {"reduced_effects": "true", "haptics": 0}
	file.store_string(JSON.stringify(legacy_data))
	file.close()
	_check(reloaded.load_progress() and reloaded.data["level"] == 27, "invalid setting types keep valid campaign progress")
	_check(reloaded.data["settings"] == {"reduced_effects": false, "haptics": true}, "invalid setting types normalize without truthiness conversion")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(legacy_path))


func _test_bonuses() -> void:
	var progress = Progress.new()
	progress.path = save_path + ".bonuses"
	progress.data["resources"] = {"stone": 100000, "wood": 100000, "essence": 100000}
	var model = Settlement.new()
	model.configure(progress)
	_check(model.battle_bonuses() == {"bonus_moves": 0, "starting_specials": 0, "boss_damage_bonus": 0, "reward_percent": 0, "essence_boost": 0}, "an empty settlement grants no battle bonus")
	for kind in range(4):
		_check(model.build(kind, kind)["ok"], "each building kind is constructible")
	var initial: Dictionary = model.battle_bonuses()
	_check(initial == {"bonus_moves": 2, "starting_specials": 1, "boss_damage_bonus": 1, "reward_percent": 15, "essence_boost": 1}, "four initial buildings provide four concrete battle benefits")
	for slot in range(4):
		for tier in range(3):
			_check(model.upgrade(slot)["ok"], "upgrading building %d tier %d succeeds" % [slot, tier + 1])
	var full: Dictionary = model.battle_bonuses()
	_check(full == {"bonus_moves": 3, "starting_specials": 2, "boss_damage_bonus": 2, "reward_percent": 30, "essence_boost": 4}, "fully upgraded battle bonuses stop at fair caps")
	for slot in range(4, 9):
		_check(model.build(slot, mini(slot - 4, 3))["ok"], "duplicate buildings may increase production")
		for tier in range(3):
			_check(model.upgrade(slot)["ok"], "duplicate buildings may be upgraded")
	_check(model.battle_bonuses() == full, "nine building slots cannot multiply battle bonuses")
	var descriptions: Array[String] = model.bonus_descriptions()
	for title in Settlement.TITLES:
		_check(title in "\n".join(descriptions), "built building bonus has Russian explanation: " + title)
	progress.data["resources"] = {"stone": 0, "wood": 0, "essence": 0}
	var rewards: Dictionary = progress.award_level(1, 1800, true, {0: 42}, full)
	_check(rewards == {"stone": 32, "wood": 23, "essence": 16}, "bounded bonuses scale score-based first-clear rewards")
	var balance: Dictionary = progress.data["resources"].duplicate()
	var repeat: Dictionary = progress.award_level(1, 100000, true, {0: 250}, full)
	_check(repeat == {"stone": 0, "wood": 0, "essence": 0} and progress.data["resources"] == balance, "bonuses cannot bypass first-clear anti-farming")
	progress.data["level"] = 10
	var boss_reward: Dictionary = progress.award_level(10, 0, true, {})
	_check(boss_reward["essence"] == 11, "boss first clear grants modest extra essence")
	progress.data["level"] = 11
	var clamped: Dictionary = progress.award_level(11, 0, true, {}, {"reward_percent": 999999, "essence_boost": 999999})
	_check(clamped == {"stone": 10, "wood": 7, "essence": 9}, "untrusted reward bonus inputs are clamped")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(progress.path))
