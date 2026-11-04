extends Node
## Autoload "Art": Kenney 1-Bit Pack sheet lookups, particle textures, fonts and the
## dark palette. Everything visual that is not element-coloured comes through here.
## Assets are CC0 by Kenney (kenney.nl); see assets/*/LICENSE_*.txt.

const SHEET: Texture2D = preload("res://assets/kenney/1bit_mono.png")
const FLOOR: Texture2D = preload("res://assets/kenney/floor_tile.png")
const WALL: Texture2D = preload("res://assets/kenney/wall_tile.png")
const FONT: Font = preload("res://assets/fonts/kenney_pixel.ttf")
const FONT_SMALL: Font = preload("res://assets/fonts/kenney_mini.ttf")

const PARTICLES := {
    "smoke": preload("res://assets/kenney/particles/smoke_04.png"),
    "flame": preload("res://assets/kenney/particles/flame_04.png"),
    "spark": preload("res://assets/kenney/particles/spark_04.png"),
    "magic": preload("res://assets/kenney/particles/magic_01.png"),
    "light": preload("res://assets/kenney/particles/light_01.png"),
    "circle": preload("res://assets/kenney/particles/circle_05.png"),
    "scorch": preload("res://assets/kenney/particles/scorch_01.png"),
    "twirl": preload("res://assets/kenney/particles/twirl_01.png"),
}

const TILE := 16


## Sheet coordinates (column, row) in the packed 1-bit sheet.
const TILES := {
    "player": [Vector2i(26, 0), Vector2i(31, 0), Vector2i(30, 0), Vector2i(27, 0)],
    "grunt": Vector2i(29, 6),
    "runner": Vector2i(26, 8),
    "brute": Vector2i(30, 6),
    "elite": Vector2i(28, 5),
    "boss": Vector2i(30, 8),
    "scrap": Vector2i(45, 16),
    "carry": Vector2i(47, 4),
    "repair": Vector2i(40, 11),
    "stairs": Vector2i(4, 10),
    "sigil": Vector2i(28, 12),
    "lock": Vector2i(0, 10),
    "cog": Vector2i(45, 16),
    "tree_a": Vector2i(3, 1),
    "tree_b": Vector2i(5, 1),
    "decals": [Vector2i(38, 11), Vector2i(32, 12), Vector2i(34, 12), Vector2i(1, 11), Vector2i(2, 11), Vector2i(26, 11), Vector2i(15, 0)],
}

const GUN_TILES := {
    "water_pistol": Vector2i(37, 9),
    "arc_rifle": Vector2i(42, 9),
    "blowtorch": Vector2i(43, 9),
    "frost_caster": Vector2i(39, 9),
    "oil_slinger": Vector2i(40, 9),
    "mist_sprayer": Vector2i(41, 9),
    "ember_carbine": Vector2i(38, 9),
    "hydro_cannon": Vector2i(43, 9),
    "glacier_lance": Vector2i(32, 2),
    "tar_mortar": Vector2i(44, 9),
    "storm_pike": Vector2i(35, 3),
    "venom_spitter": Vector2i(33, 4),
    "acid_flask": Vector2i(39, 11),
    "blood_lance": Vector2i(34, 2),
    "void_orb": Vector2i(35, 2),
    "radiant_ray": Vector2i(36, 4),
    "gale_blaster": Vector2i(34, 5),
    "stone_sling": Vector2i(37, 7),
    "flare_pistol": Vector2i(38, 9),
    "slick_wand": Vector2i(34, 4),
    "spark_needler": Vector2i(40, 9),
    "cinder_flak": Vector2i(45, 9),
    "rime_chakram": Vector2i(37, 6),
    "plague_mortar": Vector2i(44, 9),
    "blight_seeker": Vector2i(35, 4),
    "etcher_beam": Vector2i(32, 4),
    "corrosion_burst": Vector2i(41, 9),
    "vein_pistol": Vector2i(37, 9),
    "clot_orb": Vector2i(40, 2),
    "rift_seeker": Vector2i(34, 5),
    "null_wand": Vector2i(33, 5),
    "sun_cannon": Vector2i(43, 9),
    "prayer_burst": Vector2i(42, 9),
    "zephyr_rang": Vector2i(38, 6),
    "cyclone_flak": Vector2i(45, 9),
    "boulder_mortar": Vector2i(44, 9),
    "gravel_shotgun": Vector2i(39, 9),
    "eclipse_carbine": Vector2i(42, 9),
    "kettle_gun": Vector2i(40, 9),
    "storm_seeker": Vector2i(35, 5),
    "railgun": Vector2i(41, 9),
    "napalm_lobber": Vector2i(43, 9),
    "duality_burst": Vector2i(38, 9),
}

## Palette: dark, desaturated, bone and blood.
const CLEAR := Color(0.045, 0.040, 0.055)
const FLOOR_TINT := Color(0.15, 0.13, 0.15)
const WALL_TINT := Color(0.42, 0.34, 0.36)
const DECAL_TINT := Color(0.38, 0.34, 0.36)
const ENEMY_TINT := {
    "grunt": Color(0.82, 0.78, 0.70),
    "runner": Color(0.66, 0.54, 0.76),
    "brute": Color(0.62, 0.30, 0.30),
    "elite": Color(0.88, 0.45, 0.78),
    "boss": Color(0.92, 0.22, 0.30),
}
const SCRAP_TINT := Color(0.85, 0.72, 0.35)

var _cache: Dictionary = {}

## Body font: the same pixel font, which only reads at 20 px and up, so every piece of
## text in the game is drawn at 20 or larger and kept short.
var FONT_BODY: Font


func _ready() -> void:
    FONT_BODY = FONT


func tile(coord: Vector2i) -> AtlasTexture:
    if _cache.has(coord):
        return _cache[coord]
    var t := AtlasTexture.new()
    t.atlas = SHEET
    t.region = Rect2(coord.x * TILE, coord.y * TILE, TILE, TILE)
    _cache[coord] = t
    return t


## A ready-to-add Sprite2D showing one sheet tile, scaled and tinted.
func sprite(coord: Vector2i, scale: float, tint: Color) -> Sprite2D:
    var s := Sprite2D.new()
    s.texture = tile(coord)
    s.scale = Vector2(scale, scale)
    s.modulate = tint
    s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    return s


func gun_tile(id: String) -> Vector2i:
    return GUN_TILES.get(id, Vector2i(37, 9))


## Particle texture used for a reaction or effect name.
func particle_for(effect_name: String) -> Texture2D:
    match effect_name:
        "Chain Lightning":
            return PARTICLES["spark"]
        "Steam":
            return PARTICLES["smoke"]
        "Deep Freeze", "Frost Nova":
            return PARTICLES["magic"]
        "Inferno", "Ignition", "Fire Nova":
            return PARTICLES["flame"]
        "Shield broken!", "Shield restored!", "Path opened!":
            return PARTICLES["light"]
    return PARTICLES["circle"]
