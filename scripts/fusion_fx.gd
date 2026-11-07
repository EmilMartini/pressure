class_name FusionFx
extends RefCounted
## Presentation for tier 3 fusions and tier 4 cataclysms (see fusions.gd), composed from
## what already exists: the element signatures and outlines in Fx, PostFx pulses, the Sfx
## bank (rumble follows the Sfx bus), the reaction-label path for the name, and Main's
## hit-stop, flash and shake (which respect the hit-stop and screen-shake settings). Each
## call is one burst of work; nothing here runs per frame.
##
## Scale by tier: a fusion is about a signature reaction moment and a half (its signatures,
## a 28 px name, screen pulses and a short hit-stop rationed to one per STOP_GAP_MS); a cataclysm is the
## biggest moment in the game short of a boss death (its signatures ringed around the field,
## a white ring, a 44 px name in capitals, the longest hit-stop, a coloured flash).

const SIZES := { "small": 55.0, "medium": 75.0, "large": 100.0, "huge": 125.0, "cataclysm": 150.0 }
## Tier 3 hit-stops and full flashes at most this often (real ms); tier 4 is already rationed
## by Fusions.CATACLYSM_ROOM_COOLDOWN.
const STOP_GAP_MS := 450

static var _stop_ms := -100000


## `first`: discovered just now (first time ever on this save): the label says NEW.
const LABEL_GAP_MS := 4000
static var _last_label := {}   # fusion name -> real ms its label last showed


static func play(main: Node, fusion_name: String, tier: int, pos: Vector2, reach: float, entry: Dictionary, first := false) -> void:
    if main == null:
        return
    var vis: Dictionary = entry.get("visuals", {})
    var sigs: Array = vis.get("sigs", [])
    var cata := tier >= Fusions.TIER_CATACLYSM
    var size: float = SIZES.get(String(vis.get("size", "medium")), 75.0)
    var col := _color(sigs)
    var lead: int = int(sigs[sigs.size() - 1]) if not sigs.is_empty() else 0
    var fx: Fx = main.get("fx")
    if fx != null:
        # The element that just arrived leads at full size; the ones it fused with echo,
        # smaller. A cataclysm rings its echoes around the field.
        var n := sigs.size()
        for i in n:
            var kind := int(sigs[n - 1 - i])
            var s := size * (1.0 - 0.15 * float(i))
            var st := (1.4 if cata else 1.1) * (1.0 - 0.18 * float(i))
            if cata and i > 0:
                var off := Vector2.RIGHT.rotated(TAU * float(i) / float(maxi(1, n - 1)) + randf() * 0.6) * reach * 0.45
                fx.signature(kind, pos + off * Vector2(1.0, 0.6), s * 0.8, st)
            else:
                fx.signature(kind, pos, s, st)
        fx.burst_outline(pos, reach, lead, 0.45 if cata else 0.35)
        if cata:
            fx.outline(pos, reach * 1.15, 0, 0.9, 2.0, 0.45)
        var tex: Texture2D = Art.PARTICLES.get(String(vis.get("fx", "circle")), Art.PARTICLES["circle"])
        fx.puff(tex, pos, Color(col, 0.5), size * (3.0 if cata else 2.0), 0.5 if cata else 0.35, true, Vector2.ZERO, 0.8)
        fx.throw_drops(lead, pos, clampf(reach * 0.7, 60.0, 200.0), 16 if cata else 10)
        var text := fusion_name.to_upper() if cata else fusion_name
        if first:
            # Clarity pass: a discovery is a HUD toast (held until the room is clear), not a
            # second name in the fight.
            var hud = main.get("hud")
            if hud != null:
                hud.toast("New %s: %s" % ["cataclysm" if cata else "fusion", fusion_name])
        # Clarity pass: one name per fusion every LABEL_GAP_MS, not one per fire.
        var now := Time.get_ticks_msec()
        if now - int(_last_label.get(fusion_name, -100000)) < LABEL_GAP_MS:
            text = ""
        else:
            _last_label[fusion_name] = now
        var lp := pos + Vector2(0, -56.0 if cata else -42.0)
        # The name is centred on lp and about len * size * 0.75 wide: if any part of it would
        # cross the character, lift it clear above them.
        var half_w := maxf(200.0, float(text.length() * (44 if cata else 28)) * 0.75) * 0.5
        for pl in main.get("players"):
            if is_instance_valid(pl) and absf(lp.x - pl.global_position.x) < half_w + 16.0 and absf(lp.y - pl.global_position.y) < 70.0:
                lp.y = pl.global_position.y - 100.0
        if text != "":
            fx.label(lp, text, col.lightened(0.35), 44 if cata else 28, 1.8 if cata else 1.2)
    # Sound: the entry's layers, the first loudest.
    var sounds: Array = entry.get("sound", [])
    for i in sounds.size():
        Sfx.play(String(sounds[i]), (1.5 if cata else 0.0) - 2.5 * float(i), -1.0, pos)
    # Weight. Screen-wide pulses (ripple, aberration, hit-stop, flash) are rationed for tier 3
    # so six fusions a second never smear the picture; a cataclysm always gets all of them.
    var now := Time.get_ticks_msec()
    var big := cata or now - _stop_ms >= STOP_GAP_MS
    if sigs.has(Element.Kind.FIRE):
        PostFx.heat_pulse(1.2 if cata else 0.6)
    if main.has_method("shake"):
        main.shake(14.0 if cata else (7.0 if big else 4.0))
    if not big:
        return
    _stop_ms = now
    PostFx.shockwave(pos, 1.3 if cata else 0.7, reach * (1.8 if cata else 1.4))
    PostFx.aberration_pulse(2.0 if cata else 0.8)
    if cata or sigs.has(Element.Kind.HOLY) or sigs.has(Element.Kind.SHOCK):
        PostFx.bloom_pulse(1.0 if cata else 0.5)
    if main.has_method("hitstop"):
        main.hitstop(0.16 if cata else 0.07)
        main.flash(col.lightened(0.3), 0.42 if cata else 0.2, 0.35 if cata else 0.2)


## The mix of the entry's element colours, lifted so it reads on dark floors.
static func _color(sigs: Array) -> Color:
    if sigs.is_empty():
        return Color.WHITE
    var c := Color(0, 0, 0, 1)
    for k in sigs:
        var e: Color = Element.COLORS.get(int(k), Color.WHITE)
        c.r += e.r
        c.g += e.g
        c.b += e.b
    var n := float(sigs.size())
    return Color(c.r / n, c.g / n, c.b / n).lightened(0.15)
