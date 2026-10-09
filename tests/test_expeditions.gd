extends SceneTree

class TestParty extends RefCounted:
	func dispatch_validation(_hero_id: String = "", _troop_type: String = "", _resource: String = "") -> Dictionary:
		return {"ok": true, "hero_id": "warden", "troop_type": "infantry", "troop_count": 3, "yield_bonus": 25, "damage_bonus": 20}
	func yield_bonus(_hero_id: String, _resource: String) -> int:
		return 25

var checks := 0
var failures: Array[String] = []
var paths: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures.append(description)


func _fixture(suffix: String, party: RefCounted = null) -> ExpeditionModel:
	var store := ProgressStore.new()
	store.path = "user://expedition-test-%d-%s.json" % [OS.get_process_id(), suffix]
	paths.append(store.path)
	var settlement := SettlementModel.new()
	settlement.configure(store)
	var model := ExpeditionModel.new()
	check(model.configure(settlement, party), "initialize finite expeditions %s" % suffix)
	# Tests advance a deterministic logical clock, independent of the host clock.
	store.data.expedition_state.clock = Time.get_unix_time_from_system() + 10000.0
	return model


func _until_phase(model: ExpeditionModel, phase: String) -> bool:
	for index in range(500):
		if model.jobs().is_empty():
			return false
		if model.jobs()[0].phase == phase:
			return true
		model.advance(0.1)
	return false


func _run() -> void:
	var model := _fixture("travel")
	check(model.deposits().size() == 12 and model.jobs().is_empty(), "twelve finite deposits; no automatic dispatch")
	check(model.queue_status() == {"busy": 0, "capacity": 1, "free": 1}, "one initial expedition queue")
	var seen: Dictionary = {}
	var resources: Dictionary = {}
	for deposit: Dictionary in model.deposits():
		var point := ExpeditionModel._cell(deposit.cell)
		check(ExpeditionModel.field_walkable(point), "deposit sits on a clear reachable tile")
		check(not seen.has(point) and deposit.remaining >= 60 and deposit.remaining <= 140, "unique finite deposit stock")
		seen[point] = true
		resources[deposit.resource] = true
		check(not model._route(ExpeditionModel.FIELD_GATE_ACCESS, model._deposit_access(deposit)).is_empty(), "clear path from castle to every deposit")
	check(resources.size() == 3, "stone, wood and essence deposits")
	var wallet: Dictionary = model.store.data.resources.duplicate()
	var stock: Array = model.deposits().duplicate(true)
	check(model.advance(300.0).ok and model.jobs().is_empty() and model.deposits() == stock and model.store.data.resources == wallet, "idle field does not produce infinite passive resources")
	var deposit: Dictionary = model.deposits()[0]
	var deposit_id := int(deposit.id)
	var resource := str(deposit.resource)
	var initial := int(deposit.remaining)
	var original_cell: Array = deposit.cell.duplicate()
	check(model.dispatch(deposit_id).ok, "manual order sends a squad from the castle")
	check(not model.dispatch(int(model.deposits()[1].id)).ok and model.jobs().size() == 1, "busy initial queue rejects second order")
	check(model.jobs()[0].position == [15.0, 28.0], "squad starts at castle gate")
	for cell: Array in model.jobs()[0].path:
		check(not model.navigation.is_point_solid(ExpeditionModel._cell(cell)), "movement avoids trees, rocks, castle and deposit footprint")
	model.advance(1.0)
	check(model.store.data.resources == wallet and model.jobs()[0].phase == "outbound", "outbound walking never credits the warehouse")
	check(_until_phase(model, "mining"), "squad arrives at the deposit")
	model.advance(ExpeditionModel.MINING_SECONDS)
	check(model.get_deposit(deposit_id).remaining == initial - 5 and model.jobs()[0].cargo_amount == 5, "mining consumes actual finite stock into cargo")
	check(model.store.data.resources == wallet, "mined cargo stays unavailable until return")
	check(model.checkpoint(), "checkpoint saves partly mined expedition")
	var restored_store := ProgressStore.new()
	restored_store.path = model.store.path
	check(restored_store.load_progress(), "load interrupted expedition")
	var restored_city := SettlementModel.new()
	restored_city.configure(restored_store)
	var restored := ExpeditionModel.new()
	check(restored.configure(restored_city) and restored.jobs() == model.jobs() and restored.deposits() == model.deposits(), "travel, extracted ore and remaining stock persist across restart")
	if restored.jobs().is_empty():
		await _finish()
		return
	check(_until_phase(restored, "returning"), "finite extraction ends and squad heads home")
	check(not restored.get_deposit(deposit_id).active and restored.get_deposit(deposit_id).remaining == 0, "depleted mine disappears before cargo arrives")
	check(restored.store.data.resources == wallet and restored.jobs()[0].cargo_amount == initial, "all stock travels home before being banked")
	check(not restored.dispatch(deposit_id).ok, "cannot send another squad to an exhausted mine")
	restored.advance(60.0)
	check(restored.jobs().is_empty() and restored.store.data.resources[resource] == wallet[resource] + initial, "arrival credits cargo exactly once and frees queue")
	var delivered: Dictionary = restored.store.data.resources.duplicate()
	restored.advance(1.0)
	check(restored.store.data.resources == delivered, "subsequent ticks cannot duplicate delivered cargo")
	check(not restored.get_deposit(deposit_id).active, "mine remains absent until respawn timer")
	restored.advance(61.0)
	check(restored.get_deposit(deposit_id).active and restored.get_deposit(deposit_id).cell != original_cell, "exhausted deposit respawns after delay at a different random map cell")
	check(restored.get_deposit(deposit_id).remaining >= 60 and not restored._route(ExpeditionModel.FIELD_GATE_ACCESS, restored._deposit_access(restored.get_deposit(deposit_id))).is_empty(), "new deposit has finite stock and a reachable access")

	var atomic := _fixture("atomic")
	deposit_id = int(atomic.deposits()[0].id)
	check(atomic.dispatch(deposit_id).ok and _until_phase(atomic, "mining"), "set up atomic mining test")
	var original_path := atomic.store.path
	var blocked := original_path + ".blocked"
	paths.append(blocked)
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(blocked + ".tmp"))
	atomic.store.path = blocked
	var before: Dictionary = atomic.store.data.duplicate(true)
	check(not atomic.advance(10.0).ok and atomic.store.data == before, "failed save rolls back extraction, cargo, clock and stock together")
	atomic.store.path = original_path
	check(atomic.advance(10.0).ok and atomic.jobs()[0].cargo_amount > 0, "retry mines once after storage recovers")
	check(_until_phase(atomic, "returning"), "atomic test reaches return leg")
	atomic.store.path = blocked
	before = atomic.store.data.duplicate(true)
	check(not atomic.advance(60.0).ok and atomic.store.data == before, "failed arrival save cannot duplicate credit or release a reserved party")
	atomic.store.path = original_path
	var pending := int(atomic.jobs()[0].cargo_amount)
	resource = str(atomic.jobs()[0].cargo_resource)
	var previous_balance := int(atomic.store.data.resources[resource])
	check(atomic.advance(60.0).ok and atomic.jobs().is_empty() and atomic.store.data.resources[resource] == previous_balance + pending, "recovered arrival delivers precisely the preserved cargo")

	var route_repair := _fixture("route-repair")
	deposit_id = int(route_repair.deposits()[0].id)
	check(route_repair.dispatch(deposit_id).ok and _until_phase(route_repair, "returning"), "set up route repair with a loaded returning squad")
	var cargo := int(route_repair.jobs()[0].cargo_amount)
	var distant_position: Array = route_repair.jobs()[0].position.duplicate()
	var repair_wallet: Dictionary = route_repair.store.data.resources.duplicate()
	route_repair.jobs()[0].path = []
	check(route_repair.checkpoint(), "save interrupted route without discarding cargo")
	check(route_repair.advance(0.1).ok and route_repair.store.data.resources == repair_wallet and route_repair.jobs()[0].position == distant_position, "empty return route repairs without teleporting or crediting cargo")
	check(not route_repair.jobs()[0].path.is_empty() and route_repair.jobs()[0].cargo_amount == cargo, "repair preserves loaded cargo and builds an actual walk home")
	route_repair.advance(60.0)
	check(route_repair.jobs().is_empty(), "repaired route delivers only after walking to the gate")

	var boosted := _fixture("hero", TestParty.new())
	deposit_id = int(boosted.deposits()[0].id)
	boosted.get_deposit(deposit_id).remaining = 20
	resource = str(boosted.get_deposit(deposit_id).resource)
	previous_balance = int(boosted.store.data.resources[resource])
	check(boosted.dispatch(deposit_id).ok and boosted.jobs()[0].troop_count == 3 and boosted.jobs()[0].hero_id == "warden", "dispatch snapshots a hero and three soldiers")
	check(boosted.jobs()[0].yield_bonus == 25 and boosted.jobs()[0].damage_bonus == 20, "party skills are frozen for the active expedition")
	boosted.advance(120.0)
	check(boosted.jobs().is_empty() and boosted.store.data.resources[resource] == previous_balance + 25, "hero bonus improves one delivered finite batch without increasing raw stock")
	var supported := _fixture("city-bonuses")
	for index in range(6):
		supported.store.data.buildings[index] = [8, 14, 3, 7, 4, 5][index]
		supported.store.data.upgrades[index] = 3
	deposit_id = int(supported.deposits()[0].id)
	supported.get_deposit(deposit_id).remaining = 20
	resource = str(supported.get_deposit(deposit_id).resource)
	previous_balance = int(supported.store.data.resources[resource])
	var supported_heroes := HeroModel.new(supported.store)
	supported.heroes = supported_heroes
	var ui_yield := supported_heroes.yield_bonus("warden", resource)
	var ui_damage := supported_heroes.damage_bonus("warden")
	var ui_party_damage := supported_heroes.party_damage("warden", "infantry")
	check(supported.dispatch(deposit_id).ok and supported.jobs()[0].yield_bonus == ui_yield and ui_yield == 32, "job yield equals combined hero UI skill with city contribution exactly once")
	check(supported.jobs()[0].damage_bonus == ui_damage and supported.jobs()[0].party_damage == ui_party_damage and ui_party_damage == 39, "job strength equals combined hero UI party strength with city contribution exactly once")
	supported.advance(120.0)
	check(supported.store.data.resources[resource] == previous_balance + 26, "city and hero bonuses apply once to delivered cargo instead of creating passive stock")
	var fallback := _fixture("city-fallback")
	fallback.store.data.buildings[0] = 8
	fallback.store.data.upgrades[0] = 3
	fallback.store.data.buildings[1] = 3
	fallback.store.data.upgrades[1] = 3
	check(fallback.dispatch(int(fallback.deposits()[0].id)).ok and fallback.jobs()[0].yield_bonus == 8 and fallback.jobs()[0].damage_bonus == 4, "standalone expedition fallback obtains town bonuses exactly once")

	var full := _fixture("full")
	deposit_id = int(full.deposits()[0].id)
	full.get_deposit(deposit_id).remaining = 20
	resource = str(full.get_deposit(deposit_id).resource)
	full.store.data.resources[resource] = ProgressStore.MAX_RESOURCE - 3
	check(full.dispatch(deposit_id).ok and full.advance(90.0).ok, "full warehouse expedition still returns")
	check(full.jobs().size() == 1 and full.jobs()[0].phase == "delivery_retry" and full.jobs()[0].cargo_amount == 17, "full warehouse preserves undelivered cargo and keeps its party reserved")
	check(full.store.data.resources[resource] == ProgressStore.MAX_RESOURCE and not full.dispatch(int(full.deposits()[1].id)).ok, "warehouse cap cannot overflow or free a loaded queue")
	full.store.data.resources[resource] -= 17
	check(full.advance(2.0).ok and full.jobs().is_empty() and full.store.data.resources[resource] == ProgressStore.MAX_RESOURCE, "spending warehouse resources allows the preserved remainder to unload once")

	var capacity := _fixture("capacity")
	capacity.store.data.resources = {"stone": 100000, "wood": 100000, "essence": 100000}
	check(capacity.settlement.build(0, 3).ok and capacity.queue_status().capacity == 1, "unupgraded castle retains one initial queue")
	for tier in range(1, 4):
		check(capacity.settlement.upgrade(0).ok and capacity.queue_status().capacity == tier + 1, "castle upgrade opens queue %d" % (tier + 1))
	for index in range(4):
		check(capacity.dispatch(int(capacity.deposits()[index].id)).ok, "expanded castle can dispatch concurrent party %d" % index)
	check(capacity.queue_status().busy == 4 and not capacity.dispatch(int(capacity.deposits()[4].id)).ok, "four queue limit is enforced")

	var led := _fixture("led")
	var hero_model := HeroModel.new(led.store)
	led.heroes = hero_model
	led.store.data.buildings[0] = 3
	led.store.data.upgrades[0] = 3
	check(led.dispatch(int(led.deposits()[0].id), "warden", "infantry").ok, "real hero leads the first expedition")
	check(hero_model.hero_busy("warden") and hero_model.available_troops("infantry") == 17, "active expedition reserves its actual leader and soldiers")
	check(not led.dispatch(int(led.deposits()[1].id), "warden", "infantry").ok and led.jobs().size() == 1, "same hero cannot lead two squads even with open queues")
	led.store.data.heroes["ranger"] = 1
	check(led.dispatch(int(led.deposits()[1].id), "ranger", "infantry").ok and hero_model.available_troops("infantry") == 14, "another owned hero can use a second free queue")
	check(not hero_model.upgrade("warden").ok, "busy hero cannot change snapshotted expedition skills")
	check(led.checkpoint(), "save two independently led expeditions")
	var led_store := ProgressStore.new()
	led_store.path = led.store.path
	check(led_store.load_progress(), "restore multiple led squads")
	var led_city := SettlementModel.new()
	led_city.configure(led_store)
	var restored_heroes := HeroModel.new(led_store)
	var restored_led := ExpeditionModel.new()
	check(restored_led.configure(led_city, restored_heroes) and restored_heroes.hero_busy("warden") and restored_heroes.hero_busy("ranger") and restored_heroes.available_troops("infantry") == 14, "restored jobs keep both heroes and six soldiers reserved")
	var army_total := int(led_store.data.army.infantry)
	check(restored_led.advance(120.0).ok and restored_led.jobs().is_empty(), "both hero-led squads return independently")
	check(not restored_heroes.hero_busy("warden") and not restored_heroes.hero_busy("ranger") and restored_heroes.available_troops("infantry") == army_total, "return releases existing soldiers without duplicating or consuming them")

	var legacy_store := ProgressStore.new()
	legacy_store.path = "user://expedition-test-%d-legacy.json" % OS.get_process_id()
	paths.append(legacy_store.path)
	legacy_store.data.colony_pending = {"stone": 101, "wood": 73, "essence": 22}
	var legacy_wallet: Dictionary = legacy_store.data.resources.duplicate()
	var legacy_city := SettlementModel.new()
	legacy_city.configure(legacy_store)
	var migrated := ExpeditionModel.new()
	check(migrated.configure(legacy_city) and legacy_store.data.resources == legacy_wallet, "old pending ore migration never credits the warehouse before a return")
	check(legacy_store.data.colony_pending == {"stone": 0, "wood": 0, "essence": 0}, "legacy pending queue is consumed into finite stock atomically")
	for legacy_resource in ExpeditionModel.RESOURCE_KEYS:
		var old_total := 0
		var next_total := 0
		for item: Dictionary in stock:
			if item.resource == legacy_resource:
				old_total += int(item.remaining)
		for item: Dictionary in migrated.deposits():
			if item.resource == legacy_resource:
				next_total += int(item.remaining)
		check(next_total == old_total + int({"stone": 101, "wood": 73, "essence": 22}[legacy_resource]), "all old %s remains available as finite ore" % legacy_resource)
	var migrated_stock: Array = migrated.deposits().duplicate(true)
	check(migrated.configure(legacy_city) and migrated.deposits() == migrated_stock, "second configure cannot migrate old ore twice")

	var failing_store := ProgressStore.new()
	failing_store.path = legacy_store.path + ".migration-blocked"
	paths.append(failing_store.path)
	failing_store.data.colony_pending = {"stone": 10, "wood": 20, "essence": 30}
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(failing_store.path + ".tmp"))
	var failing_city := SettlementModel.new()
	failing_city.configure(failing_store)
	var failing_model := ExpeditionModel.new()
	before = failing_store.data.duplicate(true)
	check(not failing_model.configure(failing_city) and failing_store.data == before, "failed migration save preserves old pending ore and previous world mode")

	await _finish()


func _finish() -> void:
	for path in paths:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".tmp"))
	await process_frame
	if failures.is_empty():
		print("PASS: %d expedition checks (finite stock, manual queues, routes, cargo, restart, respawn, hero yield, atomic saves)." % checks)
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
		quit(1)
