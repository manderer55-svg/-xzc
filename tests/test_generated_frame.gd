extends SceneTree

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func _run() -> void:
	for key in ["ui_header", "ui_panel", "ui_result", "ui_button", "ui_small_button", "ui_badge", "ui_slot", "ui_progress"]:
		var frame := GeneratedFrame.new()
		root.add_child(frame)
		var dimensions := Vector2(379, 15) if key == "ui_progress" else Vector2(207, 112)
		frame.configure(key, dimensions)
		var spec: Dictionary = Art.frame_spec(key)
		var margins: Vector4 = spec.margins
		var expected := margins * float(spec.scale)
		_check(frame.texture is AtlasTexture, key + ": selects original atlas artwork")
		_check(frame.texture == spec.texture, key + ": uses the original generated texture")
		_check(frame.displayed_border_widths().is_equal_approx(expected), key + ": source corner widths preserved")
		_check((frame.size * frame.scale).is_equal_approx(dimensions), key + ": requested compact size retained")
		_check(frame.mouse_filter == Control.MOUSE_FILTER_IGNORE, key + ": frame cannot intercept button input")
		var original_texture := frame.texture
		var original_scale := frame.scale
		frame.set_display_size(Vector2(640, 796))
		_check(frame.texture == original_texture, key + ": resizing retains its atlas region")
		_check(frame.scale == original_scale, key + ": modal uses the same artwork scale as compact panel")
		_check(frame.displayed_border_widths().is_equal_approx(expected), key + ": large modal corners keep their width")
		_check((frame.size * frame.scale).is_equal_approx(Vector2(640, 796)), key + ": modal reaches requested size")
		frame.set_display_size(Vector2(1, 1))
		_check((frame.size * frame.scale).is_equal_approx(frame.minimum_display_size()), key + ": prevents overlapping corner slices")
		frame.free()
	if DisplayServer.get_name() != "headless":
		await _check_rendered_corners()
	if failures.is_empty():
		print("PASS: %d generated-frame fixed-corner checks." % checks)
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
		quit(1)


func _check_rendered_corners() -> void:
	# Rendering compares the same generated corner pixels at different panel
	# widths AND heights. No test artwork is drawn or baked into the skin.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(900, 680)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var compact := _preview_frame(viewport, "ui_panel", Vector2(20, 20), Vector2(207, 112))
	var wide := _preview_frame(viewport, "ui_panel", Vector2(260, 20), Vector2(600, 112))
	var tall := _preview_frame(viewport, "ui_panel", Vector2(260, 170), Vector2(600, 310))
	_preview_frame(viewport, "ui_button", Vector2(20, 520), Vector2(207, 112))
	_preview_frame(viewport, "ui_button", Vector2(260, 520), Vector2(600, 112))
	await process_frame
	await RenderingServer.frame_post_draw
	var rendered := viewport.get_texture().get_image()
	var border := int(compact.displayed_border_widths().x)
	var maximum_delta := 0.0
	for comparison in [wide, tall]:
		for corner in [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.ONE]:
			var original_bounds := _corner_bounds(compact, corner, border)
			var comparison_bounds := _corner_bounds(comparison, corner, border)
			var delta := _maximum_pixel_delta(rendered.get_region(original_bounds), rendered.get_region(comparison_bounds))
			maximum_delta = maxf(maximum_delta, delta)
			# A one-channel rounding unit accommodates GPU texture sampling.
			_check(delta <= 1.0 / 255.0 + 0.0001, "rendered %s corner %s retains its pixels" % [comparison.size * comparison.scale, corner])
	var preview_dir := ProjectSettings.globalize_path("res://art/preview")
	DirAccess.make_dir_recursive_absolute(preview_dir)
	_check(rendered.save_png(preview_dir.path_join("frames.png")) == OK, "saves native nine-slice comparison preview")
	print("FRAME_RENDER_OK corner_pixels=", border, " max_channel_delta=", maximum_delta)
	viewport.queue_free()
	await process_frame


func _preview_frame(parent: Node, key: String, position: Vector2, dimensions: Vector2) -> GeneratedFrame:
	var frame := GeneratedFrame.new()
	frame.configure(key, dimensions)
	frame.position = position
	parent.add_child(frame)
	return frame


func _corner_bounds(frame: GeneratedFrame, corner: Vector2i, border: int) -> Rect2i:
	var dimensions := Vector2i(frame.size * frame.scale)
	var origin := Vector2i(frame.position) + Vector2i(corner.x * (dimensions.x - border), corner.y * (dimensions.y - border))
	return Rect2i(origin, Vector2i.ONE * border)


func _maximum_pixel_delta(a: Image, b: Image) -> float:
	var maximum := 0.0
	for y in range(a.get_height()):
		for x in range(a.get_width()):
			var first := a.get_pixel(x, y)
			var second := b.get_pixel(x, y)
			maximum = maxf(maximum, maxf(absf(first.r - second.r), absf(first.g - second.g)))
			maximum = maxf(maximum, maxf(absf(first.b - second.b), absf(first.a - second.a)))
	return maximum
