class_name GeneratedFrame
extends NinePatchRect
## Generated artwork is sliced into fixed corners and four stretching edges.
## A uniform source-to-canvas scale preserves border thickness at every size.

var frame_key := ""
var artwork_scale := 1.0


func configure(key: String, dimensions: Vector2) -> void:
	var spec: Dictionary = Art.frame_spec(key)
	frame_key = key
	texture = spec.texture
	var margins: Vector4 = spec.margins
	patch_margin_left = int(margins.x)
	patch_margin_top = int(margins.y)
	patch_margin_right = int(margins.z)
	patch_margin_bottom = int(margins.w)
	artwork_scale = float(spec.scale)
	scale = Vector2.ONE * artwork_scale
	axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_STRETCH
	axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_STRETCH
	draw_center = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_display_size(dimensions)


func minimum_display_size() -> Vector2:
	return Vector2(patch_margin_left + patch_margin_right,
		patch_margin_top + patch_margin_bottom) * artwork_scale


func displayed_border_widths() -> Vector4:
	return Vector4(patch_margin_left, patch_margin_top,
		patch_margin_right, patch_margin_bottom) * artwork_scale


func set_display_size(dimensions: Vector2) -> void:
	# Never shrink past both opposing corner slices: that would overlap them.
	var minimum := minimum_display_size()
	size = Vector2(maxf(dimensions.x, minimum.x),
		maxf(dimensions.y, minimum.y)) / artwork_scale
