extends SceneTree

const GemSprite = preload("res://scripts/gem_view.gd")
const FXPool = preload("res://scripts/effect_pool.gd")
var checks := 0
var completed_sections := 0
var failures: Array[String] = []

func _initialize() -> void:
	_test_gem_reuse()
	_test_effect_pool()
	_check(completed_sections == 2, "all pool test sections executed")
	if failures.is_empty():
		print("PASS: %d UI pool checks (100 gem reuses, 4,800 FX plays, caps, frame advance, stable node IDs)." % checks)
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
		quit(1)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func _test_gem_reuse() -> void:
	var gem = GemSprite.new()
	root.add_child(gem)
	var layer_ids: Array[int] = []
	for child in gem.get_children():
		layer_ids.append(child.get_instance_id())
	for iteration in 100:
		gem.configure({"color": iteration % 6, "special": "bomb"}, {"kind": "stone", "hp": 12}, 70.0)
		_check(gem.special_sprite.visible, "special layer visible during reuse %d" % iteration)
		_check(gem.blocker_sprite.visible, "blocker layer visible during reuse %d" % iteration)
		_check(gem.hp_sprites[0].visible and gem.hp_sprites[1].visible, "two-digit blocker HP visible during reuse %d" % iteration)
		gem.scale = Vector2.ONE * 0.4
		gem.rotation = 1.2
		gem.modulate.a = 0.2
		gem.configure({"color": 2, "special": ""}, null, 64.0)
		_check(gem.scale == Vector2.ONE, "scale reset during reuse %d" % iteration)
		_check(gem.rotation == 0.0, "rotation reset during reuse %d" % iteration)
		_check(gem.modulate == Color.WHITE, "opacity reset during reuse %d" % iteration)
		_check(not gem.special_sprite.visible, "old special hidden during reuse %d" % iteration)
		_check(not gem.blocker_sprite.visible, "old blocker hidden during reuse %d" % iteration)
		_check(not gem.hp_sprites[0].visible and not gem.hp_sprites[1].visible, "old blocker HP hidden during reuse %d" % iteration)
		gem.configure({"color": 3, "special": ""}, null, 64.0, false)
		_check(gem.altar_sprite.visible, "unlit altar visible during reuse %d" % iteration)
		_check(gem.altar_sprite.texture == Art.texture("altar"), "unlit altar texture reset during reuse %d" % iteration)
		_check(gem.gem_sprite.size == Vector2.ONE * 48.0, "gem inset leaves altar readable during reuse %d" % iteration)
		gem.configure({"color": 3, "special": ""}, null, 64.0, true)
		_check(gem.altar_sprite.visible, "lit altar visible during reuse %d" % iteration)
		_check(gem.altar_sprite.texture == Art.texture("altar_lit"), "lit altar texture reset during reuse %d" % iteration)
		gem.configure({"color": 3, "special": ""}, null, 64.0, null)
		_check(not gem.altar_sprite.visible, "old altar hidden during reuse %d" % iteration)
	_check(gem.get_child_count() == 6, "gem reuse preserves six layers")
	_check(gem.get_child_count() == layer_ids.size(), "gem child count remains stable")
	for index in mini(gem.get_child_count(), layer_ids.size()):
		_check(gem.get_child(index).get_instance_id() == layer_ids[index], "gem layer %d retains node ID" % index)
	gem.queue_free()
	completed_sections += 1

func _test_effect_pool() -> void:
	var pool = FXPool.new()
	root.add_child(pool)
	pool.configure(true)
	_check(pool.stats() == {"created": 24, "capacity": 8, "active": 0}, "reduced startup warms all 24 nodes and permits only eight effects")
	var effect_ids: Array[int] = []
	for child in pool.get_children():
		effect_ids.append(child.get_instance_id())
		_check(child.stretch_mode == TextureRect.STRETCH_SCALE, "effect sprite preserves full lightning dimensions")
	pool.configure(false)
	_check(pool.stats() == {"created": 24, "capacity": 24, "active": 0}, "full quality reuses warmed pool")
	for round_index in 200:
		for effect in 24:
			_check(pool.play(FXPool.PREFIXES[effect % 4], Vector2(30, 40), Vector2(60, 70), PI / 2), "effect %d admitted in round %d" % [effect, round_index])
		_check(not pool.play("fx_explosion", Vector2.ZERO, Vector2.ONE), "full pool rejects overflow in round %d" % round_index)
		_check(pool.stats().active == 24, "full pool keeps 24 active effects in round %d" % round_index)
		pool._process(0.11)
		if pool.get_child_count() > 0:
			_check(pool.get_child(0).texture == Art.texture("fx_explosion_1"), "effect frame advances in round %d" % round_index)
		else:
			_check(false, "pool contains a sprite for frame advance")
		pool._process(0.30)
		_check(pool.stats().active == 0, "expired effects retire in round %d" % round_index)
		_check(pool.stats().created == 24, "round %d creates no new effects" % round_index)
		_check(pool.get_child_count() == 24, "round %d retains 24 effect nodes" % round_index)
	pool.configure(true)
	_check(pool.stats() == {"created": 24, "capacity": 8, "active": 0}, "quality reduction keeps warmed sprites")
	for effect in 8:
		_check(pool.play("fx_frost", Vector2.ZERO, Vector2.ONE), "reduced effect %d admitted" % effect)
	_check(not pool.play("fx_frost", Vector2.ZERO, Vector2.ONE), "reduced pool rejects ninth effect")
	pool.clear()
	_check(pool.stats().active == 0, "clear retires all effects")
	_check(not pool.is_processing(), "idle pool stops processing")
	pool.configure(false)
	_check(pool.get_child_count() == effect_ids.size(), "quality toggle preserves effect count")
	for index in mini(pool.get_child_count(), effect_ids.size()):
		_check(pool.get_child(index).get_instance_id() == effect_ids[index], "effect sprite %d retains node ID" % index)
	_check(not pool.play("unknown", Vector2.ZERO, Vector2.ONE), "unknown effect kinds are rejected")
	pool.queue_free()
	completed_sections += 1
