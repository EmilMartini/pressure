class_name GearShot
extends Node
## Debug capture for worn gear (WornGear on the FigureGen figure), run with the bot:
##   godot --path . --audio-driver Dummy res://scenes/main.tscn -- --autotest --secs=40
##       --gear-shot[=id,id,...] [--pixel-size=N] [--set=key:value,...] [--no-sheets]
## Saves the sheets autotest/gear_<slot>.png (every head, chest, hands and feet item worn
## on three bodies, FigureGen.gear_sheet), dresses the player in the listed items
## (default: a wizard), forces the pixel size (default 3, not saved) and saves
## autotest/gear_fight_<n>.png (the window) and gear_zoom_<n>.png (the player cropped and
## scaled 4x): one calm shot in the entrance, then shots while the bot fights.

const WEAR := ["thinking_cap", "plate_scrap", "hair_trigger", "light_boots"]
const SHOTS := [1.5, 8.0, 14.0, 20.0, 26.0, 32.0]
const CROP := 60.0   # logical screen pixels around the player

var main: Node
var _t := 0.0
var _next := 0


static func wanted() -> bool:
    for a in OS.get_cmdline_user_args():
        if a == "--gear-shot" or a.begins_with("--gear-shot="):
            return true
    return false


static func _arg(prefix: String, fallback: Array) -> Array:
    for a in OS.get_cmdline_user_args():
        if a.begins_with(prefix):
            var out: Array = []
            for id in a.substr(prefix.length()).split(",", false):
                out.append(String(id))
            return out
    return fallback


func _init(m: Node) -> void:
    main = m
    name = "GearShot"


func _ready() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://autotest"))
    var ps := _arg("--pixel-size=", ["3"])
    Settings.values["pixel_size"] = int(ps[0])
    # --set=bloom:0,crt:1 overrides other options for the capture (not saved).
    for kv in _arg("--set=", []):
        var parts := String(kv).split(":")
        if parts.size() == 2:
            Settings.values[parts[0]] = bool(int(parts[1])) if typeof(Settings.values.get(parts[0])) == TYPE_BOOL else float(parts[1])
    if not OS.get_cmdline_user_args().has("--no-sheets"):
        for slot in WornGear.SLOTS:
            var t0 := Time.get_ticks_usec()
            FigureGen.gear_sheet("res://autotest/gear_%s.png" % slot, slot)
            print("[GEAR] sheet %s %.0f ms" % [slot, float(Time.get_ticks_usec() - t0) / 1000.0])
    var p1: Player = main.players[0]
    for id in _arg("--gear-shot=", WEAR):
        p1.equip(id)
    var fig := FigureGen.generate(p1)
    print("[GEAR] wears %s -> %s" % [str(WornGear.worn_of(p1)), fig["name"]])
    # Generation cost of a fresh figure (cache cleared), averaged.
    var t1 := Time.get_ticks_usec()
    for i in 20:
        FigureGen._cache.clear()
        FigureGen.generate(p1)
    print("[GEAR] generate %.2f ms per figure (uncached)" % (float(Time.get_ticks_usec() - t1) / 20000.0))


func _process(delta: float) -> void:
    _t += delta
    if _next >= SHOTS.size() or _t < float(SHOTS[_next]):
        return
    _next += 1
    _capture(_next)


func _capture(n: int) -> void:
    await RenderingServer.frame_post_draw
    var vp := get_viewport()
    var img := vp.get_texture().get_image()
    if img == null:
        return
    img.save_png("res://autotest/gear_fight_%d.png" % n)
    var k := float(img.get_width()) / vp.get_visible_rect().size.x
    var tiles: Array = []
    for p in [main.players[0]]:
        var at: Vector2 = vp.get_canvas_transform() * (p as Node2D).global_position
        var r := Rect2i(Vector2i((at - Vector2(CROP, CROP)) * k), Vector2i(Vector2(CROP, CROP) * 2.0 * k))
        r = r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
        if r.size.x <= 0 or r.size.y <= 0:
            continue
        var c := img.get_region(r)
        c.resize(c.get_width() * 4, c.get_height() * 4, Image.INTERPOLATE_NEAREST)
        tiles.append(c)
    if tiles.is_empty():
        return
    var w := 0
    var h := 0
    for t in tiles:
        w += (t as Image).get_width() + 8
        h = maxi(h, (t as Image).get_height())
    var sheet := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
    sheet.fill(Color(0.05, 0.05, 0.05))
    var x := 0
    for t in tiles:
        var ti: Image = t
        ti.convert(Image.FORMAT_RGBA8)
        sheet.blit_rect(ti, Rect2i(Vector2i.ZERO, ti.get_size()), Vector2i(x, 0))
        x += ti.get_width() + 8
    sheet.save_png("res://autotest/gear_zoom_%d.png" % n)
    print("[GEAR] shot %d at %.0f s, enemies=%d" % [n, _t, main.current.enemies.get_child_count() if main.current != null else -1])
