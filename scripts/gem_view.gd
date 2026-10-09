class_name GemView
extends Control
## A reusable board sprite. All layers are generated artwork and survive reuse.

var altar_sprite: TextureRect
var gem_sprite: TextureRect
var special_sprite: TextureRect
var blocker_sprite: TextureRect
var exit_sprite: TextureRect
var hp_sprites: Array[TextureRect] = []

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	altar_sprite = _layer("Altar")
	gem_sprite = _layer("Gem")
	special_sprite = _layer("Special")
	blocker_sprite = _layer("Blocker")
	exit_sprite = _layer("Exit")
	hp_sprites.append(_layer("HPLeft"))
	hp_sprites.append(_layer("HPRight"))

func _layer(layer_name: String) -> TextureRect:
	var sprite := TextureRect.new()
	sprite.name = layer_name
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.visible = false
	add_child(sprite)
	return sprite

func configure(data: Dictionary, blocker: Variant, tile_size: float, altar_state: Variant = null, exit_cell: bool = false) -> void:
	var extent := maxf(1.0, tile_size)
	size = Vector2.ONE * extent
	pivot_offset = size * 0.5
	scale = Vector2.ONE
	rotation = 0.0
	modulate = Color.WHITE
	self_modulate = Color.WHITE
	visible = true
	for sprite: TextureRect in [altar_sprite, gem_sprite, special_sprite, blocker_sprite, exit_sprite]:
		sprite.modulate = Color.WHITE
		sprite.scale = Vector2.ONE
		sprite.rotation = 0.0
		sprite.texture = null
		sprite.visible = false
	for sprite in hp_sprites:
		sprite.texture = null
		sprite.visible = false
		sprite.modulate = Color.WHITE
		sprite.scale = Vector2.ONE
		sprite.rotation = 0.0
	_place(altar_sprite, extent, 0.025, 0.95)
	_place(gem_sprite, extent, 0.07, 0.86)
	_place(special_sprite, extent, 0.025, 0.95)
	_place(blocker_sprite, extent, 0.025, 0.95)
	exit_sprite.position = Vector2.ONE * extent * 0.73
	exit_sprite.size = Vector2.ONE * extent * 0.25
	if exit_cell:
		exit_sprite.texture = Art.texture("relic_exit")
		exit_sprite.visible = true

	if altar_state != null:
		altar_sprite.visible = true
		var completed := bool(altar_state) if altar_state is bool else false
		if altar_state is Dictionary:
			completed = bool(altar_state.get("completed", altar_state.get("cleared", false)))
		altar_sprite.texture = Art.texture("altar_lit" if completed else "altar")
		_place(gem_sprite, extent, 0.125, 0.75)

	if not data.is_empty():
		gem_sprite.texture = Art.texture("relic" if bool(data.get("relic", false)) else "gem_%d" % clampi(int(data.get("color", 0)), 0, 5))
		gem_sprite.visible = true
		var special := String(data.get("special", ""))
		if special in ["row", "column", "bomb", "nova"]:
			special_sprite.texture = Art.texture("special_" + special)
			special_sprite.visible = true

	if blocker == null or (blocker is bool and not blocker):
		return
	var hp := 1
	var kind := "ice"
	if blocker is Dictionary:
		hp = int(blocker.get("hp", 1))
		kind = String(blocker.get("kind", blocker.get("type", "ice")))
	else:
		hp = int(blocker)
		kind = "stone" if hp > 1 else "ice"
	if hp <= 0:
		return
	if kind not in ["stone", "ice", "frost", "lava"]:
		kind = "ice"
	blocker_sprite.texture = Art.texture("blocker_" + kind)
	blocker_sprite.visible = true
	if hp > 1:
		var digits := str(mini(hp, 99))
		var digit_width := extent * 0.18
		var digit_height := extent * 0.27
		var start := extent * 0.9 - digit_width * digits.length()
		for index in digits.length():
			var sprite := hp_sprites[index]
			sprite.position = Vector2(start + index * digit_width, extent * 0.66)
			sprite.size = Vector2(digit_width, digit_height)
			sprite.texture = Art.texture("digit_%d" % int(digits[index]))
			sprite.visible = true

func _place(sprite: TextureRect, extent: float, inset: float, fraction: float) -> void:
	sprite.position = Vector2.ONE * extent * inset
	sprite.size = Vector2.ONE * extent * fraction
	sprite.pivot_offset = sprite.size * 0.5
