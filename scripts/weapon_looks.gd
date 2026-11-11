class_name WeaponLooks
extends RefCounted
## Code-drawn looks for every weapon family (Arsenal expansion 7). Guns keep their icon
## tiles (Art.GUN_ICONS); the new families draw here, one style per family, so a weapon
## reads by its silhouette and its element owns the colour in the world.
##
## The art-pack swap: `sprite_for(id, part)` returns a texture when the pack has one at
## res://assets/weapons/<id>_<part>.png and null otherwise; `icon` and the in-world parts
## ask it first, so pack sprites replace the code-drawn shapes one by one with no other
## code change. Parts: "icon" (cards, Build page, HUD strip, the held weapon).
##
## Melee silhouettes (batch 1): sweep a blade with a guard, cleave an axe head on a haft,
## thrust a spear with a leaf tip, slam a mace head, lash a whip curve, jab a gauntlet
## block, spin a scythe blade. 1 px dark outline, metal body, element-coloured edge (a
## second element is the guard or the stripe). Drawn on a 32 px tile pointing up-right,
## like the gun tiles, so Gun's orbit and Art.icon_sized treat them the same.

const PACK_DIR := "res://assets/weapons/"
const TILE := 32
const OUTLINE := Color(0.06, 0.05, 0.07, 1.0)
const METAL := Color(0.72, 0.72, 0.76)
const METAL_DARK := Color(0.45, 0.45, 0.50)
const WOOD := Color(0.48, 0.32, 0.20)
const GRIP := Color(0.30, 0.20, 0.14)
const SMEAR_ALPHA := 0.35

static var _icons: Dictionary = {}   # id -> Texture2D
static var _pack: Dictionary = {}    # "id:part" -> Texture2D or null


## A sprite from the art pack, or null when the pack has none for this weapon part.
static func sprite_for(id: String, part: String) -> Texture2D:
    var key := id + ":" + part
    if _pack.has(key):
        return _pack[key]
    var path := PACK_DIR + "%s_%s.png" % [id, part]
    var tex: Texture2D = null
    if ResourceLoader.exists(path):
        tex = load(path) as Texture2D
    _pack[key] = tex
    return tex


## Whether this module draws the weapon (it has no gun icon tile).
static func draws(id: String) -> bool:
    return Guns.DEFS.has(id) and Art.gun_icon_path(id) == ""


## The weapon's 32 px icon: the art pack's, else the code-drawn shape.
static func icon(id: String) -> Texture2D:
    var packed := sprite_for(id, "icon")
    if packed != null:
        return packed
    if _icons.has(id):
        return _icons[id]
    var d := Guns.make(id)
    var img := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
    img.fill(Color(0, 0, 0, 0))
    var edge: Color = Element.COLORS.get(d.element, METAL) if d.element != Element.Kind.NONE else Color(0.9, 0.9, 0.95)
    var second: Color = Element.COLORS.get(d.alt_element, edge) if d.alt_element != Element.Kind.NONE else edge
    match d.style:
        "cleave":
            _stroke(img, Vector2(5, 28), Vector2(24, 9), 3.0, WOOD)
            _poly(img, [Vector2(17, 6), Vector2(27, 5), Vector2(28, 16), Vector2(22, 13)], METAL)
            _stroke(img, Vector2(27, 5), Vector2(28, 16), 2.0, edge)
            _stroke(img, Vector2(18, 8), Vector2(22, 12), 2.0, second)
        "thrust":
            _stroke(img, Vector2(3, 29), Vector2(23, 9), 2.0, WOOD)
            _poly(img, [Vector2(21, 8), Vector2(29, 3), Vector2(24, 11)], METAL)
            _stroke(img, Vector2(23, 7), Vector2(29, 3), 1.5, edge)
            _stroke(img, Vector2(19, 13), Vector2(22, 10), 2.5, second)
        "slam":
            _stroke(img, Vector2(5, 28), Vector2(18, 15), 3.0, WOOD)
            _disc(img, Vector2(21, 11), 7.0, METAL_DARK)
            _disc(img, Vector2(21, 11), 4.5, edge)
            for a in [0.0, PI * 0.5, PI, PI * 1.5]:
                _stroke(img, Vector2(21, 11) + Vector2.RIGHT.rotated(a + PI * 0.25) * 6.0, Vector2(21, 11) + Vector2.RIGHT.rotated(a + PI * 0.25) * 9.0, 2.0, METAL)
            _disc(img, Vector2(21, 11), 2.0, second)
        "lash":
            _stroke(img, Vector2(4, 28), Vector2(10, 22), 3.0, GRIP)
            var prev := Vector2(10, 22)
            for k in range(1, 11):
                var t := float(k) / 10.0
                var pt := Vector2(10, 22).lerp(Vector2(28, 4), t) + Vector2(1, 1).normalized() * sin(t * TAU) * 4.0
                _stroke(img, prev, pt, 2.0 if k < 8 else 1.5, edge if k > 6 else METAL_DARK)
                prev = pt
            _disc(img, prev, 1.5, second)
        "jab":
            _poly(img, [Vector2(8, 12), Vector2(22, 7), Vector2(26, 19), Vector2(12, 25)], METAL_DARK)
            _poly(img, [Vector2(10, 14), Vector2(21, 10), Vector2(24, 18), Vector2(13, 22)], METAL)
            for k in 4:
                _disc(img, Vector2(21, 9).lerp(Vector2(25, 19), float(k) / 3.0) + Vector2(1, 0), 1.6, edge)
            _stroke(img, Vector2(9, 18), Vector2(14, 24), 2.0, second)
        "spin":
            _stroke(img, Vector2(4, 29), Vector2(22, 9), 2.5, WOOD)
            var pts: Array = []
            for k in 9:
                var a := lerpf(-PI * 0.95, -PI * 0.2, float(k) / 8.0)
                pts.append(Vector2(21, 14) + Vector2.RIGHT.rotated(a) * 10.0)
            for k in range(8, -1, -1):
                var a := lerpf(-PI * 0.95, -PI * 0.2, float(k) / 8.0)
                pts.append(Vector2(22, 13) + Vector2.RIGHT.rotated(a) * 6.5)
            _poly(img, pts, METAL)
            for k in 8:
                _stroke(img, pts[k], pts[k + 1], 1.5, edge if k % 2 == 0 else second)
        # --- Thrown (batch 2): the object itself -----------------------------------
        "knife":
            for k in 3:
                var o := Vector2(float(k) * 4.0 - 4.0, float(1 - k) * 4.0 + 4.0)
                _poly(img, [Vector2(8, 24) + o, Vector2(10, 26) + o, Vector2(24, 8) + o, Vector2(22, 6) + o], METAL)
                _stroke(img, Vector2(10, 25) + o, Vector2(23, 8) + o, 1.0, edge)
                _stroke(img, Vector2(5, 27) + o, Vector2(9, 23) + o, 2.0, GRIP)
        "disc":
            _disc(img, Vector2(16, 16), 11.0, METAL_DARK)
            _disc(img, Vector2(16, 16), 9.0, edge)
            _disc(img, Vector2(16, 16), 4.0, Color(0, 0, 0, 0))
            _stroke(img, Vector2(9, 12), Vector2(13, 8), 1.5, Color(1, 1, 1, 0.9))
        "star":
            var spts: Array = []
            for k in 8:
                spts.append(Vector2(16, 16) + Vector2.RIGHT.rotated(PI * 0.25 * float(k) + 0.2) * (13.0 if k % 2 == 0 else 4.5))
            _poly(img, spts, edge)
            _disc(img, Vector2(16, 16), 2.5, METAL)
        "grenade":
            _disc(img, Vector2(15, 18), 9.0, edge.darkened(0.3))
            _stroke(img, Vector2(10, 13), Vector2(20, 23), 1.5, edge.lightened(0.2))
            _poly(img, [Vector2(17, 6), Vector2(23, 7), Vector2(22, 11), Vector2(18, 10)], METAL_DARK)
            _stroke(img, Vector2(22, 7), Vector2(27, 3), 1.0, Color(0.9, 0.8, 0.6))
        "javelin":
            _stroke(img, Vector2(3, 29), Vector2(23, 9), 2.0, WOOD)
            _poly(img, [Vector2(20, 7), Vector2(30, 2), Vector2(25, 12)], edge)
            _stroke(img, Vector2(6, 26), Vector2(9, 23), 3.0, METAL_DARK)
        "bola":
            _stroke(img, Vector2(8, 24), Vector2(16, 14), 1.0, Color(0.6, 0.5, 0.35))
            _stroke(img, Vector2(16, 14), Vector2(25, 9), 1.0, Color(0.6, 0.5, 0.35))
            _stroke(img, Vector2(16, 14), Vector2(22, 25), 1.0, Color(0.6, 0.5, 0.35))
            for c in [Vector2(8, 24), Vector2(25, 9), Vector2(22, 25)]:
                _disc(img, c, 4.0, edge)
        "anchor":
            _stroke(img, Vector2(16, 5), Vector2(16, 26), 3.0, METAL_DARK)
            _stroke(img, Vector2(10, 10), Vector2(22, 10), 2.0, METAL_DARK)
            _disc(img, Vector2(16, 4), 2.5, METAL)
            for k in 9:
                var t := float(k) / 8.0
                _disc(img, Vector2(16, 18) + Vector2(0, 1).rotated(lerpf(-1.4, 1.4, t)) * 9.0, 1.6, edge)
            _disc(img, Vector2(16, 18) + Vector2(0, 1).rotated(-1.4) * 9.0, 2.2, second)
            _disc(img, Vector2(16, 18) + Vector2(0, 1).rotated(1.4) * 9.0, 2.2, second)
        "boomerang":
            _poly(img, [Vector2(6, 8), Vector2(16, 4), Vector2(26, 10), Vector2(21, 12), Vector2(15, 9), Vector2(9, 13)], edge)
            _poly(img, [Vector2(6, 24), Vector2(16, 28), Vector2(26, 22), Vector2(21, 20), Vector2(15, 23), Vector2(9, 19)], second)
            _stroke(img, Vector2(4, 16), Vector2(28, 16), 1.5, WOOD)
        "pool":
            _poly(img, [Vector2(13, 4), Vector2(19, 4), Vector2(19, 10), Vector2(13, 10)], Color(0.6, 0.5, 0.4))
            _disc(img, Vector2(16, 19), 9.0, Color(0.75, 0.8, 0.85, 0.9))
            _disc(img, Vector2(16, 21), 7.0, edge)
            _stroke(img, Vector2(11, 15), Vector2(13, 13), 1.5, Color(1, 1, 1, 0.9))
        # --- New guns (batch 2), by archetype ------------------------------------------
        "revolver", "repeater", "sniper", "hymn", "shotgun", "sticky":
            var long := 24.0 if d.style == "sniper" else (18.0 if d.style == "repeater" else 15.0)
            _poly(img, [Vector2(6, 26), Vector2(10, 29), Vector2(15, 21), Vector2(11, 18)], WOOD if d.style != "hymn" else Color(0.45, 0.12, 0.14))
            _stroke(img, Vector2(12, 20), Vector2(12 + long * 0.7, 20 - long * 0.7), 4.0 if d.style == "shotgun" else 3.0, METAL_DARK)
            _stroke(img, Vector2(13, 19), Vector2(12 + long * 0.7, 20 - long * 0.7), 1.0, edge)
            if d.style == "revolver":
                _disc(img, Vector2(15, 17), 3.5, METAL)
                _disc(img, Vector2(15, 17), 1.5, edge)
            elif d.style == "repeater":
                for k in 3:
                    _stroke(img, Vector2(16 + k * 3, 16 - k * 3), Vector2(19 + k * 3, 19 - k * 3), 1.0, METAL)
            elif d.style == "sniper":
                _stroke(img, Vector2(14, 13), Vector2(20, 7), 2.5, METAL)
            elif d.style == "sticky":
                _poly(img, [Vector2(23, 9), Vector2(29, 3), Vector2(26, 11)], edge)
            elif d.style == "hymn":
                _disc(img, Vector2(17, 15), 3.0, edge)
            if d.behaviour == "converge":
                _disc(img, Vector2(26, 6), 3.0, second)
        "bubble":
            _poly(img, [Vector2(6, 26), Vector2(10, 29), Vector2(15, 21), Vector2(11, 18)], Color(0.9, 0.55, 0.3))
            _stroke(img, Vector2(12, 20), Vector2(19, 13), 4.0, Color(0.4, 0.75, 0.9))
            _disc(img, Vector2(24, 8), 5.0, Color(edge, 0.5))
            _disc(img, Vector2(22, 6), 1.2, Color(1, 1, 1, 0.9))
        "bow":
            var bpts: Array = []
            for k in 11:
                bpts.append(Vector2(16, 16) + Vector2.RIGHT.rotated(lerpf(-2.3, 0.75, float(k) / 10.0)) * 12.0)
            for k in 10:
                _stroke(img, bpts[k], bpts[k + 1], 2.0, WOOD)
            _stroke(img, bpts[0], bpts[10], 1.0, Color(0.9, 0.9, 0.85))
            _stroke(img, Vector2(6, 26), Vector2(26, 6), 1.5, METAL)
            _poly(img, [Vector2(26, 3), Vector2(29, 6), Vector2(24, 8)], edge)
        "reflect":
            _poly(img, [Vector2(5, 25), Vector2(9, 29), Vector2(16, 22), Vector2(12, 18)], METAL_DARK)
            _poly(img, [Vector2(14, 16), Vector2(22, 8), Vector2(26, 12), Vector2(18, 20)], Color(0.8, 0.9, 1.0))
            _stroke(img, Vector2(22, 10), Vector2(29, 3), 1.5, edge)
            _stroke(img, Vector2(26, 6), Vector2(30, 10), 1.0, edge)
        "harpoon":
            _stroke(img, Vector2(4, 28), Vector2(14, 18), 4.0, METAL_DARK)
            _stroke(img, Vector2(14, 18), Vector2(27, 5), 1.5, METAL)
            _poly(img, [Vector2(30, 2), Vector2(24, 4), Vector2(28, 8)], edge)
            _stroke(img, Vector2(25, 8), Vector2(22, 7), 1.0, METAL)
            _stroke(img, Vector2(5, 22), Vector2(10, 27), 1.0, Color(0.6, 0.5, 0.35))
        # --- Summons (batch 3): round bodies with an element core and a darker rim ------
        "drone":
            _stroke(img, Vector2(5, 9), Vector2(13, 9), 1.5, METAL)
            _stroke(img, Vector2(19, 9), Vector2(27, 9), 1.5, METAL)
            _stroke(img, Vector2(10, 11), Vector2(13, 14), 1.5, METAL_DARK)
            _stroke(img, Vector2(22, 11), Vector2(19, 14), 1.5, METAL_DARK)
            _disc(img, Vector2(16, 18), 9.0, edge.darkened(0.55))
            _disc(img, Vector2(16, 18), 5.5, edge)
            if d.behaviour == "rain":
                for x in [11, 16, 21]:
                    _stroke(img, Vector2(x, 27), Vector2(x - 1, 30), 1.0, second)
            elif d.behaviour == "lob":
                _disc(img, Vector2(16, 28), 2.5, METAL_DARK)
            elif d.id == "watchers_eye":
                _disc(img, Vector2(17, 18), 2.5, Color(0.05, 0.02, 0.08))
            else:
                _disc(img, Vector2(14, 16), 1.5, Color(1, 1, 1, 0.9))
        "familiar":
            _poly(img, [Vector2(7, 9), Vector2(11, 3), Vector2(13, 11)], edge.darkened(0.4))
            _poly(img, [Vector2(25, 9), Vector2(21, 3), Vector2(19, 11)], second.darkened(0.4))
            _disc(img, Vector2(16, 18), 10.0, edge.darkened(0.5))
            _disc(img, Vector2(16, 19), 7.0, edge)
            if second != edge:
                _poly(img, [Vector2(16, 9), Vector2(26, 18), Vector2(16, 28)], second)
            _disc(img, Vector2(12, 16), 1.6, OUTLINE)
            _disc(img, Vector2(20, 16), 1.6, OUTLINE)
        "orbit":
            for k in 8:
                var a0 := TAU * float(k) / 8.0
                _stroke(img, Vector2(16, 16) + Vector2.RIGHT.rotated(a0) * 10.0, Vector2(16, 16) + Vector2.RIGHT.rotated(a0 + 0.4) * 10.0, 1.0, Color(METAL, 0.6))
            _disc(img, Vector2(16, 16), 3.0, METAL_DARK)
            var n := clampi(d.summon_bodies(), 1, 3)
            for k in n:
                var at := Vector2(16, 16) + Vector2.RIGHT.rotated(-PI * 0.25 + TAU * float(k) / float(n)) * 10.0
                _disc(img, at, 4.5, edge.darkened(0.5))
                _disc(img, at, 3.0, edge if k % 2 == 0 else second)
        "swarm":
            _poly(img, [Vector2(5, 22), Vector2(9, 15), Vector2(17, 15), Vector2(21, 22), Vector2(17, 29), Vector2(9, 29)], Color(0.62, 0.5, 0.32))
            _disc(img, Vector2(13, 22), 2.5, OUTLINE)
            for at in [Vector2(22, 8), Vector2(27, 14), Vector2(17, 6), Vector2(26, 23)]:
                _disc(img, at, 2.2, edge)
                _stroke(img, at + Vector2(-2, -2), at + Vector2(0, -1), 1.0, Color(1, 1, 1, 0.7))
            if second != edge:
                _disc(img, Vector2(22, 8), 2.2, second)
        "golem":
            _poly(img, [Vector2(7, 18), Vector2(25, 18), Vector2(25, 29), Vector2(7, 29)], Color(0.50, 0.40, 0.31))
            _poly(img, [Vector2(10, 9), Vector2(22, 9), Vector2(22, 19), Vector2(10, 19)], Color(0.60, 0.50, 0.40))
            _disc(img, Vector2(16, 6), 4.0, Color(0.55, 0.45, 0.36))
            _disc(img, Vector2(16, 6), 2.0, edge)
            _stroke(img, Vector2(4, 16), Vector2(8, 24), 3.0, Color(0.5, 0.4, 0.31))
            _stroke(img, Vector2(28, 16), Vector2(24, 24), 3.0, Color(0.5, 0.4, 0.31))
        "turret":
            _stroke(img, Vector2(16, 20), Vector2(8, 29), 1.5, METAL_DARK)
            _stroke(img, Vector2(16, 20), Vector2(24, 29), 1.5, METAL_DARK)
            _stroke(img, Vector2(16, 20), Vector2(16, 29), 1.5, METAL_DARK)
            if d.chain_jumps > 0:
                _stroke(img, Vector2(16, 20), Vector2(16, 6), 3.0, METAL)
                _disc(img, Vector2(16, 6), 4.0, edge)
                _stroke(img, Vector2(20, 5), Vector2(26, 2), 1.0, edge)
                _stroke(img, Vector2(12, 5), Vector2(6, 2), 1.0, edge)
            else:
                _disc(img, Vector2(16, 16), 7.0, METAL_DARK)
                _disc(img, Vector2(16, 16), 4.5, edge)
                _stroke(img, Vector2(18, 14), Vector2(28, 6), 3.0, METAL)
        # --- Ground (batch 4): geometric marks (a dashed ring, a pillar with a gem, a jagged
        # ring, a three-stroke rune, a dotted line) -----------------------------------
        "aura", "pulse":
            var rings := [12.0] if d.style == "aura" else [6.0, 10.0, 14.0]
            for rr in rings:
                for k in 12:
                    var a0 := TAU * float(k) / 12.0
                    _stroke(img, Vector2(16, 16) + Vector2.RIGHT.rotated(a0) * rr, Vector2(16, 16) + Vector2.RIGHT.rotated(a0 + 0.26) * rr, 1.5, edge)
            if d.style == "aura":
                _disc(img, Vector2(16, 13), 3.0, Color(0.85, 0.82, 0.78))
                _poly(img, [Vector2(12, 22), Vector2(20, 22), Vector2(18, 16), Vector2(14, 16)], Color(0.85, 0.82, 0.78))
            else:
                _disc(img, Vector2(16, 16), 2.5, second)
        "trail":
            for k in 6:
                var at := Vector2(5 + 4.2 * k, 26 - 3.6 * k + (2.0 if k % 2 == 0 else -1.0))
                _disc(img, at, 1.8, edge)
            _poly(img, [Vector2(23, 5), Vector2(29, 5), Vector2(29, 11), Vector2(23, 11)], Color(0.62, 0.5, 0.32))
        "totem":
            _poly(img, [Vector2(12, 12), Vector2(20, 12), Vector2(20, 28), Vector2(12, 28)], Color(0.58, 0.55, 0.50))
            _poly(img, [Vector2(9, 27), Vector2(23, 27), Vector2(23, 30), Vector2(9, 30)], Color(0.42, 0.40, 0.37))
            _stroke(img, Vector2(12, 19), Vector2(20, 19), 1.0, Color(0.42, 0.40, 0.37))
            _disc(img, Vector2(16, 8), 4.5, edge)
            _disc(img, Vector2(15, 7), 1.5, Color(1, 1, 1, 0.8))
        "field":
            for k in 7:
                var at := Vector2(16, 18) + Vector2(cos(TAU * k / 7.0) * 11.0, sin(TAU * k / 7.0) * 7.0)
                _disc(img, at, 1.6, edge)
            _disc(img, Vector2(16, 18), 5.0, edge.darkened(0.3))
            _disc(img, Vector2(14, 17), 1.8, second)
        "snare", "pod":
            var pts: Array = []
            for k in 17:
                var a1 := TAU * float(k) / 16.0
                pts.append(Vector2(16, 17) + Vector2.RIGHT.rotated(a1) * (12.0 if k % 2 == 0 else 8.0))
            for k in 16:
                _stroke(img, pts[k], pts[k + 1], 1.5, METAL if d.style == "snare" else edge.darkened(0.2))
            if d.style == "pod":
                _disc(img, Vector2(16, 17), 5.0, edge)
                _disc(img, Vector2(16, 17), 2.5, second)
            else:
                _disc(img, Vector2(16, 17), 3.0, edge)
        "glyph":
            _stroke(img, Vector2(7, 25), Vector2(16, 6), 2.0, edge)
            _stroke(img, Vector2(16, 6), Vector2(25, 25), 2.0, edge)
            _stroke(img, Vector2(10, 17), Vector2(22, 17), 2.0, second if second != edge else edge.lightened(0.3))
        "mine":
            _disc(img, Vector2(16, 18), 9.0, Color(0.62, 0.6, 0.56))
            _disc(img, Vector2(16, 18), 6.0, edge.darkened(0.3))
            _disc(img, Vector2(16, 17), 2.5, Color(1, 1, 1, 0.9))
            var ex: Color = Element.COLORS.get(d.extra_element, edge) if d.extra_element != Element.Kind.NONE else edge
            for k in 4:
                var a2 := TAU * float(k) / 4.0 + PI * 0.25
                _stroke(img, Vector2(16, 18) + Vector2.RIGHT.rotated(a2) * 9.0, Vector2(16, 18) + Vector2.RIGHT.rotated(a2) * 13.0, 2.0, ex)
        _:   # sweep: a blade, a guard, a grip
            _stroke(img, Vector2(4, 28), Vector2(9, 23), 3.0, GRIP)
            _stroke(img, Vector2(6, 19), Vector2(13, 26), 2.5, second if second != edge else METAL_DARK)
            _poly(img, [Vector2(8, 21), Vector2(11, 24), Vector2(28, 4), Vector2(27, 3)], METAL)
            _stroke(img, Vector2(11, 23), Vector2(28, 4), 1.5, edge)
    _outline(img)
    var tex := ImageTexture.create_from_image(img)
    _icons[id] = tex
    return tex


## The swing smear (2.3): a thin shape of the swing in the element colour at 35% alpha,
## gone in 0.1 s. `f` runs 0..1 over its life. Drawn by GunFx on the "your effects" layer.
static func draw_smear(cv: CanvasItem, shape: String, c: Vector2, dir: Vector2, reach: float, half: float, col: Color, back: bool, f: float) -> void:
    var a := SMEAR_ALPHA * (1.0 - f)
    match shape:
        "thrust":
            var n := dir.orthogonal()
            var tip := c + dir * reach
            var base := c + dir * 18.0
            var w := 5.0 * (1.0 - f * 0.5)
            cv.draw_colored_polygon(PackedVector2Array([base + n * w, tip, base - n * w]), Color(col, a))
            cv.draw_line(base, tip, Color(1, 1, 1, a), 1.0)
        "slam":
            cv.draw_circle(c, reach * (0.7 + 0.3 * f), Color(col, a * 0.6))
            cv.draw_arc(c, reach * (0.7 + 0.3 * f), 0.0, TAU, 24, Color(col, a * 1.5), 1.5)
        "spin":
            cv.draw_arc(c, reach * 0.85, 0.0, TAU, 32, Color(col, a), reach * 0.3)
        _:
            var from := -half if not back else half
            var to := half if not back else -half
            var edge := lerpf(from, to, minf(1.0, f * 2.0 + 0.4))
            var pts := PackedVector2Array([c])
            var steps := 10
            for k in steps + 1:
                pts.append(c + dir.rotated(lerpf(from, edge, float(k) / float(steps))) * reach)
            cv.draw_colored_polygon(pts, Color(col, a))
            var e := dir.rotated(edge)
            cv.draw_line(c + e * reach * 0.35, c + e * reach, Color(1, 1, 1, a * 1.5), 1.5)


# --- Raster helpers (32 px tiles) -------------------------------------------


static func _stroke(img: Image, a: Vector2, b: Vector2, w: float, col: Color) -> void:
    var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2.ONE * w
    var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2.ONE * w
    for y in range(maxi(0, int(lo.y)), mini(TILE, int(hi.y) + 1)):
        for x in range(maxi(0, int(lo.x)), mini(TILE, int(hi.x) + 1)):
            var p := Vector2(x + 0.5, y + 0.5)
            if Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) <= w * 0.5:
                img.set_pixel(x, y, col)


static func _disc(img: Image, c: Vector2, r: float, col: Color) -> void:
    for y in range(maxi(0, int(c.y - r - 1)), mini(TILE, int(c.y + r + 2))):
        for x in range(maxi(0, int(c.x - r - 1)), mini(TILE, int(c.x + r + 2))):
            if Vector2(x + 0.5, y + 0.5).distance_to(c) <= r:
                img.set_pixel(x, y, col)


static func _poly(img: Image, pts: Array, col: Color) -> void:
    var poly := PackedVector2Array(pts)
    for y in TILE:
        for x in TILE:
            if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), poly):
                img.set_pixel(x, y, col)


## A 1 px dark outline around everything drawn.
static func _outline(img: Image) -> void:
    var solid := []
    for y in TILE:
        for x in TILE:
            solid.append(img.get_pixel(x, y).a > 0.5)
    for y in TILE:
        for x in TILE:
            if solid[y * TILE + x]:
                continue
            for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
                var q: Vector2i = Vector2i(x, y) + o
                if q.x >= 0 and q.y >= 0 and q.x < TILE and q.y < TILE and solid[q.y * TILE + q.x]:
                    img.set_pixel(x, y, OUTLINE)
                    break
