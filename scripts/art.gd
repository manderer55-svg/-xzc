class_name Art
extends RefCounted
## Every visual skin is an image-generation output. AtlasTexture selects regions
## without redrawing, filtering, or baking replacement artwork in code.

static var _cache: Dictionary = {}
static var _atlases: Dictionary = {}
const ROOT := "res://art/darkfantasy/"
const GEM_NAMES := ["gem_0", "gem_1", "gem_2", "gem_3", "gem_4", "gem_5",
	"special_row", "special_column", "special_bomb", "special_nova",
	"blocker_stone", "blocker_ice", "cell", "selection", "coin", "portal"]
const BUILDING_NAMES := ["ground", "quarry", "sawmill", "shrine", "fortress",
	"stone", "wood", "essence", "settlement_portal"]
const UI_REGIONS := {
	"ui_header": Rect2(8, 0, 684, 315),
	"ui_panel": Rect2(696, 58, 558, 251),
	"ui_button": Rect2(10, 350, 680, 203),
	"ui_small_button": Rect2(700, 377, 544, 184),
	"ui_result": Rect2(14, 548, 680, 365),
	"ui_badge": Rect2(694, 650, 550, 216),
	"ui_progress": Rect2(13, 992, 725, 170),
	"ui_slot": Rect2(812, 910, 294, 294),
}

static func texture(asset_name: String) -> Texture2D:
	if _cache.has(asset_name):
		return _cache[asset_name]
	var result: Texture2D
	if asset_name in ["background", "settlement_background", "icon"]:
		result = load(ROOT + asset_name + ".png") as Texture2D
	elif GEM_NAMES.has(asset_name):
		result = _grid_region("gems", GEM_NAMES.find(asset_name), 4, 4)
	elif BUILDING_NAMES.has(asset_name):
		result = _grid_region("settlement", BUILDING_NAMES.find(asset_name), 3, 3)
	elif UI_REGIONS.has(asset_name):
		var source := _atlas("ui")
		var source_rect: Rect2 = UI_REGIONS[asset_name]
		var ratio := source.get_size() / Vector2(1254, 1254)
		result = _region(source, Rect2(source_rect.position * ratio, source_rect.size * ratio))
	elif asset_name.begins_with("fx_"):
		var parts := asset_name.split("_")
		var kinds := ["explosion", "lightning", "frost", "dust"]
		if parts.size() == 3 and kinds.has(parts[1]):
			result = _grid_region("effects", kinds.find(parts[1]) * 4 + int(parts[2]), 4, 4)
	elif asset_name.begins_with("digit_"):
		result = _grid_region("digits", int(asset_name.trim_prefix("digit_")), 4, 3)
	if result == null:
		push_error("Unknown generated asset: " + asset_name)
		return null
	_cache[asset_name] = result
	return result

static func _atlas(atlas_name: String) -> Texture2D:
	if not _atlases.has(atlas_name):
		_atlases[atlas_name] = load(ROOT + atlas_name + ".png") as Texture2D
	return _atlases[atlas_name]

static func _grid_region(atlas_name: String, index: int, columns: int, rows: int) -> AtlasTexture:
	var source := _atlas(atlas_name)
	var cell_size := source.get_size() / Vector2(columns, rows)
	var top_left := Vector2(index % columns, int(index / columns)) * cell_size
	return _region(source, Rect2(top_left, cell_size))

static func _region(source: Texture2D, bounds: Rect2) -> AtlasTexture:
	var region := AtlasTexture.new()
	region.atlas = source
	region.region = bounds
	region.filter_clip = true
	return region
