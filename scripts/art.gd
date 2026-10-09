class_name Art
extends RefCounted
## Every visual skin is an image-generation output. AtlasTexture selects regions
## without redrawing, filtering, or baking replacement artwork in code.

static var _cache: Dictionary = {}
static var _atlases: Dictionary = {}
static var _contour_cache: Dictionary = {}
const ROOT := "res://art/darkfantasy/"
const GEM_NAMES := ["gem_0", "gem_1", "gem_2", "gem_3", "gem_4", "gem_5",
	"special_row", "special_column", "special_bomb", "special_nova",
	"blocker_stone", "blocker_ice", "cell", "selection", "coin", "portal"]
const BUILDING_NAMES := ["ground", "quarry", "sawmill", "shrine", "fortress",
	"stone", "wood", "essence", "settlement_portal"]
const POWER_NAMES := ["special_row", "special_column", "special_bomb", "special_nova"]
const CAMPAIGN_NAMES := ["boss_portrait", "altar", "altar_lit", "forest_badge"]
const SEAL_NAMES := ["blocker_stone", "blocker_ice", "selection", "coin"]
const FRAME_REGIONS := [Rect2(72, 93, 525, 496), Rect2(659, 93, 525, 496),
	Rect2(73, 665, 525, 497), Rect2(659, 665, 525, 497)]
const FRAME_KEYS := {"ui_header": 0, "ui_panel": 0, "ui_result": 0,
	"ui_badge": 0, "ui_button": 2, "ui_small_button": 1,
	"ui_slot": 3, "cell": 3, "ui_progress": 3}
## A common selection preserves every visible crystal face and its proportions.
## The originals remain untouched; only transparent atlas gutters are omitted.
const GEM_REGION := Rect2(16, 0, 480, 480)
const DIGIT_REGIONS := [Rect2(77, 33, 266, 310), Rect2(449, 28, 200, 313),
	Rect2(772, 31, 251, 307), Rect2(1126, 29, 244, 318), Rect2(71, 388, 269, 316),
	Rect2(433, 388, 240, 318), Rect2(766, 388, 260, 320), Rect2(1135, 389, 238, 311),
	Rect2(69, 733, 264, 319), Rect2(425, 730, 254, 319), Rect2(759, 757, 283, 272),
	Rect2(1116, 773, 256, 249)]

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
	elif FRAME_KEYS.has(asset_name):
		result = _region(_atlas("ui_nine_slice"), FRAME_REGIONS[int(FRAME_KEYS[asset_name])])
	elif asset_name == "ui_progress_fill":
		result = _region(_atlas("ui_nine_slice"), Rect2(140, 730, 400, 130))
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

static func frame_spec(asset_name: String) -> Dictionary:
	if not FRAME_KEYS.has(asset_name):
		return {}
	return {"texture": texture(asset_name), "margins": Vector4(54, 54, 54, 54),
		"scale": 0.1 if asset_name == "ui_progress" else 0.5}

static func contour_spec() -> Dictionary:
	if not _contour_cache.is_empty():
		return _contour_cache
	var source := _atlas("contour_edges")
	_contour_cache = {"edge": _region(source, Rect2(90, 306, 460, 36)),
		"convex": _region(source, Rect2(796, 160, 328, 328)),
		"concave": _region(source, Rect2(156, 787, 328, 328)),
		"edge_height": 4.2, "corner_size": 40.0, "edge_overlap": 1.5}
	return _contour_cache

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
