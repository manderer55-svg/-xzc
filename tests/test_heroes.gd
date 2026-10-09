extends SceneTree

const Heroes := preload("res://scripts/hero_model.gd")
const Expeditions := preload("res://scripts/expedition_model.gd")
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures.append(description)


func _run() -> void:
	var store := ProgressStore.new()
	store.path = "user://heroes-test-%d.json" % OS.get_process_id()
	store.data.resources = {"stone": 10000, "wood": 10000, "essence": 10000}
	var heroes := Heroes.new(store)
	check(heroes.owned().size() == 1 and heroes.hero_level("warden") == 1, "one starting commander")
	check(heroes.available_troops("infantry") == 20, "starting garrison can support first expedition")
	var ready := heroes.dispatch_validation()
	check(ready.ok and ready.hero_id == "warden" and ready.troop_type == "infantry" and ready.troop_count == 3, "first queue reserves three soldiers and one hero")
	check(not heroes.recruit("ranger").ok, "additional commanders require a tavern")
	check(not heroes.buy_chest().ok, "card chests require a tavern")
	check(not heroes.train("infantry").ok, "starting soldiers do not grant free training")
	check(not heroes.select_troop("archer").ok and not heroes.select_troop("cavalry").ok, "advanced troops require their military buildings")
	check(not heroes.select("missing").ok and not heroes.upgrade("missing").ok, "unknown heroes cannot be selected or improved")
	var catalog := heroes.catalog()
	catalog[0]["name"] = "changed"
	check(heroes.catalog()[0].name == "Бран", "catalog is safe for UI decoration")
	store.data.buildings[0] = 13
	var empty_cards: Dictionary = store.data.duplicate(true)
	check(not heroes.recruit("ranger").ok and store.data == empty_cards, "resources alone cannot unlock a hero without its cards")
	var chest_balance: Dictionary = store.data.resources.duplicate()
	var chest := heroes.buy_chest()
	check(chest.ok and store.data.hero_state.chests == 1, "tavern sells a card chest")
	var card_total := 0
	for amount in chest.cards.values():
		card_total += int(amount)
	check(card_total == 3, "a chest grants three hero cards")
	for resource in ProgressStore.RESOURCE_KEYS:
		check(store.data.resources[resource] == chest_balance[resource] - Heroes.CHEST_COST[resource], "chest pays banked " + resource)
	check(heroes.info().card_chances == "25% каждому герою", "equal hero card chances are disclosed")
	for id in ["ranger", "seer", "marshal"]:
		store.data.hero_state.cards[id] = 3
		var before: Dictionary = store.data.resources.duplicate()
		check(heroes.recruit(id).ok and heroes.hero_level(id) == 1, "unlock " + id)
		check(store.data.resources == before and heroes.card_count(id) == 0, "unlock consumes only three matching cards")
		var snapshot: Dictionary = store.data.duplicate(true)
		check(not heroes.recruit(id).ok and store.data == snapshot, "duplicate recruitment never charges twice")
	check(heroes.owned().size() == 4 and heroes.info().recruit_unlocked, "four distinct commanders in the tavern")
	check(heroes.yield_bonus("warden", "stone") > heroes.yield_bonus("warden", "wood"), "warden specializes in ore")
	check(heroes.yield_bonus("ranger", "wood") > heroes.yield_bonus("ranger", "stone"), "ranger specializes in timber")
	check(heroes.yield_bonus("seer", "essence") > heroes.yield_bonus("seer", "wood"), "seer specializes in essence")
	check(heroes.damage_bonus("marshal") > heroes.damage_bonus("warden"), "marshal specializes in troop command")
	for id in ["warden", "ranger", "seer", "marshal"]:
		for resource in ProgressStore.RESOURCE_KEYS:
			for raw in range(1, 81):
				var expected := raw + int(raw * heroes.yield_bonus(id, resource) / 100)
				check(heroes.extraction_cargo(id, resource, raw) == expected, "finite raw stock gets one rounded yield bonus")
	check(heroes.extraction_cargo("warden", "stone", -5) == 0, "invalid raw extraction cannot mint resources")
	store.data.buildings[1] = 11
	store.data.buildings[2] = 12
	store.data.buildings[3] = 10
	for type in ["infantry", "archer", "cavalry"]:
		var previous := int(store.data.army[type])
		var balance: Dictionary = store.data.resources.duplicate()
		check(heroes.select_troop(type).ok and heroes.train(type, 5).ok, "unlock and train " + type)
		check(store.data.army[type] == previous + 5 and heroes.available_troops(type) == previous + 5, "training adds available " + type)
		for resource in ProgressStore.RESOURCE_KEYS:
			check(store.data.resources[resource] == balance[resource] - int(heroes._troop(type).cost_per_unit[resource]) * 5, "training pays " + resource)
	check(heroes.party_damage("marshal", "cavalry") > heroes.party_damage("warden", "infantry"), "army type and command skill affect actual party damage")
	var untouched: Dictionary = store.data.duplicate(true)
	check(not heroes.train("cavalry", 0).ok and not heroes.train("cavalry", 101).ok and store.data == untouched, "training amount is bounded")
	store.data.expedition_state = {"jobs": [
		{"id": 1, "phase": "outbound", "hero_id": "warden", "troop_type": "infantry", "troop_count": 3, "yield_bonus": 20, "damage_bonus": 10},
		{"id": 2, "phase": "mining", "hero_id": "ranger", "troop_type": "archer", "troop_count": 3, "yield_bonus": 25, "damage_bonus": 8},
		{"id": 3, "phase": "returning", "hero_id": "seer", "troop_type": "cavalry", "troop_count": 3, "yield_bonus": 25, "damage_bonus": 12},
	]}
	check(heroes.available_troops("infantry") == 22 and heroes.available_troops("archer") == 2 and heroes.available_troops("cavalry") == 2, "each job reserves its own soldiers")
	check(not heroes.dispatch_validation("warden", "infantry").ok, "one hero cannot lead multiple simultaneous queues")
	check(not heroes.dispatch_validation("marshal", "archer").ok, "reserved archers cannot be duplicated across queues")
	check(heroes.dispatch_validation("marshal", "infantry").ok, "fourth distinct commander may lead free infantry")
	check(not heroes.upgrade("warden").ok, "a busy commander's snapshot cannot change in flight")
	var job_party := heroes.party_for_job(1)
	check(job_party.hero_id == "warden" and job_party.troop_count == 3 and job_party.party_damage == 33, "job shows its saved commander skill and party")
	store.data.expedition_state.jobs[0].phase = "delivery_retry"
	check(heroes.hero_busy("warden") and heroes.available_troops("infantry") == 22, "a full warehouse keeps returning party reserved")
	store.data.expedition_state.jobs.remove_at(0)
	check(not heroes.hero_busy("warden") and heroes.available_troops("infantry") == 25, "only confirmed arrival releases commander and troops")
	store.data.expedition_state.jobs.clear()
	var yield_before := heroes.yield_bonus("warden", "stone")
	var damage_before := heroes.damage_bonus("warden")
	store.data.hero_state.cards.warden = 20
	for level in range(2, Heroes.MAX_LEVEL + 1):
		var balance: Dictionary = store.data.resources.duplicate()
		var cards := heroes.card_count("warden")
		check(heroes.upgrade("warden").ok and heroes.hero_level("warden") == level, "commander advances to level %d" % level)
		check(store.data.resources == balance and heroes.card_count("warden") == cards - 2 * (level - 1), "upgrade consumes matching duplicates and preserves resources")
	check(heroes.yield_bonus("warden", "stone") > yield_before and heroes.damage_bonus("warden") > damage_before, "levels improve both extraction and army damage")
	var hero_yield := heroes.yield_bonus("warden", "stone")
	var hero_damage := heroes.damage_bonus("warden")
	store.data.buildings[4] = 8
	store.data.buildings[5] = 14
	store.data.buildings[6] = 7
	check(heroes.yield_bonus("warden", "stone") == mini(50, hero_yield + 3), "alliance buildings actually improve expedition yields")
	check(heroes.damage_bonus("warden") == hero_damage + 2, "citadel actually improves the commanded party damage")
	store.data.buildings[4] = -1
	store.data.buildings[5] = -1
	store.data.buildings[6] = -1
	untouched = store.data.duplicate(true)
	check(not heroes.upgrade("warden").ok and store.data == untouched, "fifth level is the current cap")
	store.data.army.infantry = Heroes.MAX_ARMY
	untouched = store.data.duplicate(true)
	check(not heroes.train("infantry", 1).ok and store.data == untouched, "army capacity cannot overflow")
	store.data.resources = {"stone": 0, "wood": 0, "essence": 0}
	untouched = store.data.duplicate(true)
	check(not heroes.train("cavalry", 5).ok and not heroes.buy_chest().ok and store.data == untouched, "training and chests require delivered resources")
	check(not heroes.upgrade("ranger").ok and store.data == untouched, "hero improvement requires its duplicate cards")
	store.data.resources = {"stone": 10000, "wood": 10000, "essence": 10000}
	# Real jobs snapshot the skill, consume finite raw ore and release a party only at the gate.
	store.data.army.infantry = 20
	var settlement := SettlementModel.new()
	settlement.configure(store)
	var expeditions := Expeditions.new()
	check(expeditions.configure(settlement, heroes), "initialize the actual resource map with heroes")
	var deposit: Dictionary = {}
	for candidate: Dictionary in expeditions.deposits():
		if candidate.resource == "stone":
			deposit = candidate
			break
	check(not deposit.is_empty(), "map contains a reachable ore site")
	if not deposit.is_empty():
		var stock := int(deposit.remaining)
		var expected_cargo := heroes.extraction_cargo("warden", "stone", stock)
		var banked := int(store.data.resources.stone)
		var dispatched := expeditions.dispatch(int(deposit.id), "warden", "infantry")
		check(dispatched.ok and heroes.hero_busy("warden") and heroes.available_troops("infantry") == 17, "dispatch reserves the chosen commander and three real soldiers")
		var guard := 0
		while not expeditions.jobs().is_empty() and str(expeditions.jobs()[0].phase) != "returning" and guard < 200:
			expeditions.advance(0.5)
			guard += 1
		check(int(deposit.remaining) == 0 and not bool(deposit.active), "hero's bonus does not increase finite raw stock")
		check(store.data.resources.stone == banked and heroes.hero_busy("warden"), "mining does not bank cargo or release the commander before arrival")
		if not expeditions.jobs().is_empty():
			check(int(expeditions.jobs()[0].raw_cargo) == stock and int(expeditions.jobs()[0].cargo_amount) == expected_cargo, "the extraction bonus applies once to the final cargo")
		expeditions.advance(60.0)
		check(store.data.resources.stone == banked + expected_cargo, "the real returning party banks exactly the finite cargo and hero bonus")
		check(not heroes.hero_busy("warden") and heroes.available_troops("infantry") == 20, "arrival makes the hero and same soldiers available for another queue")
	check(heroes.select("ranger").ok and heroes.select_troop("archer").ok, "selection is saved for the next queue")
	# Reload checks the real ProgressStore schema; queues independently preserve reservations.
	check(store.save_progress(), "save completed hero and military progress")
	var restored := ProgressStore.new()
	restored.path = store.path
	check(restored.load_progress(), "reload hero save")
	var reload_heroes := Heroes.new(restored)
	check(reload_heroes.hero_level("warden") == 5 and reload_heroes.owned().size() == 4, "hero ownership and upgrades survive restart")
	check(reload_heroes.info().selected_hero == "ranger" and reload_heroes.info().selected_troop == "archer", "hero and troop selection survive restart")
	check(restored.data.army == store.data.army, "trained army survives restart")
	check(restored.data.hero_state == store.data.hero_state, "cards and chest sequence survive restart")
	# Guaranteed occasional first-clear cards join the same atomic reward transaction.
	var campaign := ProgressStore.new()
	campaign.path = store.path + ".campaign"
	var campaign_heroes := Heroes.new(campaign)
	campaign.data.level = 3
	campaign.award_level(3, 1200, true, {})
	var level_reward := Heroes.level_card_reward(3)
	check(campaign_heroes.card_count(str(level_reward.hero_id)) == 1, "first clear of every third level grants a hero card")
	var card_snapshot: Dictionary = campaign.data.hero_state.cards.duplicate()
	campaign.award_level(3, 2400, true, {})
	check(campaign.data.hero_state.cards == card_snapshot, "replayed level cannot duplicate a hero card")
	campaign.award_level(6, 2400, true, {})
	check(campaign.data.hero_state.cards == card_snapshot, "locked level cannot grant a card")
	campaign.data.level = 10
	campaign.award_level(10, 2400, false, {})
	check(campaign.data.hero_state.cards == card_snapshot, "failed boss attempt cannot grant a card")
	campaign.award_level(10, 2400, true, {})
	var boss_reward := Heroes.level_card_reward(10)
	check(campaign_heroes.card_count(str(boss_reward.hero_id)) == 1, "boss first clear guarantees a hero card")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(campaign.path))
	var saved_path := store.path
	var blocked := saved_path + ".blocked"
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(blocked + ".tmp"))
	store.path = blocked
	store.data.heroes.erase("seer")
	store.data.hero_state.cards.seer = 3
	store.data.hero_state.cards.ranger = 2
	untouched = store.data.duplicate(true)
	check(not heroes.recruit("seer").ok and store.data == untouched, "failed unlock save rolls back cards and ownership")
	check(not heroes.upgrade("ranger").ok and store.data == untouched, "failed upgrade save rolls back cards and level")
	check(not heroes.buy_chest().ok and store.data == untouched, "failed chest save rolls back payment, cards and sequence")
	check(not heroes.train("archer", 5).ok and store.data == untouched, "failed training save rolls back payment and soldiers")
	check(not heroes.select("marshal").ok and store.data == untouched, "failed hero selection save restores previous selection")
	check(not heroes.select_troop("cavalry").ok and store.data == untouched, "failed troop selection save restores previous selection")
	store.data.level = 6
	untouched = store.data.duplicate(true)
	store.award_level(6, 2400, true, {})
	check(store.data == untouched and store.last_award_status == "save_failed", "failed first-clear save rolls back the level, resources and hero card together")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(blocked + ".tmp"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(saved_path))
	if failures.is_empty():
		print("PASS: %d hero checks (card chests, unlocks, duplicates, first-clear rewards, finite yield, troop training, reservations, reload, atomic saves)." % checks)
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
		quit(1)
