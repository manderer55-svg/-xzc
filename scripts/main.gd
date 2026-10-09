extends Control
## All visible illustration, frames, tiles and effects come from the generated art atlas.
## Runtime drawing is limited to text, arranging textures and animating those textures.

const CANVAS := Vector2(720, 1280)
const GOLD := Color("e4c68b")
const IVORY := Color("eee7d9")
const MUTED := Color("b8ac99")
const UI_FONT: Font = preload("res://art/fonts/DejaVuSans.ttf")
const UI_FONT_BOLD: Font = preload("res://art/fonts/DejaVuSans-Bold.ttf")
const GEM_NAMES := ["Рубин", "Сапфир", "Изумруд", "Аметист", "Янтарь", "Лунный камень"]
const BUILDING_KEYS := ["quarry", "sawmill", "shrine", "fortress"]
const BUILDING_NAMES := ["Каменоломня", "Лесопилка", "Святилище", "Крепость"]

var engine: MatchEngine
var store: ProgressStore
var settlement: SettlementModel
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
var current_screen := "game"
var selected_slot := 4
var selected_kind := 0
var choosing_level := 1
var reward_banked := false
var last_rewards: Dictionary = {}
var texture_hit_masks: Dictionary = {}

var game_screen: Control
var settlement_screen: Control
var cells_layer: Control
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
var settlement_grid: Control
var resource_labels: Array[GeneratedNumber] = []
var slot_title: Label
var slot_detail: Label
var settlement_status: Label
var build_button: TextureButton
var upgrade_button: TextureButton
var modal: Control
var modal_title: Label
var modal_body: Label
var modal_action: TextureButton
var modal_secondary: TextureButton
var level_modal: Control
var level_choice_label: GeneratedNumber
var end_won := false


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
	_build_game_screen()
	_build_settlement_screen()
	_build_result_modal()
	_build_level_modal()
	active_level = maxi(1, int(store.data.get("level", 1)))
	_load_level(active_level)
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
	var texture: Texture2D = Art.texture("ui_small_button" if small else "ui_button")
	node.texture_normal = texture
	node.texture_pressed = texture
	node.texture_hover = texture
	node.texture_disabled = texture
	node.ignore_texture_size = true
	node.stretch_mode = TextureButton.STRETCH_SCALE
	node.position = position
	node.size = dimensions
	node.focus_mode = Control.FOCUS_ALL
	node.pressed.connect(action)
	node.button_down.connect(func(): node.modulate = Color(0.77, 0.72, 0.64))
	node.button_up.connect(func(): node.modulate = Color.WHITE)
	node.mouse_entered.connect(func(): if not node.disabled: node.modulate = Color(1.15, 1.08, 0.95))
	node.mouse_exited.connect(func(): node.modulate = Color.WHITE)
	parent.add_child(node)
	_label(node, text_value, Vector2(5, 0), dimensions - Vector2(10, 0), 22 if not small else 19, GOLD, true)
	return node


func _number(parent: Node, text_value: String, position: Vector2, dimensions: Vector2, centered: bool = false) -> GeneratedNumber:
	var node := GeneratedNumber.new()
	node.position = position
	node.size = dimensions
	node.centered = centered
	node.text = text_value
	parent.add_child(node)
	return node


func _new_screen() -> Control:
	var screen := Control.new()
	screen.size = CANVAS
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(screen)
	return screen


func _build_game_screen() -> void:
	game_screen = _new_screen()
	_texture(game_screen, "background", Vector2.ZERO, CANVAS)
	_texture(game_screen, "ui_header", Vector2(20, 18), Vector2(680, 120))
	_label(game_screen, "ПЕПЕЛЬНЫЙ ПРЕДЕЛ", Vector2(58, 35), Vector2(604, 46), 32, GOLD, true)
	_label(game_screen, "ХРОНИКИ ОСКОЛКОВ", Vector2(80, 80), Vector2(560, 30), 15, MUTED, true)
	level_label = _label(game_screen, "УРОВЕНЬ", Vector2(238, 121), Vector2(152, 36), 19, GOLD, true)
	level_number = _number(game_screen, "1", Vector2(384, 117), Vector2(137, 46))
	_button(game_screen, "Уровни", Vector2(537, 115), Vector2(156, 48), _open_level_picker, true)
	_texture(game_screen, "ui_panel", Vector2(24, 171), Vector2(435, 111))
	_label(game_screen, "СИЛА ОСКОЛКОВ", Vector2(64, 188), Vector2(365, 27), 14, MUTED)
	score_label = _number(game_screen, "0", Vector2(64, 208), Vector2(165, 49))
	target_label = _label(game_screen, "ЦЕЛЬ", Vector2(243, 215), Vector2(70, 36), 14, MUTED, true)
	target_number = _number(game_screen, "0", Vector2(317, 208), Vector2(115, 49), true)
	_texture(game_screen, "ui_progress", Vector2(46, 252), Vector2(390, 13)).modulate = Color(0.42, 0.40, 0.46)
	progress_fill = _texture(game_screen, "ui_progress", Vector2(46, 252), Vector2(0, 13))
	_texture(game_screen, "ui_panel", Vector2(475, 171), Vector2(221, 111))
	_label(game_screen, "ХОДЫ", Vector2(490, 180), Vector2(190, 27), 15, MUTED, true)
	moves_label = _number(game_screen, "30", Vector2(501, 208), Vector2(168, 62), true)
	_texture(game_screen, "ui_panel", Vector2(20, 300), Vector2(680, 703))
	shape_label = _label(game_screen, "", Vector2(50, 308), Vector2(620, 38), 17, MUTED, true)
	cells_layer = Control.new()
	gems_layer = Control.new()
	effects_layer = Control.new()
	for layer: Control in [cells_layer, gems_layer, effects_layer]:
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.size = CANVAS
		game_screen.add_child(layer)
	selection_ring = _texture(effects_layer, "selection", Vector2.ZERO, Vector2(72, 72))
	selection_ring.visible = false
	status_label = _label(game_screen, "Соедините три кристалла. Четыре создают молнию.", Vector2(30, 1015), Vector2(660, 52), 18, MUTED, true)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_button(game_screen, "Подсказка", Vector2(24, 1090), Vector2(207, 77), _show_hint)
	_button(game_screen, "Заново", Vector2(248, 1090), Vector2(207, 77), _retry)
	_button(game_screen, "Цитадель", Vector2(472, 1090), Vector2(224, 77), _open_settlement)
	_label(game_screen, "Проведите по фишке или коснитесь двух соседних.", Vector2(42, 1188), Vector2(636, 42), 17, MUTED, true)


func _build_settlement_screen() -> void:
	settlement_screen = _new_screen()
	settlement_screen.visible = false
	_texture(settlement_screen, "settlement_background", Vector2.ZERO, CANVAS)
	_texture(settlement_screen, "ui_header", Vector2(20, 18), Vector2(680, 120))
	_label(settlement_screen, "ЦИТАДЕЛЬ ПЕПЛА", Vector2(58, 39), Vector2(604, 44), 32, GOLD, true)
	_label(settlement_screen, "ОСКОЛКИ ПИТАЮТ ВАШЕ ВЛАДЕНИЕ", Vector2(58, 86), Vector2(604, 28), 15, MUTED, true)
	for i in range(3):
		var x := 24.0 + i * 229.0
		_texture(settlement_screen, "ui_panel", Vector2(x, 155), Vector2(214, 103))
		_texture(settlement_screen, ["stone", "wood", "essence"][i], Vector2(x + 12, 173), Vector2(62, 62))
		_label(settlement_screen, ["КАМЕНЬ", "ДРЕВО", "ЭССЕНЦИЯ"][i], Vector2(x + 77, 170), Vector2(132, 24), 13, MUTED)
		resource_labels.append(_number(settlement_screen, "0", Vector2(x + 77, 191), Vector2(128, 53)))
	_label(settlement_screen, "Выберите участок и возведите постройку", Vector2(36, 276), Vector2(648, 42), 19, IVORY, true)
	settlement_grid = Control.new()
	settlement_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	settlement_grid.size = CANVAS
	settlement_screen.add_child(settlement_grid)
	_texture(settlement_screen, "ui_panel", Vector2(24, 753), Vector2(672, 134))
	slot_title = _label(settlement_screen, "", Vector2(64, 780), Vector2(588, 37), 24, GOLD)
	slot_detail = _label(settlement_screen, "", Vector2(64, 821), Vector2(588, 48), 16, MUTED)
	slot_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for i in range(4):
		var key: String = BUILDING_KEYS[i]
		var button := _button(settlement_screen, "", Vector2(24 + 171 * i, 908), Vector2(159, 104), func(): _choose_kind(i), true)
		_texture(button, key, Vector2(43, 3), Vector2(74, 68))
		_label(button, BUILDING_NAMES[i], Vector2(1, 71), Vector2(157, 25), 14, GOLD, true)
	build_button = _button(settlement_screen, "Построить", Vector2(24, 1032), Vector2(326, 73), _build_selected)
	upgrade_button = _button(settlement_screen, "Улучшить", Vector2(367, 1032), Vector2(329, 73), _upgrade_selected)
	_button(settlement_screen, "Собрать ресурсы", Vector2(24, 1120), Vector2(326, 73), _mine)
	_button(settlement_screen, "К кристаллам", Vector2(367, 1120), Vector2(329, 73), _close_settlement)
	settlement_status = _label(settlement_screen, "", Vector2(32, 1201), Vector2(656, 50), 16, MUTED, true)
	settlement_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _build_result_modal() -> void:
	modal = _new_screen()
	modal.visible = false
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_texture(modal, "background", Vector2.ZERO, CANVAS).modulate = Color(0.2, 0.18, 0.23)
	_texture(modal, "ui_result", Vector2(40, 257), Vector2(640, 749))
	_texture(modal, "ui_badge", Vector2(291, 295), Vector2(138, 138))
	modal_title = _label(modal, "", Vector2(80, 451), Vector2(560, 56), 34, GOLD, true)
	modal_body = _label(modal, "", Vector2(100, 523), Vector2(520, 203), 23, IVORY, true)
	modal_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	modal_action = _button(modal, "", Vector2(130, 753), Vector2(460, 80), _result_continue)
	modal_secondary = _button(modal, "В цитадель", Vector2(130, 851), Vector2(460, 80), _result_settlement)


func _build_level_modal() -> void:
	level_modal = _new_screen()
	level_modal.visible = false
	level_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_texture(level_modal, "background", Vector2.ZERO, CANVAS).modulate = Color(0.2, 0.18, 0.23)
	_texture(level_modal, "ui_result", Vector2(40, 310), Vector2(640, 650))
	_label(level_modal, "ВРАТА ИСПЫТАНИЙ", Vector2(80, 375), Vector2(560, 50), 29, GOLD, true)
	_label(level_modal, "Процедурные разломы разных форм", Vector2(70, 437), Vector2(580, 36), 17, MUTED, true)
	level_choice_label = _number(level_modal, "1", Vector2(205, 505), Vector2(310, 91), true)
	_button(level_modal, "−", Vector2(104, 513), Vector2(93, 76), func(): _change_level_choice(-1), true)
	_button(level_modal, "+", Vector2(523, 513), Vector2(93, 76), func(): _change_level_choice(1), true)
	_button(level_modal, "−100", Vector2(104, 615), Vector2(153, 60), func(): _change_level_choice(-100), true)
	_button(level_modal, "+100", Vector2(284, 615), Vector2(153, 60), func(): _change_level_choice(100), true)
	_button(level_modal, "+1000", Vector2(464, 615), Vector2(153, 60), func(): _change_level_choice(1000), true)
	_button(level_modal, "Войти в разлом", Vector2(130, 720), Vector2(460, 80), _confirm_level_choice)
	_button(level_modal, "Вернуться", Vector2(130, 820), Vector2(460, 66), func(): level_modal.visible = false, true)


func _load_level(number: int) -> void:
	_cancel_animations()
	active_level = clampi(number, 1, ProgressStore.MAX_LEVEL)
	engine = MatchEngine.new()
	engine.initialize(active_level)
	selected = Vector2i(-1, -1)
	reward_banked = false
	last_rewards.clear()
	modal.visible = false
	level_modal.visible = false
	selection_ring.visible = false
	busy = false
	var width := int(engine.level_data.get("width", 8))
	var height := int(engine.level_data.get("height", 8))
	tile_size = minf(minf(628.0 / width, 620.0 / height), 80.0)
	board_size = Vector2(width, height) * tile_size
	board_origin = Vector2((720.0 - board_size.x) / 2.0, 352.0 + (630.0 - board_size.y) / 2.0)
	_clear_children(cells_layer)
	for cell: Vector2i in engine.cells:
		_texture(cells_layer, "cell", _cell_origin(cell), Vector2.ONE * tile_size)
	_render_board(engine.cells, engine.blockers)
	_update_hud()
	status_label.text = "Три — совпадение · четыре — молния · пять — звезда"
	var shape := String(engine.level_data.get("shape", "Разлом"))
	shape_label.text = "%s · ритуал %d" % [_shape_name(shape), active_level]
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


func _render_board(board: Dictionary, blockers: Dictionary, falling: bool = false) -> void:
	var old_snapshot := tile_snapshot.duplicate(true)
	var available: Array = old_snapshot.keys()
	available.sort_custom(func(a: Vector2i, b: Vector2i): return a.y > b.y)
	_clear_children(gems_layer)
	tile_nodes.clear()
	tile_snapshot = board.duplicate(true)
	var order: Array = board.keys()
	order.sort_custom(func(a: Vector2i, b: Vector2i): return a.y > b.y)
	for cell: Vector2i in order:
		var data: Dictionary = board[cell]
		var node := Control.new()
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node.position = _cell_origin(cell)
		node.size = Vector2.ONE * tile_size
		node.pivot_offset = node.size * 0.5
		gems_layer.add_child(node)
		_texture(node, "gem_%d" % int(data.get("color", 0)), Vector2.ONE * tile_size * 0.07, Vector2.ONE * tile_size * 0.86)
		var special := String(data.get("special", ""))
		if not special.is_empty():
			_texture(node, "special_" + special, Vector2.ONE * tile_size * 0.025, Vector2.ONE * tile_size * 0.95)
		if blockers.has(cell):
			var blocker = blockers[cell]
			var kind := "ice"
			var hp := 1
			if blocker is Dictionary:
				kind = String(blocker.get("kind", blocker.get("type", "ice")))
				hp = int(blocker.get("hp", 1))
			else:
				hp = int(blocker)
				kind = "stone" if hp > 1 else "ice"
			_texture(node, "blocker_" + kind, Vector2.ONE * tile_size * 0.025, Vector2.ONE * tile_size * 0.95)
			if hp > 1:
				_label(node, str(hp), Vector2(tile_size * 0.63, tile_size * 0.66), Vector2.ONE * tile_size * 0.27, maxi(12, int(tile_size * 0.23)), IVORY, true)
		tile_nodes[cell] = node
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
				tween.tween_property(node, "position", _cell_origin(cell), 0.24 + (cell.y - source.y) * 0.021).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func _same_gravity_segment(a: Vector2i, b: Vector2i, board: Dictionary, blockers: Dictionary) -> bool:
	if a == b:
		return true
	for row in range(a.y, b.y + 1):
		var cell := Vector2i(a.x, row)
		if not board.has(cell) or blockers.has(cell):
			return false
	return true


func _update_hud() -> void:
	score_label.text = str(engine.score)
	var target := int(engine.level_data.get("target", 1000))
	target_number.text = str(target)
	moves_label.text = str(engine.moves)
	progress_fill.size.x = 390.0 * clampf(float(engine.score) / maxi(1, target), 0.0, 1.0)
	moves_label.modulate = Color("ed998b") if engine.moves <= 5 else Color.WHITE


func _input(event: InputEvent) -> void:
	if busy or current_screen != "game" or modal.visible or level_modal.visible:
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
	turn_generation += 1
	for tween in running_tweens:
		if tween.is_valid():
			tween.kill()
	running_tweens.clear()
	if is_instance_valid(effects_layer):
		for child in effects_layer.get_children():
			if child != selection_ring:
				child.queue_free()
	pointer_down = false
	pointer_touch_id = -1


func _attempt_swap(a: Vector2i, b: Vector2i) -> void:
	if busy or not engine.cells.has(a) or not engine.cells.has(b):
		return
	busy = true
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
		return
	Input.vibrate_handheld(25)
	for step: Dictionary in result.get("steps", []):
		if generation != turn_generation:
			return
		_animate_step(step)
		await get_tree().create_timer(0.31).timeout
		if generation != turn_generation:
			return
		_render_board(step.get("board", engine.cells), step.get("blockers", engine.blockers), true)
		score_label.text = str(step.get("score", engine.score))
		var combo := int(step.get("combo", 1))
		status_label.text = "КАСКАД ×%d · сила разлома растёт" % combo if combo > 1 else "Осколки наполняют цитадель силой"
		await get_tree().create_timer(0.47).timeout
	if generation != turn_generation:
		return
	_render_board(engine.cells, engine.blockers)
	_update_hud()
	busy = false
	if bool(result.get("won", false)) or bool(result.get("lost", false)):
		_show_result(bool(result.get("won", false)))
	elif engine.legal_moves().is_empty():
		status_label.text = "Разлом изменился — ищите новое сочетание."


func _animate_step(step: Dictionary) -> void:
	for activation in step.get("activated", []):
		var position_value: Vector2i = activation.get("position", Vector2i.ZERO)
		var special := String(activation.get("special", "bomb"))
		if special == "row":
			_spawn_fx("fx_lightning", Vector2(board_origin.x + board_size.x / 2, _cell_center(position_value).y), Vector2(board_size.x + 80, tile_size * 1.3))
		elif special == "column":
			_spawn_fx("fx_lightning", Vector2(_cell_center(position_value).x, board_origin.y + board_size.y / 2), Vector2(board_size.y + 80, tile_size * 1.3), PI * 0.5)
		else:
			_spawn_fx("fx_explosion", _cell_center(position_value), Vector2.ONE * tile_size * (4.4 if special == "nova" else 3.0))
		Input.vibrate_handheld(45)
	for hit in step.get("blocker_hits", []):
		var position_value: Vector2i = hit if hit is Vector2i else hit.get("position", Vector2i.ZERO)
		_spawn_fx("fx_frost", _cell_center(position_value), Vector2.ONE * tile_size * 1.8)
	for position_value: Vector2i in step.get("removed", []):
		_spawn_fx("fx_dust", _cell_center(position_value), Vector2.ONE * tile_size * 1.6, randf_range(-0.5, 0.5))
		if tile_nodes.has(position_value):
			var node: Control = tile_nodes[position_value]
			var tween := _tween().set_parallel()
			tween.tween_property(node, "scale", Vector2.ONE * 0.15, 0.23).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
			tween.tween_property(node, "modulate:a", 0.0, 0.23)
			tile_snapshot.erase(position_value)
	for special in step.get("spawned", []):
		_spawn_fx("fx_frost", _cell_center(special.get("position", Vector2i.ZERO)), Vector2.ONE * tile_size * 1.7)


func _spawn_fx(prefix: String, center: Vector2, dimensions: Vector2, angle: float = 0.0) -> void:
	var node := _texture(effects_layer, prefix + "_0", center - dimensions * 0.5, dimensions)
	node.pivot_offset = dimensions * 0.5
	node.rotation = angle
	node.scale = Vector2.ONE * 0.75
	var tween := _tween().set_parallel()
	tween.tween_property(node, "scale", Vector2.ONE * 1.18, 0.38).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "modulate:a", 0.0, 0.20).set_delay(0.18)
	_animate_fx_frames(node, prefix, turn_generation)


func _animate_fx_frames(node: TextureRect, prefix: String, generation: int) -> void:
	for frame in range(4):
		if not is_instance_valid(node) or generation != turn_generation:
			return
		node.texture = Art.texture(prefix + "_%d" % frame)
		await get_tree().create_timer(0.095).timeout
	if is_instance_valid(node):
		node.queue_free()


func _show_hint() -> void:
	if busy:
		return
	var moves: Array = engine.legal_moves()
	if moves.is_empty():
		status_label.text = "Нет ходов. Начните ритуал заново."
		return
	var move = moves[0]
	var a: Vector2i
	var b: Vector2i
	if move is Dictionary:
		a = move.get("a", move.get("from", Vector2i.ZERO))
		b = move.get("b", move.get("to", Vector2i.RIGHT))
	else:
		a = move[0]
		b = move[1]
	_select_tile(a)
	var direction := "вправо" if b.x > a.x else "влево" if b.x < a.x else "вниз" if b.y > a.y else "вверх"
	status_label.text = "Подсказка: сдвиньте выделенный кристалл %s." % direction
	var tween := _tween().set_loops(3)
	tween.tween_property(selection_ring, "modulate:a", 0.4, 0.30)
	tween.tween_property(selection_ring, "modulate:a", 1.0, 0.30)


func _retry() -> void:
	if busy:
		return
	_load_level(active_level)


func _show_result(won: bool) -> void:
	end_won = won
	if not reward_banked:
		last_rewards = store.award_level(active_level, engine.score, won, engine.collected)
		reward_banked = store.last_award_status != "save_failed"
	var save_failed := store.last_award_status == "save_failed"
	modal_title.text = "ХРОНИКА НЕ ЗАПИСАНА" if save_failed else "РИТУАЛ ЗАВЕРШЁН" if won else "СИЛА ИССЯКЛА"
	var body := _reward_text(last_rewards) if won or save_failed else "Ходы закончились. Лучший результат сохранён."
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
	choosing_level = active_level
	level_choice_label.text = str(choosing_level)
	level_modal.visible = true


func _change_level_choice(delta: int) -> void:
	choosing_level = clampi(choosing_level + delta, 1, ProgressStore.MAX_LEVEL)
	level_choice_label.text = str(choosing_level)


func _confirm_level_choice() -> void:
	_load_level(choosing_level)


func _open_settlement() -> void:
	if busy:
		return
	current_screen = "settlement"
	game_screen.visible = false
	settlement_screen.visible = true
	_update_settlement()


func _close_settlement() -> void:
	current_screen = "game"
	settlement_screen.visible = false
	game_screen.visible = true


func _update_settlement() -> void:
	var resources: Dictionary = store.data.get("resources", {})
	for i in range(3):
		resource_labels[i].text = str(resources.get(["stone", "wood", "essence"][i], 0))
	_clear_children(settlement_grid)
	var buildings: Array = store.data.get("buildings", [])
	var upgrades: Array = store.data.get("upgrades", [])
	var building_layers: Array[Dictionary] = []
	for slot in range(9):
		var row := slot / 3
		var column := slot % 3
		var center := Vector2(360 + (column - row) * 99, 367 + (column + row) * 73)
		var ground := TextureButton.new()
		ground.texture_normal = Art.texture("ground")
		ground.texture_pressed = ground.texture_normal
		ground.texture_click_mask = _texture_hit_mask("ground")
		ground.ignore_texture_size = true
		ground.stretch_mode = TextureButton.STRETCH_SCALE
		ground.position = center - Vector2(101, 57)
		ground.size = Vector2(202, 114)
		ground.pressed.connect(func(): _choose_slot(slot))
		settlement_grid.add_child(ground)
		if slot == selected_slot:
			ground.modulate = Color(1.25, 1.13, 0.87)
		var kind := int(buildings[slot]) if slot < buildings.size() else -1
		if kind >= 0 and kind < BUILDING_KEYS.size():
			var tier := int(upgrades[slot]) if slot < upgrades.size() else 0
			building_layers.append({"slot": slot, "kind": kind, "center": center})
			_label(ground, "I".repeat(maxi(1, tier + 1)), Vector2(59, 81), Vector2(85, 27), 15, GOLD, true)
		else:
			_texture(ground, "portal", Vector2(71, 27), Vector2(60, 60)).modulate = Color(0.65, 0.65, 0.74, 0.8)
	for building in building_layers:
		var key: String = BUILDING_KEYS[int(building.kind)]
		var building_button := TextureButton.new()
		building_button.texture_normal = Art.texture(key)
		building_button.texture_click_mask = _texture_hit_mask(key)
		building_button.ignore_texture_size = true
		building_button.stretch_mode = TextureButton.STRETCH_SCALE
		building_button.position = Vector2(building.center) - Vector2(71, 116)
		building_button.size = Vector2(142, 149)
		building_button.pressed.connect(func(): _choose_slot(int(building.slot)))
		settlement_grid.add_child(building_button)
	var selected_building := int(buildings[selected_slot]) if selected_slot < buildings.size() else -1
	build_button.disabled = selected_building >= 0
	var selected_upgrade := int(upgrades[selected_slot]) if selected_slot < upgrades.size() else 0
	upgrade_button.disabled = selected_building < 0 or selected_upgrade >= SettlementModel.MAX_UPGRADE
	build_button.modulate = Color(0.5, 0.5, 0.5) if build_button.disabled else Color.WHITE
	upgrade_button.modulate = Color(0.5, 0.5, 0.5) if upgrade_button.disabled else Color.WHITE
	if selected_building < 0:
		slot_title.text = "Участок %d · %s" % [selected_slot + 1, BUILDING_NAMES[selected_kind]]
		slot_detail.text = "Строительство: %s\nПостройки добывают ресурсы между сражениями." % _cost_text(settlement.get_build_cost(selected_kind))
	else:
		var tier := int(upgrades[selected_slot]) if selected_slot < upgrades.size() else 0
		slot_title.text = "%s · уровень %d" % [BUILDING_NAMES[selected_building], tier + 1]
		var upgrade_text := "Максимальный уровень" if tier >= SettlementModel.MAX_UPGRADE else "Улучшение: %s" % _cost_text(settlement.get_upgrade_cost(selected_slot))
		slot_detail.text = "%s\nЗа минуту: %s" % [upgrade_text, _cost_text(settlement.production())]
	if settlement_status.text.is_empty():
		settlement_status.text = "Побеждайте в разломах, стройте и собирайте добычу."


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
	selected_slot = slot
	_update_settlement()


func _choose_kind(kind: int) -> void:
	selected_kind = kind
	_update_settlement()


func _operation_ok(result) -> bool:
	if result is Dictionary:
		return bool(result.get("ok", result.get("success", false)))
	return bool(result)


func _build_selected() -> void:
	var result = settlement.build(selected_slot, selected_kind)
	settlement_status.text = "%s возведена. Сила владения растёт." % BUILDING_NAMES[selected_kind] if _operation_ok(result) else _operation_error(result)
	_update_settlement()


func _upgrade_selected() -> void:
	var result = settlement.upgrade(selected_slot)
	settlement_status.text = "Постройка улучшена. Добыча увеличилась." if _operation_ok(result) else _operation_error(result)
	_update_settlement()


func _operation_error(result) -> String:
	if result is Dictionary:
		return String(result.get("reason", result.get("error", result.get("message", "Не хватает ресурсов. Победите в разломе."))))
	return "Не хватает ресурсов. Победите в разломе."


func _mine() -> void:
	var result = settlement.mine()
	if result is Dictionary and not bool(result.get("ok", false)):
		settlement_status.text = String(result.get("reason", "Не удалось собрать добычу."))
		_update_settlement()
		return
	var rewards: Dictionary = result if result is Dictionary else {}
	if rewards.has("rewards"):
		rewards = rewards.rewards
	elif rewards.has("resources"):
		rewards = rewards.resources
	var total := int(rewards.get("stone", 0)) + int(rewards.get("wood", 0)) + int(rewards.get("essence", 0))
	settlement_status.text = "Собрано: %s" % _cost_text(rewards) if total > 0 else "Добыча идёт. Вернитесь после следующего сражения."
	_update_settlement()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if is_instance_valid(modal) and modal.visible:
			if store.last_award_status == "save_failed":
				return
			modal.visible = false
		elif is_instance_valid(level_modal) and level_modal.visible:
			level_modal.visible = false
		elif current_screen == "settlement":
			_close_settlement()


func _smoke() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var preview_dir := ProjectSettings.globalize_path("res://art/preview")
	DirAccess.make_dir_recursive_absolute(preview_dir)
	await _capture_preview(preview_dir.path_join("gameplay.png"))
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
	print("UI_SMOKE_OK")
	get_tree().quit()


func _capture_preview(path: String) -> void:
	if DisplayServer.get_name() == "headless":
		await get_tree().process_frame
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)


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
