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
const POWER_NAMES := ["special_row", "special_column", "special_bomb", "special_nova"]
const CAMPAIGN_NAMES := ["boss_portrait", "altar", "altar_lit", "forest_badge"]
const SEAL_NAMES := ["blocker_stone", "blocker_ice", "selection", "coin"]
## A common selection preserves every visible crystal face and its proportions.
## The originals remain untouched; only transparent atlas gutters are omitted.
const GEM_REGION := Rect2(16, 0, 480, 480)
const DIGIT_REGIONS := [Rect2(77, 33, 266, 310), Rect2(449, 28, 200, 313),
	Rect2(772, 31, 251, 307), Rect2(1126, 29, 244, 318), Rect2(71, 388, 269, 316),
	Rect2(433, 388, 240, 318), Rect2(766, 388, 260, 320), Rect2(1135, 389, 238, 311),
	Rect2(69, 733, 264, 319), Rect2(425, 730, 254, 319), Rect2(759, 757, 283, 272),
	Rect2(1116, 773, 256, 249)]
const UI_REGIONS := {
	"ui_header": Rect2(29, 124, 381, 128),
	"ui_panel": Rect2(435, 100, 387, 174),
	"ui_button": Rect2(847, 120, 381, 140),
	"ui_small_button": Rect2(29, 527, 382, 141),
	"ui_result": Rect2(436, 414, 385, 361),
	"ui_badge": Rect2(847, 498, 381, 194),
	"ui_progress": Rect2(29, 963, 381, 78),
	"ui_progress_fill": Rect2(877, 148, 319, 84),
	"ui_slot": Rect2(438, 819, 378, 365),
	"cell": Rect2(850, 817, 375, 365),
}

static func texture(asset_name: String) -> Texture2D:
	if _cache.has(asset_name):
		return _cache[asset_name]
	var result: Texture2D
	if asset_name in ["background", "settlement_background", "icon", "board_frame", "forest_background", "home_background"]:
		result = load(ROOT + asset_name + ".png") as Texture2D
	elif asset_name.begins_with("gem_") and asset_name.trim_prefix("gem_").is_valid_int():
		var source := _atlas("gems_clean")
		var gem_index := int(asset_name.trim_prefix("gem_"))
		var cell_size := source.get_size() / Vector2(3, 2)
		var origin := Vector2(gem_index % 3, int(gem_index / 3)) * cell_size
		var ratio := source.get_size() / Vector2(1536, 1024)
		result = _region(source, Rect2(origin + GEM_REGION.position * ratio, GEM_REGION.size * ratio))
	elif POWER_NAMES.has(asset_name):
		result = _grid_region("powers_readable", POWER_NAMES.find(asset_name), 2, 2)
	elif CAMPAIGN_NAMES.has(asset_name):
		result = _grid_region("campaign", CAMPAIGN_NAMES.find(asset_name), 2, 2)
	elif SEAL_NAMES.has(asset_name):
		result = _grid_region("seals_clean", SEAL_NAMES.find(asset_name), 2, 2)
	elif UI_REGIONS.has(asset_name):
		var source := _atlas("ui_clean")
		var source_rect: Rect2 = UI_REGIONS[asset_name]
		var ratio := source.get_size() / Vector2(1254, 1254)
		result = _region(source, Rect2(source_rect.position * ratio, source_rect.size * ratio))
	elif GEM_NAMES.has(asset_name):
		result = _grid_region("gems", GEM_NAMES.find(asset_name), 4, 4)
	elif BUILDING_NAMES.has(asset_name):
		result = _grid_region("settlement", BUILDING_NAMES.find(asset_name), 3, 3)
	elif asset_name.begins_with("fx_"):
		var parts := asset_name.split("_")
		var kinds := ["explosion", "lightning", "frost", "dust"]
		if parts.size() == 3 and kinds.has(parts[1]):
			result = _grid_region("effects", kinds.find(parts[1]) * 4 + int(parts[2]), 4, 4)
	elif asset_name.begins_with("digit_"):
		var source := _atlas("digits_clean")
		var digit_index := int(asset_name.trim_prefix("digit_"))
		if digit_index >= 0 and digit_index < DIGIT_REGIONS.size():
			var bounds: Rect2 = DIGIT_REGIONS[digit_index]
			var ratio := source.get_size() / Vector2(1448, 1086)
			result = _region(source, Rect2(bounds.position * ratio, bounds.size * ratio))
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
