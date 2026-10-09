extends Control
## All visible illustration, frames, tiles and effects come from the generated art atlas.
## Runtime drawing is limited to text, arranging textures and animating those textures.

const CANVAS := Vector2(720, 1280)
const GOLD := Color("e4c68b")
const IVORY := Color("eee7d9")
const MUTED := Color("b8ac99")
const UI_FONT: Font = preload("res://art/fonts/DejaVuSans.ttf")
const UI_FONT_BOLD: Font = preload("res://art/fonts/DejaVuSans-Bold.ttf")
const TITLE_FONT: Font = preload("res://art/fonts/DejaVuSerif-Bold.ttf")
const GEM_NAMES := ["Рубин", "Аметист", "Изумруд", "Сапфир", "Янтарь", "Лунный камень"]
const BUILDING_KEYS := Art.CITY_KEYS
const BUILDING_NAMES := SettlementModel.TITLES

var engine: MatchEngine
var store: ProgressStore
var settlement: SettlementModel
var heroes: HeroModel
var expeditions: ExpeditionModel
var expedition_paused := false
var colony_ui_clock := 0.0
var selected_deposit := -1
var colony_heading: Label
var colony_queue_label: Label
var colony_mode_button: TextureButton
var colony_palette_button: TextureButton
var management: ColonyManagementPanel
var active_level := 1
var busy := false
var selected := Vector2i(-1, -1)
var pointer_start := Vector2.ZERO
var pointer_cell := Vector2i(-1, -1)
var pointer_down := false
var pointer_touch_id := -1
var tile_size := 72.0
var board_origin := Vector2.ZERO
var board_size := Vector2.ZERO
var tile_nodes: Dictionary = {}
var tile_snapshot: Dictionary = {}
var running_tweens: Array[Tween] = []
var turn_generation := 0
var current_screen := "home"
var settlement_origin := "home"
var home_after_turn := false
var home_time := 0.0
var selected_slot := 4
var selected_kind := 0
var choosing_level := 1
var reward_banked := false
var last_rewards: Dictionary = {}
var entry_bonuses: Dictionary = {}
var texture_hit_masks: Dictionary = {}
var gem_pool: Array[GemView] = []
var cell_nodes: Dictionary = {}
var altar_nodes: Dictionary = {}
var fx_pool: EffectPool
var hint_tween: Tween
var hint_serial := 0
var hint_searching := false
var paused_gesture := false

var home_screen: Control
var home_background: TextureRect
var home_continue: TextureButton
var home_level_number: GeneratedNumber
var home_region_label: Label
var game_screen: Control
var settlement_screen: Control
var cells_layer: Control
var board_contour: BoardContour
var gems_layer: Control
var effects_layer: Control
var selection_ring: TextureRect
var level_label: Label
var score_label: GeneratedNumber
var target_label: Label
var target_number: GeneratedNumber
var level_number: GeneratedNumber
var moves_label: GeneratedNumber
var status_label: Label
var progress_fill: TextureRect
var shape_label: Label
var settlement_grid: MineColony
var building_choices: Array[TextureButton] = []
var resource_labels: Array[GeneratedNumber] = []
var slot_title: Label
var slot_detail: Label
var settlement_status: Label
var build_button: TextureButton
var upgrade_button: TextureButton
var settlement_return_button: TextureButton
var modal: Control
var modal_title: Label
var modal_body: Label
var hero_reward_portrait: TextureRect
var modal_action: TextureButton
var modal_secondary: TextureButton
var level_modal: Control
var level_choice_label: GeneratedNumber
var end_won := false
var mission_icon: TextureRect
var objective_number: GeneratedNumber
var mission_description: Label
var boss_timer_label: Label
var game_background: TextureRect
var utility_modal: Control
var utility_title: Label
var utility_body: Label
var reduced_button: TextureButton
var haptics_button: TextureButton
var sound_button: TextureButton
var audio: AudioDirector
var utility_mode := "help"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	store = ProgressStore.new()
	if "--smoke" in OS.get_cmdline_user_args():
		store.path = "user://ui-smoke-progress.json"
		if FileAccess.file_exists(store.path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(store.path))
	store.load_progress()
	settlement = SettlementModel.new()
	settlement.configure(store)
	heroes = HeroModel.new(store)
	expeditions = ExpeditionModel.new()
	expeditions.configure(settlement, heroes)
	audio = AudioDirector.new()
	audio.enabled = bool(store.data.settings.sound)
	add_child(audio)
	_build_home_screen()
	_build_game_screen()
	_build_settlement_screen()
	management = ColonyManagementPanel.new()
	management.configure(settlement, heroes)
	management.building_chosen.connect(_choose_kind)
	management.updated.connect(_update_settlement)
	management.closed.connect(func(): settlement_grid.interaction_enabled = true)
	add_child(management)
	_build_result_modal()
	_build_level_modal()
	_build_utility_modal()
	active_level = maxi(1, int(store.data.get("level", 1)))
	_load_level(active_level)
	_show_home()
	if not store.last_error.is_empty():
		status_label.text = store.last_error
	if "--smoke" in OS.get_cmdline_user_args():
		_smoke()


func _texture(parent: Node, key: String, position: Vector2, dimensions: Vector2) -> TextureRect:
	var node := TextureRect.new()
	node.texture = Art.texture(key)
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_SCALE
	node.position = position
	node.size = dimensions
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node


func _frame(parent: Node, key: String, position: Vector2, dimensions: Vector2) -> GeneratedFrame:
	var node := GeneratedFrame.new()
	node.configure(key, dimensions)
	node.position = position
	parent.add_child(node)
	return node


func _label(parent: Node, text_value: String, position: Vector2, dimensions: Vector2, font_size: int = 24, color: Color = IVORY, centered: bool = false) -> Label:
	var node := Label.new()
	node.text = text_value
	node.position = position
	node.size = dimensions
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_font_override("font", UI_FONT_BOLD if font_size >= 28 else UI_FONT)
	node.add_theme_color_override("font_color", color)
	node.add_theme_color_override("font_shadow_color", Color("180f17"))
	node.add_theme_constant_override("shadow_offset_x", 1)
	node.add_theme_constant_override("shadow_offset_y", 2)
	node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if centered:
		node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node


func _button(parent: Node, text_value: String, position: Vector2, dimensions: Vector2, action: Callable, small: bool = false) -> TextureButton:
	var node := TextureButton.new()
	node.ignore_texture_size = true
	node.position = position
	node.size = dimensions
	node.focus_mode = Control.FOCUS_ALL
	node.pressed.connect(func():
		audio.play("tap")
		action.call())
	node.button_down.connect(func(): node.modulate = Color(0.77, 0.72, 0.64))
	node.button_up.connect(func(): node.modulate = Color.WHITE)
	node.mouse_entered.connect(func(): if not node.disabled: node.modulate = Color(1.15, 1.08, 0.95))
	node.mouse_exited.connect(func(): node.modulate = Color.WHITE)
	parent.add_child(node)
	var frame := _frame(node, "ui_small_button" if small else "ui_button", Vector2.ZERO, dimensions)
	frame.name = "GeneratedButtonFrame"
	node.custom_minimum_size = frame.minimum_display_size()
	node.resized.connect(func(): frame.set_display_size(node.size))
	_label(node, text_value, Vector2(12, 0), dimensions - Vector2(24, 0), 26 if not small else 24, GOLD, true)
	return node


func _number(parent: Node, text_value: String, position: Vector2, dimensions: Vector2, centered: bool = false) -> GeneratedNumber:
	var node := GeneratedNumber.new()
	node.position = position
	node.size = dimensions
	node.centered = centered
	node.text = text_value
	parent.add_child(node)
	# Warm the reusable generated glyph slots before the first rendered frame.
	node.text = "99999999"
	node.text = text_value
	return node


func _new_screen() -> Control:
	var screen := Control.new()
	screen.size = CANVAS
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(screen)
	return screen


func _build_home_screen() -> void:
	home_screen = _new_screen()
	var background_key := "home_background" if ResourceLoader.exists("res://art/darkfantasy/home_background.png") else "forest_background"
	home_background = _texture(home_screen, background_key, Vector2(-12, -12), CANVAS + Vector2(24, 24))
	home_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_label(home_screen, "ПЕПЕЛЬНЫЙ", Vector2(55, 72), Vector2(610, 73), 48, GOLD, true).add_theme_font_override("font", TITLE_FONT)
	_label(home_screen, "ПРЕДЕЛ", Vector2(55, 137), Vector2(610, 76), 52, IVORY, true).add_theme_font_override("font", TITLE_FONT)
	_label(home_screen, "ТЁМНОЕ ФЭНТЕЗИ · ТРИ В РЯД", Vector2(60, 225), Vector2(600, 34), 17, MUTED, true)
	home_region_label = _label(home_screen, "ПРОКЛЯТЫЙ ЛЕС", Vector2(70, 275), Vector2(580, 43), 24, IVORY, true)
	home_continue = _button(home_screen, "Продолжить поход", Vector2(60, 838), Vector2(600, 140), _continue_from_home)
	for child in home_continue.get_children():
		if child is Label:
			child.position = Vector2(20, 17)
			child.size = Vector2(560, 53)
			child.add_theme_font_size_override("font_size", 30)
	_label(home_continue, "РАЗЛОМ", Vector2(199, 81), Vector2(130, 31), 18, MUTED, true)
	home_level_number = _number(home_continue, "1", Vector2(327, 75), Vector2(136, 43), true)
	_button(home_screen, "Цитадель", Vector2(60, 997), Vector2(291, 112), _open_settlement, true)
	_button(home_screen, "Правила", Vector2(369, 997), Vector2(291, 112), _open_help, true)
	_button(home_screen, "Настройки", Vector2(60, 1125), Vector2(600, 112), _open_settings, true)


func _process(delta: float) -> void:
	if is_instance_valid(expeditions) and not expedition_paused:
		var result := expeditions.advance(delta)
		if not result.ok and current_screen == "settlement":
			settlement_status.text = String(result.get("reason", "Не удалось сохранить поход."))
		for delivery: Dictionary in result.get("deliveries", []):
			if current_screen == "settlement":
				settlement_status.text = "Отряд вернулся: %s" % _cost_text({delivery.get("resource", "stone"): delivery.get("amount", 0)})
		colony_ui_clock += delta
		if colony_ui_clock >= 0.5 and current_screen == "settlement":
			colony_ui_clock = 0.0
			_update_settlement()
	# Motion only repositions the original generated backdrop; no artwork is drawn.
	if current_screen != "home" or not is_instance_valid(home_background):
		return
	if bool(store.data.settings.reduced_effects):
		home_background.position = Vector2(-12, -12)
		return
	home_time += minf(delta, 0.1)
	home_background.position = Vector2(-12 + sin(home_time * 0.12) * 5.0, -12 + cos(home_time * 0.1) * 5.0)


func _refresh_home() -> void:
	home_level_number.text = str(active_level)
	home_region_label.text = String(engine.level_data.get("region", "Проклятый лес")).to_upper()
	_set_button_text(home_continue, "Продолжить поход")


func _show_home() -> void:
	if busy:
		home_after_turn = true
		return
	home_after_turn = false
	_clear_hint()
	_reset_pointer()
	selected = Vector2i(-1, -1)
	selection_ring.visible = false
	modal.visible = false
	level_modal.visible = false
	utility_modal.visible = false
	current_screen = "home"
	game_screen.visible = false
	settlement_screen.visible = false
	home_screen.visible = true
	_refresh_home()


func _continue_from_home() -> void:
	if busy:
		return
	current_screen = "game"
	home_screen.visible = false
	settlement_screen.visible = false
	game_screen.visible = true
	_reset_pointer()
	if engine.is_won() or engine.is_lost():
		_show_result(engine.is_won())


func _build_game_screen() -> void:
	game_screen = _new_screen()
	game_screen.visible = false
	game_background = _texture(game_screen, "background", Vector2.ZERO, CANVAS)
	_frame(game_screen, "ui_header", Vector2(24, 12), Vector2(672, 99))
	_label(game_screen, "ПЕПЕЛЬНЫЙ ПРЕДЕЛ", Vector2(60, 21), Vector2(600, 45), 30, GOLD, true)
	level_label = _label(game_screen, "Проклятый лес · разлом", Vector2(100, 67), Vector2(386, 32), 19, IVORY, true)
	level_number = _number(game_screen, "1", Vector2(483, 65), Vector2(148, 36))
	_button(game_screen, "Главная", Vector2(24, 119), Vector2(210, 112), _show_home, true)
	_button(game_screen, "Уровни", Vector2(249, 119), Vector2(210, 112), _open_level_picker, true)
	_button(game_screen, "Правила", Vector2(474, 119), Vector2(222, 112), _open_help, true)
	_frame(game_screen, "ui_panel", Vector2(24, 235), Vector2(440, 148))
	mission_icon = _texture(game_screen, "gem_0", Vector2(50, 262), Vector2(69, 69))
	mission_description = _label(game_screen, "", Vector2(127, 249), Vector2(303, 49), 21, IVORY)
	mission_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objective_number = _number(game_screen, "0", Vector2(127, 300), Vector2(108, 46))
	_label(game_screen, "/", Vector2(237, 303), Vector2(23, 38), 23, MUTED, true)
	target_number = _number(game_screen, "0", Vector2(265, 300), Vector2(168, 46))
	_frame(game_screen, "ui_progress", Vector2(53, 355), Vector2(379, 15)).modulate = Color(0.3, 0.3, 0.35)
	progress_fill = _texture(game_screen, "ui_progress_fill", Vector2(53, 355), Vector2(0, 15))
	_frame(game_screen, "ui_panel", Vector2(478, 235), Vector2(218, 148))
	_label(game_screen, "ХОДЫ", Vector2(494, 252), Vector2(186, 30), 19, MUTED, true)
	moves_label = _number(game_screen, "30", Vector2(506, 286), Vector2(162, 70), true)
	shape_label = _label(game_screen, "", Vector2(38, 384), Vector2(644, 31), 18, IVORY, true)
	cells_layer = Control.new()
	board_contour = BoardContour.new()
	gems_layer = Control.new()
	effects_layer = Control.new()
	for layer: Control in [cells_layer, board_contour, gems_layer, effects_layer]:
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.size = CANVAS
		game_screen.add_child(layer)
	for y in range(9):
		for x in range(9):
			var cell := Vector2i(x, y)
			cell_nodes[cell] = _texture(cells_layer, "cell", Vector2.ZERO, Vector2.ONE)
			cell_nodes[cell].visible = false
			cell_nodes[cell].modulate = Color(0.54, 0.55, 0.62)
			altar_nodes[cell] = _texture(cells_layer, "altar", Vector2.ZERO, Vector2.ONE)
			altar_nodes[cell].visible = false
	for index in range(81):
		var gem := GemView.new()
		gems_layer.add_child(gem)
		gem.visible = false
		gem_pool.append(gem)
	fx_pool = EffectPool.new()
	effects_layer.add_child(fx_pool)
	fx_pool.configure(bool(store.data.settings.reduced_effects))
	selection_ring = _texture(effects_layer, "selection", Vector2.ZERO, Vector2(72, 72))
	selection_ring.visible = false
	_label(game_screen, "ОЧКИ", Vector2(32, 1010), Vector2(79, 31), 16, MUTED)
	score_label = _number(game_screen, "0", Vector2(107, 1007), Vector2(146, 43))
	status_label = _label(game_screen, "", Vector2(273, 1009), Vector2(419, 45), 18, IVORY, true)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	boss_timer_label = _label(game_screen, "", Vector2(30, 1189), Vector2(660, 57), 19, IVORY, true)
	boss_timer_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_button(game_screen, "Подсказка", Vector2(24, 1063), Vector2(207, 112), _show_hint)
	_button(game_screen, "Заново", Vector2(248, 1063), Vector2(207, 112), _retry)
	_button(game_screen, "Цитадель", Vector2(472, 1063), Vector2(224, 112), _open_settlement)


func _build_settlement_screen() -> void:
	settlement_screen = _new_screen()
	settlement_screen.visible = false
	_frame(settlement_screen, "ui_header", Vector2(20, 18), Vector2(680, 108))
	colony_heading = _label(settlement_screen, "ЗЕМЛИ ПЕПЕЛЬНОГО ПРЕДЕЛА", Vector2(40, 40), Vector2(640, 40), 27, GOLD, true)
	colony_queue_label = _label(settlement_screen, "", Vector2(40, 83), Vector2(640, 30), 18, IVORY, true)
	for i in range(3):
		var x := 24.0 + i * 229.0
		_frame(settlement_screen, "ui_panel", Vector2(x, 132), Vector2(214, 96))
		_texture(settlement_screen, ["stone", "wood", "essence"][i], Vector2(x + 10, 148), Vector2(58, 58))
		_label(settlement_screen, ["КАМЕНЬ", "ДРЕВО", "ЭССЕНЦИЯ"][i], Vector2(x + 72, 145), Vector2(132, 24), 13, MUTED)
		resource_labels.append(_number(settlement_screen, "0", Vector2(x + 72, 169), Vector2(132, 48)))
	settlement_grid = MineColony.new()
	settlement_grid.position = Vector2(0, 242)
	settlement_grid.size = Vector2(720, 668)
	settlement_grid.configure(settlement, expeditions)
	settlement_grid.selected.connect(_choose_slot)
	settlement_grid.deposit_selected.connect(_choose_deposit)
	settlement_screen.add_child(settlement_grid)
	_label(settlement_screen, "Перетяните карту · два пальца — масштаб", Vector2(26, 230), Vector2(520, 26), 15, IVORY)
	_button(settlement_screen, "−", Vector2(542, 256), Vector2(72, 72), func(): settlement_grid.set_zoom(settlement_grid.camera_zoom / 1.2), true)
	_button(settlement_screen, "+", Vector2(620, 256), Vector2(72, 72), func(): settlement_grid.set_zoom(settlement_grid.camera_zoom * 1.2), true)
	_button(settlement_screen, "Центр", Vector2(542, 334), Vector2(150, 72), func(): settlement_grid.focus_home(), true)
	_frame(settlement_screen, "ui_panel", Vector2(24, 918), Vector2(672, 180))
	slot_title = _label(settlement_screen, "", Vector2(52, 932), Vector2(616, 36), 24, GOLD)
	slot_detail = _label(settlement_screen, "", Vector2(52, 975), Vector2(616, 112), 17, IVORY)
	slot_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	build_button = _button(settlement_screen, "Отправить", Vector2(24, 1104), Vector2(214, 82), _colony_action)
	upgrade_button = _button(settlement_screen, "Герои", Vector2(253, 1104), Vector2(214, 82), _colony_secondary)
	colony_mode_button = _button(settlement_screen, "В город", Vector2(482, 1104), Vector2(214, 82), _toggle_colony_mode)
	colony_palette_button = _button(settlement_screen, "Постройки", Vector2(24, 1192), Vector2(214, 70), _open_build_palette, true)
	_button(settlement_screen, "Таверна", Vector2(253, 1192), Vector2(214, 70), _open_heroes, true)
	settlement_return_button = _button(settlement_screen, "Главная", Vector2(482, 1192), Vector2(214, 70), _close_settlement, true)
	settlement_status = _label(settlement_screen, "", Vector2(24, 884), Vector2(672, 28), 15, IVORY, true)


func _open_build_palette() -> void:
	if settlement_grid.mode != "city":
		settlement_grid.set_mode("city")
	settlement_grid.interaction_enabled = false
	management.open_build()
	_update_settlement()


func _open_heroes() -> void:
	settlement_grid.interaction_enabled = false
	management.open_heroes()


func _toggle_colony_mode() -> void:
	settlement_grid.set_mode("city" if settlement_grid.mode == "region" else "region")
	_update_settlement()


func _choose_deposit(id: int) -> void:
	selected_deposit = id
	_update_settlement()


func _colony_action() -> void:
	if settlement_grid.mode == "city":
		_build_selected()
	else:
		var result := expeditions.dispatch(selected_deposit)
		settlement_status.text = String(result.get("reason", "Отряд отправлен."))
		_update_settlement()


func _colony_secondary() -> void:
	if settlement_grid.mode == "city":
		_upgrade_selected()
	else:
		_open_heroes()


func _build_result_modal() -> void:
	modal = _new_screen()
	modal.visible = false
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_texture(modal, "background", Vector2.ZERO, CANVAS).modulate = Color(0.2, 0.18, 0.23)
	_frame(modal, "ui_result", Vector2(40, 257), Vector2(640, 749))
	_frame(modal, "ui_badge", Vector2(291, 295), Vector2(138, 138))
	modal_title = _label(modal, "", Vector2(80, 451), Vector2(560, 56), 34, GOLD, true)
	modal_body = _label(modal, "", Vector2(100, 523), Vector2(520, 203), 23, IVORY, true)
	modal_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hero_reward_portrait = _texture(modal, "hero_0", Vector2(548, 646), Vector2(64, 74))
	hero_reward_portrait.visible = false
	modal_action = _button(modal, "", Vector2(130, 735), Vector2(460, 112), _result_continue)
	modal_secondary = _button(modal, "В цитадель", Vector2(130, 853), Vector2(460, 112), _result_settlement)


func _build_level_modal() -> void:
	level_modal = _new_screen()
	level_modal.visible = false
	level_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_texture(level_modal, "background", Vector2.ZERO, CANVAS).modulate = Color(0.2, 0.18, 0.23)
	_frame(level_modal, "ui_result", Vector2(40, 280), Vector2(640, 778))
	_label(level_modal, "ВРАТА ИСПЫТАНИЙ", Vector2(80, 375), Vector2(560, 50), 29, GOLD, true)
	_label(level_modal, "Процедурные разломы разных форм", Vector2(70, 437), Vector2(580, 36), 17, MUTED, true)
	level_choice_label = _number(level_modal, "1", Vector2(205, 505), Vector2(310, 91), true)
	_button(level_modal, "−", Vector2(84, 502), Vector2(112, 112), func(): _change_level_choice(-1), true)
	_button(level_modal, "+", Vector2(524, 502), Vector2(112, 112), func(): _change_level_choice(1), true)
	for i in range(4):
		var jump: int = [-100, 10, 100, 1000][i]
		var caption := "Босс" if jump == 10 else str(jump) if jump < 0 else "+" + str(jump)
		var action := func():
			if jump == 10:
				_jump_to_boss()
			else:
				_change_level_choice(jump)
		_button(level_modal, caption, Vector2(72 + 144 * i, 638), Vector2(138, 112), action, true)
	_button(level_modal, "Войти в разлом", Vector2(130, 769), Vector2(460, 112), _confirm_level_choice)
	_button(level_modal, "Вернуться", Vector2(130, 889), Vector2(460, 112), func(): level_modal.visible = false, true)


func _build_utility_modal() -> void:
	utility_modal = _new_screen()
	utility_modal.visible = false
	utility_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_texture(utility_modal, "background", Vector2.ZERO, CANVAS).modulate = Color(0.18, 0.18, 0.22)
	_frame(utility_modal, "ui_result", Vector2(40, 265), Vector2(640, 796))
	utility_title = _label(utility_modal, "", Vector2(86, 387), Vector2(548, 57), 29, GOLD, true)
	utility_body = _label(utility_modal, "", Vector2(88, 465), Vector2(544, 370), 22, IVORY)
	utility_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reduced_button = _button(utility_modal, "", Vector2(112, 551), Vector2(496, 112), func(): _toggle_setting("reduced_effects"))
	haptics_button = _button(utility_modal, "", Vector2(112, 683), Vector2(496, 112), func(): _toggle_setting("haptics"))
	sound_button = _button(utility_modal, "", Vector2(112, 797), Vector2(496, 74), func(): _toggle_setting("sound"))
	_button(utility_modal, "Вернуться", Vector2(130, 873), Vector2(460, 112), _close_utility)


func _open_settings() -> void:
	_reset_pointer()
	_clear_hint()
	utility_mode = "settings"
	utility_title.text = "НАСТРОЙКИ"
	utility_body.text = "Для слабого телефона включите экономные эффекты."
	utility_body.size.y = 78
	reduced_button.visible = true
	haptics_button.visible = true
	sound_button.visible = true
	_refresh_settings()
	utility_modal.visible = true


func _refresh_settings() -> void:
	_set_button_text(reduced_button, "Эффекты: экономные" if bool(store.data.settings.reduced_effects) else "Эффекты: полные")
	_set_button_text(haptics_button, "Вибрация: включена" if bool(store.data.settings.haptics) else "Вибрация: выключена")
	fx_pool.configure(bool(store.data.settings.reduced_effects))
	_set_button_text(sound_button, "Звук: включён" if bool(store.data.settings.sound) else "Звук: выключен")
	audio.set_enabled(bool(store.data.settings.sound))


func _toggle_setting(key: String) -> void:
	if not store.update_setting(key, not bool(store.data.settings[key])):
		utility_body.text = store.last_error
	else:
		utility_body.text = "Настройка сохранена."
	_refresh_settings()


func _close_utility() -> void:
	utility_modal.visible = false
	_reset_pointer()


func _open_help() -> void:
	_reset_pointer()
	_clear_hint()
	utility_mode = "help"
	utility_title.text = "ПРАВИЛА РАЗЛОМА"
	reduced_button.visible = false
	haptics_button.visible = false
	sound_button.visible = false
	utility_body.size.y = 370
	var state: Dictionary = engine.objective_state()
	var rules := {
		"score": "Наберите нужное число очков за оставшиеся ходы.",
		"collect": "Собирайте кристаллы «%s»: засчитывается только этот цвет." % GEM_NAMES[int(state.get("color", 0))],
		"seals": "Разрушьте все печати. Совпадения рядом с печатью снимают прочность; молнии и взрывы тоже помогают.",
		"altars": "Зажгите все алтари: соберите совпадение на отмеченной клетке.",
		"relic": "Проведите амулеты к выходам со стрелкой. Собирайте кристаллы под реликвией: она падает вниз, не участвует в совпадениях и не уничтожается усилителями.",
		"boss": "Победите хранителя. Его слабость: %s. Каждые три хода он накладывает новые печати своего региона." % GEM_NAMES[int(state.get("color", 0))],
	}
	utility_body.text = String(rules.get(state.get("kind", "score"), rules.score)) + "\n\n3 в ряд — совпадение.\n4 — молния по линии.\nТ или L — взрыв вокруг бомбы.\n5 — звезда очищает цвет.\n\nМеняйте соседние кристаллы свайпом или двумя касаниями."
	utility_modal.visible = true


func _reset_pointer() -> void:
	pointer_down = false
	pointer_touch_id = -1


func _clear_hint() -> void:
	hint_serial += 1
	hint_searching = false
	if hint_tween != null and hint_tween.is_valid():
		hint_tween.kill()
	hint_tween = null
	if is_instance_valid(selection_ring):
		selection_ring.modulate = Color.WHITE


func _vibrate(duration: int) -> void:
	if bool(store.data.settings.haptics):
		Input.vibrate_handheld(duration)


func _load_level(number: int) -> void:
	_cancel_animations()
	home_after_turn = false
	active_level = clampi(number, 1, ProgressStore.MAX_LEVEL)
	engine = MatchEngine.new()
	entry_bonuses = settlement.battle_bonuses()
	engine.initialize(active_level, entry_bonuses)
	selected = Vector2i(-1, -1)
	reward_banked = false
	last_rewards.clear()
	modal.visible = false
	level_modal.visible = false
	utility_modal.visible = false
	selection_ring.visible = false
	busy = false
	var width := int(engine.level_data.get("width", 8))
	var height := int(engine.level_data.get("height", 8))
	tile_size = minf(minf(620.0 / width, 564.0 / height), 78.0)
	board_size = Vector2(width, height) * tile_size
	board_origin = Vector2((720.0 - board_size.x) / 2.0, 428.0 + (568.0 - board_size.y) / 2.0)
	board_contour.configure(engine.cells.keys(), board_origin, tile_size)
	for cell: Vector2i in cell_nodes:
		cell_nodes[cell].visible = engine.cells.has(cell)
		cell_nodes[cell].position = _cell_origin(cell)
		cell_nodes[cell].size = Vector2.ONE * tile_size
	tile_nodes.clear()
	var index := 0
	for gem in gem_pool:
		gem.visible = false
	for cell: Vector2i in engine.cells:
		tile_nodes[cell] = gem_pool[index]
		index += 1
	tile_snapshot.clear()
	_render_board(engine.cells, engine.blockers, false, engine.altars)
	_update_hud()
	status_label.text = "Проведите по кристаллу для обмена."
	var bonuses := entry_bonuses
	if int(bonuses.bonus_moves) > 0 or int(bonuses.starting_specials) > 0:
		status_label.text = "Цитадель: +%d ходов, %d бонусов." % [int(bonuses.bonus_moves), int(bonuses.starting_specials)]
	var shape := String(engine.level_data.get("shape", "Разлом"))
	shape_label.text = _shape_name(shape)
	if engine.level_data.objective.kind == "boss":
		shape_label.text = "%s · %s" % [String(engine.level_data.boss.name), _shape_name(shape)]
	level_label.text = "%s · разлом" % String(engine.level_data.get("region", "Проклятый лес"))
	game_background.texture = Art.texture(["forest_background", "ice_background", "lava_background"][int(engine.level_data.region_index)])
	level_number.text = str(active_level)


func _shape_name(shape: String) -> String:
	var names := {"citadel": "Двор цитадели", "rectangle": "Каменный двор", "diamond": "Сердце разлома", "cross": "Крест стихий", "ring": "Кольцо пепла", "hourglass": "Песочные врата", "wings": "Крылья ночи", "heart": "Сердце титана", "rune": "Древняя руна", "hexagon": "Шестигранный алтарь", "stairs": "Ступени бездны", "arch": "Свод руин", "islands": "Острова осколков", "skull": "Череп титана", "chalice": "Чаша теней"}
	return String(names.get(shape, shape.capitalize()))


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func _cell_origin(cell: Vector2i) -> Vector2:
	return board_origin + Vector2(cell) * tile_size


func _cell_center(cell: Vector2i) -> Vector2:
	return _cell_origin(cell) + Vector2.ONE * tile_size * 0.5


func _render_board(board: Dictionary, blockers: Dictionary, falling: bool = false, altars: Dictionary = {}) -> void:
	var old_snapshot := tile_snapshot.duplicate(true)
	var available: Array = old_snapshot.keys()
	available.sort_custom(func(a: Vector2i, b: Vector2i): return a.y > b.y)
	tile_snapshot = board.duplicate(true)
	var order: Array = board.keys()
	order.sort_custom(func(a: Vector2i, b: Vector2i): return a.y > b.y)
	for cell: Vector2i in order:
		var data: Dictionary = board[cell]
		var node: GemView = tile_nodes[cell]
		var altar = altars.get(cell, null)
		var seal: Variant = blockers.get(cell, null)
		if seal != null and int(engine.level_data.region_index) > 0:
			seal = {"hp": int(seal), "kind": "frost" if int(engine.level_data.region_index) == 1 else "lava"}
		node.configure(data, seal, tile_size, null, cell in engine.level_data.get("relic_exits", []))
		if altar != null:
			node.gem_sprite.position = Vector2.ONE * tile_size * 0.125
			node.gem_sprite.size = Vector2.ONE * tile_size * 0.75
		node.position = _cell_origin(cell)
		if falling:
			var segment_top := cell.y
			while board.has(Vector2i(cell.x, segment_top - 1)) and not blockers.has(Vector2i(cell.x, segment_top - 1)):
				segment_top -= 1
			var source := cell if blockers.has(cell) else Vector2i(cell.x, segment_top - 1)
			for candidate: Vector2i in available:
				if candidate.x == cell.x and candidate.y <= cell.y and old_snapshot[candidate] == data and _same_gravity_segment(candidate, cell, board, blockers):
					source = candidate
					available.erase(candidate)
					break
			if source != cell:
				node.position = _cell_origin(source)
				var tween := _tween()
				tween.tween_property(node, "position", _cell_origin(cell), 0.18 + (cell.y - source.y) * 0.02).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	for cell: Vector2i in altar_nodes:
		var fixed_altar: TextureRect = altar_nodes[cell]
		fixed_altar.visible = altars.has(cell)
		if fixed_altar.visible:
			fixed_altar.position = _cell_origin(cell) + Vector2.ONE * tile_size * 0.025
			fixed_altar.size = Vector2.ONE * tile_size * 0.95
			fixed_altar.texture = Art.texture("altar_lit" if bool(altars[cell]) else "altar")


func _same_gravity_segment(a: Vector2i, b: Vector2i, board: Dictionary, blockers: Dictionary) -> bool:
	if a == b:
		return true
	for row in range(a.y, b.y + 1):
		var cell := Vector2i(a.x, row)
		if not board.has(cell) or blockers.has(cell):
			return false
	return true


func _update_hud(state: Dictionary = {}) -> void:
	if state.is_empty():
		state = engine.objective_state()
	score_label.text = str(engine.score)
	moves_label.text = str(engine.moves)
	moves_label.modulate = Color("ed998b") if engine.moves <= 5 else Color.WHITE
	var kind := String(state.get("kind", "score"))
	var current := int(state.get("current", 0))
	var target := int(state.get("target", 1))
	var titles := {"score": "Наберите очки", "collect": "Соберите: %s" % GEM_NAMES[int(state.get("color", 0))], "seals": "Разрушьте печати", "altars": "Зажгите алтари", "relic": "Проведите реликвии", "boss": "Здоровье хранителя"}
	mission_description.text = String(titles.get(kind, titles.score))
	var icon_key := "gem_%d" % int(state.get("color", 0))
	if kind == "score":
		icon_key = "coin"
	elif kind == "seals":
		icon_key = "blocker_ice"
	elif kind == "altars":
		icon_key = "altar_lit"
	elif kind == "relic":
		icon_key = "relic"
	elif kind == "boss":
		icon_key = ["boss_portrait", "boss_ice", "boss_lava"][int(engine.level_data.region_index)]
		current = int(state.get("boss_hp", 0))
		target = int(state.get("boss_max_hp", 1))
	mission_icon.texture = Art.texture(icon_key)
	objective_number.text = str(current)
	target_number.text = str(target)
	var progress := float(current) / maxi(1, target)
	if kind == "boss":
		progress = 1.0 - progress
	progress_fill.size.x = 379.0 * clampf(progress, 0.0, 1.0)
	if kind == "boss":
		boss_timer_label.text = "Слабость: %s · атака через %d ход(а)" % [GEM_NAMES[int(state.get("color", 0))], int(state.get("attack_in", 3))]
	else:
		boss_timer_label.text = "3 — совпадение · 4 — молния · Т/L — бомба · 5 — звезда"


func _input(event: InputEvent) -> void:
	if busy or current_screen != "game" or modal.visible or level_modal.visible or utility_modal.visible:
		return
	var position_value := Vector2.ZERO
	var pressed := false
	var released := false
	if event is InputEventScreenTouch:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		if pointer_down and event.pressed and pointer_touch_id != event.index:
			return
		if not event.pressed and pointer_touch_id != event.index:
			return
		position_value = event.position
		pressed = event.pressed
		released = not event.pressed
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		if pointer_down and pointer_touch_id >= 0:
			return
		position_value = event.position
		pressed = event.pressed
		released = not event.pressed
	else:
		return
	# Transform window input into the portrait canvas for scaled and letterboxed windows.
	position_value = get_global_transform_with_canvas().affine_inverse() * position_value
	if pressed:
		pointer_cell = _point_to_cell(position_value)
		pointer_down = engine.cells.has(pointer_cell)
		pointer_start = position_value
		pointer_touch_id = event.index if event is InputEventScreenTouch and pointer_down else -1
	elif released and pointer_down:
		pointer_down = false
		pointer_touch_id = -1
		var delta := position_value - pointer_start
		if delta.length() > tile_size * 0.28:
			var direction := Vector2i(signi(int(delta.x)), 0) if absf(delta.x) > absf(delta.y) else Vector2i(0, signi(int(delta.y)))
			_attempt_swap(pointer_cell, pointer_cell + direction)
		else:
			_select_tile(pointer_cell)


func _point_to_cell(point: Vector2) -> Vector2i:
	var offset := (point - board_origin) / tile_size
	return Vector2i(floori(offset.x), floori(offset.y))


func _select_tile(cell: Vector2i) -> void:
	_clear_hint()
	if not engine.cells.has(cell):
		return
	if engine.cells.has(selected) and abs(cell.x - selected.x) + abs(cell.y - selected.y) == 1:
		_attempt_swap(selected, cell)
		return
	selected = cell
	selection_ring.position = _cell_origin(cell) - Vector2.ONE * tile_size * 0.045
	selection_ring.size = Vector2.ONE * tile_size * 1.09
	selection_ring.visible = true
	selection_ring.modulate = Color.WHITE


func _tween() -> Tween:
	var tween := create_tween()
	running_tweens.append(tween)
	tween.finished.connect(func(): running_tweens.erase(tween), CONNECT_ONE_SHOT)
	return tween


func _cancel_animations() -> void:
	_clear_hint()
	turn_generation += 1
	for tween in running_tweens:
		if tween.is_valid():
			tween.kill()
	running_tweens.clear()
	if is_instance_valid(fx_pool):
		fx_pool.clear()
	pointer_down = false
	pointer_touch_id = -1


func _attempt_swap(a: Vector2i, b: Vector2i) -> void:
	if busy or not engine.cells.has(a) or not engine.cells.has(b):
		return
	busy = true
	_clear_hint()
	selected = Vector2i(-1, -1)
	selection_ring.visible = false
	var generation := turn_generation
	var result: Dictionary = engine.try_swap(a, b)
	if tile_nodes.has(a) and tile_nodes.has(b):
		var first: Control = tile_nodes[a]
		var second: Control = tile_nodes[b]
		var tween := _tween().set_parallel()
		tween.tween_property(first, "position", _cell_origin(b), 0.17).set_trans(Tween.TRANS_QUAD)
		tween.tween_property(second, "position", _cell_origin(a), 0.17).set_trans(Tween.TRANS_QUAD)
		await tween.finished
		if generation != turn_generation:
			return
		if bool(result.get("valid", false)):
			tile_nodes[a] = second
			tile_nodes[b] = first
			var temporary = tile_snapshot[a]
			tile_snapshot[a] = tile_snapshot[b]
			tile_snapshot[b] = temporary
		else:
			var reverse := _tween().set_parallel()
			reverse.tween_property(first, "position", _cell_origin(a), 0.17)
			reverse.tween_property(second, "position", _cell_origin(b), 0.17)
			await reverse.finished
	if generation != turn_generation:
		return
	if not bool(result.get("valid", false)):
		status_label.text = "Этот обмен не создаёт совпадение. Попробуйте другой."
		busy = false
		if home_after_turn:
			_show_home()
		return
	_vibrate(25)
	audio.play("match")
	for step: Dictionary in result.get("steps", []):
		if generation != turn_generation:
			return
		_animate_step(step)
		await get_tree().create_timer(0.31).timeout
		if generation != turn_generation:
			return
		_render_board(step.get("board", engine.cells), step.get("blockers", engine.blockers), true, step.get("altars", engine.altars))
		_update_hud(step.get("objective", {}))
		score_label.text = str(step.get("score", engine.score))
		var combo := int(step.get("combo", 1))
		if not step.get("boss_attack", []).is_empty():
			status_label.text = "Хранитель наложил новые печати!"
		elif int(step.get("boss_damage", 0)) > 0:
			status_label.text = "Хранитель: −%d здоровья" % int(step.boss_damage)
		else:
			status_label.text = "Каскад ×%d" % combo if combo > 1 else "Совпадение!"
		await get_tree().create_timer(0.47).timeout
	if generation != turn_generation:
		return
	_render_board(engine.cells, engine.blockers, false, engine.altars)
	_update_hud()
	busy = false
	if bool(result.get("won", false)) or bool(result.get("lost", false)):
		_show_result(bool(result.get("won", false)))
	elif engine.legal_moves().is_empty():
		status_label.text = "Разлом изменился — ищите новое сочетание."
	if home_after_turn:
		if modal.visible and store.last_award_status == "save_failed":
			home_after_turn = false
		else:
			_show_home()


func _animate_step(step: Dictionary) -> void:
	if int(step.get("combo", 1)) > 1:
		audio.play("cascade")
	for activation in step.get("activated", []):
		var position_value: Vector2i = activation.get("position", Vector2i.ZERO)
		var special := String(activation.get("special", "bomb"))
		audio.play("lightning" if special in ["row", "column"] else "explosion")
		if special == "row":
			_spawn_fx("fx_lightning", Vector2(board_origin.x + board_size.x / 2, _cell_center(position_value).y), Vector2(board_size.x + 80, tile_size * 1.3))
		elif special == "column":
			_spawn_fx("fx_lightning", Vector2(_cell_center(position_value).x, board_origin.y + board_size.y / 2), Vector2(board_size.y + 80, tile_size * 1.3), PI * 0.5)
		else:
			_spawn_fx("fx_explosion", _cell_center(position_value), Vector2.ONE * tile_size * (4.4 if special == "nova" else 3.0))
		_vibrate(45)
	for hit in step.get("blocker_hits", []):
		var position_value: Vector2i = hit if hit is Vector2i else hit.get("position", Vector2i.ZERO)
		_spawn_fx("fx_frost", _cell_center(position_value), Vector2.ONE * tile_size * 1.8)
	var index := 0
	var frequency := 3 if bool(store.data.settings.reduced_effects) else 1
	var removed_colors: Dictionary = {}
	for entry in step.get("removed_details", []):
		removed_colors[entry.position] = int(entry.color)
	for position_value: Vector2i in step.get("removed", []):
		if index % frequency == 0:
			_spawn_fx("fx_shards_%d" % int(removed_colors.get(position_value, 0)), _cell_center(position_value), Vector2(tile_size * 1.7, tile_size * 0.76))
		index += 1
		if tile_nodes.has(position_value):
			var node: Control = tile_nodes[position_value]
			var tween := _tween().set_parallel()
			tween.tween_property(node, "scale", Vector2.ONE * 0.15, 0.23).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
			tween.tween_property(node, "modulate:a", 0.0, 0.23)
			tile_snapshot.erase(position_value)
	for special in step.get("spawned", []):
		_spawn_fx("fx_frost", _cell_center(special.get("position", Vector2i.ZERO)), Vector2.ONE * tile_size * 1.7)
	for attack: Vector2i in step.get("boss_attack", []):
		_spawn_fx("fx_frost", _cell_center(attack), Vector2.ONE * tile_size * 1.8)


func _spawn_fx(prefix: String, center: Vector2, dimensions: Vector2, angle: float = 0.0) -> void:
	fx_pool.play(prefix, center, dimensions, angle)


func _show_hint() -> void:
	if busy or hint_searching:
		return
	_clear_hint()
	var serial := hint_serial
	hint_searching = true
	var moves: Array = engine.legal_moves()
	if moves.is_empty():
		hint_searching = false
		status_label.text = "Нет ходов. Начните ритуал заново."
		return
	status_label.text = "Ищу ход для цели разлома…"
	var state: Dictionary = engine.objective_state()
	var weak := int(state.get("color", 0))
	if String(state.kind) in ["collect", "boss"]:
		moves.sort_custom(func(first, second):
			var left := int(engine.cells[first[0]].color == weak) + int(engine.cells[first[1]].color == weak)
			var right := int(engine.cells[second[0]].color == weak) + int(engine.cells[second[1]].color == weak)
			return left > right)
	var best_move = moves[0]
	var best_metric := -INF
	# A bounded one-turn lookahead yields each frame; cancellation never mutates play.
	for index in range(mini(12, moves.size())):
		if serial != hint_serial or busy or current_screen != "game":
			return
		var simulation := engine.clone_model()
		var result: Dictionary = simulation.try_swap(moves[index][0], moves[index][1])
		var after: Dictionary = simulation.objective_state()
		var metric: float = float(int(after.current) - int(state.current)) * 10000.0 + simulation.score - engine.score
		if state.kind == "relic":
			for position: Vector2i in simulation.cells:
				if bool(simulation.cells[position].get("relic", false)):
					metric += position.y * 200.0
		metric -= maxi(0, simulation.blockers.size() - engine.blockers.size()) * 300.0
		if bool(result.get("won", false)):
			metric += 1000000.0
		if metric > best_metric:
			best_metric = metric
			best_move = moves[index]
		await get_tree().process_frame
	if serial != hint_serial or busy:
		return
	hint_searching = false
	var a: Vector2i = best_move[0]
	var b: Vector2i = best_move[1]
	_select_tile(a)
	var direction := "вправо" if b.x > a.x else "влево" if b.x < a.x else "вниз" if b.y > a.y else "вверх"
	status_label.text = "Для цели: сдвиньте выделенный кристалл %s." % direction
	hint_tween = _tween().set_loops(3)
	hint_tween.tween_property(selection_ring, "modulate:a", 0.4, 0.30)
	hint_tween.tween_property(selection_ring, "modulate:a", 1.0, 0.30)


func _retry() -> void:
	if busy:
		return
	_load_level(active_level)


func _show_result(won: bool) -> void:
	end_won = won
	if won and not reward_banked:
		audio.play("victory")
	if not reward_banked:
		last_rewards = store.award_level(active_level, engine.score, won, engine.collected, entry_bonuses)
		reward_banked = store.last_award_status != "save_failed"
	var save_failed := store.last_award_status == "save_failed"
	modal_title.text = "ХРОНИКА НЕ ЗАПИСАНА" if save_failed else "РИТУАЛ ЗАВЕРШЁН" if won else "СИЛА ИССЯКЛА"
	var body := _reward_text(last_rewards) if won or save_failed else "Ходы закончились. Лучший результат сохранён."
	if not store.last_hero_reward.is_empty() and won and not save_failed:
		body += "\nКарта героя: %s +1" % store.last_hero_reward.get("name", store.last_hero_reward.get("hero_id", ""))
	hero_reward_portrait.visible = not store.last_hero_reward.is_empty() and won and not save_failed
	if hero_reward_portrait.visible:
		hero_reward_portrait.texture = Art.texture(String(store.last_hero_reward.get("portrait", "hero_0")))
	modal_body.text = "Уровень %d\n%d очков\n\n%s" % [active_level, engine.score, body]
	_set_button_text(modal_action, "Повторить сохранение" if save_failed else "Следующий разлом" if won else "Попробовать ещё")
	modal_secondary.disabled = save_failed
	modal_secondary.modulate = Color(0.5, 0.5, 0.5) if save_failed else Color.WHITE
	modal.visible = true


func _reward_text(rewards: Dictionary) -> String:
	match store.last_award_status:
		"save_failed":
			return "Результат и награда не сохранены.\n" + store.last_error
		"locked":
			return "Тренировочный разлом. Для награды завершите уровень %d." % int(store.data.level)
		"replay":
			return "Лучший результат сохранён. Награда уже получена."
		"invalid":
			return "Этот разлом находится за пределами похода."
	if rewards.has("resources"):
		rewards = rewards.resources
	return "В цитадель: %d камня · %d древа\n%d эссенции" % [int(rewards.get("stone", 0)), int(rewards.get("wood", 0)), int(rewards.get("essence", 0))]


func _set_button_text(button: TextureButton, value: String) -> void:
	for child in button.get_children():
		if child is Label:
			child.text = value
			return


func _result_continue() -> void:
	if store.last_award_status == "save_failed":
		_show_result(end_won)
		if store.last_award_status == "save_failed":
			return
	_load_level(mini(ProgressStore.MAX_LEVEL, active_level + 1) if end_won else active_level)


func _result_settlement() -> void:
	if store.last_award_status == "save_failed":
		return
	modal.visible = false
	if end_won:
		_load_level(mini(ProgressStore.MAX_LEVEL, active_level + 1))
	_open_settlement()


func _open_level_picker() -> void:
	if busy:
		return
	_clear_hint()
	_reset_pointer()
	choosing_level = active_level
	level_choice_label.text = str(choosing_level)
	level_modal.visible = true


func _change_level_choice(delta: int) -> void:
	choosing_level = clampi(choosing_level + delta, 1, ProgressStore.MAX_LEVEL)
	level_choice_label.text = str(choosing_level)


func _jump_to_boss() -> void:
	choosing_level = mini(ProgressStore.MAX_LEVEL, (choosing_level / 10 as int) * 10 + 10)
	level_choice_label.text = str(choosing_level)


func _confirm_level_choice() -> void:
	_load_level(choosing_level)


func _open_settlement() -> void:
	if busy:
		return
	_clear_hint()
	_reset_pointer()
	selected = Vector2i(-1, -1)
	selection_ring.visible = false
	settlement_origin = current_screen
	current_screen = "settlement"
	home_screen.visible = false
	game_screen.visible = false
	settlement_screen.visible = true
	expeditions.sync_elapsed()
	settlement_grid.set_mode("region")
	_set_button_text(settlement_return_button, "Главная" if settlement_origin == "home" else "К кристаллам")
	_update_settlement()


func _close_settlement() -> void:
	expeditions.checkpoint()
	management.close_panel()
	settlement_grid.cancel_gestures()
	if settlement_origin == "home":
		_show_home()
	else:
		_continue_from_home()


func _update_settlement() -> void:
	if not is_instance_valid(settlement_grid):
		return
	for i in range(3):
		resource_labels[i].text = str(store.data.resources.get(["stone", "wood", "essence"][i], 0))
	settlement_grid.refresh(store.data, selected_slot)
	var queue := expeditions.queue_status()
	colony_heading.text = "ГОРОД ПЕПЕЛЬНОГО ПРЕДЕЛА" if settlement_grid.mode == "city" else "ЗЕМЛИ ПЕПЕЛЬНОГО ПРЕДЕЛА"
	colony_queue_label.text = "30 × 30 · отряды %d/%d · замок и ратуша открывают очереди" % [queue.busy, queue.capacity]
	_set_button_text(colony_mode_button, "Карта" if settlement_grid.mode == "city" else "В город")
	colony_palette_button.visible = settlement_grid.mode == "city"
	if settlement_grid.mode == "region":
		_set_button_text(build_button, "Отправить")
		_set_button_text(upgrade_button, "Герои")
		upgrade_button.disabled = false
		upgrade_button.modulate = Color.WHITE
		var deposit := expeditions.get_deposit(selected_deposit)
		build_button.disabled = deposit.is_empty() or not bool(deposit.get("active", false)) or queue.free <= 0
		build_button.modulate = Color(0.5, 0.5, 0.5) if build_button.disabled else Color.WHITE
		var names := {"stone": "Рудник камня", "wood": "Лесная делянка", "essence": "Залежь эссенции"}
		slot_title.text = names.get(deposit.get("resource", ""), "Выберите месторождение")
		var hero_id := String(store.data.selected_hero)
		var hero_name := hero_id
		for hero: Dictionary in heroes.catalog():
			if hero.id == hero_id:
				hero_name = hero.name
		var details := "Герой: %s · свободных очередей: %d\n" % [hero_name, queue.free]
		if not deposit.is_empty():
			details += "Запас: %d · навык добычи: +%d%%\n" % [deposit.remaining, heroes.yield_bonus(hero_id, String(deposit.resource))]
		else:
			details += "Отряды выходят из замка и возвращают груз на склад.\n"
		var jobs: Array[String] = []
		for job: Dictionary in expeditions.jobs():
			var leader := String(job.hero_id)
			for hero: Dictionary in heroes.catalog():
				if hero.id == leader:
					leader = hero.name
			jobs.append("%s: %s (%d с)" % [leader, {"outbound": "идёт", "mining": "добывает", "returning": "возвращается", "delivery_retry": "ждёт склад"}.get(job.phase, "поход"), expeditions.job_eta(job)])
		slot_detail.text = details + (" · ".join(jobs) if not jobs.is_empty() else "Карточки героев: уровни матч-3 и сундуки таверны.")
		return
	_set_button_text(build_button, "Возвести этап" if selected_slot == -1 else "Построить")
	_set_button_text(upgrade_button, "Улучшить")
	if selected_slot == -1:
		var stage := int(store.data.bunker_level)
		slot_title.text = "Бункер · %s" % SettlementModel.BUNKER_STAGES[stage]
		var cost := settlement.bunker_cost()
		slot_detail.text = "Следующий этап: %s\nЦена: %s" % [SettlementModel.BUNKER_STAGES[mini(3, stage + 1)], _cost_text(cost)] if stage < 3 else "Бункер завершён. +2 эссенции за первое прохождение (предел +4)."
		build_button.disabled = cost.is_empty()
		upgrade_button.disabled = true
	else:
		var kind := int(store.data.buildings[selected_slot])
		var tier := int(store.data.upgrades[selected_slot])
		build_button.disabled = kind >= 0
		upgrade_button.disabled = kind < 0 or tier >= SettlementModel.MAX_UPGRADE
		if kind < 0:
			slot_title.text = "Участок %d · %s" % [selected_slot + 1, BUILDING_NAMES[selected_kind]]
			slot_detail.text = "Цена: %s\n%s\n«Постройки» — выбрать другое здание." % [_cost_text(settlement.get_build_cost(selected_kind)), settlement.get_building_description(selected_kind)]
		else:
			slot_title.text = "%s · уровень %d" % [BUILDING_NAMES[kind], tier + 1]
			var cost := "Максимальный уровень" if tier >= SettlementModel.MAX_UPGRADE else "Улучшение: %s" % _cost_text(settlement.get_upgrade_cost(selected_slot))
			slot_detail.text = "%s\n%s" % [cost, settlement.get_building_description(kind)]
	build_button.modulate = Color(0.5, 0.5, 0.5) if build_button.disabled else Color.WHITE
	upgrade_button.modulate = Color(0.5, 0.5, 0.5) if upgrade_button.disabled else Color.WHITE


func _texture_hit_mask(key: String) -> BitMap:
	# Hit areas follow generated PNG transparency; this never draws visual artwork.
	if texture_hit_masks.has(key):
		return texture_hit_masks[key]
	var texture := Art.texture(key)
	var image_data := texture.get_image() if texture != null else null
	if image_data == null:
		return null
	var bitmap := BitMap.new()
	bitmap.create_from_image_alpha(image_data, 0.2)
	texture_hit_masks[key] = bitmap
	return bitmap


func _cost_text(cost) -> String:
	if not cost is Dictionary:
		return str(cost)
	var parts: Array[String] = []
	for key in ["stone", "wood", "essence"]:
		var amount := int(cost.get(key, 0))
		if amount > 0:
			parts.append("%d %s" % [amount, {"stone": "камня", "wood": "древа", "essence": "эссенции"}[key]])
	return " · ".join(parts) if not parts.is_empty() else "бесплатно"


func _choose_slot(slot: int) -> void:
	if slot == -2:
		slot = 3
	settlement_grid.set_mode("city")
	selected_slot = slot
	_update_settlement()


func _choose_kind(kind: int) -> void:
	if selected_slot < 0:
		selected_slot = 4
	selected_kind = kind
	settlement_grid.set_mode("city")
	_update_settlement()


func _operation_ok(result) -> bool:
	if result is Dictionary:
		return bool(result.get("ok", result.get("success", false)))
	return bool(result)


func _build_selected() -> void:
	var result = settlement.build_bunker() if selected_slot == -1 else settlement.build(selected_slot, selected_kind)
	settlement_status.text = "%s: строительство сохранено." % ("Бункер" if selected_slot == -1 else BUILDING_NAMES[selected_kind]) if _operation_ok(result) else _operation_error(result)
	_update_settlement()


func _upgrade_selected() -> void:
	var result = settlement.upgrade(selected_slot)
	settlement_status.text = "Постройка улучшена. Бонусы со следующей попытки." if _operation_ok(result) else _operation_error(result)
	_update_settlement()


func _operation_error(result) -> String:
	if result is Dictionary:
		return String(result.get("reason", result.get("error", result.get("message", "Не хватает ресурсов. Победите в разломе."))))
	return "Не хватает ресурсов. Победите в разломе."


func _mine() -> void:
	settlement_grid.dispatch()
	settlement_status.text = "Рабочие несут добычу на склад. Ресурсы зачисляются после доставки."
	_update_settlement()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED and is_instance_valid(audio):
		audio.set_paused(false)
		expedition_paused = false
		if is_instance_valid(expeditions):
			expeditions.sync_elapsed()
	if what == NOTIFICATION_APPLICATION_PAUSED:
		expedition_paused = true
		if is_instance_valid(expeditions):
			expeditions.checkpoint()
		if is_instance_valid(settlement_grid):
			settlement_grid.cancel_gestures()
		if is_instance_valid(audio):
			audio.set_paused(true)
		_reset_pointer()
		_clear_hint()
		return
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if is_instance_valid(management) and management.visible:
			management.close_panel()
		elif is_instance_valid(utility_modal) and utility_modal.visible:
			_close_utility()
		elif is_instance_valid(level_modal) and level_modal.visible:
			level_modal.visible = false
		elif is_instance_valid(modal) and modal.visible:
			if store.last_award_status == "save_failed":
				return
			_result_continue()
		elif current_screen == "settlement":
			_close_settlement()
		elif current_screen == "game":
			_show_home()
		elif current_screen == "home":
			get_tree().quit()


func _smoke() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not _smoke_frames():
		get_tree().quit(1)
		return
	var preview_dir := ProjectSettings.globalize_path("res://art/preview")
	DirAccess.make_dir_recursive_absolute(preview_dir)
	if not await _smoke_home_navigation(preview_dir):
		get_tree().quit(1)
		return
	await _capture_preview(preview_dir.path_join("gameplay.png"))
	var contour_generation := board_contour.rebuild_count
	var contour_nodes := board_contour.get_children().map(func(node: Node): return node.get_instance_id())
	var legal: Array = engine.legal_moves()
	if not legal.is_empty():
		var move = legal[0]
		var a: Vector2i
		var b: Vector2i
		if move is Dictionary:
			a = move.get("a", move.get("from", Vector2i.ZERO))
			b = move.get("b", move.get("to", Vector2i.RIGHT))
		else:
			a = move[0]
			b = move[1]
		var previous_moves := engine.moves
		await _smoke_tap(a)
		if selected != a:
			push_error("UI_SMOKE_TAP_FAILED: selection does not map to crystal")
			get_tree().quit(1)
			return
		await _smoke_tap(b)
		var deadline := Time.get_ticks_msec() + 10000
		while busy and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		if busy or engine.moves != previous_moves - 1:
			push_error("UI_SMOKE_INPUT_SWAP_FAILED")
			get_tree().quit(1)
			return
		print("UI_SMOKE_MOVE_OK score=", engine.score, " moves=", engine.moves)
		legal = engine.legal_moves()
		if not legal.is_empty():
			move = legal[0]
			a = move[0]
			b = move[1]
			previous_moves = engine.moves
			await _smoke_swipe(a, b)
			deadline = Time.get_ticks_msec() + 10000
			while busy and Time.get_ticks_msec() < deadline:
				await get_tree().process_frame
			if busy or engine.moves != previous_moves - 1:
				push_error("UI_SMOKE_TOUCH_SWIPE_FAILED")
				get_tree().quit(1)
				return
			print("UI_SMOKE_TOUCH_OK score=", engine.score, " moves=", engine.moves)
	if board_contour.rebuild_count != contour_generation or board_contour.get_children().map(func(node: Node): return node.get_instance_id()) != contour_nodes:
		push_error("UI_SMOKE_CONTOUR_REBUILT_DURING_TURN")
		get_tree().quit(1)
		return
	print("UI_SMOKE_CONTOUR_OK edges=", board_contour.topology.edges.size(), " stable_during_turns=true")
	if DisplayServer.get_name() != "headless":
		Engine.time_scale = 0.1
		_spawn_fx("fx_lightning", board_origin + board_size * 0.5, Vector2(board_size.x + 80, tile_size * 1.8))
		_spawn_fx("fx_explosion", board_origin + board_size * Vector2(0.35, 0.65), Vector2.ONE * tile_size * 3.2)
		_spawn_fx("fx_frost", board_origin + board_size * Vector2(0.72, 0.35), Vector2.ONE * tile_size * 2.2)
		await _capture_preview(preview_dir.path_join("effects.png"))
		Engine.time_scale = 1.0
		await get_tree().create_timer(0.5).timeout
		_show_result(false)
		await _capture_preview(preview_dir.path_join("result.png"))
		modal.visible = false
	_open_settlement()
	_build_selected()
	if int(store.data.buildings[selected_slot]) != selected_kind:
		push_error("UI_SMOKE_BUILD_FAILED: " + settlement_status.text)
		get_tree().quit(1)
		return
	store.data.last_mine_time = int(Time.get_unix_time_from_system()) - 120
	_mine()
	print("UI_SMOKE_SETTLEMENT_OK resources=", store.data.resources)
	await _capture_preview(preview_dir.path_join("settlement.png"))
	_close_settlement()
	if not _smoke_save_failure():
		get_tree().quit(1)
		return
	_load_level(1000)
	print("UI_SMOKE_LEVEL_1000_OK cells=", engine.cells.size(), " shape=", engine.level_data.get("shape", ""))
	await _capture_preview(preview_dir.path_join("level1000.png"))
	if not await _smoke_objectives_and_pools(preview_dir):
		get_tree().quit(1)
		return
	if not await _smoke_city_and_sound(preview_dir):
		get_tree().quit(1)
		return
	print("UI_SMOKE_OK")
	get_tree().quit()


func _smoke_frames() -> bool:
	var pending: Array[Node] = [self]
	var frames := 0
	var frame_buttons := 0
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		for child in node.get_children():
			pending.append(child)
		if node is GeneratedFrame:
			frames += 1
			var spec: Dictionary = Art.frame_spec(node.frame_key)
			if node.texture != spec.texture or not node.displayed_border_widths().is_equal_approx(spec.margins * float(spec.scale)):
				push_error("UI_SMOKE_FRAME_CORNERS_CHANGED")
				return false
		if node is TextureButton and node.has_node("GeneratedButtonFrame"):
			frame_buttons += 1
			var frame: GeneratedFrame = node.get_node("GeneratedButtonFrame")
			if node.texture_normal != null or frame.mouse_filter != Control.MOUSE_FILTER_IGNORE or not (frame.size * frame.scale).is_equal_approx(node.size):
				push_error("UI_SMOKE_STRETCHED_BUTTON_FRAME")
				return false
	if frames < 14 or frame_buttons < 20:
		push_error("UI_SMOKE_FRAME_COVERAGE_FAILED")
		return false
	print("UI_SMOKE_FRAMES_OK frames=", frames, " buttons=", frame_buttons, " fixed_corners=true")
	return true


func _smoke_city_and_sound(preview_dir: String) -> bool:
	_notification(NOTIFICATION_APPLICATION_RESUMED)
	_open_settings()
	var sound_before := bool(store.data.settings.sound)
	await _smoke_press_control(sound_button)
	if bool(store.data.settings.sound) == sound_before or audio.enabled != bool(store.data.settings.sound):
		push_error("UI_SMOKE_SOUND_TOUCH_FAILED")
		return false
	await _smoke_press_control(sound_button)
	_close_utility()
	_open_settlement()
	var before_data := store.data.duplicate(true)
	var before_bonuses := entry_bonuses.duplicate(true)
	store.data.resources = {"stone": 100000, "wood": 100000, "essence": 100000}
	await _smoke_touch_control(colony_mode_button)
	if settlement_grid.mode != "city":
		push_error("UI_SMOKE_CITY_MODE_FAILED")
		return false
	var camera_before := settlement_grid.camera_offset
	var selection_before := selected_slot
	await _smoke_colony_drag(Vector2(230, 320), Vector2(330, 370))
	if settlement_grid.camera_offset.is_equal_approx(camera_before) or selected_slot != selection_before:
		push_error("UI_SMOKE_CAMERA_DRAG_FAILED")
		return false
	var zoom_before := settlement_grid.camera_zoom
	await _smoke_colony_pinch()
	if settlement_grid.camera_zoom <= zoom_before or selected_slot != selection_before:
		push_error("UI_SMOKE_CAMERA_PINCH_FAILED")
		return false
	for kind in range(BUILDING_KEYS.size()):
		selected_slot = kind
		store.data.buildings[kind] = -1
		_update_settlement()
		settlement_grid.focus_slot(kind)
		await _smoke_press_control(colony_palette_button)
		var choice := management.build_buttons[kind]
		await get_tree().process_frame
		await get_tree().process_frame
		management.scroll.ensure_control_visible(choice)
		await get_tree().process_frame
		await get_tree().process_frame
		await _smoke_press_control(choice)
		if selected_kind != kind or management.visible:
			push_error("UI_SMOKE_BUILDING_CHOICE_FAILED kind=%d" % kind)
			return false
		if kind == 3:
			await _smoke_touch_control(build_button)
		else:
			await _smoke_press_control(build_button)
		if int(store.data.buildings[kind]) != kind:
			push_error("UI_SMOKE_BUILDING_TOUCH_FAILED kind=%d" % kind)
			return false
		selected_slot = 63
		await _smoke_colony_tap(settlement_grid.world_to_view(ColonyMap.iso(ColonyMap.slot_cell(kind))))
		if selected_slot != kind:
			push_error("UI_SMOKE_BUILDING_GROUND_TAP_FAILED kind=%d" % kind)
			return false
	if entry_bonuses != before_bonuses:
		push_error("UI_SMOKE_BUILDING_CHANGED_ACTIVE_ATTEMPT")
		return false
	settlement_grid.focus_home()
	await _capture_preview(preview_dir.path_join("settlement_built.png"))
	settlement_grid.set_zoom(0.18)
	settlement_grid.focus_home()
	await _capture_preview(preview_dir.path_join("city_overview.png"))
	settlement_grid.set_zoom(0.75)
	_choose_slot(-1)
	settlement_grid.focus_slot(-1)
	for stage in range(1, 4):
		await _smoke_press_control(build_button)
		if int(store.data.bunker_level) != stage:
			push_error("UI_SMOKE_BUNKER_STAGE_FAILED")
			return false
		await _capture_preview(preview_dir.path_join("bunker_%d.png" % stage))
	_open_heroes()
	var cards_before := 0
	for value in store.data.hero_state.cards.values():
		cards_before += int(value)
	await _smoke_press_control(management.chest_button)
	var cards_after := 0
	for value in store.data.hero_state.cards.values():
		cards_after += int(value)
	if cards_after != cards_before + 3:
		push_error("UI_SMOKE_HERO_CHEST_FAILED")
		return false
	await _capture_preview(preview_dir.path_join("heroes.png"))
	store.data.hero_state.cards.ranger = maxi(3, int(store.data.hero_state.cards.ranger))
	management.open_heroes()
	await _smoke_press_control(management.hero_action_buttons.ranger)
	if not store.data.heroes.has("ranger"):
		push_error("UI_SMOKE_HERO_CARD_UNLOCK_FAILED")
		return false
	await _smoke_press_control(management.tab_buttons.army)
	var army_before := int(store.data.army.infantry)
	await _smoke_press_control(management.train_buttons.infantry)
	if int(store.data.army.infantry) != army_before + 5:
		push_error("UI_SMOKE_ARMY_TRAIN_FAILED")
		return false
	await _capture_preview(preview_dir.path_join("army.png"))
	_notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	if management.visible or current_screen != "settlement":
		push_error("UI_SMOKE_MANAGEMENT_BACK_FAILED")
		return false
	heroes.select("warden")
	await _smoke_press_control(colony_mode_button)
	var target: Dictionary = expeditions.deposits()[0]
	settlement_grid.focus_deposit(int(target.id))
	await _smoke_colony_tap(settlement_grid.world_to_view(ColonyMap.iso(Vector2i(target.cell[0], target.cell[1]))))
	if selected_deposit != int(target.id):
		push_error("UI_SMOKE_DEPOSIT_TAP_FAILED")
		return false
	await _smoke_press_control(build_button)
	if expeditions.jobs().size() != 1:
		push_error("UI_SMOKE_EXPEDITION_DISPATCH_FAILED")
		return false
	expeditions.advance(3.0)
	var party_position := expeditions.job_position(expeditions.jobs()[0])
	settlement_grid.set_zoom(1.0)
	settlement_grid.focus_position(ColonyMap.iso(Vector2i(roundi(party_position.x), roundi(party_position.y))))
	await get_tree().process_frame
	await _capture_preview(preview_dir.path_join("expedition.png"))
	settlement_grid.set_zoom(0.18)
	settlement_grid.focus_home()
	await _capture_preview(preview_dir.path_join("region_overview.png"))
	var resource := String(target.resource)
	var balance_before := int(store.data.resources[resource])
	for tick in range(300):
		expeditions.advance(0.5)
		if tick % 30 == 0:
			await get_tree().process_frame
	if not expeditions.jobs().is_empty() or int(store.data.resources[resource]) <= balance_before:
		push_error("UI_SMOKE_EXPEDITION_RETURN_FAILED")
		return false
	store.data.level = maxi(3, int(store.data.level))
	store.data.banked_levels.erase("3")
	_load_level(3)
	reward_banked = false
	_show_result(true)
	if store.last_hero_reward.is_empty() or not hero_reward_portrait.visible:
		push_error("UI_SMOKE_HERO_CARD_RESULT_FAILED")
		return false
	await _capture_preview(preview_dir.path_join("hero_reward.png"))
	modal.visible = false
	store.data = before_data
	store.save_progress()
	expeditions.configure(settlement, heroes)
	_update_settlement()
	_close_settlement()
	audio.set_enabled(false)
	await get_tree().create_timer(0.3).timeout
	print("UI_SMOKE_CITY_AUDIO_OK buildings=15 map_cells=900 camera_drag=true pinch=true finite_squads=true hero_cards=true training=true bunker=true")
	return true


func _smoke_colony_point(local: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * settlement_grid.get_global_transform_with_canvas() * local


func _smoke_colony_tap(local: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = _smoke_colony_point(local)
		event.global_position = event.position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)
		await get_tree().process_frame


func _smoke_colony_drag(start: Vector2, finish: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.position = _smoke_colony_point(start)
	down.global_position = down.position
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	Input.parse_input_event(down)
	await get_tree().process_frame
	var move := InputEventMouseMotion.new()
	move.position = _smoke_colony_point(finish)
	move.global_position = move.position
	move.relative = _smoke_colony_point(finish) - _smoke_colony_point(start)
	move.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(move)
	await get_tree().process_frame
	var up := InputEventMouseButton.new()
	up.position = move.position
	up.global_position = up.position
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame


func _smoke_colony_pinch() -> void:
	for index in range(2):
		var touch := InputEventScreenTouch.new()
		touch.index = index
		touch.position = _smoke_colony_point(Vector2(240 + index * 160, 330))
		touch.pressed = true
		Input.parse_input_event(touch)
		await get_tree().process_frame
	var drag := InputEventScreenDrag.new()
	drag.index = 1
	drag.position = _smoke_colony_point(Vector2(460, 330))
	drag.relative = _smoke_colony_point(Vector2(60, 0)) - _smoke_colony_point(Vector2.ZERO)
	Input.parse_input_event(drag)
	await get_tree().process_frame
	for index in range(2):
		var touch := InputEventScreenTouch.new()
		touch.index = index
		touch.position = _smoke_colony_point(Vector2(240 if index == 0 else 460, 330))
		touch.pressed = false
		Input.parse_input_event(touch)
		await get_tree().process_frame


func _capture_preview(path: String) -> void:
	if DisplayServer.get_name() == "headless":
		await get_tree().process_frame
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)


func _smoke_press_control(control: Control, fraction: Vector2 = Vector2(0.5, 0.5)) -> void:
	var point := get_viewport().get_final_transform() * control.get_global_transform_with_canvas() * (control.size * fraction)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)
		await get_tree().process_frame


func _smoke_touch_control(control: Control) -> void:
	var point := get_viewport().get_final_transform() * control.get_global_transform_with_canvas() * (control.size * 0.5)
	for pressed in [true, false]:
		var touch := InputEventScreenTouch.new()
		touch.index = 0
		touch.position = point
		touch.pressed = pressed
		Input.parse_input_event(touch)
		await get_tree().process_frame


func _smoke_home_navigation(preview_dir: String) -> bool:
	if current_screen != "home" or not home_screen.visible or game_screen.visible or home_level_number.text != str(store.data.level):
		push_error("UI_SMOKE_HOME_STARTUP_FAILED")
		return false
	var board := engine.snapshot()
	var moves := engine.moves
	var bonuses := entry_bonuses.duplicate(true)
	await _capture_preview(preview_dir.path_join("home.png"))
	_open_settings()
	if current_screen != "home" or not utility_modal.visible:
		push_error("UI_SMOKE_HOME_SETTINGS_OPEN_FAILED")
		return false
	_notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	if utility_modal.visible or current_screen != "home" or not home_screen.visible:
		push_error("UI_SMOKE_HOME_SETTINGS_BACK_FAILED")
		return false
	_open_help()
	_notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	_open_settlement()
	if current_screen != "settlement" or settlement_origin != "home":
		push_error("UI_SMOKE_HOME_SETTLEMENT_OPEN_FAILED")
		return false
	_notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	if current_screen != "home":
		push_error("UI_SMOKE_HOME_SETTLEMENT_BACK_FAILED")
		return false
	await _smoke_press_control(home_continue)
	if current_screen != "game" or not game_screen.visible or home_screen.visible:
		push_error("UI_SMOKE_HOME_CONTINUE_TOUCH_FAILED")
		return false
	_open_settlement()
	_close_settlement()
	_notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	if current_screen != "home" or engine.snapshot() != board or engine.moves != moves or entry_bonuses != bonuses:
		push_error("UI_SMOKE_HOME_PRESERVED_BATTLE_FAILED")
		return false
	_continue_from_home()
	print("UI_SMOKE_HOME_OK startup=true continue_touch=true settings_back=true settlement_back=true battle_preserved=true")
	return true


func _smoke_tap(cell: Vector2i) -> void:
	var point := get_viewport().get_final_transform() * get_global_transform_with_canvas() * _cell_center(cell)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)
		await get_tree().process_frame


func _smoke_swipe(a: Vector2i, b: Vector2i) -> void:
	for index in range(2):
		var event := InputEventScreenTouch.new()
		event.index = 0
		event.position = get_viewport().get_final_transform() * get_global_transform_with_canvas() * _cell_center(a if index == 0 else b)
		event.pressed = index == 0
		Input.parse_input_event(event)
		await get_tree().process_frame
		if index == 0:
			# A second finger must not replace the active gesture's origin.
			for secondary_pressed in [true, false]:
				var secondary := InputEventScreenTouch.new()
				secondary.index = 1
				secondary.position = get_viewport().get_final_transform() * get_global_transform_with_canvas() * _cell_center(b)
				secondary.pressed = secondary_pressed
				Input.parse_input_event(secondary)
				await get_tree().process_frame


func _smoke_save_failure() -> bool:
	# A private smoke-save path deliberately points inside a regular file.
	# No real player save or protected filesystem location is touched.
	var original_path := store.path
	var obstacle_path := "user://ui-smoke-save-obstacle"
	var obstacle := FileAccess.open(obstacle_path, FileAccess.WRITE)
	if obstacle == null:
		push_error("UI_SMOKE_SAVE_FIXTURE_FAILED")
		return false
	obstacle.store_string("UI smoke test")
	obstacle.close()
	var original_level := active_level
	var before := store.data.duplicate(true)
	store.path = obstacle_path.path_join("progress.json")
	reward_banked = false
	_show_result(true)
	_result_continue()
	if store.last_award_status != "save_failed" or reward_banked or active_level != original_level or not modal.visible or store.data != before:
		push_error("UI_SMOKE_SAVE_ROLLBACK_FAILED")
		return false
	store.path = original_path
	_result_continue()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(obstacle_path))
	if active_level != original_level + 1 or not store.data.banked_levels.has(str(original_level)):
		push_error("UI_SMOKE_SAVE_RETRY_FAILED")
		return false
	print("UI_SMOKE_SAVE_FAILURE_RETRY_OK")
	return true


func _smoke_objectives_and_pools(preview_dir: String) -> bool:
	var gem_ids: Array[int] = []
	for gem in gem_pool:
		gem_ids.append(gem.get_instance_id())
	var effects_created := int(fx_pool.stats().created)
	_open_settings()
	_toggle_setting("reduced_effects")
	_toggle_setting("haptics")
	var reloaded := ProgressStore.new()
	reloaded.path = store.path
	if not reloaded.load_progress() or not bool(reloaded.data.settings.reduced_effects) or bool(reloaded.data.settings.haptics):
		push_error("UI_SMOKE_SETTINGS_PERSIST_FAILED")
		return false
	for index in range(64):
		_spawn_fx("fx_dust", Vector2(350, 700), Vector2(70, 70))
	if int(fx_pool.stats().active) > 8 or int(fx_pool.stats().created) != effects_created:
		push_error("UI_SMOKE_REDUCED_FX_CAP_FAILED")
		return false
	fx_pool.clear()
	await _capture_preview(preview_dir.path_join("settings.png"))
	_toggle_setting("reduced_effects")
	_close_utility()
	_load_level(6)
	await _capture_preview(preview_dir.path_join("board_ring.png"))
	for number in [2, 3, 4, 5, 10, 30, 50]:
		_load_level(number)
		var kind: String = engine.objective_state().kind
		await _capture_preview(preview_dir.path_join("mission_%s%s.png" % [kind, "_ice" if number == 30 else "_lava" if number == 50 else ""]))
		if number in [2, 3]:
			await _capture_preview(preview_dir.path_join("board_%s.png" % String(engine.level_data.shape)))
		var turns := 3 if number == 10 else 1
		var static_altar_positions: Dictionary = {}
		for cell: Vector2i in engine.altars:
			static_altar_positions[cell] = altar_nodes[cell].global_position
		for index in range(turns):
			var legal: Array = engine.legal_moves()
			if legal.is_empty() or engine.is_won() or engine.is_lost():
				break
			var move = legal[0]
			var before := engine.moves
			await _smoke_swipe(move[0], move[1])
			var deadline := Time.get_ticks_msec() + 10000
			while busy and Time.get_ticks_msec() < deadline:
				for cell: Vector2i in static_altar_positions:
					if altar_nodes[cell].global_position != static_altar_positions[cell] or altar_nodes[cell].scale != Vector2.ONE or altar_nodes[cell].modulate.a != 1.0:
						push_error("UI_SMOKE_ALTAR_MOVED_WITH_GEM")
						return false
				await get_tree().process_frame
			if busy or engine.moves != before - 1:
				push_error("UI_SMOKE_OBJECTIVE_INPUT_FAILED: " + kind)
				return false
		if number in [10, 30, 50]:
			await _capture_preview(preview_dir.path_join("boss%s.png" % ("" if number == 10 else "_ice" if number == 30 else "_lava")))
		_open_help()
		await _capture_preview(preview_dir.path_join("help_%s.png" % kind))
		_close_utility()
		for index in range(gem_pool.size()):
			if gem_pool[index].get_instance_id() != gem_ids[index]:
				push_error("UI_SMOKE_GEM_POOL_ID_CHANGED")
				return false
		print("UI_SMOKE_OBJECTIVE_OK kind=", kind, " progress=", engine.objective_state().current, "/", engine.objective_state().target)
	var original_board := engine.snapshot()
	var original_score := engine.score
	var original_moves := engine.moves
	await _show_hint()
	if not engine.cells.has(selected) or engine.snapshot() != original_board or engine.score != original_score or engine.moves != original_moves:
		push_error("UI_SMOKE_HINT_MUTATED_PLAY")
		return false
	_clear_hint()
	_show_hint()
	_open_help()
	await get_tree().process_frame
	_close_utility()
	if hint_searching:
		push_error("UI_SMOKE_HINT_CANCEL_FAILED")
		return false
	_smoke_clear_selection()
	if not await _smoke_pause_and_back():
		return false
	if int(fx_pool.stats().created) != effects_created or effects_created != 24 or gem_pool.size() != 81:
		push_error("UI_SMOKE_POOL_ALLOCATIONS_CHANGED")
		return false
	print("UI_SMOKE_POOLS_OK gems=81 fx=24 reduced_limit=8 settings_persisted=true")
	return true


func _smoke_clear_selection() -> void:
	selected = Vector2i(-1, -1)
	selection_ring.visible = false


func _smoke_pause_and_back() -> bool:
	_load_level(1)
	var move = engine.legal_moves()[0]
	var before_moves := engine.moves
	await _smoke_swipe(move[0], move[1])
	_notification(NOTIFICATION_APPLICATION_PAUSED)
	_notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	var deadline := Time.get_ticks_msec() + 10000
	while busy and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if busy or engine.moves != before_moves - 1 or pointer_down or current_screen != "home":
		push_error("UI_SMOKE_PAUSE_TURN_FAILED")
		return false
	var completed_board := engine.snapshot()
	_continue_from_home()
	if engine.snapshot() != completed_board or current_screen != "game":
		push_error("UI_SMOKE_TURN_HOME_RESUME_FAILED")
		return false
	_show_result(false)
	_notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	if modal.visible or busy or engine.is_lost() or engine.is_won():
		push_error("UI_SMOKE_TERMINAL_BACK_FAILED")
		return false
	_notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	if current_screen != "home" or utility_modal.visible or not home_screen.visible:
		push_error("UI_SMOKE_GAME_BACK_HOME_FAILED")
		return false
	_open_settings()
	_close_utility()
	if current_screen != "home":
		push_error("UI_SMOKE_HOME_SETTINGS_CHANGED_SCREEN")
		return false
	_continue_from_home()
	print("UI_SMOKE_ALTARS_HINT_PAUSE_BACK_OK")
	return true
