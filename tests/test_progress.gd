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
	DirAccess.remove_absolute(ProjectSettings.globalize_path(recovery.corrupt_backup_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(broken_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	if failures == 0:
		print("PASS: progress persistence, first-clear rewards, settlement transactions, mining and recovery")
	quit(0 if failures == 0 else 1)


func _check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + description)
