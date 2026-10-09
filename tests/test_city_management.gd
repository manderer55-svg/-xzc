extends SceneTree
var failures: Array[String] = []
var checks := 0
var selected := -1
func _initialize() -> void:
	call_deferred("_run")
func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
func press(button: TextureButton) -> void:
	var point := button_point(button)
	var move := InputEventMouseMotion.new()
	move.position = point
	Input.parse_input_event(move)
	await process_frame
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.position = point
	down.pressed = true
	Input.parse_input_event(down)
	await process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.position = point
	Input.parse_input_event(up)
	await process_frame
func touch(button: TextureButton, index: int = 0) -> void:
	var point := button_point(button)
	var down := InputEventScreenTouch.new()
	down.index = index
	down.position = point
	down.pressed = true
	Input.parse_input_event(down)
	await process_frame
	var up := InputEventScreenTouch.new()
	up.index = index
	up.position = point
	Input.parse_input_event(up)
	await process_frame
func button_point(button: TextureButton) -> Vector2:
	return root.get_final_transform() * button.get_global_transform_with_canvas() * (button.size * 0.5)
func preview(tag: String) -> void:
	if "--preview" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var suffix := "-phone" if "--phone" in OS.get_cmdline_user_args() else ""
	root.get_texture().get_image().save_png("/tmp/ashen-management-%s%s.png" % [tag, suffix])
func picture_bounds(node: Node) -> void:
	for child in node.get_children():
		if child is TextureRect and child.get_parent() is Control:
			var parent: Control = child.get_parent()
			check(child.size.x > 0 and child.size.y > 0, "generated illustration has nonempty display dimensions")
			check(Rect2(Vector2.ZERO, parent.size).encloses(Rect2(child.position, child.size)), "generated illustration fits its card without atlas minimum-size overflow")
		picture_bounds(child)
func _run() -> void:
	root.size = Vector2i(450, 800) if "--phone" in OS.get_cmdline_user_args() else Vector2i(720, 1280)
	for key in ColonyManagementPanel.BUILDING_KEYS:
		var generated := Art.texture(key) as AtlasTexture
		check(generated != null and generated.atlas.resource_path.contains("cartoon"), "catalogue uses new generated art: " + key)
		if generated != null:
			check(Rect2(Vector2.ZERO, generated.atlas.get_size()).encloses(generated.region), "generated building crop stays inside its atlas: " + key)
	for index in range(4):
		var portrait := Art.texture("hero_%d" % index) as AtlasTexture
		check(portrait != null and portrait.atlas.resource_path.contains("heroes_cartoon"), "new generated hero portrait %d" % index)
	for index in range(3):
		var troop := Art.texture("troop_%d" % index) as AtlasTexture
		check(troop != null and troop.atlas.resource_path.contains("heroes_cartoon"), "new generated troop portrait %d" % index)
	var store := ProgressStore.new()
	store.path = "user://management-test-%d.json" % OS.get_process_id()
	store.data.resources = {"stone": 10000, "wood": 10000, "essence": 10000}
	var settlement := SettlementModel.new()
	settlement.configure(store)
	var heroes := HeroModel.new(store)
	var panel := ColonyManagementPanel.new()
	root.add_child(panel)
	panel.configure(settlement, heroes)
	panel.building_chosen.connect(func(kind: int): selected = kind)
	check(not panel.visible, "modal starts hidden")
	panel.open_heroes()
	await process_frame
	check(panel.hero_action_buttons.size() == 4, "four readable hero cards")
	check(panel.chest_button.disabled, "chest requires tavern with visible hint")
	picture_bounds(panel)
	await preview("heroes")
	store.data.buildings[0] = 13
	panel.open_heroes()
	await process_frame
	check(not panel.chest_button.disabled, "tavern enables chests")
	await press(panel.chest_button)
	check(store.data.hero_state.chests == 1, "real mouse click buys chest")
	var cards := 0
	for id in store.data.hero_state.cards:
		cards += int(store.data.hero_state.cards[id])
	check(cards == 3, "chest updates all card counts")
	check(panel.chest_cost_labels.size() == 3 and panel.chest_cost_labels[0].text == "60" and panel.chest_cost_labels[1].text == "40" and panel.chest_cost_labels[2].text == "15", "resource prices remain visibly printed on chest button after purchase feedback")
	check(panel._subtitle.text.contains("25%") and panel._subtitle.text.contains("3 карты"), "chest quantity and odds remain visible after purchase feedback")
	await touch(panel.chest_button)
	check(store.data.hero_state.chests == 2, "real touchscreen tap buys exactly one chest through Godot UI emulation")
	store.data.hero_state.cards.warden = 2
	panel.open_heroes()
	await process_frame
	await press(panel.upgrade_button)
	check(store.data.heroes.warden == 2 and store.data.hero_state.cards.warden == 0, "real upgrade click spends matching cards")
	store.data.hero_state.cards.ranger = 3
	panel.open_heroes()
	await process_frame
	await press(panel.hero_action_buttons.ranger)
	check(store.data.heroes.has("ranger") and store.data.selected_hero == "ranger", "real unlock click opens and selects hero")
	panel.open_army()
	await process_frame
	check(panel.train_buttons.size() == 3 and panel.troop_buttons.size() == 3, "all three troop types have distinct actions")
	check(panel.train_buttons.infantry.disabled, "training unavailable without barracks")
	picture_bounds(panel)
	await preview("army")
	store.data.buildings[1] = 11
	panel.open_army()
	await process_frame
	var previous := int(store.data.army.infantry)
	await press(panel.train_buttons.infantry)
	check(int(store.data.army.infantry) == previous + 5, "real training click trains five infantry")
	panel.open_build()
	await process_frame
	check(panel.build_buttons.size() == SettlementModel.TITLES.size() and panel.build_buttons.size() >= 15, "catalogue contains all expandable castle building definitions")
	picture_bounds(panel)
	for tile in panel.build_buttons:
		check(tile.size.x >= 72 and tile.size.y >= 72, "building touch area is at least 72px")
		check(tile.position.x >= 0 and tile.position.x + tile.size.x <= panel.scroll.size.x, "catalogue tile stays within horizontal scroll bounds")
	await preview("build")
	var button: TextureButton = panel.build_buttons[0]
	var point := button_point(button)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.position = point
	down.pressed = true
	Input.parse_input_event(down)
	await process_frame
	var drag := InputEventMouseMotion.new()
	drag.relative = Vector2(0, -120) * root.get_final_transform().get_scale()
	drag.position = point + drag.relative
	Input.parse_input_event(drag)
	await process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.position = drag.position
	Input.parse_input_event(up)
	await process_frame
	check(selected == -1 and panel.visible, "dragging catalogue never chooses a building")
	check(panel.scroll.scroll_vertical > 0, "real mouse drag actually moves the expanded catalogue")
	await create_timer(0.22).timeout
	panel.open_build()
	await process_frame
	var touch_origin := button_point(panel.build_buttons[0])
	var touch_down := InputEventScreenTouch.new()
	touch_down.position = touch_origin
	touch_down.pressed = true
	Input.parse_input_event(touch_down)
	await process_frame
	var touch_drag := InputEventScreenDrag.new()
	touch_drag.relative = Vector2(0, -130) * root.get_final_transform().get_scale()
	touch_drag.position = touch_origin + touch_drag.relative
	Input.parse_input_event(touch_drag)
	await process_frame
	var touch_up := InputEventScreenTouch.new()
	touch_up.position = touch_drag.position
	Input.parse_input_event(touch_up)
	await process_frame
	check(panel.scroll.scroll_vertical > 0 and selected == -1 and panel.visible, "real touch drag scrolls without choosing a building")
	await create_timer(0.22).timeout
	panel.open_build()
	await process_frame
	panel.scroll.scroll_vertical = 10000
	await process_frame
	await process_frame
	await press(panel.build_buttons[-1])
	check(selected == panel.build_buttons.size() - 1 and not panel.visible, "real tile click reaches last building through scroll and closes modal")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(store.path))
	panel.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS: %d management UI checks (actual generated art, mouse/touch, cards/chests, training, scrolling)." % checks)
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
		quit(1)
