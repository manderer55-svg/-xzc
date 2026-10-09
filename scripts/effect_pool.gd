class_name EffectPool
extends Control
## Bounded generated-frame effects. Playback never creates nodes, tweens or timers.

const FULL_CAPACITY := 24
const REDUCED_CAPACITY := 8
const FRAME_COUNT := 4
const DURATION := 0.4
const PREFIXES := ["fx_explosion", "fx_lightning", "fx_frost", "fx_dust"]

var _sprites: Array[TextureRect] = []
var _frames: Dictionary = {}
var _ages := PackedFloat32Array()
var _running := PackedByteArray()
var _frame_indices := PackedInt32Array()
var _effect_kinds := PackedInt32Array()
var _capacity := 0
var _active := 0
var _created := 0

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)

func configure(reduced: bool) -> void:
	clear()
	_capacity = REDUCED_CAPACITY if reduced else FULL_CAPACITY
	for prefix: String in PREFIXES:
		if _frames.has(prefix):
			continue
		var textures: Array[Texture2D] = []
		for frame in FRAME_COUNT:
			textures.append(Art.texture(prefix + "_%d" % frame))
		_frames[prefix] = textures
	# Warm every slot even if startup uses reduced effects. Quality changes never
	# allocate nodes; inactive slots stay hidden and cannot be admitted by play.
	while _sprites.size() < FULL_CAPACITY:
		var sprite := TextureRect.new()
		sprite.name = "PooledEffect%d" % _sprites.size()
		sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sprite.stretch_mode = TextureRect.STRETCH_SCALE
		sprite.visible = false
		add_child(sprite)
		_sprites.append(sprite)
		_ages.append(0.0)
		_running.append(0)
		_frame_indices.append(-1)
		_effect_kinds.append(0)
		_created += 1

func play(prefix: String, center: Vector2, dimensions: Vector2, angle: float = 0.0) -> bool:
	if not _frames.has(prefix) or _active >= _capacity:
		return false
	var index := -1
	for candidate in _capacity:
		if _running[candidate] == 0:
			index = candidate
			break
	if index < 0:
		return false
	var sprite := _sprites[index]
	var extent := Vector2(maxf(1.0, dimensions.x), maxf(1.0, dimensions.y))
	sprite.size = extent
	sprite.position = center - extent * 0.5
	sprite.pivot_offset = extent * 0.5
	sprite.rotation = angle
	sprite.scale = Vector2.ONE * 0.75
	sprite.modulate = Color.WHITE
	sprite.self_modulate = Color.WHITE
	sprite.texture = _frames[prefix][0]
	sprite.visible = true
	_ages[index] = 0.0
	_running[index] = 1
	_frame_indices[index] = 0
	_effect_kinds[index] = PREFIXES.find(prefix)
	_active += 1
	set_process(true)
	return true

func _process(delta: float) -> void:
	for index in _capacity:
		if _running[index] == 0:
			continue
		_ages[index] += maxf(0.0, delta)
		var progress := minf(1.0, _ages[index] / DURATION)
		var sprite := _sprites[index]
		if progress >= 1.0:
			_running[index] = 0
			sprite.visible = false
			_active -= 1
			continue
		var frame := mini(FRAME_COUNT - 1, int(progress * FRAME_COUNT))
		if frame != _frame_indices[index]:
			sprite.texture = _frames[PREFIXES[_effect_kinds[index]]][frame]
			_frame_indices[index] = frame
		var eased := 1.0 - pow(1.0 - progress, 2.0)
		sprite.scale = Vector2.ONE * lerpf(0.75, 1.18, eased)
		sprite.modulate.a = 1.0 - clampf((progress - 0.45) / 0.55, 0.0, 1.0)
	if _active == 0:
		set_process(false)

func clear() -> void:
	for index in _sprites.size():
		_running[index] = 0
		_ages[index] = 0.0
		_frame_indices[index] = -1
		var sprite := _sprites[index]
		sprite.visible = false
		sprite.scale = Vector2.ONE
		sprite.rotation = 0.0
		sprite.modulate = Color.WHITE
		sprite.texture = null
	_active = 0
	set_process(false)

func stats() -> Dictionary:
	return {"created": _created, "capacity": _capacity, "active": _active}
