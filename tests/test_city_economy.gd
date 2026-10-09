extends SceneTree

class CountingStore extends ProgressStore:
	var writes := 0
	func save_progress() -> bool:
		writes += 1
		return super.save_progress()

var checks := 0
var failed := false
var save_path := "user://city-economy-%d.json" % OS.get_process_id()

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error("FAIL: " + message)

func _run() -> void:
	var store := CountingStore.new()
	store.path = save_path
	store.data.expedition_mode = true
	store.data.resources = {"stone": 100000000, "wood": 100000000, "essence": 100000000}
	var city := SettlementModel.new()
	city.configure(store)
	var before: Dictionary = store.data.resources.duplicate()
	check(city.build(0, 6).ok, "town hall schedules construction")
	var job := city.construction_job().duplicate()
	check(store.data.buildings[0] == -1 and city.highest_building_level(6) == 0, "unfinished building grants no bonuses")
	check(city.construction_remaining(int(job.started_at)) == 120, "first construction takes two real minutes")
	check(not city.sync_construction(int(job.ends_at) - 1), "never completes early")
	check(not city.build(1, 13).ok and not city.upgrade(0).ok, "single builder queue rejects overlap without payment")
	check(store.data.resources.stone == before.stone - 100 and store.data.resources.wood == before.wood - 90, "cost charged once at scheduling")
	var restored := CountingStore.new()
	restored.path = save_path
	check(restored.load_progress() and restored.data.construction == store.data.construction, "pending timer survives process restart")
	var resumed := SettlementModel.new()
	resumed.configure(restored)
	check(resumed.sync_construction(int(job.ends_at)) and resumed.highest_building_level(6) == 1, "offline completion constructs the actual building")
	check(not resumed.sync_construction(int(job.ends_at) + 100), "completion is idempotent")
	var old_cost := 0
	var old_time := 0
	for level in range(2, 21):
		var cost := resumed.get_upgrade_cost(0)
		check(cost.stone > old_cost, "level %d has increasing farming cost" % level)
		old_cost = int(cost.stone)
		var duration := SettlementModel.construction_seconds(level)
		check(duration >= old_time, "level %d takes longer to improve" % level)
		old_time = duration
		check(resumed.upgrade(0).ok and resumed.highest_building_level(6) == level - 1, "level %d does not grant capacity early" % level)
		var pending := resumed.construction_job().duplicate()
		check(resumed.sync_construction(int(pending.ends_at)), "level %d completes at deadline" % level)
		check(resumed.highest_building_level(6) == level and resumed.expedition_capacity() == mini(4, level), "level %d retained with queue cap" % level)
	check(not resumed.upgrade(0).ok, "twentieth level is the building cap")
	check(restored.save_progress(), "advanced city save persists")
	var late := ProgressStore.new()
	late.path = save_path
	check(late.load_progress() and int(late.data.upgrades[0]) == 19, "level twenty survives normalization")
	check(SettlementModel.upgrade_multiplier(5) * 100 >= 10000 and SettlementModel.upgrade_multiplier(6) * 100 >= 25000, "level five and six require substantial gathering")
	check(SettlementModel.construction_seconds(5) == 3600 and SettlementModel.construction_seconds(6) == 7200, "midgame work takes one and two hours")
	# Failed scheduling and failed completion must preserve paid resources and pending work.
	var snapshot := restored.data.duplicate(true)
	restored._save_allowed = false
	check(not resumed.build(1, 13).ok and restored.data == snapshot, "failed scheduling rolls back resource deduction")
	restored._save_allowed = true
	check(resumed.build(1, 13).ok, "prepare pending tavern")
	var pending := resumed.construction_job().duplicate()
	snapshot = restored.data.duplicate(true)
	restored._save_allowed = false
	check(not resumed.sync_construction(int(pending.ends_at)) and restored.data == snapshot, "failed completion retains pending job and no new tavern")
	restored._save_allowed = true
	check(resumed.sync_construction(int(pending.ends_at)) and restored.data.buildings[1] == 13, "retry completion safely activates tavern once")
	var expedition := ExpeditionModel.new()
	check(expedition.configure(resumed), "create long-lived deposits")
	for deposit: Dictionary in expedition.deposits():
		check(int(deposit.remaining) >= 3000 and int(deposit.remaining) <= 6000 and int(deposit.level) == 1, "initial points contain fifty to one hundred minutes of raw stock")
	var stocks := expedition.deposits().duplicate(true)
	for completed in [0, 24, 25, 49, 50, 975, 1000]:
		restored.data.level = completed + 1
		check(expedition.deposit_level() == mini(40, 1 + completed / 25), "deposit tier follows only cleared match-3 stages")
	check(expedition.deposits() == stocks, "progress never resets or inflates existing finite stock")
	var deposit: Dictionary = expedition.deposits()[0]
	var previous_cell: Array = deposit.cell.duplicate()
	deposit.active = false
	deposit.remaining = 0
	deposit.respawn_at = float(restored.data.expedition_state.clock)
	check(expedition.advance(1.0).ok and int(deposit.level) == 40 and deposit.remaining >= 32250 and deposit.cell != previous_cell, "new endgame point scales and respawns at another reachable cell")
	check(ExpeditionModel.MINING_BATCH / ExpeditionModel.MINING_SECONDS == 1.0, "base extraction is sixty per minute rather than four per second")
	var writes_before := restored.writes
	var profile_start := Time.get_ticks_usec()
	for frame in range(3000):
		expedition.advance(1.0 / 60.0)
	check(restored.writes == writes_before, "fifty seconds of idle rendering cause zero persistence writes")
	check(not expedition._will_persist(1.0 / 60.0), "idle animation ticks need no save snapshot")
	print("IDLE_PROFILE: 3000 ticks ", Time.get_ticks_usec() - profile_start, " usec, writes=", restored.writes - writes_before)
	check(expedition.dispatch(int(deposit.id)).ok, "send party to long endgame point")
	profile_start = Time.get_ticks_usec()
	check(expedition.advance(3.0 * 24.0 * 3600.0).ok and expedition.jobs().is_empty(), "finite expedition completes after multi-day real offline interval")
	print("OFFLINE_PROFILE: 3 days finite simulation ", Time.get_ticks_usec() - profile_start, " usec")

	# Warehouse delivery waits for the whole following party and survives restart in that hold.
	deposit.remaining = 5
	deposit.initial_stock = 5
	deposit.active = true
	check(expedition.dispatch(int(deposit.id)).ok, "prepare a short cargo trip for arrival hold")
	var held: Dictionary = expedition.jobs()[0]
	var outbound := maxi(0, held.path.size() - 1) * expedition._travel_step(held)
	expedition.advance(outbound + ExpeditionModel.MINING_SECONDS)
	check(held.phase == "returning", "loaded party starts real return route")
	var bank_before := int(restored.data.resources[deposit.resource])
	var return_seconds := maxi(0, held.path.size() - 1) * expedition._travel_step(held)
	expedition.advance(return_seconds + expedition._travel_step(held))
	check(not expedition.jobs().is_empty() and restored.data.resources[deposit.resource] == bank_before, "leader arrival alone cannot bank or release the following soldiers")
	check(float(held.arrival_elapsed) > 0.0 and expedition.checkpoint(), "partial warehouse assembly is saved")
	var reload_hold := ProgressStore.new()
	reload_hold.path = save_path
	check(reload_hold.load_progress(), "reload warehouse assembly")
	var reload_city := SettlementModel.new()
	reload_city.configure(reload_hold)
	var resumed_hold := ExpeditionModel.new()
	check(resumed_hold.configure(reload_city) and not resumed_hold.jobs().is_empty(), "saved arrival hold keeps party reservations")
	var cargo_amount := int(resumed_hold.jobs()[0].cargo_amount)
	resumed_hold.advance(3.0 * resumed_hold._travel_step(resumed_hold.jobs()[0]))
	check(resumed_hold.jobs().is_empty() and reload_hold.data.resources[deposit.resource] == bank_before + cargo_amount, "whole-party completion delivers once and frees queue")

	# Higher levels change actual economy, not just the number drawn above a building.
	late.data.buildings[2] = 0
	late.data.upgrades[2] = 19
	var upgraded := SettlementModel.new()
	upgraded.configure(late)
	check(upgraded.mining_batch("stone") == 24 and upgraded.mining_batch("wood") == 5, "twentieth quarry accelerates only stone extraction")
	check(upgraded.work_seconds(6) < SettlementModel.construction_seconds(6), "high town hall reduces actual construction time")
	late.data.buildings[1] = 13
	late.data.upgrades[1] = 0
	var cost_before := upgraded.get_upgrade_cost(1)
	late.data.buildings[3] = 9
	late.data.upgrades[3] = 19
	check(upgraded.get_upgrade_cost(1).stone < cost_before.stone, "high market discounts an actual resource payment")
	var march_before := upgraded.march_seconds("infantry")
	late.data.buildings[4] = 10
	late.data.upgrades[4] = 19
	check(upgraded.march_seconds("infantry") < march_before and upgraded.march_seconds("cavalry") < upgraded.march_seconds("infantry"), "stable levels improve real logistics and mounted travel")
	late.data.buildings[5] = 13
	late.data.upgrades[5] = 19
	var heroes := HeroModel.new(late)
	check(heroes.chest_cost().stone < HeroModel.CHEST_COST.stone, "advanced tavern discounts actual chests")

	late.path = save_path + ".skills"
	for pair in [[6, 11], [7, 4], [8, 5], [9, 7], [10, 3]]:
		late.data.buildings[int(pair[0])] = int(pair[1])
		late.data.upgrades[int(pair[0])] = 19
	check(upgraded.mining_seconds("infantry") < 5.0 and upgraded.work_seconds(6) < SettlementModel.construction_seconds(6), "high tools, military discipline and citadel affect actual work")
	var skill_map := ExpeditionModel.new()
	check(skill_map.configure(upgraded, heroes), "configure real skills expedition")
	var stone: Dictionary = skill_map.deposits()[0]
	check(skill_map.dispatch(int(stone.id), "warden", "infantry").ok, "dispatch snapshots trained and equipped party")
	var skill_job: Dictionary = skill_map.jobs()[0]
	var saved_interval := float(skill_job.mining_seconds)
	var saved_damage := int(skill_job.party_damage)
	check(skill_job.mining_batch == 24 and saved_interval < 5.0 and int(skill_job.damage_bonus) > 100, "twentieth-level buildings generate bounded enhanced job stats")
	late.data.upgrades[6] = 0
	late.data.upgrades[7] = 0
	check(skill_job.mining_seconds == saved_interval and heroes.party_for_job(int(skill_job.id)).party_damage == saved_damage, "later city changes cannot mutate an already dispatched party")
	check(skill_map.checkpoint(), "save advanced party snapshot")
	var reload_skills := ProgressStore.new()
	reload_skills.path = late.path
	check(reload_skills.load_progress(), "reload veteran party save")
	var reload_skills_city := SettlementModel.new()
	reload_skills_city.configure(reload_skills)
	var reloaded_skills := ExpeditionModel.new()
	check(reloaded_skills.configure(reload_skills_city, HeroModel.new(reload_skills)), "restore advanced party")
	check(is_equal_approx(float(reloaded_skills.jobs()[0].mining_seconds), saved_interval) and int(reloaded_skills.jobs()[0].party_damage) == saved_damage, "restart preserves exact per-party speed and damage snapshot")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(late.path))

	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	if not failed:
		print("PASS: ", checks, " city economy checks (real timers, offline completion, atomic saves, twenty building levels, campaign deposits).")
	quit(1 if failed else 0)
