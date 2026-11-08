class_name Themes
extends RefCounted
## Dungeon looks per floor, from the Dungeon Crawl Stone Soup tiles under
## res://assets/dungeon/ (CC0, see assets/dungeon/CREDITS.txt):
##   floor 1 crypt   grey flagstones, catacomb walls, candles, cobwebs, dust
##   floor 2 ruins   vine-grown flagstones, overgrown walls, trees, drips, fireflies, moss
##   floor 3 frozen  frosted slabs, pale marble walls, snow, glints, ice sheets, breath
##   floor 4 forge   volcanic floor, hell-stone walls, flame braziers, embers, lava pools
##   floor 5 void    black cobalt, abyss walls, violet motes, rifts, wisps
##   sanctum (hub)   ornate crypt mosaic, carved relief walls, gold statues
## Each theme lists weighted tile variants for floor and walls (mostly plain, some cracked,
## mossy or carved), door gate tiles, wall decor, tints, an ambient light colour and the
## chasm lip / water colours. Floors pick a variant per tile cell from a hash of the cell
## and the room seed, so a room looks the same on every visit; walls hash with a seed per
## theme only, so a SecretWall drawn at the same world cells matches its wall exactly.
##
## Readability keys (see the "Readability" section below; tuned against the ENDESGA 64
## quantization): `floor_wash` a flat veil over the floor tiles (alpha = how much of their
## detail it hides) that also sets the floor's value, `wall_wash` the same for walls whose
## tiles are near black (forge, void), `edge` the lit top of walls and pillars, `outline`
## the line where solid geometry meets the floor, `water_hi` pool glints and rims.
##
## Tiles are drawn at one texel per post-process pixel cell (`texel(zoom)`, see PostFx), so
## a 32 px tile spans 32 screen cells and the camera snap keeps texels on the grid.

const ROOT := "res://assets/dungeon/"
const ORDER := ["crypt", "ruins", "frozen", "forge", "void"]

const THEMES := {
    "crypt": {
        "floor": [["floor/rect_gray_0_old.png", 6.0], ["floor/rect_gray_1_old.png", 4.0], ["floor/rect_gray_2_old.png", 3.0],
            ["floor/rect_gray_3_old.png", 3.0], ["floor/tomb_1_old.png", 0.8], ["floor/tomb_3_old.png", 0.6], ["floor/cobble_blood_2_old.png", 0.35]],
        "floor_tint": Color(0.58, 0.56, 0.62),
        "wall": [["wall/catacombs_0.png", 5.0], ["wall/catacombs_1.png", 4.0], ["wall/catacombs_2.png", 3.0], ["wall/catacombs_3.png", 3.0],
            ["wall/catacombs_4.png", 2.0], ["wall/catacombs_5.png", 1.0], ["wall/catacombs_12.png", 0.3], ["wall/catacombs_14.png", 0.25]],
        "wall_tint": Color(1.12, 1.08, 1.18),
        "door_closed": "gate_closed", "door_locked": "gate_closed", "door_tint": Color(0.78, 0.74, 0.74),
        "decor": ["statues/statue_angel.png", "vaults/sarcophagus_sealed.png", "statues/statue_wraith.png", "altars/altar_old.png", "statues/crumbled_column_1.png"],
        "decor_tint": Color(0.70, 0.68, 0.74),
        "light": "torch",
        "ambient": Color(1.0, 0.70, 0.38),
        "lip": Color(0.30, 0.28, 0.31),
        "floor_wash": Color(0.11, 0.10, 0.12, 0.50), "edge": Color(0.80, 0.77, 0.86), "outline": Color(0.025, 0.02, 0.035),
        "water_hi": Color(0.70, 0.84, 1.0),
        "water": ["water/deep_water.png", "water/deep_water_2.png"], "water_tint": Color(0.62, 0.70, 0.85),
    },
    "ruins": {
        "floor": [["floor/floor_vines_0_new.png", 4.0], ["floor/floor_vines_1_new.png", 3.0], ["floor/floor_vines_3_new.png", 2.0],
            ["floor/floor_vines_5_new.png", 2.0], ["floor/pebble_brown_2_old.png", 0.8], ["floor/lair_1_new.png", 0.8], ["floor/moss_2.png", 0.35]],
        "floor_tint": Color(1.10, 1.16, 1.02),
        "wall": [["wall/wall_vines_0.png", 3.0], ["wall/wall_vines_1.png", 3.0], ["wall/wall_vines_2.png", 3.0], ["wall/wall_vines_3.png", 2.0],
            ["wall/wall_vines_4.png", 1.5], ["wall/wall_vines_5.png", 1.0], ["wall/wall_vines_6.png", 0.6]],
        "wall_tint": Color(0.60, 0.65, 0.57),
        "door_closed": "gate_closed", "door_locked": "gate_sealed", "door_tint": Color(0.74, 0.76, 0.66),
        "decor": ["trees/mangrove_1.png", "statues/crumbled_column_3.png", "trees/mangrove_2.png", "statues/statue_naga.png", "trees/mangrove_3.png", "statues/granite_stump_new.png"],
        "decor_tint": Color(0.66, 0.70, 0.60),
        "light": "",
        "ambient": Color(0.62, 0.95, 0.45),
        "lip": Color(0.30, 0.28, 0.22),
        "floor_wash": Color(0.11, 0.12, 0.085, 0.45), "edge": Color(0.74, 0.82, 0.60), "outline": Color(0.02, 0.03, 0.02),
        "water_hi": Color(0.70, 0.95, 0.85),
        "water": ["water/shoals_deep_water_5.png", "water/shoals_deep_water_6.png"], "water_tint": Color(0.55, 0.72, 0.62),
    },
    "frozen": {
        "floor": [["floor/ice_0_new.png", 5.0], ["floor/ice_1_new.png", 3.0], ["floor/ice_2_new.png", 3.0], ["floor/ice_3_new.png", 2.0],
            ["floor/frozen_4.png", 0.7], ["floor/frozen_10.png", 0.5]],
        "floor_tint": Color(0.56, 0.62, 0.74),
        "wall": [["wall/marble_wall_1.png", 4.0], ["wall/marble_wall_2.png", 3.0], ["wall/marble_wall_3.png", 3.0], ["wall/marble_wall_4.png", 2.0],
            ["wall/marble_wall_5.png", 2.0], ["wall/marble_wall_6.png", 1.0], ["wall/marble_wall_10.png", 0.25]],
        "wall_tint": Color(0.46, 0.52, 0.62),
        "door_closed": "gate_closed", "door_locked": "gate_runed", "door_tint": Color(0.72, 0.80, 0.92),
        "decor": ["statues/statue_angel.png", "statues/statue_orb.png", "statues/statue_princess.png", "statues/statue_orb_guardian.png", "statues/crumbled_column_2.png"],
        "decor_tint": Color(0.72, 0.84, 1.0),
        "light": "",
        "ambient": Color(0.62, 0.86, 1.0),
        "lip": Color(0.42, 0.50, 0.60),
        "floor_wash": Color(0.10, 0.12, 0.15, 0.50), "edge": Color(0.80, 0.90, 1.00), "outline": Color(0.02, 0.03, 0.06),
        "water_hi": Color(0.85, 0.97, 1.0),
        "water": ["water/deep_water.png", "water/deep_water_2.png"], "water_tint": Color(0.62, 0.78, 0.95),
    },
    "forge": {
        "floor": [["floor/volcanic_floor_0.png", 5.0], ["floor/volcanic_floor_1.png", 3.0], ["floor/volcanic_floor_2.png", 3.0],
            ["floor/volcanic_floor_3.png", 2.0], ["floor/volcanic_floor_4.png", 1.0], ["floor/volcanic_floor_6.png", 1.0], ["floor/rough_red_1.png", 0.3]],
        "floor_tint": Color(1.70, 1.42, 1.34),
        "wall": [["wall/hell_2.png", 4.0], ["wall/hell_3.png", 3.0], ["wall/hell_4.png", 3.0], ["wall/hell_5.png", 2.0], ["wall/hell_6.png", 1.5],
            ["wall/hell_8.png", 0.3], ["wall/hell_9.png", 0.25]],
        "wall_tint": Color(1.12, 0.84, 0.78),
        "door_closed": "gate_closed", "door_locked": "gate_sealed", "door_tint": Color(0.82, 0.62, 0.52),
        "decor": ["statues/statue_iron.png", "altars/altar_makhleb_flame_1.png", "statues/statue_imp.png", "altars/altar_makhleb_flame_1.png", "vaults/statue_iron_golem.png"],
        "decor_tint": Color(0.80, 0.66, 0.62),
        "light": "brazier",
        "ambient": Color(1.0, 0.48, 0.18),
        "lip": Color(0.42, 0.18, 0.10),
        "floor_wash": Color(0.20, 0.10, 0.085, 0.45), "wall_wash": Color(0.34, 0.16, 0.12, 0.30), "edge": Color(0.98, 0.62, 0.42), "outline": Color(0.03, 0.01, 0.01),
        "water_hi": Color(0.75, 0.80, 0.95),
        "water": ["water/deep_water.png", "water/deep_water_2.png"], "water_tint": Color(0.62, 0.66, 0.78),
    },
    "void": {
        "floor": [["floor/black_cobalt_2.png", 5.0], ["floor/black_cobalt_3.png", 3.0], ["floor/black_cobalt_4.png", 3.0], ["floor/black_cobalt_6.png", 2.0],
            ["floor/black_cobalt_7.png", 2.0], ["floor/black_cobalt_11.png", 0.9], ["floor/black_cobalt_12.png", 0.8]],
        "floor_tint": Color(1.45, 1.25, 1.75),
        "wall": [["wall/abyss/abyss_darkgray_0.png", 3.0], ["wall/abyss/abyss_darkgray_1.png", 3.0], ["wall/abyss/abyss_darkgray_2.png", 3.0],
            ["wall/abyss/abyss_darkgray_3.png", 2.0], ["wall/abyss/abyss_darkgray_7.png", 1.0], ["wall/stone_black_marked_1.png", 0.3], ["wall/stone_black_marked_6.png", 0.3]],
        "wall_tint": Color(1.30, 1.16, 1.50),
        "door_closed": "gate_closed", "door_locked": "gate_runed", "door_tint": Color(0.70, 0.62, 0.86),
        "decor": ["statues/statue_ancient_evil.png", "altars/altar_lugonu.png", "altars/dithmenos.png", "statues/statue_wraith.png", "altars/dithmenos_2.png"],
        "decor_tint": Color(0.80, 0.70, 0.96),
        "light": "",
        "ambient": Color(0.72, 0.42, 1.0),
        "lip": Color(0.30, 0.18, 0.42),
        "floor_wash": Color(0.13, 0.10, 0.20, 0.58), "wall_wash": Color(0.32, 0.25, 0.46, 0.42), "edge": Color(0.76, 0.62, 1.0), "outline": Color(0.02, 0.0, 0.04),
        "water_hi": Color(0.85, 0.75, 1.0),
        "water": ["water/ink_full.png", "water/ink_full.png"], "water_tint": Color(0.75, 0.70, 0.95),
    },
    # Phase 5 (Rotting Gardens): bog floor, slime-grown walls, sick trees; spore pods and
    # marsh gas are added by Room/Ambience ("garden").
    "garden": {
        "floor": [["floor/bog_green_0_new.png", 4.0], ["floor/bog_green_1_new.png", 3.0], ["floor/bog_green_2_new.png", 3.0],
            ["floor/bog_green_3_new.png", 2.0], ["floor/moss_1.png", 0.8], ["floor/swamp_1_new.png", 0.5], ["floor/green_bones_3.png", 0.3]],
        "floor_tint": Color(0.98, 1.06, 0.84),
        "wall": [["wall/slime_0_new.png", 4.0], ["wall/slime_1_new.png", 3.0], ["wall/slime_2_new.png", 3.0], ["wall/slime_3_new.png", 2.0],
            ["wall/slime_4.png", 1.0], ["wall/slime_5.png", 0.6]],
        "wall_tint": Color(0.70, 0.78, 0.58),
        "door_closed": "gate_closed", "door_locked": "gate_sealed", "door_tint": Color(0.70, 0.76, 0.56),
        "decor": ["trees/tree_1_yellow.png", "statues/statue_snail.png", "trees/tree_2_yellow.png", "trees/mangrove_2.png", "statues/crumbled_column_4.png"],
        "decor_tint": Color(0.72, 0.80, 0.56),
        "light": "",
        "ambient": Color(0.78, 0.95, 0.40),
        "lip": Color(0.24, 0.26, 0.14),
        "floor_wash": Color(0.10, 0.12, 0.06, 0.48), "edge": Color(0.78, 0.86, 0.52), "outline": Color(0.02, 0.03, 0.01),
        "water_hi": Color(0.78, 0.95, 0.60),
        "water": ["water/deep_water_murky.png", "water/deep_water_murky_2.png"], "water_tint": Color(0.60, 0.72, 0.48),
    },
    # Phase 5 (Drowned Cistern): wet limestone, brick and shoal walls, murky water; drains
    # and standing puddles are added by Room/Ambience ("cistern").
    "cistern": {
        "floor": [["floor/limestone_0.png", 4.0], ["floor/limestone_1.png", 3.0], ["floor/limestone_2.png", 3.0], ["floor/limestone_3.png", 2.0],
            ["floor/limestone_5.png", 1.0], ["floor/limestone_8.png", 0.5]],
        "floor_tint": Color(0.62, 0.74, 0.84),
        "wall": [["wall/shoals_wall_1.png", 4.0], ["wall/shoals_wall_2.png", 3.0], ["wall/shoals_wall_3.png", 3.0], ["wall/shoals_wall_4.png", 2.0],
            ["wall/brick_gray_1.png", 1.0], ["wall/brick_gray_3.png", 0.5]],
        "wall_tint": Color(0.62, 0.74, 0.86),
        "door_closed": "gate_closed", "door_locked": "gate_runed", "door_tint": Color(0.66, 0.76, 0.86),
        "decor": ["statues/statue_mermaid.png", "statues/statue_hydra.png", "statues/crumbled_column_5.png", "statues/statue_naga.png"],
        "decor_tint": Color(0.66, 0.78, 0.90),
        "light": "torch",
        "ambient": Color(0.50, 0.78, 1.0),
        "lip": Color(0.22, 0.28, 0.34),
        "floor_wash": Color(0.07, 0.10, 0.14, 0.50), "edge": Color(0.70, 0.84, 0.96), "outline": Color(0.01, 0.02, 0.04),
        "water_hi": Color(0.75, 0.92, 1.0),
        "water": ["water/deep_water_murky.png", "water/deep_water_murky_2.png"], "water_tint": Color(0.52, 0.66, 0.80),
    },
    "sanctum": {
        "floor": [["floor/crypt_domino_1a.png", 3.0], ["floor/crypt_domino_2a.png", 3.0], ["floor/crypt_domino_3a.png", 2.0], ["floor/crypt_domino_4a.png", 2.0],
            ["floor/crypt_domino_5a.png", 2.0], ["floor/crypt_domino_6a.png", 1.0], ["floor/crypt_domino_7a.png", 1.0], ["floor/crypt_domino_1b.png", 0.4]],
        "floor_tint": Color(1.45, 1.32, 1.18),
        "wall": [["wall/relief_0.png", 3.0], ["wall/relief_1.png", 3.0], ["wall/relief_2.png", 2.0], ["wall/relief_3.png", 1.0]],
        "wall_tint": Color(1.02, 0.96, 0.92),
        "door_closed": "gate_closed", "door_locked": "gate_runed", "door_tint": Color(0.86, 0.80, 0.70),
        "decor": ["vaults/golden_statue_1.png", "altars/altar_shining_one.png", "vaults/golden_statue_2.png", "statues/statue_sword.png"],
        "decor_tint": Color(0.86, 0.80, 0.70),
        "light": "torch",
        "ambient": Color(1.0, 0.80, 0.45),
        "lip": Color(0.35, 0.30, 0.26),
        "floor_wash": Color(0.14, 0.12, 0.10, 0.50), "edge": Color(0.86, 0.76, 0.58), "outline": Color(0.03, 0.02, 0.02),
        "water_hi": Color(0.70, 0.84, 1.0),
        "water": ["water/deep_water.png", "water/deep_water_2.png"], "water_tint": Color(0.62, 0.70, 0.85),
    },
}

const TORCH_FRAMES := ["wall/torches/torch_1.png", "wall/torches/torch_2.png", "wall/torches/torch_3.png", "wall/torches/torch_4.png"]
const BRAZIER_FRAMES := ["altars/altar_makhleb_flame_1.png", "altars/altar_makhleb_flame_2.png", "altars/altar_makhleb_flame_3.png",
    "altars/altar_makhleb_flame_4.png", "altars/altar_makhleb_flame_5.png", "altars/altar_makhleb_flame_6.png",
    "altars/altar_makhleb_flame_7.png", "altars/altar_makhleb_flame_8.png"]
const LAVA_FRAMES := ["floor/lava_0.png", "floor/lava_1.png", "floor/lava_2.png", "floor/lava_3.png"]

## The theme rooms are being built with now (Room sets it from the floor, the hub to
## "sanctum"); Door and SecretWall read it.
static var current := "crypt"
static var _tex: Dictionary = {}


static func for_floor(n: int) -> String:
    return String(ORDER[clampi(n - 1, 0, ORDER.size() - 1)])


static func def(theme: String = "") -> Dictionary:
    return THEMES.get(theme if theme != "" else current, THEMES["crypt"])


## A tile under ROOT, loaded once.
static func tex(path: String) -> Texture2D:
    if _tex.has(path):
        return _tex[path]
    var t: Texture2D = null
    var full := ROOT + path
    if ResourceLoader.exists(full):
        t = load(full) as Texture2D
    if t == null:
        push_warning("Themes: missing tile %s" % full)
        t = Art.FLOOR
    _tex[path] = t
    return t


## World size of one tile texel: one post-process pixel cell at the camera's zoom.
static func texel(zoom: float) -> float:
    return PostFx.cell_world(zoom)


## Stable 31-bit hash of a tile cell and a seed.
static func cell_hash(cx: int, cy: int, seed_v: int) -> int:
    var h := (cx * 73856093) ^ (cy * 19349663) ^ (seed_v * 83492791)
    h = (h ^ (h >> 13)) * 1274126177
    return (h ^ (h >> 16)) & 0x7FFFFFFF


## A weighted pick from [[path, weight], ...] by hash.
static func pick(list: Array, h: int) -> Texture2D:
    var total := 0.0
    for e in list:
        total += float(e[1])
    var x := float(h % 100000) / 100000.0 * total
    for e in list:
        x -= float(e[1])
        if x < 0.0:
            return tex(String(e[0]))
    return tex(String(list[0][0]))


## The seed walls of a theme hash with (shared by every room of the floor, so a secret
## wall placed anywhere picks the same variants as the wall it replaces).
static func wall_seed(theme: String = "") -> int:
    return hash(theme if theme != "" else current) & 0xFFFF


## A wall fill for `rect` (local to the node it is added to); its tile grid is anchored
## to the world, so it lines up with every other wall of the theme.
static func wall_fill(rect: Rect2, zoom: float, tint_mul: Color = Color.WHITE, theme: String = "") -> TileFill:
    var d := def(theme)
    var f := TileFill.new()
    f.list = d["wall"]
    f.rect = rect
    f.texel = texel(zoom)
    f.seed_v = wall_seed(theme)
    f.tint = (d["wall_tint"] as Color) * tint_mul
    var wash: Color = d.get("wall_wash", Color(0, 0, 0, 0))
    f.wash = Color(wash.r * tint_mul.r, wash.g * tint_mul.g, wash.b * tint_mul.b, wash.a)
    return f


## A floor fill for `rect` with a per-room seed.
static func floor_fill(rect: Rect2, zoom: float, seed_v: int, tint_mul: Color = Color.WHITE, theme: String = "") -> TileFill:
    var d := def(theme)
    var f := TileFill.new()
    f.list = d["floor"]
    f.rect = rect
    f.texel = texel(zoom)
    f.seed_v = seed_v
    f.tint = (d["floor_tint"] as Color) * tint_mul
    var wash: Color = d.get("floor_wash", Color(0, 0, 0, 0))
    f.wash = Color(wash.r * tint_mul.r, wash.g * tint_mul.g, wash.b * tint_mul.b, wash.a)
    return f


## The three gate tiles for a door: [left, middle, right] (or [up, middle, down] when the
## door is in a side wall). `kind` is "closed", "open" or "locked".
static func door_tiles(horizontal: bool, kind: String, theme: String = "") -> Array:
    var d := def(theme)
    var base := "gate_open"
    if kind == "closed":
        base = String(d["door_closed"])
    elif kind == "locked":
        base = String(d["door_locked"])
    if horizontal:
        return [tex("doors/%s_left.png" % base), tex("doors/%s_middle.png" % base), tex("doors/%s_right.png" % base)]
    var vb := base.replace("gate_", "vgate_")
    return [tex("doors/%s_up.png" % vb), tex("doors/%s_middle.png" % vb), tex("doors/%s_down.png" % vb)]


## Draws tiles from `list` ([[path, weight], ...]) over `rect` (local to `ci`), one
## variant per 32-texel tile cell. The tile grid is anchored to the world: `origin` is the
## world position of `ci`'s local origin. Each texel is `texel` world units.
## (`ci` is any CanvasItem; it is left untyped so the readability preview tool can pass
## an image canvas.)
static func draw_tiles(ci, list: Array, rect: Rect2, origin: Vector2, texel_w: float, seed_v: int, tint: Color) -> void:
    if list.is_empty() or rect.size.x <= 0.0 or rect.size.y <= 0.0 or texel_w <= 0.0:
        return
    var tw := 32.0 * texel_w
    var w0 := rect.position + origin
    var w1 := rect.end + origin
    var wr := Rect2(w0, rect.size)
    for cy in range(floori(w0.y / tw), ceili(w1.y / tw)):
        for cx in range(floori(w0.x / tw), ceili(w1.x / tw)):
            var cell := Rect2(Vector2(cx, cy) * tw, Vector2(tw, tw))
            var clip := cell.intersection(wr)
            if clip.size.x <= 0.01 or clip.size.y <= 0.01:
                continue
            var t := pick(list, cell_hash(cx, cy, seed_v))
            var src := Rect2((clip.position - cell.position) / texel_w, clip.size / texel_w)
            ci.draw_texture_rect_region(t, Rect2(clip.position - origin, clip.size), src, tint)


# --- Readability: edges, shadows, chasms, pools ----------------------------------
# One value ladder for every theme, kept apart after the ENDESGA quantization: chasm black
# and outlines < floor (dark, its detail veiled by `floor_wash`) < wall faces < lit wall
# tops (`edge`). Light comes from the top left: tops and left sides lit, bottoms and right
# sides shaded, drop shadows below and to the right. Sizes are whole texels `tx`, so each
# band is exactly one or two post-process cells wide wherever it lands. Room calls these
# per 20 px layout cell; `ci` is any CanvasItem (untyped for the preview tool).


## Edges of one solid layout cell at `p` (size `cs`) whose sides up / dn / lf / rt face
## open ground: a dark outline just outside, a lit top two texels deep, a faintly lit left
## side, a shaded bottom and right side inside. `soft` (rubble) takes the light down.
static func draw_block_edges(ci, p: Vector2, cs: float, tx: float, up: bool, dn: bool, lf: bool, rt: bool, td: Dictionary, soft: bool = false) -> void:
    var hi: Color = td.get("edge", Color(0.7, 0.7, 0.7))
    var ol: Color = td.get("outline", Color(0.02, 0.02, 0.03))
    var k := 0.55 if soft else 1.0
    var xl := tx if lf else 0.0
    var xr := tx if rt else 0.0
    if up:
        ci.draw_rect(Rect2(p.x - xl, p.y - tx, cs + xl + xr, tx), ol)
    if dn:
        ci.draw_rect(Rect2(p.x - xl, p.y + cs, cs + xl + xr, tx), ol)
    if lf:
        ci.draw_rect(Rect2(p.x - tx, p.y, tx, cs), ol)
    if rt:
        ci.draw_rect(Rect2(p.x + cs, p.y, tx, cs), ol)
    if dn:
        ci.draw_rect(Rect2(p.x, p.y + cs - tx, cs, tx), Color(0, 0, 0, 0.45))
    if rt:
        ci.draw_rect(Rect2(p.x + cs - tx, p.y, tx, cs), Color(0, 0, 0, 0.32))
    if lf:
        ci.draw_rect(Rect2(p.x, p.y, tx, cs), Color(hi, 0.35 * k))
    if up:
        ci.draw_rect(Rect2(p.x, p.y, cs, tx), Color(hi, 0.95 * k))
        ci.draw_rect(Rect2(p.x, p.y + tx, cs, tx), Color(hi, 0.42 * k))


## The drop shadow on the open cell at `p` from solid neighbours: `above`, `left`, and
## `corner` (above-left). Light from the top left, so it falls down and to the right.
static func draw_floor_shadow(ci, p: Vector2, cs: float, tx: float, above: bool, left: bool, corner: bool) -> void:
    if above:
        ci.draw_rect(Rect2(p, Vector2(cs, 2.0 * tx)), Color(0, 0, 0, 0.42))
        ci.draw_rect(Rect2(p + Vector2(0, 2.0 * tx), Vector2(cs, 2.0 * tx)), Color(0, 0, 0, 0.2))
    if left:
        var y0 := 0.0 if corner else tx
        ci.draw_rect(Rect2(p + Vector2(0, y0), Vector2(2.0 * tx, cs - y0)), Color(0, 0, 0, 0.34))
        ci.draw_rect(Rect2(p + Vector2(2.0 * tx, y0), Vector2(tx, cs - y0)), Color(0, 0, 0, 0.15))
    elif corner and not above:
        ci.draw_rect(Rect2(p + Vector2(0, tx), Vector2(2.0 * tx, tx)), Color(0, 0, 0, 0.3))


## One chasm cell: a black drop; along the far (top) edge the floor's broken lip in the
## theme's stone over the shadowed face of the drop, along the near (bottom) edge a lip
## catching the light, the sides a plain stone edge.
static func draw_chasm_cell(ci, p: Vector2, cs: float, tx: float, up: bool, dn: bool, lf: bool, rt: bool, td: Dictionary) -> void:
    var lip: Color = td["lip"]
    ci.draw_rect(Rect2(p, Vector2(cs, cs)), Color(0.0, 0.0, 0.0))
    if up:
        ci.draw_rect(Rect2(p, Vector2(cs, tx)), lip.lightened(0.2))
        ci.draw_rect(Rect2(p + Vector2(0, tx), Vector2(cs, tx)), lip.darkened(0.45))
        ci.draw_rect(Rect2(p + Vector2(0, 2.0 * tx), Vector2(cs, tx)), lip.darkened(0.75))
    if lf:
        ci.draw_rect(Rect2(p, Vector2(tx, cs)), lip.darkened(0.15))
    if rt:
        ci.draw_rect(Rect2(p + Vector2(cs - tx, 0), Vector2(tx, cs)), lip.darkened(0.3))
    if dn:
        ci.draw_rect(Rect2(p + Vector2(0, cs - tx), Vector2(cs, tx)), lip.lightened(0.5))


## One deep-water cell: the theme's water tiles, a stone lip and a dark drop at the far
## edge, a lit rim at the near edge and sparse bright glints, so pools read as hazards.
static func draw_pool_cell(ci, p: Vector2, cs: float, tx: float, up: bool, dn: bool, lf: bool, rt: bool, td: Dictionary, origin: Vector2, hsh: int) -> void:
    var water_list: Array = [[String(td["water"][0]), 1.0], [String(td["water"][1]), 1.0]]
    var hi: Color = td.get("water_hi", Color(0.8, 0.9, 1.0))
    ci.draw_rect(Rect2(p, Vector2(cs, cs)), Color(0.04, 0.08, 0.16))
    draw_tiles(ci, water_list, Rect2(p, Vector2(cs, cs)), origin, tx, 9001, td["water_tint"])
    if hsh % 3 == 0:
        var g := p + Vector2(float(hsh % 7) + 2.0, float((hsh >> 4) % 9) + 5.0)
        ci.draw_rect(Rect2(g, Vector2(3.0 * tx, tx)), Color(hi, 0.8))
        ci.draw_rect(Rect2(g + Vector2(tx, -tx), Vector2(tx, tx)), Color(hi, 0.45))
    if up:
        ci.draw_rect(Rect2(p, Vector2(cs, tx)), td["lip"])
        ci.draw_rect(Rect2(p + Vector2(0, tx), Vector2(cs, tx)), Color(0.02, 0.04, 0.10))
        ci.draw_rect(Rect2(p + Vector2(0, 2.0 * tx), Vector2(cs, tx)), Color(hi, 0.35))
    if dn:
        ci.draw_rect(Rect2(p + Vector2(0, cs - tx), Vector2(cs, tx)), Color(hi, 0.7))
    if lf:
        ci.draw_rect(Rect2(p, Vector2(tx, cs)), Color(hi, 0.35))
    if rt:
        ci.draw_rect(Rect2(p + Vector2(cs - tx, 0), Vector2(tx, cs)), Color(hi, 0.35))


## A static node drawing `draw_tiles` once.
class TileFill extends Node2D:
    var list: Array = []
    var rect := Rect2()
    var texel := 2.0
    var seed_v := 0
    var tint := Color.WHITE
    var wash := Color(0, 0, 0, 0)   # a flat veil over the tiles (floors: keeps their detail faint)

    func _ready() -> void:
        texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

    # The tile grid is anchored to the world through this node's world position, so
    # neighbouring fills (and a secret wall in a wall line) join seamlessly.
    func _draw() -> void:
        Themes.draw_tiles(self, list, rect, global_position, texel, seed_v, tint)
        if wash.a > 0.0:
            draw_rect(rect, wash)
