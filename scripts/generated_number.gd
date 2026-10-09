class_name GeneratedNumber
extends Control
## HUD numerals use generated golden glyphs instead of a font.

var text: String = "0":
	set(value):
		text = value
		if is_inside_tree():
			_layout_digits()
var centered := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_layout_digits)
	_layout_digits()

func _layout_digits() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var glyphs: Array[int] = []
	for symbol in text:
		if symbol.is_valid_int():
			glyphs.append(int(symbol))
		elif symbol == "+":
			glyphs.append(10)
		elif symbol == "×":
			glyphs.append(11)
	if glyphs.is_empty() or size.x <= 0 or size.y <= 0:
		return
	var glyph_width := minf(size.y * 0.72, size.x / glyphs.size())
	var height := minf(size.y, glyph_width / 0.72)
	var start := (size.x - glyph_width * glyphs.size()) * 0.5 if centered else 0.0
	for index in glyphs.size():
		var sprite := TextureRect.new()
		sprite.texture = Art.texture("digit_%d" % glyphs[index])
		sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sprite.position = Vector2(start + index * glyph_width, (size.y - height) * 0.5)
		sprite.size = Vector2(glyph_width, height)
		add_child(sprite)
