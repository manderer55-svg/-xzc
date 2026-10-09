class_name GeneratedNumber
extends Control
## HUD numerals use generated golden glyphs instead of a font.

var text: String = "0":
	set(value):
		if text == value:
			return
		text = value
		if is_inside_tree():
			_layout_digits()
var centered := false:
	set(value):
		centered = value
		if is_inside_tree():
			_layout_digits()
var _glyph_nodes: Array[TextureRect] = []
var created_count := 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_layout_digits)
	_layout_digits()

func _layout_digits() -> void:
	var glyphs: Array[int] = []
	for symbol in text:
		if symbol.is_valid_int():
			glyphs.append(int(symbol))
		elif symbol == "+":
			glyphs.append(10)
		elif symbol == "×":
			glyphs.append(11)
	for sprite in _glyph_nodes:
		sprite.visible = false
	if glyphs.is_empty() or size.x <= 0 or size.y <= 0:
		return
	while _glyph_nodes.size() < glyphs.size():
		var sprite := TextureRect.new()
		sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(sprite)
		_glyph_nodes.append(sprite)
		created_count += 1
	var glyph_width := minf(size.y * 0.70, size.x / glyphs.size())
	var height := minf(size.y, glyph_width / 0.70)
	var start := (size.x - glyph_width * glyphs.size()) * 0.5 if centered else 0.0
	for index in glyphs.size():
		var sprite := _glyph_nodes[index]
		sprite.texture = Art.texture("digit_%d" % glyphs[index])
		sprite.visible = true
		sprite.position = Vector2(start + index * glyph_width, (size.y - height) * 0.5)
		sprite.size = Vector2(glyph_width, height)
