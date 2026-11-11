extends Node
## Autoload "Art": Kenney 1-Bit Pack sheet lookups, particle textures, fonts and the
## dark palette. Everything visual that is not element-coloured comes through here.
## Assets are CC0 by Kenney (kenney.nl); see assets/*/LICENSE_*.txt.
##
## Icons: items, guns, level-up options, classes and Shrine talents use the 32 px
## Dungeon Crawl Stone Soup tiles under ICON_ROOT (CC0, see assets/icons/CREDITS.txt).
## `icon(path)` loads one (cached; a missing path warns once and falls back to a 1-bit
## tile), `draw_icon` draws one crisply into any rect (integer upscale, smooth downscale),
## `gun_icon(id)` / `reward_icon(reward)` look up the data tables below. The tiles are
## already coloured, so they are drawn untinted except for dimming (locked, empty).

const SHEET: Texture2D = preload("res://assets/kenney/1bit_mono.png")
const FLOOR: Texture2D = preload("res://assets/kenney/floor_tile.png")
const WALL: Texture2D = preload("res://assets/kenney/wall_tile.png")
const FONT: Font = preload("res://assets/fonts/kenney_pixel.ttf")

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

const ICON_ROOT := "res://assets/icons/"
## 1-bit tile shown when an icon path is missing.
const ICON_FALLBACK := Vector2i(45, 16)

## Gun id -> icon (path under ICON_ROOT), one family per archetype so the shape says how it
## fires: hand crossbows (pistols), crossbows (bursts, flak), blowguns (repeaters), flasks
## (throwers), discs (mines), lamps (cannons, turret), wands (forking wands), rods
## (homing), bows (chain), spears (charge), a halberd (melee), a fan, a phial and a
## lantern (sprayers), orbs and crystals (orbs), a rune (nova).
const GUN_ICONS := {
    "water_pistol": "item/weapon/ranged/hand_crossbow.png",
    "arc_rifle": "item/weapon/artefact/urand_storm_bow.png",
    "blowtorch": "item/misc/misc_lantern.png",
    "frost_caster": "item/misc/misc_rune.png",
    "oil_slinger": "item/potion/black_new.png",
    "mist_sprayer": "item/misc/misc_phial.png",
    "ember_carbine": "item/weapon/ranged/crossbow_2.png",
    "hydro_cannon": "item/misc/misc_horn.png",
    "glacier_lance": "item/weapon/artefact/urand_crystal_spear_new.png",
    "tar_mortar": "item/misc/misc_disc_new.png",
    "storm_pike": "item/weapon/halberd_2.png",
    "venom_spitter": "item/weapon/ranged/blowgun_1.png",
    "acid_flask": "item/potion/bubbly.png",
    "blood_lance": "item/weapon/artefact/urand_bloodbane_new.png",
    "void_orb": "item/misc/misc_crystal_new.png",
    "radiant_ray": "item/weapon/artefact/urand_brilliance.png",
    "gale_blaster": "item/misc/misc_fan_new.png",
    "stone_sling": "item/weapon/ranged/sling_1.png",
    "flare_pistol": "item/weapon/artefact/urand_firestarter.png",
    "slick_wand": "item/wand/gem_wood_new.png",
    "spark_needler": "item/weapon/ranged/blowgun_2.png",
    "cinder_flak": "item/weapon/ranged/crossbow_1.png",
    "rime_chakram": "item/weapon/ranged/silver_tomahawk.png",
    "plague_mortar": "item/potion/murky.png",
    "blight_seeker": "item/wand/gem_lead_new.png",
    "etcher_beam": "item/rod/rod_2_new.png",
    "corrosion_burst": "item/misc/misc_disc_old.png",
    "vein_pistol": "item/weapon/ranged/hand_crossbow_2.png",
    "clot_orb": "item/misc/misc_orb.png",
    "rift_seeker": "item/rod/rod_6_new.png",
    "null_wand": "item/wand/gem_iron_new.png",
    "sun_cannon": "item/misc/misc_lamp_new.png",
    "prayer_burst": "item/weapon/holy_scourge.png",
    "zephyr_rang": "item/weapon/artefact/urand_gyre.png",
    "cyclone_flak": "item/rod/rod_9_new.png",
    "boulder_mortar": "item/weapon/ranged/arbalest_1.png",
    "gravel_shotgun": "item/weapon/ranged/rock_old.png",
    "eclipse_carbine": "item/weapon/ranged/arbalest_3.png",
    "kettle_gun": "item/misc/magic_lamp.png",
    "storm_seeker": "item/rod/rod_1_old.png",
    "railgun": "item/weapon/artefact/urand_sniper.png",
    "napalm_lobber": "item/weapon/artefact/urand_hellfire.png",
    "duality_burst": "item/weapon/artefact/urand_elemental.png",
    # Arsenal batch 5: legendaries whose style has no code-drawn shape (guns, the lob).
    "heart_of_the_forge": "item/weapon/artefact/spwpn_scepter_of_asmodeus.png",
    "the_conductor": "item/weapon/artefact/spwpn_staff_of_olgreb.png",
    "echo_engine": "item/weapon/artefact/urand_punk.png",
    "glass_of_ages": "item/weapon/artefact/urand_chilly_death_new.png",
    "skyfall": "item/weapon/artefact/urand_eos.png",
}
## Guns whose tile stands upright (a flask, an orb) instead of lying diagonally like a
## held weapon; the orbiting sprite does not rotate these toward the aim.
const GUN_ICON_UPRIGHT := ["acid_flask", "void_orb", "clot_orb", "oil_slinger", "plague_mortar", "frost_caster",
    "tar_mortar", "corrosion_burst", "kettle_gun", "sun_cannon", "blowtorch", "gravel_shotgun"]
## Trophy wall icons for rewards that are neither a gun nor a class: the full reward
## string is checked first, then its prefix.
const REWARD_ICONS := {
    "rarity:epic": "item/book/purple_new.png",
    "rarity:legendary": "item/book/book_orange.png",
    "rarity": "item/book/gold.png",
    "shop": "item/scroll/scroll-yellow.png",
    "room": "item/scroll/scroll-red.png",
    "obstacle": "item/scroll/scroll-brown.png",
    "secret:lantern": "item/misc/misc_lantern.png",
    "secret:alcove": "item/misc/key.png",
    "secret:hoard": "item/misc/misc_box.png",
}
const REWARD_ICON_DEFAULT := "item/scroll/scroll_old.png"

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
var _icon_cache: Dictionary = {}    # path -> Texture2D
var _sized_cache: Dictionary = {}   # "texture id:px" -> Texture2D
var _icon_warned: Dictionary = {}   # full path -> true once warned

## Text rule (Emil, 2026-11-10). Kenney Pixel (FONT) is the game's look: titles, names,
## numbers, prices and HUD counters. Every sentence (descriptions, menu help, talk boxes,
## tooltips, card effects) uses FONT_BODY, Godot's built-in Open Sans (ThemeDB.fallback_font,
## ships with the engine), at BODY_SIZE or more at 1280x720; secondary lines may drop to
## SMALL_SIZE, never lower. Kenney Mini is retired: its lowercase letters blur together.
## `text_font` / `text_px` apply the rule to text laid out for the pixel font.
## 2026-11-11 (Emil: "the new font is also a little bit large"): every body size is about
## 11% smaller than the first text pass (18 and 15 then); BODY_SCALE shrinks sizes that
## were written as literals for that pass.
const BODY_SIZE := 16
const SMALL_SIZE := 13
const BODY_SCALE := 0.89
var FONT_BODY: Font


func _ready() -> void:
    FONT_BODY = ThemeDB.fallback_font


## True for sentence-length text: three or more words with lowercase letters. Names,
## numbers, button captions and all-caps titles stay in the pixel font.
static func is_prose(text: String) -> bool:
    if text.count(" ") < 2 or text == text.to_upper():
        return false
    var words := 0
    for w in text.split(" ", false):
        if w.length() >= 2 and w != w.to_upper():
            words += 1
    return words >= 3


## The font for `text`: FONT_BODY for sentences, FONT for everything else.
func text_font(text: String) -> Font:
    return FONT_BODY if FONT_BODY != null and is_prose(text) else FONT


## The size to draw `text` at when its layout was made for the pixel font at `pixel_px`:
## unchanged for pixel text; for sentences the body size that fills about the same box
## (Open Sans is about 1.5x wider than Kenney Pixel at the same px), never under SMALL_SIZE.
func text_px(text: String, pixel_px: int) -> int:
    if text_font(text) == FONT:
        return pixel_px
    return body_px(pixel_px)


## Body-font size for a slot sized for the pixel font at `pixel_px`.
static func body_px(pixel_px: int) -> int:
    if pixel_px >= 28:
        return 19
    if pixel_px >= 26:
        return 18
    if pixel_px >= 22:
        return BODY_SIZE
    return 14


## A body size written for the first text pass, at today's scale (never under SMALL_SIZE).
static func bpx(px: int) -> int:
    return maxi(roundi(float(px) * BODY_SCALE), SMALL_SIZE)


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


## Legacy 1-bit tile of a gun; only the fallback for a missing gun icon now.
func gun_tile(id: String) -> Vector2i:
    return GUN_TILES.get(id, Vector2i(37, 9))


# --- Icons (Dungeon Crawl tiles) -----------------------------------------------


## The icon texture at `path` (under ICON_ROOT, or a full res:// path), loaded once.
## An empty path gives the 1-bit `fallback` tile; a missing file also warns once in
## debug builds.
func icon(path: String, fallback: Vector2i = ICON_FALLBACK) -> Texture2D:
    if path == "":
        return tile(fallback)
    if _icon_cache.has(path):
        return _icon_cache[path]
    var full := path if path.begins_with("res://") else ICON_ROOT + path
    var tex: Texture2D = null
    if ResourceLoader.exists(full):
        tex = load(full) as Texture2D
    if tex == null:
        if OS.is_debug_build() and not _icon_warned.has(full):
            _icon_warned[full] = true
            push_warning("Art.icon: missing %s, using a 1-bit fallback tile" % full)
        tex = tile(fallback)
    _icon_cache[path] = tex
    return tex


## True when `path` names an icon file that exists.
func has_icon(path: String) -> bool:
    if path == "":
        return false
    return ResourceLoader.exists(path if path.begins_with("res://") else ICON_ROOT + path)


## `tex` resampled to `px` square (Lanczos, alpha edges fixed first), cached. Shrinks a
## 32 px tile without nearest-neighbour dropping whole rows of pixels.
func icon_sized(tex: Texture2D, px: int) -> Texture2D:
    if tex == null or px <= 0 or (tex.get_width() == px and tex.get_height() == px):
        return tex
    var key := "%d:%d" % [tex.get_instance_id(), px]
    if _sized_cache.has(key):
        return _sized_cache[key]
    var out: Texture2D = tex
    var img: Image = tex.get_image()
    if img != null and not img.is_empty():
        img = img.duplicate()
        if img.is_compressed():
            img.decompress()
        img.convert(Image.FORMAT_RGBA8)
        img.fix_alpha_edges()
        img.resize(px, px, Image.INTERPOLATE_LANCZOS)
        out = ImageTexture.create_from_image(img)
    _sized_cache[key] = out
    return out


## Draws `tex` centred in `rect`, as large as fits while staying crisp. On a UI layer
## above the PostFx (HUD, cards, menus, the Crisp layer) with post-processing on, the
## icon gets the world's pixel treatment (`icon_pixel`): one icon pixel per screen cell,
## in the palette, so UI icons match the pixelated world. Elsewhere (world canvases, which
## the PostFx pixelates anyway, or post-fx off): whole-number upscales of the tile, or a
## smooth resample (in steps of 4 px) when the rect is smaller.
func draw_icon(ci: CanvasItem, tex: Texture2D, rect: Rect2, modulate: Color = Color.WHITE) -> void:
    if tex == null:
        return
    var side := minf(rect.size.x, rect.size.y)
    if _pixel_ui(ci):
        var k := maxf(0.05, ci.get_global_transform_with_canvas().get_scale().x)
        var ps := PostFx.pixel_size()
        var screen_px := int(side * k)
        var pt := icon_pixel(tex, screen_px)
        var dside := float(pt.get_width()) / k
        var pat := (rect.position + (rect.size - Vector2(dside, dside)) / 2.0).round()
        ci.draw_texture_rect(pt, Rect2(pat, Vector2(dside, dside)), false, modulate)
        return
    var base := float(maxi(1, tex.get_width()))
    var t := tex
    var px := base
    if side >= base:
        px = floorf(side / base) * base
    else:
        var want := maxi(8, int(side) - int(side) % 4)
        t = icon_sized(tex, want)
        px = float(want)
    var at := (rect.position + (rect.size - Vector2(px, px)) / 2.0).round()
    ci.draw_texture_rect(t, Rect2(at, Vector2(px, px)), false, modulate)


## True when `ci` draws above the PostFx layer with post-processing on: its icons get the
## pixel treatment so they match the world under the grid.
func _pixel_ui(ci: CanvasItem) -> bool:
    if ci == null or not ci.is_inside_tree() or not Settings.flag("post_fx"):
        return false
    var layer := ci.get_canvas_layer_node()
    return layer != null and layer.layer > 1


## `tex` as the world's pixel grid would show it at `screen_px` on screen: box-filtered
## down to screen_px / pixel_size texels (premultiplied, so edges do not go dark), alpha
## cut to on/off, quantized to the PostFx palette (when Settings "palette" is on), then
## scaled up by pixel_size with nearest. Cached per texture, size, pixel size and palette.
func icon_pixel(tex: Texture2D, screen_px: int) -> Texture2D:
    if tex == null:
        return tex
    var ps := int(PostFx.pixel_size())
    # Never more icon pixels than the tile has: a big icon shows each tile pixel as a
    # whole number of cells instead.
    var cells := clampi(screen_px / maxi(1, ps), 4, maxi(4, tex.get_width()))
    var up := ps * maxi(1, screen_px / maxi(1, cells * ps))
    var pal := Settings.flag("palette")
    var key := "px:%d:%d:%d:%s" % [tex.get_instance_id(), cells, up, pal]
    if _sized_cache.has(key):
        return _sized_cache[key]
    var out: Texture2D = tex
    var src: Image = tex.get_image()
    if src != null and not src.is_empty():
        src = src.duplicate()
        if src.is_compressed():
            src.decompress()
        src.convert(Image.FORMAT_RGBA8)
        var img := _box_down(src, cells)
        if pal:
            _quantize(img)
        img.resize(cells * up, cells * up, Image.INTERPOLATE_NEAREST)
        out = ImageTexture.create_from_image(img)
    _sized_cache[key] = out
    return out


## Area-average `src` down to `n` x `n` (fractional coverage, premultiplied alpha); alpha
## then cut at a half so the icon keeps a hard pixel edge.
static func _box_down(src: Image, n: int) -> Image:
    var sw := src.get_width()
    var sh := src.get_height()
    var out := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
    var fx := float(sw) / float(n)
    var fy := float(sh) / float(n)
    for oy in n:
        var y0 := float(oy) * fy
        var y1 := y0 + fy
        for ox in n:
            var x0 := float(ox) * fx
            var x1 := x0 + fx
            var acc := Vector4.ZERO
            var wsum := 0.0
            for sy in range(int(y0), mini(sh, ceili(y1))):
                var wy := minf(y1, float(sy + 1)) - maxf(y0, float(sy))
                if wy <= 0.0:
                    continue
                for sx in range(int(x0), mini(sw, ceili(x1))):
                    var wx := minf(x1, float(sx + 1)) - maxf(x0, float(sx))
                    if wx <= 0.0:
                        continue
                    var c := src.get_pixel(sx, sy)
                    var w := wx * wy
                    acc += Vector4(c.r * c.a, c.g * c.a, c.b * c.a, c.a) * w
                    wsum += w
            if wsum <= 0.0 or acc.w / wsum < 0.5:
                out.set_pixel(ox, oy, Color(0, 0, 0, 0))
            else:
                out.set_pixel(ox, oy, Color(acc.x / acc.w, acc.y / acc.w, acc.z / acc.w, 1.0))
    return out


var _lut_img: Image = null


## Every opaque pixel of `img` to its nearest palette colour (the PostFx lookup table).
func _quantize(img: Image) -> void:
    if _lut_img == null:
        var lt: Image = PostFx.LUT.get_image()
        if lt == null or lt.is_empty():
            return
        _lut_img = lt.duplicate()
        if _lut_img.is_compressed():
            _lut_img.decompress()
        _lut_img.convert(Image.FORMAT_RGBA8)
    for y in img.get_height():
        for x in img.get_width():
            var c := img.get_pixel(x, y)
            if c.a <= 0.0:
                continue
            var r := clampi(roundi(c.r * 31.0), 0, 31)
            var g := clampi(roundi(c.g * 31.0), 0, 31)
            var b := clampi(roundi(c.b * 31.0), 0, 31)
            var q := _lut_img.get_pixel(b * 32 + r, g)
            img.set_pixel(x, y, Color(q.r, q.g, q.b, 1.0))


## A ready-to-add Sprite2D showing an icon texture at `scale`, untinted.
func icon_sprite(tex: Texture2D, scale: float) -> Sprite2D:
    var s := Sprite2D.new()
    s.texture = tex
    s.scale = Vector2(scale, scale)
    s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    return s


func gun_icon_path(id: String) -> String:
    return String(GUN_ICONS.get(id, ""))


## A gun's icon; falls back to its old 1-bit tile.
func gun_icon(id: String) -> Texture2D:
    var packed := WeaponLooks.sprite_for(id, "icon")
    if packed != null:
        return packed
    if WeaponLooks.draws(id):
        return WeaponLooks.icon(id)
    return icon(gun_icon_path(id), gun_tile(id))


func gun_icon_upright(id: String) -> bool:
    return GUN_ICON_UPRIGHT.has(id)


## Icon path for an achievement reward: "gun:<id>" and "kit:<id>" show the gun, "mark:<id>" the Mark,
## anything else a book or scroll from REWARD_ICONS.
func reward_icon_path(reward: String) -> String:
    if reward.begins_with("gun:"):
        return gun_icon_path(reward.substr(4))
    if reward.begins_with("mark:"):
        return Loadout.mark_icon_path(reward.substr(5))
    if reward.begins_with("kit:"):
        return gun_icon_path(reward.substr(4))
    if reward.begins_with("item:"):
        return Items.icon_path(Items.get_item(reward.substr(5)))
    if REWARD_ICONS.has(reward):
        return String(REWARD_ICONS[reward])
    var prefix := reward.get_slice(":", 0)
    return String(REWARD_ICONS.get(prefix, REWARD_ICON_DEFAULT))


func reward_icon(reward: String) -> Texture2D:
    return icon(reward_icon_path(reward))


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


# --- Review sheet ------------------------------------------------------------------


## Every icon the game shows for an item, gun, level-up option, class, Shrine talent,
## empty slot and trophy, at 2x with its id, in labelled sections, saved as one PNG at
## `path` (like FigureGen.debug_sheet). A red frame marks a missing file (the 1-bit
## fallback is drawn instead), an orange frame an item without its own icon (slot icon).
static func debug_icon_sheet(path: String) -> Error:
    var sections: Array = []   # [title, entries]; entry: [label, icon path, tint, slot fallback]
    var slot_rows: Array = []
    for slot in Items.SLOTS:
        slot_rows.append([String(slot), String(Items.SLOT_ICONS[slot]), Color.WHITE, false])
    sections.append(["EMPTY SLOTS", slot_rows])
    var ids: Array = Items.catalog.keys()
    ids.sort_custom(func(x, y):
        var ix := Items.SLOTS.find(Items.get_item(String(x)).get("slot", ""))
        var iy := Items.SLOTS.find(Items.get_item(String(y)).get("slot", ""))
        return ix < iy if ix != iy else String(x) < String(y))
    var item_rows: Array = []
    for id in ids:
        var it: Dictionary = Items.get_item(String(id))
        item_rows.append([String(id), Items.icon_path(it), Items.icon_tint(it), String(it.get("icon", "")) == ""])
    sections.append(["ITEMS", item_rows])
    var gun_rows: Array = []
    for gid in Guns.all_ids():
        gun_rows.append([String(gid), Art.gun_icon_path(String(gid)), Color.WHITE, false])
    sections.append(["GUNS", gun_rows])
    var up_rows: Array = []
    for opt in LevelUps.options().filter(func(o): return int(o["rarity"]) == int(LevelUps.options().filter(func(q): return q["base"] == o["base"])[0]["rarity"])):
        var o: Dictionary = opt
        up_rows.append([String(o["id"]), String(o.get("icon", "")), Color.WHITE, false])
    sections.append(["LEVEL-UPS", up_rows])
    var class_rows: Array = []
    for m in Loadout.marks():
        var md: Dictionary = m
        class_rows.append([String(md["id"]), String(md["icon"]), Color.WHITE, false])
    sections.append(["MARKS", class_rows])
    var talent_rows: Array = []
    for row in Mastery.icon_rows():
        talent_rows.append([String(row[0]), String(row[1]), Color.WHITE, false])
    talent_rows.append([String(Mastery.SURVIVAL["id"]), String(Mastery.SURVIVAL["icon"]), Color.WHITE, false])
    talent_rows.append(["embers", Mastery.EMBER_ICON, Color.WHITE, false])
    sections.append(["SHRINE TALENTS", talent_rows])
    var trophy_rows: Array = []
    for a in Progress.ACHIEVEMENTS:
        var ad: Dictionary = a
        trophy_rows.append([String(ad["id"]), Progress.achievement_icon_path(ad), Color.WHITE, false])
    sections.append(["TROPHIES", trophy_rows])

    var cols := 12
    var cell_w := 156
    var cell_h := 108
    var head_h := 30
    var height := 16
    for sec in sections:
        var rows_n: int = ((sec[1] as Array).size() + cols - 1) / cols
        height += head_h + rows_n * cell_h + 8
    var sheet := Image.create_empty(cols * cell_w + 16, height, false, Image.FORMAT_RGBA8)
    sheet.fill(Color(0.09, 0.08, 0.10))
    var y := 8
    for sec in sections:
        var entries: Array = sec[1]
        FigureGen._text(sheet, 10, y + 6, "%s  %d" % [String(sec[0]), entries.size()], Color(0.95, 0.85, 0.55), 3)
        y += head_h
        for i in entries.size():
            var e: Array = entries[i]
            var ox := 8 + (i % cols) * cell_w
            var oy := y + (i / cols) * cell_h
            var well := Rect2i(ox + (cell_w - 72) / 2, oy, 72, 72)
            var icon_path := String(e[1])
            var missing := not Art.has_icon(icon_path)
            var frame := Color(0.85, 0.2, 0.2) if missing else (Color(1.0, 0.6, 0.2) if bool(e[3]) else Color(0.3, 0.27, 0.3))
            sheet.fill_rect(well, frame)
            sheet.fill_rect(well.grow(-2), Color(0.15, 0.13, 0.15))
            var tex: Texture2D = Art.icon(icon_path)
            var src: Image = tex.get_image() if tex != null else null
            if src != null and not src.is_empty():
                var big: Image = src.duplicate()
                if big.is_compressed():
                    big.decompress()
                big.convert(Image.FORMAT_RGBA8)
                big.resize(64, 64, Image.INTERPOLATE_NEAREST)
                var tint: Color = e[2]
                if tint != Color.WHITE:
                    for py in 64:
                        for px in 64:
                            big.set_pixel(px, py, big.get_pixel(px, py) * tint)
                sheet.blend_rect(big, Rect2i(0, 0, 64, 64), well.position + Vector2i(4, 4))
            var label := String(e[0]).to_upper()
            var per_line := (cell_w - 8) / 8
            FigureGen._text(sheet, ox + 4, oy + 78, label.substr(0, per_line), Color(0.85, 0.8, 0.75), 2)
            if label.length() > per_line:
                FigureGen._text(sheet, ox + 4, oy + 92, label.substr(per_line, per_line), Color(0.85, 0.8, 0.75), 2)
        y += ((entries.size() + cols - 1) / cols) * cell_h + 8
    return sheet.save_png(path)
