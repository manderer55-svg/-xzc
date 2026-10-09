class_name ColonyManagementPanel
extends Control
## A touch-sized catalogue layered above the map. Artwork remains generated;
## only layout, selection, scrolling and text are drawn by the interface.

signal building_chosen(kind: int)
signal updated
signal closed

const UI_FONT: Font = preload("res://art/fonts/DejaVuSans.ttf")
const UI_FONT_BOLD: Font = preload("res://art/fonts/DejaVuSans-Bold.ttf")
const GOLD := Color("d4b376")
const IVORY := Color("efe3c8")
const MUTED := Color("b2b09f")
const BUILDING_KEYS := ["quarry", "sawmill", "shrine", "fortress", "forge", "watchtower",
	"townhall", "citadel", "alliance_hall", "market", "stable", "barracks", "archery", "tavern", "alliance_store"]
const RESOURCE_KEYS := ["stone", "wood", "essence"]
const RESOURCE_NAMES := {"stone": "камень", "wood": "древо", "essence": "эссенция"}

var settlement: SettlementModel
var heroes: HeroModel
var build_buttons: Array[TextureButton] = []
var hero_action_buttons: Dictionary = {}
var train_buttons: Dictionary = {}
var troop_buttons: Dictionary = {}
var tab_buttons: Dictionary = {}
var upgrade_button: TextureButton
var chest_button: TextureButton
var chest_cost_labels: Array[Label] = []
var status_label: Label
var scroll: ScrollContainer
var content: Control
var mode := "build"
var _title: Label
var _subtitle: Label
var _page: Control
var _scroll_thumb: GeneratedFrame
var _scroll_track: GeneratedFrame
var _initialized := false
var _drag_index := -2
var _drag_origin := Vector2.ZERO
var _drag_scroll := 0
var _gesture_moved := false
var _suppress_until := 0


func configure(settlement_model: SettlementModel, hero_model: HeroModel) -> void:
	settlement = settlement_model
	heroes = hero_model
	if _initialized:
		return
	_initialized = true
	size = Vector2(720, 1280)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_frame(self, "ui_panel", Vector2.ZERO, size).modulate = Color(0.62, 0.68, 0.73)
	_frame(self, "ui_header", Vector2(24, 44), Vector2(672, 150))
	_title = _label(self, "", Vector2(54, 69), Vector2(520, 58), 30, GOLD)
	_subtitle = _label(self, "", Vector2(54, 126), Vector2(524, 45), 18, MUTED)
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_button(self, "×", Vector2(589, 72), Vector2(80, 82), close_panel, 35)
	for index in range(3):
		var key: String = ["build", "heroes", "army"][index]
		var caption: String = ["ПОСТРОЙКИ", "ГЕРОИ", "ВОЙСКА"][index]
		tab_buttons[key] = _button(self, caption, Vector2(30 + index * 224, 207), Vector2(212, 78), func(): _show_mode(key), 22)
	_page = Control.new()
	_page.position = Vector2(0, 306)
	_page.size = Vector2(720, 798)
	_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_page)
	_frame(self, "ui_panel", Vector2(24, 1115), Vector2(672, 136))
	status_label = _label(self, "", Vector2(48, 1128), Vector2(624, 49), 18, IVORY, true)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	upgrade_button = _button(self, "Улучшить героя", Vector2(38, 1180), Vector2(316, 72), _upgrade_selected, 23)
	upgrade_button.visible = false
	chest_button = _button(self, "", Vector2(366, 1180), Vector2(316, 72), _buy_chest, 23)
	_label(chest_button, "Купить сундук", Vector2(10, 1), Vector2(296, 32), 20, GOLD, true)
	for index in range(3):
		var x := 18.0 + index * 92.0
		_picture(chest_button, RESOURCE_KEYS[index], Vector2(x, 40), Vector2(24, 22))
		chest_cost_labels.append(_label(chest_button, str(HeroModel.CHEST_COST[RESOURCE_KEYS[index]]), Vector2(x + 26, 35), Vector2(60, 32), 18, IVORY))
	chest_button.visible = false
	set_process(true)


func open_build() -> void:
	visible = true
	_show_mode("build")


func open_heroes() -> void:
	visible = true
	_show_mode("heroes")


func open_army() -> void:
	visible = true
	_show_mode("army")


func close_panel() -> void:
	visible = false
	_drag_index = -2
	_gesture_moved = false
	closed.emit()


func _show_mode(next_mode: String, feedback: String = "") -> void:
	mode = next_mode
	_drag_index = -2
	_gesture_moved = false
	scroll = null
	_scroll_thumb = null
	_scroll_track = null
	build_buttons.clear()
	hero_action_buttons.clear()
	train_buttons.clear()
	troop_buttons.clear()
	for child in _page.get_children():
		_page.remove_child(child)
		child.queue_free()
	for key in tab_buttons:
		tab_buttons[key].modulate = Color(1.18, 1.10, 0.88) if key == mode else Color(0.82, 0.82, 0.86)
	upgrade_button.visible = mode == "heroes"
	chest_button.visible = mode == "heroes"
	if mode == "build":
		_title.text = "ПОСТРОЙКИ ЗАМКА"
		_subtitle.text = "Выберите здание, затем свободный участок в городе."
		_build_catalogue()
		status_label.text = "Листайте каталог вверх и вниз. Постройки развиваются до 20 уровней."
	elif mode == "heroes":
		_title.text = "ТАВЕРНА И ГЕРОИ"
		_subtitle.text = "Сундук: 3 карты · %s.\nГерои открываются и растут за карты." % str(heroes.info().get("card_chances", "25% каждому герою"))
		_build_heroes()
		status_label.text = _hero_footer()
	else:
		_title.text = "ВОЙСКА ЗАМКА"
		_subtitle.text = "Пехота, стрелки и конница сопровождают героя на карте."
		_build_army()
		status_label.text = "На одну очередь нужно 3 свободных воина и свободный герой."
	if not feedback.is_empty():
		status_label.text = feedback


func _build_catalogue() -> void:
	scroll = ScrollContainer.new()
	scroll.position = Vector2(30, 0)
	scroll.size = Vector2(642, 790)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	_page.add_child(scroll)
	content = Control.new()
	var count := SettlementModel.TITLES.size()
	content.custom_minimum_size = Vector2(630, ceili(float(count) / 3.0) * 252)
	content.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(content)
	for kind in range(count):
		var card := _button(content, "", Vector2(5 + (kind % 3) * 210, int(kind / 3) * 252), Vector2(200, 238), func(): _choose_building(kind), 20)
		build_buttons.append(card)
		var art_key: String = BUILDING_KEYS[kind] if kind < BUILDING_KEYS.size() else "citadel"
		_picture(card, art_key, Vector2(26, 12), Vector2(148, 112))
		var title := _label(card, String(SettlementModel.TITLES[kind]), Vector2(10, 122), Vector2(180, 52), 18, GOLD, true)
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var cost := settlement.get_build_cost(kind)
		for resource_index in range(3):
			var resource: String = RESOURCE_KEYS[resource_index]
			var x := 9.0 + resource_index * 62.0
			_picture(card, resource, Vector2(x, 178), Vector2(22, 25))
			_label(card, str(cost.get(resource, 0)), Vector2(x - 3, 206), Vector2(54, 23), 17, IVORY, true)
	_scroll_track = _frame(_page, "ui_progress", Vector2(681, 0), Vector2(12, 790))
	_scroll_track.modulate = Color(0.55, 0.55, 0.62)
	_scroll_thumb = _frame(_page, "ui_progress", Vector2(678, 0), Vector2(18, 96))
	_scroll_thumb.modulate = Color(1.30, 1.12, 0.83)


func _build_heroes() -> void:
	var info := heroes.info()
	var owned: Dictionary = {}
	for hero: Dictionary in info.get("heroes", []):
		owned[str(hero.id)] = hero
	var catalogue := heroes.catalog()
	for index in range(catalogue.size()):
		var entry: Dictionary = catalogue[index]
		var id := str(entry.id)
		var available := owned.has(id)
		var hero: Dictionary = owned.get(id, entry)
		var card := Control.new()
		card.position = Vector2(30 + (index % 2) * 338, int(index / 2) * 386)
		card.size = Vector2(322, 370)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_page.add_child(card)
		var frame := _frame(card, "ui_panel", Vector2.ZERO, card.size)
		frame.modulate = Color(1.17, 1.09, 0.88) if str(info.get("selected_hero", "")) == id else Color.WHITE
		_picture(card, str(entry.get("portrait", "hero_%d" % index)), Vector2(100, 15), Vector2(122, 118))
		_label(card, str(entry.get("name", id)) + (" · %d ур." % int(hero.get("level", 1)) if available else ""), Vector2(14, 137), Vector2(294, 35), 23, GOLD, true)
		var role := _label(card, str(entry.get("role", "Герой")), Vector2(16, 173), Vector2(290, 41), 17, MUTED, true)
		role.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var stats := _label(card, _hero_stats(hero, available), Vector2(20, 215), Vector2(282, 73), 17, IVORY, true)
		stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var caption := "Выбрать" if available else "Открыть героя"
		if available and bool(hero.get("busy", false)):
			caption = "В походе"
		elif available and str(info.get("selected_hero", "")) == id:
			caption = "Выбран"
		var action := _button(card, caption, Vector2(20, 289), Vector2(282, 74), func(): _hero_action(id, available), 23)
		action.disabled = available and bool(hero.get("busy", false))
		if action.disabled:
			action.modulate = Color(0.65, 0.65, 0.68)
		hero_action_buttons[id] = action
	var selected: Dictionary = owned.get(str(info.get("selected_hero", "")), {})
	var required_cards := int(selected.get("upgrade_cards", 0))
	upgrade_button.disabled = selected.is_empty() or required_cards <= 0 or int(selected.get("cards", 0)) < required_cards
	upgrade_button.modulate = Color(0.65, 0.65, 0.68) if upgrade_button.disabled else Color.WHITE
	chest_button.disabled = not bool(info.get("recruit_unlocked", false))
	chest_button.modulate = Color(0.65, 0.65, 0.68) if chest_button.disabled else Color.WHITE
	var chest_cost: Dictionary = info.get("chest_cost", HeroModel.CHEST_COST)
	for index in range(3):
		chest_cost_labels[index].text = str(chest_cost.get(RESOURCE_KEYS[index], 0))


func _build_army() -> void:
	var info := heroes.info()
	var troops: Array = info.get("troops", [])
	for index in range(troops.size()):
		var troop: Dictionary = troops[index]
		var id := str(troop.id)
		var row := Control.new()
		row.position = Vector2(30, 16 + index * 248)
		row.size = Vector2(660, 232)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_page.add_child(row)
		_frame(row, "ui_panel", Vector2.ZERO, row.size)
		_picture(row, str(troop.get("portrait", "troop_%d" % index)), Vector2(14, 40), Vector2(116, 142))
		_label(row, str(troop.get("name", id)), Vector2(140, 19), Vector2(290, 38), 23, GOLD)
		_label(row, "Всего %d · свободно %d" % [int(troop.get("count", 0)), int(troop.get("available", 0))], Vector2(140, 63), Vector2(296, 47), 18, IVORY)
		var training_unlocked := bool(troop.get("training_unlocked", troop.get("unlocked", false)))
		var detail := "Обучение 5: " + _cost_text(_multiply_cost(troop.get("cost_per_unit", {}), 5)) if training_unlocked else "Постройте: " + _troop_building_title(troop)
		var description := _label(row, detail, Vector2(140, 115), Vector2(286, 94), 17, MUTED)
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var selected := str(info.get("selected_troop", "")) == id
		var pick := _button(row, "Выбраны" if selected else "Выбрать", Vector2(439, 21), Vector2(198, 78), func(): _select_troop(id), 23)
		troop_buttons[id] = pick
		if selected:
			pick.modulate = Color(1.18, 1.10, 0.88)
		var training := _button(row, "Обучить 5", Vector2(439, 124), Vector2(198, 78), func(): _train_troop(id), 23)
		training.disabled = not training_unlocked
		if training.disabled:
			training.modulate = Color(0.65, 0.65, 0.68)
		train_buttons[id] = training


func _choose_building(kind: int) -> void:
	if _click_suppressed():
		return
	building_chosen.emit(kind)
	close_panel()


func _hero_action(id: String, is_owned: bool) -> void:
	if _click_suppressed():
		return
	var result: Dictionary = heroes.select(id) if is_owned else heroes.recruit(id)
	_feedback(result)


func _upgrade_selected() -> void:
	if _click_suppressed():
		return
	var id := str(heroes.info().get("selected_hero", ""))
	_feedback(heroes.upgrade(id))


func _buy_chest() -> void:
	if _click_suppressed():
		return
	_feedback(heroes.buy_chest())


func _select_troop(id: String) -> void:
	_feedback(heroes.select_troop(id))


func _train_troop(id: String) -> void:
	_feedback(heroes.train(id, 5))


func _feedback(result: Dictionary) -> void:
	var message := str(result.get("reason", "Готово."))
	if bool(result.get("ok", false)) and result.get("cards") is Dictionary:
		var received: Array[String] = []
		for hero: Dictionary in heroes.catalog():
			var amount := int(result.cards.get(hero.id, 0))
			if amount > 0:
				received.append("%s ×%d" % [str(hero.name), amount])
		if not received.is_empty():
			message = "Карты сундука: " + " · ".join(received)
	if not bool(result.get("ok", false)) and result.has("cost"):
		var cost: Dictionary = result.cost
		if not cost.is_empty():
			message += " " + _cost_text(cost)
	_show_mode(mode, message)
	updated.emit()


func _hero_stats(hero: Dictionary, is_owned: bool) -> String:
	var bonuses: Dictionary = hero.get("yield_bonuses", {})
	var resource := str(hero.get("resource", "stone"))
	var yield_text := "%s +%d%%" % [str(RESOURCE_NAMES.get(resource, "Добыча")), int(bonuses.get(resource, 0))]
	if resource == "all":
		var smallest_bonus := 50
		for key in RESOURCE_KEYS:
			smallest_bonus = mini(smallest_bonus, int(bonuses.get(key, 0)))
		yield_text = "Вся добыча +%d%%" % smallest_bonus
	var damage := int(hero.get("damage_bonus", 0))
	var cards := int(hero.get("cards", 0))
	var required := int(hero.get("upgrade_cards", 0)) if is_owned else int(hero.get("unlock_cards", 3))
	var card_text := "Карты: %d/%d" % [cards, required] if required > 0 else "Карты: %d · максимум" % cards
	var text := yield_text + "\nУрон войск +%d%%\n%s" % [damage, card_text]
	return text


func _hero_footer() -> String:
	var info := heroes.info()
	var chest_cost: Dictionary = info.get("chest_cost", {"stone": 60, "wood": 40, "essence": 15})
	if not bool(info.get("recruit_unlocked", false)):
		return "Постройте таверну для сундуков и новых героев. Первые победы дают карты для улучшения Брана."
	return "Сундук: 3 карты (25% каждый герой) · " + _cost_text(chest_cost) + "."


func _troop_building_title(troop: Dictionary) -> String:
	var building: Variant = troop.get("building", -1)
	if building is int and int(building) >= 0 and int(building) < SettlementModel.TITLES.size():
		return str(SettlementModel.TITLES[int(building)])
	return str(building)


func _multiply_cost(cost: Dictionary, amount: int) -> Dictionary:
	var output: Dictionary = {}
	for key in cost:
		output[key] = int(cost[key]) * amount
	return output


func _cost_text(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for resource in RESOURCE_KEYS:
		var amount := int(cost.get(resource, 0))
		if amount > 0:
			parts.append("%s: %d" % [RESOURCE_NAMES[resource], amount])
	return ", ".join(parts) if not parts.is_empty() else "бесплатно"


func _process(_delta: float) -> void:
	if not visible or not is_instance_valid(scroll) or not is_instance_valid(_scroll_thumb):
		return
	var height := maxf(1.0, content.size.y)
	var viewport_height := scroll.size.y
	var thumb_height := clampf(viewport_height * viewport_height / height, 72.0, viewport_height)
	_scroll_thumb.set_display_size(Vector2(18, thumb_height))
	_scroll_thumb.position.y = float(scroll.scroll_vertical) / maxf(1.0, height - viewport_height) * (viewport_height - thumb_height)
	_scroll_thumb.visible = height > viewport_height
	_scroll_track.visible = height > viewport_height


func _input(event: InputEvent) -> void:
	if not visible or not is_instance_valid(scroll):
		return
	var is_press := false
	var is_release := false
	var is_motion := false
	var pointer := Vector2.ZERO
	var index := -1
	if event is InputEventScreenTouch:
		pointer = event.position
		index = event.index
		is_press = event.pressed
		is_release = not event.pressed
	elif event is InputEventScreenDrag:
		pointer = event.position
		index = event.index
		is_motion = true
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		pointer = event.position
		is_press = event.pressed
		is_release = not event.pressed
	elif event is InputEventMouseMotion:
		pointer = event.position
		is_motion = true
	else:
		return
	var local := scroll.get_global_transform_with_canvas().affine_inverse() * pointer
	if is_press and Rect2(Vector2.ZERO, scroll.size).has_point(local) and _drag_index == -2:
		_drag_index = index
		_drag_origin = local
		_drag_scroll = scroll.scroll_vertical
		_gesture_moved = false
	elif index == _drag_index and is_motion:
		var displacement := local - _drag_origin
		if displacement.length() > 12.0:
			_gesture_moved = true
		if _gesture_moved:
			scroll.scroll_vertical = _drag_scroll - int(displacement.y)
			_suppress_until = Time.get_ticks_msec() + 180
			get_viewport().set_input_as_handled()
	elif index == _drag_index and is_release:
		if _gesture_moved:
			_suppress_until = Time.get_ticks_msec() + 180
			get_viewport().set_input_as_handled()
		_drag_index = -2
		_gesture_moved = false


func _click_suppressed() -> bool:
	return _gesture_moved or Time.get_ticks_msec() < _suppress_until


func _frame(parent: Node, key: String, location: Vector2, dimensions: Vector2) -> GeneratedFrame:
	var frame := GeneratedFrame.new()
	frame.configure(key, dimensions)
	frame.position = location
	parent.add_child(frame)
	return frame


func _picture(parent: Node, key: String, location: Vector2, dimensions: Vector2) -> TextureRect:
	var picture := TextureRect.new()
	picture.texture = Art.texture(key)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.position = location
	picture.size = dimensions
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(picture)
	return picture


func _label(parent: Node, value: String, location: Vector2, dimensions: Vector2, font_size: int, color: Color, centered: bool = false) -> Label:
	var label := Label.new()
	label.text = value
	label.position = location
	label.size = dimensions
	label.add_theme_font_override("font", UI_FONT_BOLD if font_size >= 23 else UI_FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color("180f17"))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if centered:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _button(parent: Node, caption: String, location: Vector2, dimensions: Vector2, action: Callable, font_size: int = 23) -> TextureButton:
	var button := TextureButton.new()
	button.position = location
	button.size = dimensions
	button.ignore_texture_size = true
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.focus_mode = Control.FOCUS_ALL
	button.pressed.connect(func():
		if not _click_suppressed():
			action.call())
	button.button_down.connect(func(): button.modulate = Color(0.77, 0.72, 0.64))
	button.button_up.connect(func(): button.modulate = Color.WHITE)
	parent.add_child(button)
	var frame := _frame(button, "ui_small_button", Vector2.ZERO, dimensions)
	frame.name = "GeneratedButtonFrame"
	button.custom_minimum_size = frame.minimum_display_size()
	button.resized.connect(func(): frame.set_display_size(button.size))
	if not caption.is_empty():
		_label(button, caption, Vector2(12, 0), dimensions - Vector2(24, 0), font_size, GOLD, true)
	return button
