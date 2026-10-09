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
const REGIONAL_NAMES := ["boss_ice", "boss_lava", "blocker_frost", "blocker_lava", "relic", "relic_exit"]
const REGIONAL_REGIONS := [Rect2(0, 0, 512, 590), Rect2(512, 0, 512, 590),
	Rect2(60, 590, 420, 410), Rect2(545, 590, 440, 410),
	Rect2(10, 1005, 502, 500), Rect2(530, 1005, 480, 500)]
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

const CITY_KEYS := ["quarry", "sawmill", "shrine", "fortress", "forge", "watchtower", "townhall", "citadel", "alliance_hall", "market", "stable", "barracks", "archery", "tavern", "alliance_store"]
const CITY_REGIONS := [Rect2(16, 22, 407, 343), Rect2(434, 28, 407, 360), Rect2(857, 44, 400, 336),
 Rect2(15, 379, 428, 416), Rect2(463, 450, 447, 351), Rect2(943, 389, 264, 427),
 Rect2(20, 795, 416, 415), Rect2(448, 846, 459, 364), Rect2(924, 986, 332, 214)]
const EXTRA_REGIONS := [Rect2(66, 5, 438, 375), Rect2(569, 35, 413, 320), Rect2(1041, 61, 459, 303),
 Rect2(62, 388, 432, 279), Rect2(553, 378, 455, 296), Rect2(1079, 383, 426, 282),
 Rect2(72, 678, 434, 310), Rect2(572, 680, 490, 310)]
const GROUND_REGIONS := [Rect2(3, 108, 417, 244), Rect2(419, 108, 416, 244), Rect2(836, 108, 416, 244),
 Rect2(1, 492, 418, 249), Rect2(419, 492, 417, 249), Rect2(834, 492, 419, 249),
 Rect2(3, 881, 416, 248), Rect2(419, 879, 416, 249), Rect2(836, 880, 416, 248)]
const NATURE_REGIONS := [Rect2(76, 37, 305, 385), Rect2(468, 61, 389, 355), Rect2(923, 109, 368, 304), Rect2(1372, 118, 365, 294),
 Rect2(57, 494, 348, 332), Rect2(469, 504, 397, 325), Rect2(918, 531, 387, 285), Rect2(1363, 540, 371, 290)]
const HERO_REGIONS := [Rect2(16, 30, 442, 403), Rect2(464, 15, 434, 418), Rect2(900, 15, 426, 416), Rect2(1329, 40, 429, 393)]
const TROOP_REGIONS := [Rect2(10, 441, 424, 432), Rect2(460, 441, 408, 428), Rect2(895, 428, 442, 444)]
const BUNKER_REGIONS := [Rect2(22, 13, 732, 448), Rect2(790, 30, 725, 444), Rect2(17, 480, 753, 523), Rect2(781, 476, 742, 521)]

static func texture(asset_name: String) -> Texture2D:
	if _cache.has(asset_name):
		return _cache[asset_name]
	var result: Texture2D
	if asset_name.begins_with("iso_tile_"):
		result = _region(_atlas("iso_ground"), GROUND_REGIONS[clampi(int(asset_name.trim_prefix("iso_tile_")), 0, 8)])
	elif asset_name.begins_with("iso_decor_"):
		result = _region(_atlas("iso_nature"), NATURE_REGIONS[clampi(int(asset_name.trim_prefix("iso_decor_")), 0, 7)])
	elif asset_name.begins_with("hero_world_"):
		var parts := asset_name.split("_")
		var source := _atlas("hero_world_cartoon")
		var row := int(parts[2])
		var starts := [0.0, 298.0, 596.0, 904.0]
		var heights := [294.0, 294.0, 307.0, 334.0]
		result = _region(source, Rect2(int(parts[3]) * source.get_width() / 4.0, starts[row], source.get_width() / 4.0, heights[row]))
	elif asset_name.begins_with("hero_"):
		result = _region(_atlas("heroes_cartoon"), HERO_REGIONS[clampi(int(asset_name.trim_prefix("hero_")), 0, 3)])
	elif asset_name.begins_with("troop_"):
		result = _region(_atlas("heroes_cartoon"), TROOP_REGIONS[clampi(int(asset_name.trim_prefix("troop_")), 0, 2)])
	elif asset_name == "alliance_crest":
		result = _region(_atlas("heroes_cartoon"), Rect2(1392, 445, 360, 418))
	elif asset_name in CITY_KEYS:
		var index := CITY_KEYS.find(asset_name)
		result = _region(_atlas("city_cartoon"), CITY_REGIONS[index]) if index <= 6 else _region(_atlas("city_extra_cartoon"), EXTRA_REGIONS[index - 7])
	elif asset_name == "settlement_background":
		result = load(ROOT + "colony_terrain.png") as Texture2D
	elif asset_name == "ore_site":
		result = _region(_atlas("city_cartoon"), CITY_REGIONS[8])
	elif asset_name == "warehouse":
		result = _region(_atlas("city_cartoon"), CITY_REGIONS[7])
	elif asset_name.begins_with("bunker_"):
		result = _region(_atlas("bunker_cartoon"), BUNKER_REGIONS[clampi(int(asset_name.trim_prefix("bunker_")), 0, 3)])
	elif asset_name.begins_with("worker_"):
		var parts := asset_name.split("_")
		var index := int(parts[1]) * 8 + int(parts[2])
		var region := _grid_region("troops_cartoon", index, 8, 5)
		region.region = region.region.grow(-4)
		result = region
	elif asset_name in ["background", "icon", "board_frame", "forest_background", "home_background", "ice_background", "lava_background"]:
		result = load(ROOT + asset_name + ".png") as Texture2D
	elif asset_name.begins_with("gem_") and asset_name.trim_prefix("gem_").is_valid_int():
		var source := _atlas("gems_shapes")
		var gem_index := int(asset_name.trim_prefix("gem_"))
		var cell_size := source.get_size() / Vector2(3, 2)
		var origin := Vector2(gem_index % 3, int(gem_index / 3)) * cell_size
		var ratio := source.get_size() / Vector2(1536, 1024)
		result = _region(source, Rect2(origin + GEM_REGION.position * ratio, GEM_REGION.size * ratio))
	elif POWER_NAMES.has(asset_name):
		result = _grid_region("powers_clean", POWER_NAMES.find(asset_name), 2, 2)
	elif REGIONAL_NAMES.has(asset_name):
		result = _region(_atlas("regional_objects"), REGIONAL_REGIONS[REGIONAL_NAMES.find(asset_name)])
	elif asset_name in ["forge", "watchtower"]:
		result = _grid_region("mine_structures", 5 if asset_name == "forge" else 6, 3, 3)
	elif CAMPAIGN_NAMES.has(asset_name):
		result = _grid_region("campaign_clean", CAMPAIGN_NAMES.find(asset_name), 2, 2)
	elif SEAL_NAMES.has(asset_name):
		result = _grid_region("seals_clean", SEAL_NAMES.find(asset_name), 2, 2)
	elif FRAME_KEYS.has(asset_name):
		result = _region(_atlas("ui_nine_slice"), FRAME_REGIONS[int(FRAME_KEYS[asset_name])])
	elif asset_name == "ui_progress_fill":
		result = _region(_atlas("ui_nine_slice"), Rect2(140, 730, 400, 130))
	elif asset_name == "portal":
		result = _grid_region("settlement_clean", 8, 3, 3)
	elif GEM_NAMES.has(asset_name):
		result = _grid_region("gems", GEM_NAMES.find(asset_name), 4, 4)
	elif BUILDING_NAMES.has(asset_name):
		var index := BUILDING_NAMES.find(asset_name)
		result = _grid_region("mine_structures", index, 3, 3) if index <= 4 else _grid_region("settlement_clean", index, 3, 3)
	elif asset_name.begins_with("fx_shards_"):
		var parts := asset_name.split("_")
		if parts.size() == 4:
			result = _grid_region("shards_clean", int(parts[2]) * 4 + int(parts[3]), 4, 6)
	elif asset_name.begins_with("fx_"):
		var parts := asset_name.split("_")
		var kinds := ["explosion", "lightning", "frost", "dust"]
		if parts.size() == 3 and kinds.has(parts[1]):
			result = _grid_region("effects_clean", kinds.find(parts[1]) * 8 + int(parts[2]), 8, 4)
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
