class_name Hud
extends Control
## In-run HUD split across the screen like a traditional action game: vitals cards top
## left, room title, wave timer and boss bar top centre, minimap with scrap and kills top
## right, gear bottom left, gun hotbars bottom centre and the vent gauge bottom right.
## Every label uses the readable body font; the pixel font is kept for headings and big
## numbers only.

const CELL := 22.0
const CELL_GAP := 5.0
const MARGIN := 16.0

const CARD_W := 300.0
const CARD_H := 84.0
const CARD_GAP := 12.0

const SLOT := 44.0
const SLOT_GAP := 6.0
const SLOTS_PER_ROW := 10
const GEAR_BIG := 36.0   # fits a 32 px icon at 1x
const GEAR_SMALL := 22.0

const VENT_W := 240.0
const VENT_H := 16.0
const VENT_STACK := 68.0

## How far the bottom widgets lift while the F1 help strip is showing.
const HELP_LIFT := 84.0

const HOT := Color(1.0, 0.45, 0.15)
const COLD := Color(0.45, 0.75, 1.0)
const ANNOUNCE := Color(1.0, 0.9, 0.4)

const ROOM_ICONS := {
    RoomData.Type.START: Vector2i(41, 16),
    RoomData.Type.BOSS: Vector2i(38, 11),
    RoomData.Type.SHOP: Vector2i(36, 16),
    RoomData.Type.TREASURE: Vector2i(9, 11),
    RoomData.Type.CHALLENGE: Vector2i(28, 12),
    RoomData.Type.HIDDEN: Vector2i(37, 13),
    RoomData.Type.DEAL: Vector2i(38, 11),
}

var main: Main
var _font: Font
var _toasts: Array = []   # { text, t }
var _time := 0.0
## Last thing picked up, shown in one line over the gear row for PICK_TIME seconds:
## { name, effect, col (rarity text colour), frame (rarity colour), tag (rarity word),
## icon, icon_tint, who, t }. Rarity owns the colour; a gun's tier maps through
## Items.tier_rarity. Elements never colour HUD frames (GDD 6, "Rarity owns colour").
var _pick: Dictionary = {}
var _seen_items: Dictionary = {}   # player instance id -> item ids worn last frame
var _seen_guns: Dictionary = {}    # player instance id -> gun ids carried last frame

const PICK_TIME := 3.0

## Health bar readability: per player instance id, [ghost fraction, hold secs, hit flash secs,
## last hp]. The ghost is the health just lost, shown in pale red and drained after a beat.
var _hp_fx: Dictionary = {}
const GHOST_HOLD := 0.45
const HIT_FLASH := 0.25


func _ready() -> void:
    set_anchors_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    _font = Art.FONT
    if OS.get_cmdline_user_args().has("--ui-shot"):
        _ui_shot_begin()


# --- Review capture: rarity and element colours across the UI -----------------------
#
# `godot --path . -- --ui-shot --instance=N` (fresh throwaway save, telemetry and Shrine
# files, never the real ones) dresses player 1 in one elemental item per rarity and four
# guns at tiers 1 to 4 with mods of every rarity, then saves to res://autotest/:
#   ui_hud.png        gear boxes, gun hotbar, minimap, the pickup line
#   ui_items.png      item cards Common, Uncommon, Rare (element items: badge row)
#   ui_items2.png     item cards Epic, Legendary + the palette strip and every badge
#   ui_guns.png       gun cards tier I..IV (tier colours, element badges, mod rarities)
#   ui_sheet.png      the character sheet
#   ui_gunpick.png    the gun-pick overlay
#   ui_journal.png    journal Gear tab, ui_journal_reactions.png the Reactions tab
#   ui_shop.png       a shop pedestal card on the Crisp layer
# then quits.


func _ui_shot_begin() -> void:
    var tag := Main._instance_tag()
    Progress.save_path = "user://save_uishot%s.json" % tag
    Progress.reset()
    Mastery.save_path = "user://mastery_uishot%s.json" % tag
    Telemetry.FILE = "user://telemetry/runs_uishot%s.jsonl" % tag
    _ui_shot.call_deferred()


func _ui_wait(secs: float) -> void:
    await get_tree().create_timer(secs, true).timeout


func _ui_save(name: String) -> void:
    await RenderingServer.frame_post_draw
    var img := get_viewport().get_texture().get_image()
    if img != null:
        img.save_png("res://autotest/%s.png" % name)
        print("[UI SHOT] %s" % name)


## One item per rarity (elemental when the catalog has one), each in its own slot.
func _ui_items(slot_filter: Callable) -> Array:
    var ids: Array = Items.catalog.keys()
    ids.sort()
    var out: Array = []
    var used: Array = []
    for r in 5:
        var pick := ""
        for pass_i in 2:
            for id in ids:
                var it: Dictionary = Items.get_item(String(id))
                var slot := String(it.get("slot", ""))
                if int(it.get("rarity", 0)) != r or not slot_filter.call(slot) or used.has(slot):
                    continue
                if pass_i == 0 and not it.has("element"):
                    continue
                pick = String(id)
                break
            if pick != "":
                break
        if pick != "":
            out.append(pick)
            if slot_filter.call("ring") or slot_filter.call("head"):
                used.append(String(Items.get_item(pick)["slot"]))
    return out


func _ui_shot() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://autotest"))
    await _ui_wait(1.0)
    var p: Player = main.players[0]
    var gear := _ui_items(func(s: String) -> bool: return s != "mod" and s != "active" and s != "")
    for id in gear:
        p.equip(String(id))
    var mods := _ui_items(func(s: String) -> bool: return s == "mod")
    # Four guns whose elements share hues with rarities (wet, poison, void, fire, holy).
    p.weight_capacity = 99
    var want := [Element.Kind.WET, Element.Kind.POISON, Element.Kind.VOID, Element.Kind.FIRE, Element.Kind.HOLY]
    var gun_ids: Array = []
    for k in want:
        for gid in Guns.all_ids():
            if Guns.make(String(gid)).element == k and not gun_ids.has(gid):
                gun_ids.append(gid)
                break
    for gid in gun_ids.slice(0, 4):
        p.add_gun(String(gid), false)
    var t := 1
    for g in p.guns:
        g.tier = clampi(t, 1, Gun.MAX_TIER)
        g.mods.clear()
        for m in mini(g.tier, mods.size()):
            g.mods.append(mods[(m + t) % mods.size()])
        t += 1
    p.recalc_stats()
    await _ui_wait(0.6)
    await _ui_save("ui_hud")

    # Card gallery on its own layer over everything.
    var layer := CanvasLayer.new()
    layer.layer = 60
    layer.process_mode = Node.PROCESS_MODE_ALWAYS
    main.add_child(layer)
    var view := Control.new()
    view.set_anchors_preset(Control.PRESET_FULL_RECT)
    view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    layer.add_child(view)
    var page := { "n": 0 }
    view.draw.connect(func(): _ui_gallery(view, int(page["n"]), gear, p))
    for n in 3:
        page["n"] = n
        view.queue_redraw()
        await _ui_wait(0.2)
        await _ui_save(["ui_items", "ui_items2", "ui_guns"][n])
    layer.queue_free()

    main.pause_menu.show_for_test("res://autotest/ui_sheet.png", p)
    await _ui_wait(2.0)
    main.pause_menu.visible = false
    get_tree().paused = false

    if p.guns.size() > 1 and not mods.is_empty():
        main.gun_pick.pick(p, p.guns, String(mods[0]), func(_g): pass)
        await _ui_wait(0.6)
        await _ui_save("ui_gunpick")
        main.gun_pick._cancel()
        get_tree().paused = false

    for d in Elements.all_defs().slice(0, 8):
        Progress.stats["reaction:" + String(d["name"])] = 1
    var jl := CanvasLayer.new()
    jl.layer = 60
    jl.process_mode = Node.PROCESS_MODE_ALWAYS
    main.add_child(jl)
    var root := CenterContainer.new()
    root.set_anchors_preset(Control.PRESET_FULL_RECT)
    root.theme = UiTheme.make()
    jl.add_child(root)
    var journal := Journal.new(func(): pass)
    root.add_child(journal)
    await _ui_wait(0.2)
    journal.set_tab(2)
    await _ui_wait(0.4)
    # Focus a rare-or-better entry so its rarity focus frame and card show.
    var entries: Array = journal._list.get_children()
    var focus_at := mini(entries.size() - 1, 40)
    for i in entries.size():
        var e: Node = entries[i]
        if e is Button and (e as Button).get_theme_color("font_color") == Items.RARITY_TEXT_COLORS[Items.Rarity.RARE]:
            focus_at = i
            break
    if focus_at >= 0 and entries[focus_at] is Button:
        (entries[focus_at] as Button).grab_focus()
    await _ui_wait(0.4)
    await _ui_save("ui_journal")
    journal.set_tab(3)
    await _ui_wait(0.4)
    await _ui_save("ui_journal_reactions")
    jl.queue_free()

    for pos in main.rooms.keys():
        if main.rooms[pos].type == RoomData.Type.SHOP:
            main.enter_room(pos, Vector2i.ZERO)
            await _ui_wait(0.5)
            if main.current != null and not main.current.pedestals.is_empty():
                p.global_position = main.current.pedestals[0].global_position + Vector2(0, 30)
            await _ui_wait(0.5)
            await _ui_save("ui_shop")
            break
    get_tree().quit()


## Gallery page `n`: 0 items Common..Rare, 1 Epic, Legendary + palette and badges, 2 guns.
func _ui_gallery(v: Control, n: int, gear: Array, p: Player) -> void:
    v.draw_rect(Rect2(Vector2.ZERO, v.size), Color(0.045, 0.040, 0.055))
    var x := 16.0
    if n == 0 or n == 1:
        var ids: Array = gear.slice(0, 3) if n == 0 else gear.slice(3, 5)
        for id in ids:
            var it := Items.get_item(String(id))
            var opts := { "width": 340.0, "player": p }
            if n == 1 and id == ids[-1]:
                opts["price"] = Items.price(it, 6)
                opts["highlight"] = true
            ItemCard.draw(v, Rect2(Vector2(x, 16), Vector2(340, 0)), it, opts)
            x += 356.0
        if n == 1:
            # The palette strip: frame colour, text colour, and the word.
            var y := 16.0
            var px := x
            for r in 5:
                var box := Rect2(Vector2(px, y), Vector2(40, 28))
                v.draw_rect(box, Color(0.05, 0.04, 0.06))
                v.draw_rect(box, Items.RARITY_COLORS[r], false, 3.0)
                ItemCard.draw_pips(v, box.position + Vector2(5, 5), r + 1, Items.RARITY_COLORS[r])
                v.draw_string(Art.FONT, Vector2(px + 50.0, y + 21.0), Items.RARITY_NAMES[r], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Items.RARITY_TEXT_COLORS[r])
                y += 38.0
            y += 10.0
            for k in Element.ALL:
                ItemCard.draw_element_badge(v, Vector2(px, y), k)
                y += 30.0
    else:
        for g in p.guns.slice(0, 4):
            ItemCard.draw_gun(v, Rect2(Vector2(x, 16), Vector2(300, 0)), g.data, { "gun": g, "player": p, "width": 300.0 })
            x += 312.0


## Clarity pass: toasts that arrive during a fight wait until the room is clear.
var _held: Array[String] = []


func toast(text: String) -> void:
    if _fighting():
        _held.append(text)
        return
    _toasts.append({ "text": text, "t": 5.0 })


func _fighting() -> bool:
    return main != null and main.current != null and main.current.active


func _process(delta: float) -> void:
    _time += delta
    if not _held.is_empty() and not _fighting():
        for text in _held:
            _toasts.append({ "text": text, "t": 5.0 })
        _held.clear()
    for i in range(_toasts.size() - 1, -1, -1):
        _toasts[i]["t"] -= delta
        if _toasts[i]["t"] <= 0.0:
            _toasts.remove_at(i)
    _watch_pickups(delta)
    _tick_discovery(delta)
    _tick_banner(get_process_delta_time() / maxf(Engine.time_scale, 0.001))
    queue_redraw()


## Notices new gear and guns on any player and keeps the newest for the pickup label.
func _watch_pickups(delta: float) -> void:
    if not _pick.is_empty():
        _pick["t"] = float(_pick["t"]) - delta
        if float(_pick["t"]) <= 0.0:
            _pick = {}
    if main == null:
        return
    for p in main.players:
        if not is_instance_valid(p):
            continue
        var pid: int = p.get_instance_id()
        var items: Array = []
        var counts: Dictionary = p.gear_counts()
        for cid in counts.keys():
            for c in int(counts[cid]):
                items.append(cid)
        var guns: Array = []
        for g in p.guns:
            guns.append(g.data.id)
        if _seen_items.has(pid):
            var before_items: Array = _seen_items[pid].duplicate()
            for id in items:
                if before_items.has(id):
                    before_items.erase(id)
                else:
                    _announce_item(p, String(id))
            var before_guns: Array = _seen_guns[pid].duplicate()
            for gi in p.guns.size():
                var gid: String = p.guns[gi].data.id
                if before_guns.has(gid):
                    before_guns.erase(gid)
                else:
                    _announce_gun(p, p.guns[gi])
        _seen_items[pid] = items
        _seen_guns[pid] = guns


func _announce_item(p: Player, id: String) -> void:
    var it: Dictionary = Items.get_item(id)
    if it.is_empty():
        return
    var effect := String(it.get("desc", ""))
    var n := p.item_count(id)
    if n > 1:
        effect = "x%d   %s" % [n, effect]
    _pick = {
        "name": String(it["name"]), "effect": effect, "col": Items.rarity_text_color(it),
        "frame": Items.rarity_color(it), "tag": Items.rarity_name(it).to_upper(),
        "icon": Items.icon(it), "icon_tint": Items.ui_icon_tint(it), "who": p.display_name(), "t": PICK_TIME,
    }


func _announce_gun(p: Player, g: Gun) -> void:
    var dmg: float = g.data.damage * g.tier_mult()
    var dps: float = g.data.dps_at(dmg, g.top_fire_rate())
    _pick = {
        "name": g.display_name(), "effect": "%s, DPS %.0f, weight %d" % [Element.NAMES[g.data.element], dps, g.data.weight],
        "col": Items.tier_text_color(g.tier), "frame": Items.tier_color(g.tier),
        "tag": String(Items.RARITY_NAMES[Items.tier_rarity(g.tier)]).to_upper(),
        "icon": Art.gun_icon(g.data.id), "icon_tint": Color.WHITE,
        "who": p.display_name(), "t": PICK_TIME,
    }


func _draw() -> void:
    var vp := get_viewport_rect().size
    var bottom := vp.y - MARGIN - (HELP_LIFT if main.show_help else 0.0)

    _draw_top(vp)
    var map_bottom := _draw_minimap(vp)
    _draw_scrap(vp, map_bottom)
    for i in main.players.size():
        _draw_vitals(main.players[i], Vector2(MARGIN, MARGIN + float(i) * (CARD_H + CARD_GAP)))
    if not main.players.is_empty():
        _draw_hotbars(vp, bottom)
        _draw_main_gear(main.players[0], bottom)
        _draw_pick(bottom)
        _draw_vents(vp, bottom)
    if main.show_help:
        _draw_help(vp)
    _draw_toasts(vp)
    _draw_edge_arrows(vp)
    _draw_discovery(vp)
    _draw_dash_hint(vp)
    _draw_banner(vp)


## Synergy and resonance banners (section 12): top band only, one at a time, at most one
## every BANNER_GAP s (the rest queue), BANNER_SECS on screen. Title 28 px, line 22 px.
const BANNER_SECS := 2.0
const BANNER_GAP := 8.0
var _banners: Array = []          # queued { title, line, color, big }
var _banner: Dictionary = {}      # showing now, with "t"
var _banner_ready := 0.0          # real seconds until the next may show


func banner(title: String, line: String, color: Color, big: bool) -> void:
    _banners.append({ "title": title, "line": line, "color": color, "big": big })


func _tick_banner(delta: float) -> void:
    _banner_ready = maxf(0.0, _banner_ready - delta)
    if not _banner.is_empty():
        _banner["t"] = float(_banner["t"]) - delta
        if float(_banner["t"]) <= 0.0:
            _banner = {}
    if _banner.is_empty() and not _banners.is_empty() and _banner_ready <= 0.0:
        _banner = _banners.pop_front()
        _banner["t"] = BANNER_SECS
        _banner_ready = BANNER_GAP


func _draw_banner(vp: Vector2) -> void:
    if _banner.is_empty():
        return
    var a := clampf(float(_banner["t"]) / 0.4, 0.0, 1.0) * clampf((BANNER_SECS - float(_banner["t"])) / 0.15 + 0.2, 0.0, 1.0)
    var col: Color = _banner["color"]
    var w := maxf(_body_width(String(_banner["title"]), 28), _body_width(String(_banner["line"]), 22)) + 60.0
    var box := Rect2((vp.x - w) / 2.0, vp.y * 0.11, w, 70.0)
    draw_rect(box, Color(0.04, 0.03, 0.05, 0.9 * a))
    draw_rect(box, Color(col, a), false, 3.0 if bool(_banner["big"]) else 2.0)
    _body_in(Rect2(box.position + Vector2(0, 4), Vector2(w, 34)), String(_banner["title"]), 28, Color(col, a))
    _body_in(Rect2(box.position + Vector2(0, 38), Vector2(w, 28)), String(_banner["line"]), 22, Color(UiTheme.BONE, a))


## First room of a run, until the first dash ever: one prompt (section 7.3).
func _draw_dash_hint(vp: Vector2) -> void:
    if main.players.is_empty() or main.floor_number != 1 or Settings.flag("dash_learned"):
        return
    var p: Player = main.players[0]
    if p.dashes > 0:
        return
    var text := "%s: dash through danger" % p.input.prompt("dash")
    var w := _body_width(text, 20) + 32.0
    var box := Rect2(vp.x / 2.0 - w / 2.0, vp.y * 0.72, w, 34.0)
    draw_rect(box, Color(0, 0, 0, 0.55))
    _body_in(box, text, 20, UiTheme.BONE)



# --- Discoveries and edge arrows (Core loop reset 4.5, 4.6) --------------------

const DISCOVER_SECS := 3.0
var _discoveries: Array[String] = []
var _discover_t := 0.0


## The first time a reaction, fusion or cataclysm happens on this save: "Discovered: X" at the
## left screen edge for DISCOVER_SECS, one at a time (the rest queue). The codex keeps it.
func discover(what: String, big := false) -> void:
    if not _discoveries.has(what):
        _discoveries.append(what)
        if big:
            _discover_big[what] = true


## Cataclysms (FusionFx, first find only): the same line at the edge, large and held longer.
var _discover_big := {}
const DISCOVER_BIG_SECS := 4.0


func _tick_discovery(delta: float) -> void:
    if _discoveries.is_empty():
        return
    if _discover_t <= 0.0:
        _discover_t = DISCOVER_BIG_SECS if _discover_big.has(_discoveries[0]) else DISCOVER_SECS
        Fx.count_text("discovery")
    _discover_t -= delta
    if _discover_t <= 0.0:
        _discover_big.erase(_discoveries.pop_front())


func _draw_discovery(vp: Vector2) -> void:
    if _discoveries.is_empty() or _discover_t <= 0.0:
        return
    var big := _discover_big.has(_discoveries[0])
    var secs := DISCOVER_BIG_SECS if big else DISCOVER_SECS
    var a := clampf(_discover_t / 0.4, 0.0, 1.0) * clampf((secs - _discover_t) / 0.15, 0.0, 1.0)
    if big:
        # A cataclysm's name, once ever: large, but at the left edge, never over the fight.
        var name_ := String(_discoveries[0]).to_upper()
        var bw := maxf(_body_width(name_, 34), _body_width("New cataclysm", 16)) + 36.0
        var bbox := Rect2(0.0, vp.y * 0.36, bw, 66.0)
        draw_rect(bbox, Color(0, 0, 0, 0.6 * a))
        draw_rect(Rect2(bbox.position, Vector2(5.0, bbox.size.y)), Color(1.0, 0.8, 0.45, 0.9 * a))
        _body_in(Rect2(bbox.position + Vector2(18, 4), Vector2(bw - 18.0, 20.0)), "New cataclysm", 16, Color(1.0, 0.85, 0.6, 0.85 * a), HORIZONTAL_ALIGNMENT_LEFT)
        _body_in(Rect2(bbox.position + Vector2(18, 24), Vector2(bw - 18.0, 40.0)), name_, 34, Color(1.0, 0.95, 0.85, a), HORIZONTAL_ALIGNMENT_LEFT)
        return
    var text := "Discovered: %s" % _discoveries[0]
    var w := _body_width(text, 20) + 28.0
    var box := Rect2(0.0, vp.y * 0.42, w, 32.0)
    draw_rect(box, Color(0, 0, 0, 0.55 * a))
    draw_rect(Rect2(box.position, Vector2(3.0, box.size.y)), Color(0.6, 1.0, 0.8, 0.8 * a))
    _body_in(Rect2(box.position + Vector2(14, 0), box.size - Vector2(14, 0)), text, 20, Color(0.75, 1.0, 0.85, a), HORIZONTAL_ALIGNMENT_LEFT)


## Every hostile enemy off screen within ARROW_REACH of the player gets a small arrow at the
## screen edge in the hostile signature (black outline, red rim); key threats a larger one
## with their silhouette, pulsing while they wind up an attack.
const ARROW_REACH := 700.0
var arrows_drawn := 0       # last frame's count (the camera check)
var offscreen_near := 0     # last frame's off-screen enemies in reach


func _draw_edge_arrows(vp: Vector2) -> void:
    arrows_drawn = 0
    offscreen_near = 0
    if main.players.is_empty() or main.current == null:
        return
    var p: Player = main.players[0]
    var xf := get_viewport().get_canvas_transform()
    var screen := Rect2(Vector2.ZERO, vp)
    var inner := screen.grow(-22.0)
    var centre := vp / 2.0
    var r2 := ARROW_REACH * ARROW_REACH
    for e in EnemyGrid.nodes(get_tree(), &"enemies"):
        if not is_instance_valid(e) or not e is Enemy or e.emerge > 0.0:
            continue
        if e.global_position.distance_squared_to(p.global_position) > r2:
            continue
        var sp: Vector2 = xf * e.global_position
        if screen.grow(-4.0).has_point(sp):
            continue
        offscreen_near += 1
        var dir := (sp - centre).normalized()
        # Where the ray from the centre leaves the inner rect.
        var tx := (inner.size.x / 2.0) / maxf(0.001, absf(dir.x))
        var ty := (inner.size.y / 2.0) / maxf(0.001, absf(dir.y))
        var at := centre + dir * minf(tx, ty)
        var key: bool = e.is_elite or e.kind_name == "boss" or e.is_key_threat()
        var size := 13.0 if key else 8.0
        if key and e.winding_up():
            size *= 1.0 + 0.3 * _pulse(10.0)
        var tip := at + dir * size
        var side := dir.orthogonal() * size * 0.7
        var tri := PackedVector2Array([tip, at - dir * size * 0.6 + side, at - dir * size * 0.6 - side])
        var out := PackedVector2Array([tip + dir * 2.5, at - dir * (size * 0.6 + 2.0) + side * 1.3, at - dir * (size * 0.6 + 2.0) - side * 1.3])
        draw_colored_polygon(out, Color(0, 0, 0, 0.9))
        draw_colored_polygon(tri, Color(0.95, 0.18, 0.15, 0.95))
        if key:
            var tile = Enemy.KIND_TILES.get(e.kind_name)
            if tile != null:
                _icon(tile, Rect2(at - dir * (size + 16.0) - Vector2(10, 10), Vector2(20, 20)), Color(1.0, 0.85, 0.8, 0.95))
        arrows_drawn += 1


# --- Helpers ---------------------------------------------------------------


func _body_font() -> Font:
    return Art.FONT_BODY if Art.FONT_BODY != null else _font


## Draws text with a drop shadow. Pixel-font text is never smaller than 22 px. Body sizes
## here were written for the first text pass and are scaled by Art.bpx, never under 18 px
## (fight text has to read at a glance).
func _text(pos: Vector2, text: String, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, shadow := true, pixel := false) -> void:
    var font := _font if pixel else _body_font()
    size = maxi(size, 22) if pixel else _bsz(size)
    if shadow:
        var off := Vector2(2, 2) if pixel else Vector2(1, 1)
        draw_string(font, pos + off, text, align, width, size, Color(0, 0, 0, 0.75 * color.a))
    draw_string(font, pos, text, align, width, size, color)


## Body text at a baseline.
func _body(pos: Vector2, text: String, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, shadow := true) -> void:
    _text(pos, text, size, color, align, width, shadow, false)


## Pixel-font heading or big number at a baseline.
func _title(pos: Vector2, text: String, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
    _text(pos, text, size, color, align, width, true, true)


## Body text vertically centred in a rect, aligned horizontally inside it.
func _body_in(rect: Rect2, text: String, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_CENTER, shadow := true) -> void:
    var font := _body_font()
    var s := _bsz(size)
    var base := rect.position.y + (rect.size.y + font.get_ascent(s) - font.get_descent(s)) / 2.0
    _body(Vector2(rect.position.x, base), text, size, color, align, rect.size.x, shadow)


func _body_width(text: String, size: int) -> float:
    return _body_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _bsz(size)).x


## A HUD body size at today's scale (Art.bpx), never under 18 px.
func _bsz(size: int) -> int:
    return maxi(Art.bpx(size), 18)


func _centered(y: float, text: String, size: int, color: Color, vp: Vector2, pixel := false) -> void:
    _text(Vector2(0, y), text, size, color, HORIZONTAL_ALIGNMENT_CENTER, vp.x, true, pixel)


func _bar(rect: Rect2, fraction: float, color: Color, border := Color(0, 0, 0, 0.8)) -> void:
    draw_rect(rect, Color(0.05, 0.04, 0.05, 0.85))
    draw_rect(Rect2(rect.position, Vector2(rect.size.x * clampf(fraction, 0.0, 1.0), rect.size.y)), color)
    draw_rect(rect.grow(1.0), border, false, 2.0)


func _icon(coord: Vector2i, rect: Rect2, color: Color) -> void:
    draw_texture_rect(Art.tile(coord), rect, false, color)


## An item, gun or upgrade icon (a Dungeon Crawl tile), drawn crisply into `rect`.
func _icon_tex(tex: Texture2D, rect: Rect2, color: Color) -> void:
    Art.draw_icon(self, tex, rect, color)


func _backdrop(rect: Rect2, alpha := 0.4) -> void:
    draw_rect(rect, Color(0.03, 0.02, 0.04, alpha))


func _pulse(speed: float) -> float:
    return 0.5 + 0.5 * sin(_time * speed)


# --- Top centre: room, timer, boss, hints, announcements ------------------


func _draw_top(vp: Vector2) -> void:
    var room := main.current
    if room == null:
        return
    var cx := vp.x / 2.0
    _centered(34, "%s   %s" % [Regions.display_name(main.region_id).to_upper(), room.data.type_name().to_upper()], 28, Color(room.data.color(), 0.95), vp, true)
    if room.active and room.data.type == RoomData.Type.ARENA and not Main.old_balance:
        # Fun pass 1: a room to clear; the count of what is left, not a timer.
        var left := room.enemies_left()
        _centered(96, "%d LEFT" % left, 40 if left > 3 else 48, Color(1.0, 0.75, 0.4) if left <= 3 else UiTheme.BONE, vp, true)
    elif room.active and room.data.type == RoomData.Type.ARENA:
        var secs := ceili(room.wave_time_left)
        var col := Color(1.0, 0.35, 0.3) if secs <= 5 else UiTheme.BONE
        var size := 64 if secs > 5 else 72 + int(8.0 * absf(sin(_time * 8.0)))
        _centered(96, str(secs), size, col, vp, true)
    elif room.boss != null and is_instance_valid(room.boss):
        var b := room.boss
        var w := 560.0
        var r := Rect2(cx - w / 2.0, 52, w, 22)
        _bar(r, b.hp / b.max_hp, Color(0.85, 0.15, 0.25))
        _body_in(r, "%d / %d" % [int(b.hp), int(b.max_hp)], 20, Color.WHITE)
        var y := 100.0
        if b.body != null:
            _draw_boss_frame(b, r, vp)
            y = 128.0
        if b.shielded():
            draw_rect(r.grow(4.0), Color(1, 1, 1, 0.5 + 0.4 * absf(sin(_time * 6.0))), false, 3.0)
            var line := "SHIELD  %d / %d cracks   any reaction cracks it, %s cracks twice" % [b.shield_hp, b.shield_max, b.weakness_name()]
            _centered(int(y), line, 17, Color(1, 1, 1, 0.92), vp)
        elif b.body == null:
            _centered(104, "BOSS", 24, Color(1, 0.8, 0.8), vp, true)
    elif room.active:
        _centered(86, "FIGHT", 40, Color(1.0, 0.5, 0.4), vp, true)
    else:
        var hint := ""
        match room.data.type:
            RoomData.Type.CHALLENGE:
                hint = "Doors stay open. Touch the sigil to begin." if not room.data.cleared else "Cleared"
            RoomData.Type.SHOP:
                hint = "Y / R locks a ware for the next shop. Scrap carries over" if not Main.old_balance else "Scrap buys guns, carry capacity and repairs"
            RoomData.Type.DEAL:
                hint = "Take one. Each has its price"
            RoomData.Type.TREASURE:
                hint = "Take one"
            RoomData.Type.START:
                hint = "Choose your first gun" if room.has_gun_choice() else "Pick a door"
            _:
                hint = "Cleared" if room.data.cleared else ""
        if hint != "":
            _centered(66, hint, 18, UiTheme.DIM, vp)

    if main.message != "":
        var pop: float = clampf((3.0 - main._message_time) / 0.15, 0.0, 1.0)
        _centered(150, main.message, int(26 + 12 * pop), ANNOUNCE, vp, true)


## The boss framework's frame (BossBody): its name over the bar, phase pips, the stagger bar
## under it, a chip per body part with its element states and compound, and for the first
## seconds of the fight a large name card.
func _draw_boss_frame(b: Enemy, r: Rect2, vp: Vector2) -> void:
    var bb: BossBody = b.body
    var name := BossBody.display_name(b.boss_kind)
    _body_in(Rect2(r.position.x + 8.0, r.position.y, r.size.x - 16.0, r.size.y), name.to_upper(), 16, Color(1.0, 0.92, 0.88), HORIZONTAL_ALIGNMENT_LEFT)
    # Phase pips at the bar's right end: lit up to the current phase.
    for k in bb.phases():
        var pc := Vector2(r.end.x + 14.0 + 14.0 * float(k), r.position.y + r.size.y * 0.5)
        draw_rect(Rect2(pc - Vector2(5, 5), Vector2(10, 10)), Color(0.05, 0.0, 0.03))
        draw_rect(Rect2(pc - Vector2(3.5, 3.5), Vector2(7, 7)), Color(1.0, 0.3, 0.2) if k < b._phase else Color(0.3, 0.2, 0.2))
    # Stagger: fills from reactions; while staggered it flashes and drains.
    var sr := Rect2(r.position.x, r.end.y + 4.0, r.size.x, 8.0)
    draw_rect(sr.grow(2.0), Color(0.05, 0.0, 0.03, 0.9))
    if bb.staggered():
        var k := bb.stagger_t / BossBody.STAGGER_SECS
        draw_rect(Rect2(sr.position, Vector2(sr.size.x * k, sr.size.y)), Color(1.0, 0.95, 0.5, 0.7 + 0.3 * absf(sin(_time * 10.0))))
        _body_in(Rect2(r.position.x + 8.0, r.position.y, r.size.x - 16.0, r.size.y), "STAGGERED", 16, Color(1.0, 0.95, 0.55), HORIZONTAL_ALIGNMENT_RIGHT)
    else:
        draw_rect(Rect2(sr.position, Vector2(sr.size.x * bb.stagger, sr.size.y)), Color(1.0, 0.8, 0.3, 0.85))
    if bb.has_parts():
        var chips: Array = []
        for i in bb.parts.size():
            var p: Dictionary = bb.parts[i]
            var st: Dictionary = p["states"] if i != bb.cur else b.states
            var cid: String = String(p["compound"]) if i != bb.cur else b.compound
            var label := String(p["name"])
            if p["broken"]:
                label += " (torn)"
            elif not bb.visible(i):
                if b._phase < int(p.get("from_phase", 0)):
                    label += " (sealed)"
                elif p.get("burrows", false) and b.burrowed():
                    label += " (underground)"
                else:
                    label += " (covered)"
            elif cid != "":
                label += ": " + String(Fusions.compound(cid).get("name", cid))
                var only: Array = p.get("only", [])
                if only.size() == 1:
                    label += ", %s shatters it" % Element.NAMES[only[0]].to_lower()
            chips.append({ "label": label, "states": st.keys(), "on": bb.visible(i) })
        var cw := r.size.x / float(chips.size())
        for i in chips.size():
            var c: Dictionary = chips[i]
            var cr := Rect2(r.position.x + cw * float(i), sr.end.y + 4.0, cw - 6.0, 18.0)
            draw_rect(cr, Color(0.05, 0.0, 0.03, 0.75))
            var px := cr.position.x + 6.0
            for kind in c["states"]:
                draw_rect(Rect2(px, cr.position.y + 5.0, 8, 8), Element.COLORS[kind])
                px += 11.0
            _body_in(Rect2(px, cr.position.y, cr.end.x - px, cr.size.y), String(c["label"]), 13, UiTheme.BONE if c["on"] else UiTheme.DIM)
    # Name card: the entrance (BossShow), big, with its epithet and where you are.
    var show: BossShow = main.current.show if main.current != null else null
    var a := show.card() if show != null and is_instance_valid(show) else 0.0
    if a > 0.0:
        var cy := vp.y * 0.76   # the lower third: the camera holds the boss in the middle
        var ac := BossShow.accent(b.boss_kind)
        draw_rect(Rect2(0, cy - 70.0, vp.x, 150.0), Color(0.02, 0.0, 0.02, 0.78 * a))
        draw_rect(Rect2(0, cy - 70.0, vp.x, 3.0), Color(ac, 0.9 * a))
        draw_rect(Rect2(0, cy + 80.0, vp.x, 3.0), Color(ac, 0.9 * a))
        var grow := 1.0 + 0.08 * (1.0 - a)
        _centered(int(cy + 8.0), name.to_upper(), int(64.0 * grow), Color(1.0, 0.9, 0.82, a), vp, true)
        _centered(int(cy + 42.0), show.epithet(), 20, Color(ac.lerp(Color.WHITE, 0.4), a), vp)
        _centered(int(cy + 68.0), Regions.display_name(main.region_id).to_upper(), 14, Color(1.0, 0.6, 0.5, 0.8 * a), vp)


# --- Top right: minimap, scrap, kills -------------------------------------


## Draws the minimap and returns the y of its bottom edge.
func _draw_minimap(vp: Vector2) -> float:
    var pitch := CELL + CELL_GAP
    var grid := float(FloorGen.GRID)
    var size := grid * pitch
    var origin := Vector2(vp.x - MARGIN - size, MARGIN)
    # Backdrop only behind the discovered rooms, not the whole grid: a full square read
    # as a black box over the room once the dungeon art got darker.
    var lo := Vector2(INF, INF)
    var hi := Vector2(-INF, -INF)
    for kpos in main.rooms.keys():
        if (main.rooms[kpos] as RoomData).discovered:
            var cpos := origin + Vector2(kpos.x, kpos.y) * pitch
            lo = lo.min(cpos)
            hi = hi.max(cpos + Vector2(CELL, CELL))
    if lo.x < INF:
        draw_rect(Rect2(lo - Vector2(6, 6), hi - lo + Vector2(12, 12)), Color(0, 0, 0, 0.3))
    for pos in main.rooms.keys():
        var r: RoomData = main.rooms[pos]
        if not r.discovered:
            continue
        var cell := Rect2(origin + Vector2(pos.x, pos.y) * pitch, Vector2(CELL, CELL))
        var col: Color = r.color()
        if not r.visited:
            col = Color(col, 0.35)
        elif not r.cleared:
            col = Color(col, 0.7)
        draw_rect(cell, Color(col.r * 0.5, col.g * 0.5, col.b * 0.5, col.a))
        draw_rect(cell, col, false, 1.5)
        if ROOM_ICONS.has(r.type):
            _icon(ROOM_ICONS[r.type], cell.grow(-2.0), Color(1, 1, 1, col.a))
        for d in r.doors.keys():
            if r.doors[d]["obstacle"] != "":
                continue
            var c := cell.get_center() + Vector2(d.x, d.y) * (CELL / 2.0 + 2.0)
            draw_rect(Rect2(c - Vector2(2, 2), Vector2(4, 4)), Color(1, 1, 1, 0.6 * col.a))
        if pos == main.current_pos:
            draw_rect(cell.grow(3.0), Color(1, 1, 1, 0.6 + 0.4 * absf(sin(_time * 4.0))), false, 2.0)
    return origin.y + size + 6.0


func _draw_scrap(vp: Vector2, top: float) -> void:
    var right := vp.x - MARGIN
    var y := top + 10.0
    var num := str(main.scrap)
    var size := 32
    var tw := _font.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
    var icon := Rect2(right - tw - 40.0, y, 32, 32)
    _backdrop(Rect2(icon.position.x - 8.0, y - 6.0, right - icon.position.x + 14.0, 70.0))
    _icon(Art.TILES["scrap"], icon, Art.SCRAP_TINT)
    _title(Vector2(right - tw, y + 27.0), num, size, Art.SCRAP_TINT)
    _body(Vector2(right - 200.0, y + 54.0), "KILLS %d" % main.total_kills, 16, UiTheme.DIM, HORIZONTAL_ALIGNMENT_RIGHT, 200.0)


# --- Top left: vitals card per player --------------------------------------


func _draw_vitals(p: Player, origin: Vector2) -> void:
    var card := Rect2(origin, Vector2(CARD_W, CARD_H))
    draw_rect(card, Color(0.03, 0.02, 0.04, 0.72))
    draw_rect(card, Color(p.color, 0.5), false, 2.0)

    # Portrait
    var box := Rect2(origin + Vector2(10, 10), Vector2(64, 64))
    draw_rect(box, Color(0.08, 0.06, 0.08))
    draw_rect(box, p.color, false, 2.0)
    var form: Dictionary = Items.form_for(p)
    var tint: Color = Color.WHITE if p.alive else Color(0.3, 0.3, 0.3)
    var frames: Array = form["frames"]
    var portrait: Texture2D = frames[0]
    draw_texture_rect(portrait, box.grow(-8.0), false, tint)

    var x := origin.x + 84.0
    var w := CARD_W - 84.0 - 10.0

    # Name and level pill
    var pname := p.display_name()
    var name_w := maxf(30.0, Art.FONT.get_string_size(pname, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 4.0)
    var name_rect := Rect2(x, origin.y + 8.0, name_w, 22.0)
    _body_in(name_rect, pname, 20, p.color, HORIZONTAL_ALIGNMENT_LEFT)
    var pill := Rect2(x + name_w + 4.0, origin.y + 9.0, 58.0, 20.0)
    draw_rect(pill, Color(0.55, 0.4, 0.15, 0.9))
    draw_rect(pill, Color(0, 0, 0, 0.6), false, 1.0)
    _body_in(pill, "LV %d" % p.level, 20, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, false)
    if not p.alive:
        _body_in(Rect2(x, origin.y + 8.0, w, 22.0), "DOWN", 16, Color(1.0, 0.35, 0.3), HORIZONTAL_ALIGNMENT_RIGHT)

    # Health: the share just lost lingers as a pale ghost, the bar flashes white on a hit,
    # and under Sfx.HEART_LOW the bar and card border pulse red (faster under HEART_CRIT).
    var hp_rect := Rect2(x, origin.y + 36.0, w, 20.0)
    var hp_frac := clampf(p.hp / p.max_hp, 0.0, 1.0)
    var st: Array = _hp_fx.get(p.get_instance_id(), [hp_frac, 0.0, 0.0, p.hp])
    if p.hp < float(st[3]) - 0.01:
        st[1] = GHOST_HOLD
        st[2] = HIT_FLASH
    st[3] = p.hp
    var dt := get_process_delta_time() / maxf(Engine.time_scale, 0.001)
    st[1] = maxf(0.0, float(st[1]) - dt)
    st[2] = maxf(0.0, float(st[2]) - dt)
    if float(st[1]) <= 0.0:
        st[0] = move_toward(float(st[0]), hp_frac, dt * 0.8)
    st[0] = maxf(float(st[0]), hp_frac)
    _hp_fx[p.get_instance_id()] = st
    var low := p.alive and hp_frac < Sfx.HEART_LOW
    var crit := p.alive and hp_frac < Sfx.HEART_CRIT
    var bar_col := Color(0.85, 0.2, 0.2).lerp(Color(0.35, 0.85, 0.4), hp_frac)
    var border := Color(0, 0, 0, 0.8)
    if low:
        var beat := _pulse(9.0 if crit else 5.5)
        if not Settings.flag("flashes"):
            beat = 0.5
        bar_col = Color(0.95, 0.12, 0.1).lerp(Color(1.0, 0.75, 0.7), 0.45 * beat)
        border = Color(1.0, 0.15, 0.1).lerp(Color(1.0, 0.9, 0.85), beat * (0.6 if crit else 0.3))
        draw_rect(card.grow(2.0), Color(1.0, 0.15, 0.1, 0.35 + 0.5 * beat), false, 3.0)
    _bar(hp_rect, hp_frac, bar_col, border)
    var ghost := float(st[0])
    if ghost > hp_frac:
        draw_rect(Rect2(hp_rect.position + Vector2(hp_rect.size.x * hp_frac, 0), Vector2(hp_rect.size.x * (ghost - hp_frac), hp_rect.size.y)), Color(1.0, 0.75, 0.6, 0.85))
    if float(st[2]) > 0.0:
        draw_rect(hp_rect, Color(1, 1, 1, 0.6 * float(st[2]) / HIT_FLASH))
    _body_in(hp_rect, "%d / %d" % [int(ceilf(p.hp)), int(p.max_hp)], 20, Color.WHITE)
    if low and main.players.size() == 1:   # co-op cards stack too close for the word
        _body_in(Rect2(card.position.x, card.end.y + 2.0, CARD_W, 22.0), "LOW HEALTH" if not crit else "CRITICAL", 18, Color(1.0, 0.3, 0.25).lerp(Color.WHITE, 0.3 * _pulse(6.0)), HORIZONTAL_ALIGNMENT_LEFT)

    # Experience toward the next level
    # The floor's Mending reserve (section 10): a thin green bar under the health bar,
    # draining as passive healing uses it; it refills on the next floor.
    if p.mend_max > 0.0:
        var mr := Rect2(x, origin.y + 57.0, w, 4.0)
        draw_rect(mr, Color(0.05, 0.08, 0.05, 0.85))
        draw_rect(Rect2(mr.position, Vector2(mr.size.x * clampf(p.mend_rate(), 0.0, 1.0), mr.size.y)), Color(0.4, 0.9, 0.45, 0.9))
    _bar(Rect2(x, origin.y + 64.0, w, 6.0), p.xp / p.xp_to_next(), Color(0.85, 0.65, 0.2))

    if p.last_message != "":
        _body_in(Rect2(card.end.x + 10.0, origin.y + 30.0, 420.0, 24.0), p.last_message, 16, ANNOUNCE, HORIZONTAL_ALIGNMENT_LEFT)


# --- Bottom centre: gun hotbars --------------------------------------------


func _draw_hotbars(vp: Vector2, bottom: float) -> void:
    var y := bottom
    var many := main.players.size() > 1
    for i in main.players.size():
        var p: Player = main.players[i]
        var n := p.guns.size()
        var cols := clampi(n, 1, SLOTS_PER_ROW)
        var rows := maxi(1, ceili(float(n) / float(SLOTS_PER_ROW)))
        var block_h := float(rows) * SLOT + float(rows - 1) * SLOT_GAP
        var guns_w := float(cols) * SLOT + float(cols - 1) * SLOT_GAP

        var weight := "WEIGHT %d / %d" % [p.total_weight(), p.weight_capacity]
        var weight_w := _body_width(weight, 16)
        var tag_w := 32.0 if many else 0.0
        var gear_w := 0.0
        if i > 0:
            gear_w = 14.0 + _gear_width(GEAR_SMALL)
        var total := tag_w + guns_w + 12.0 + weight_w + gear_w
        var x := (vp.x - total) / 2.0
        var top := y - block_h
        _backdrop(Rect2(x - 8.0, top - 8.0, total + 16.0, block_h + 16.0))

        if many:
            _body_in(Rect2(x, top, 26.0, block_h), p.display_name().left(2), 20, p.color)
            draw_rect(Rect2(x + 27.0, top, 2.0, block_h), Color(p.color, 0.6))
            x += tag_w

        if n == 0:
            var empty := Rect2(x, top, SLOT, SLOT)
            draw_rect(empty, Color(0.08, 0.06, 0.08, 0.6))
            draw_rect(empty, Color(0.25, 0.22, 0.24), false, 1.0)
        for k in n:
            var gun: Gun = p.guns[k]
            var col := k % SLOTS_PER_ROW
            var row := k / SLOTS_PER_ROW
            var slot := Rect2(x + float(col) * (SLOT + SLOT_GAP), top + float(row) * (SLOT + SLOT_GAP), SLOT, SLOT)
            _draw_gun_slot(gun, slot)
        x += guns_w + 12.0

        var heavy := p.total_weight() >= p.weight_capacity
        _body_in(Rect2(x, top, weight_w, block_h), weight, 16, ItemCard.BAD if heavy else UiTheme.BONE, HORIZONTAL_ALIGNMENT_LEFT)
        x += weight_w

        if i > 0:
            _draw_gear(p, Vector2(x + 14.0, top + (block_h - GEAR_SMALL) / 2.0), GEAR_SMALL)

        y = top - 8.0 - 12.0 - 8.0


func _draw_gun_slot(gun: Gun, slot: Rect2) -> void:
    # Frame and tier pips in the tier's rarity colour (Items.tier_color); the element is
    # only a small swatch, bottom-right, never the frame.
    var tc: Color = Items.tier_color(gun.tier)
    draw_rect(slot, Color(0.08, 0.06, 0.08, 0.9))
    _icon_tex(Art.gun_icon(gun.data.id), slot.grow(-6.0), Color.WHITE)
    draw_rect(slot, tc, false, 2.0)
    # Tier pips, bottom-left.
    ItemCard.draw_pips(self, Vector2(slot.position.x + 4.0, slot.end.y - 8.0), gun.tier, tc)
    # Element swatch, bottom-right.
    var sw := Rect2(slot.end.x - 10.0, slot.end.y - 10.0, 6.0, 6.0)
    draw_rect(sw.grow(1.0), Color(0, 0, 0, 0.85))
    draw_rect(sw, Element.COLORS[gun.data.element])
    # One rarity dot per fitted mod, top-right, filling leftward.
    var m := 0
    for id in gun.mods:
        var c := Vector2(slot.end.x - 6.0 - float(m) * 8.0, slot.position.y + 6.0)
        draw_circle(c, 4.0, Color(0, 0, 0, 0.8))
        draw_circle(c, 3.0, Items.rarity_color(Items.get_item(str(id))))
        m += 1


# --- Bottom left: gear -----------------------------------------------------


## Extra space before the active item so it reads as its own thing.
const ACTIVE_GAP := 10.0


## The item strip (Core loop reset 3.1: no slots): the active, then up to STRIP_ITEMS items,
## rarest first, each with its "x3" count; "+N" when more are owned. Resonance chips sit
## above it.
const STRIP_ITEMS := 8


func _gear_width(s: float) -> float:
    var gap := 4.0 if s >= GEAR_BIG else 3.0
    return float(STRIP_ITEMS + 1) * (s + gap) - gap + ACTIVE_GAP


func _draw_main_gear(p: Player, bottom: float) -> void:
    var origin := Vector2(MARGIN, bottom - GEAR_BIG)
    _backdrop(Rect2(origin - Vector2(8, 8), Vector2(_gear_width(GEAR_BIG) + 16.0, GEAR_BIG + 16.0)))
    _draw_gear(p, origin, GEAR_BIG)


func _draw_gear(p: Player, origin: Vector2, s: float) -> void:
    var gap := 4.0 if s >= GEAR_BIG else 3.0
    var abox := Rect2(origin, Vector2(s, s))
    draw_rect(abox, Color(0.08, 0.06, 0.08, 0.9))
    if p.equipment.has("active"):
        var ait := Items.get_item(p.equipment["active"])
        var charged := p.active_charges > 0
        _icon_tex(Items.icon(ait), abox.grow(-2.0), Items.ui_icon_tint(ait) if charged else Color(0.4, 0.38, 0.4))
        draw_rect(abox, Items.rarity_color(ait), false, 2.0)
        _draw_charge_pips(abox, p.active_charges, Items.active_max_charges(p))
    else:
        _icon_tex(Items.slot_icon("active"), abox.grow(-2.0), Color(0.32, 0.3, 0.32, 0.8))
        draw_rect(abox, Color(0.25, 0.22, 0.24), false, 1.0)
    var ids: Array = p.inventory.keys()
    ids.sort_custom(func(a, b):
        var ra := int(Items.get_item(a).get("rarity", 0))
        var rb := int(Items.get_item(b).get("rarity", 0))
        return ra > rb if ra != rb else int(p.inventory[a]) > int(p.inventory[b]))
    var x := origin.x + s + gap + ACTIVE_GAP
    for k in mini(ids.size(), STRIP_ITEMS):
        var box := Rect2(x + float(k) * (s + gap), origin.y, s, s)
        draw_rect(box, Color(0.08, 0.06, 0.08, 0.9))
        if k == STRIP_ITEMS - 1 and ids.size() > STRIP_ITEMS:
            _body_in(box, "+%d" % (ids.size() - STRIP_ITEMS + 1), 18 if s >= GEAR_BIG else 14, UiTheme.BONE)
            draw_rect(box, Color(0.45, 0.42, 0.44), false, 1.0)
            continue
        var it := Items.get_item(String(ids[k]))
        _icon_tex(Items.icon(it), box.grow(-2.0), Items.ui_icon_tint(it))
        draw_rect(box, Items.rarity_color(it), false, 2.0)
        var n := int(p.inventory[ids[k]])
        if n > 1 and s >= GEAR_BIG:
            _body_in(Rect2(box.position + Vector2(0, s * 0.45), Vector2(s - 2.0, s * 0.55)), "x%d" % n, 18, UiTheme.BONE, HORIZONTAL_ALIGNMENT_RIGHT)
    if s >= GEAR_BIG:
        # Resonance chips: "Vent II" in the tag's colour, over the strip.
        var cx := origin.x
        for t in p.resonance_tiers.keys():
            var label := "%s%s" % [Items.tag_name(String(t)), " II" if int(p.resonance_tiers[t]) >= 2 else ""]
            var w := _body_width(label, 18) + 14.0
            var chip := Rect2(cx, origin.y - 34.0, w, 26.0)
            draw_rect(chip, Color(0.05, 0.04, 0.06, 0.9))
            draw_rect(chip, Items.tag_color(String(t)), false, 2.0)
            _body_in(chip, label, 18, Items.tag_color(String(t)))
            cx += w + 6.0


## The last pickup in one line over the gear row: icon, name in its rarity colour, then
## what it does. Fades over its last half second.
func _draw_pick(bottom: float) -> void:
    if _pick.is_empty():
        return
    var a := clampf(float(_pick["t"]) / 0.5, 0.0, 1.0)
    var y := bottom - GEAR_BIG - 16.0 - 34.0 - (34.0 if not main.players[0].resonance_tiers.is_empty() else 0.0)
    var name_text := String(_pick["name"])
    if main.players.size() > 1:
        name_text = "%s: %s" % [_pick["who"], name_text]
    var effect := String(_pick["effect"])
    var name_w := _body_width(name_text, 20)
    var eff_w := _body_width(effect, 20)
    var w := minf(30.0 + name_w + 14.0 + eff_w + 16.0, 760.0)
    var box := Rect2(MARGIN - 8.0, y, w, 30.0)
    draw_rect(box, Color(0.05, 0.04, 0.06, 0.88 * a))
    var col: Color = _pick["col"]
    var frame: Color = _pick.get("frame", col)
    var tag := String(_pick.get("tag", ""))
    var tag_w := _body_width(tag, 16) + 10.0 if tag != "" else 0.0
    box.size.x = minf(box.size.x + tag_w, 800.0)
    draw_rect(Rect2(box.position, Vector2(4.0, box.size.y)), Color(frame, a))
    draw_rect(box, Color(frame, 0.6 * a), false, 1.5)
    _icon_tex(_pick["icon"], Rect2(box.position + Vector2(10, 4), Vector2(22, 22)), Color(_pick["icon_tint"], a))
    var x := box.position.x + 38.0
    _body_in(Rect2(x, y, name_w, 30.0), name_text, 20, Color(col, a), HORIZONTAL_ALIGNMENT_LEFT)
    x += name_w + 10.0
    if tag != "":
        _body_in(Rect2(x, y + 2.0, tag_w, 30.0), tag, 16, Color(col, a), HORIZONTAL_ALIGNMENT_LEFT)
        x += tag_w
    x += 4.0
    _body_in(Rect2(x, y, box.end.x - x - 8.0, 30.0), effect, 20, Color(UiTheme.BONE, a), HORIZONTAL_ALIGNMENT_LEFT)


## A row of charge pips along the bottom edge of the active item's box.
func _draw_charge_pips(box: Rect2, charges: int, max_charges: int) -> void:
    if max_charges <= 0:
        return
    var pip_w := clampf((box.size.x - 4.0) / float(max_charges) - 2.0, 2.0, 6.0)
    for c in max_charges:
        var pip := Rect2(box.position.x + 3.0 + float(c) * (pip_w + 2.0), box.end.y - 6.0, pip_w, 4.0)
        draw_rect(pip.grow(1.0), Color(0, 0, 0, 0.8))
        draw_rect(pip, ANNOUNCE if c < charges else Color(0.25, 0.22, 0.24))


# --- Bottom right: vent gauge ----------------------------------------------


func _draw_vents(vp: Vector2, bottom: float) -> void:
    var many := main.players.size() > 1
    for i in main.players.size():
        var by := bottom - 8.0 - VENT_H - float(i) * VENT_STACK
        var g := Rect2(vp.x - MARGIN - 32.0 - VENT_W, by, VENT_W, VENT_H)
        _draw_vent(main.players[i], g, many)


func _draw_vent(p: Player, g: Rect2, tagged: bool) -> void:
    var limit := maxf(p.pressure_limit(), 0.001)
    var frac := clampf(p.pressure / limit, -1.0, 1.0)
    var hot := p.pressure > 0.0
    var side := HOT if hot else COLD
    var ready := absf(p.pressure) >= Player.VENT_MIN

    _backdrop(Rect2(g.position - Vector2(32, 36), Vector2(g.size.x + 64.0, g.size.y + 44.0)))

    # Ready glow: soft rings around the bar, breathing.
    if ready:
        var breath := 0.45 + 0.55 * _pulse(6.0)
        for k in 4:
            draw_rect(g.grow(3.0 + float(k) * 2.5), Color(side, (0.32 - float(k) * 0.07) * breath), false, 2.5)

    # Bar, filling outward from the centre.
    draw_rect(g, Color(0.05, 0.04, 0.05, 0.85))
    var half := g.size.x / 2.0
    if frac > 0.0:
        draw_rect(Rect2(g.position.x + half, g.position.y, half * frac, g.size.y), HOT)
    elif frac < 0.0:
        draw_rect(Rect2(g.position.x + half + half * frac, g.position.y, -half * frac, g.size.y), COLD)
    draw_rect(g.grow(1.0), Color(0, 0, 0, 0.8), false, 2.0)
    draw_rect(Rect2(g.position.x + half - 1.5, g.position.y - 3.0, 3.0, g.size.y + 6.0), Color.WHITE)

    # Cold and hot ends.
    _icon(Vector2i(40, 11), Rect2(g.position.x - 24.0, g.position.y - 2.0, 20, 20), COLD)
    draw_texture_rect(Art.PARTICLES["flame"], Rect2(g.end.x + 3.0, g.position.y - 4.0, 22, 22), false, HOT)

    # Label and prompt.
    var label := "%s VENT" % p.display_name().to_upper() if tagged else "VENT"
    var label_y := g.position.y - 10.0
    _body(Vector2(g.position.x, label_y), label, 16, UiTheme.BONE)
    var kind := p.input.last_kind
    var lw := _body_width(label, 16)
    if PlayerInput.vent_auto():
        _body(Vector2(g.position.x + lw + 10.0, label_y), "AUTO", 13, UiTheme.DIM)
    else:
        var prompt := p.input.prompt("vent")
        var pw := _prompt_width(prompt, kind, 20.0)
        Prompts.draw(self, Vector2(g.position.x + lw + 10.0 + pw / 2.0, g.position.y - 16.0), prompt, kind, 20.0)
    # Dash pips beside the gauge: lit while a charge is ready, filling while it recharges.
    var cap := p.dash_max_charges()
    for i in cap:
        var pip := Rect2(g.position.x - 32.0 - 18.0 - float(cap - 1 - i) * 16.0, g.position.y + 1.0, 12.0, 12.0)
        draw_rect(pip.grow(1.5), Color(0, 0, 0, 0.8))
        draw_rect(pip, Color(0.12, 0.11, 0.12))
        if i < p.dash_charges:
            draw_rect(pip, Color(0.92, 0.92, 0.88))
        elif i == p.dash_charges and p.dash_recharge > 0.0:
            var k := 1.0 - p.dash_recharge / maxf(0.01, p.dash_cooldown())
            draw_rect(Rect2(pip.position + Vector2(0, pip.size.y * (1.0 - k)), Vector2(pip.size.x, pip.size.y * k)), Color(0.6, 0.6, 0.58))

    if ready:
        _body(Vector2(g.end.x - 120.0, label_y), "READY", 15, Color(side, 0.6 + 0.4 * _pulse(6.0)), HORIZONTAL_ALIGNMENT_RIGHT, 120.0)


## Width Prompts.draw uses for a label, so the icon can sit flush after the VENT word.
func _prompt_width(label: String, kind: String, size: float) -> float:
    if kind == "pad":
        if Prompts.FACE.has(label):
            return size
        return size * 0.55 * float(label.length()) + size * 0.6
    return maxf(size, size * 0.5 * float(label.length()) + size * 0.5)


# --- Overlays --------------------------------------------------------------


func _draw_help(vp: Vector2) -> void:
    var inp: PlayerInput = main.players[0].input if not main.players.is_empty() else null
    var pad := inp != null and inp.last_kind == "pad"
    var lines := [
        "MOVE  %s      DASH  %s      ACTIVE  %s      INTERACT  %s      weapons aim and fire on their own" % [
            "left stick" if pad else "WASD", inp.prompt("dash") if inp != null else "Space",
            inp.prompt("active") if inp != null else "Q", "A" if pad else "E"],

        "CHARACTER  %s      PAUSE  %s      MARK THIS MOMENT  %s      F1 hides this" % [
            "Back" if pad else "C", "Start" if pad else "Esc", "hold Back" if pad else "F8"],
    ]
    var y := vp.y - 14.0 - 22.0 * lines.size()
    draw_rect(Rect2(0, y - 22, vp.x, 22.0 * lines.size() + 14), Color(0, 0, 0, 0.55))
    for line in lines:
        _centered(y, line, 16, Color(0.85, 0.82, 0.78), vp)
        y += 22.0


func _draw_toasts(_vp: Vector2) -> void:
    # Top-left, under the player card and its low-health label: never over the character.
    var y := 150.0
    var shown := _toasts.slice(maxi(0, _toasts.size() - 4))
    for t in shown:
        var alpha: float = clampf(t["t"], 0.0, 1.0)
        var pop: float = clampf((5.0 - t["t"]) / 0.15, 0.0, 1.0)
        var box := Rect2(16, y, 360, 30)
        draw_rect(box, Color(0, 0, 0, 0.6 * alpha))
        draw_rect(box, Color(0.6, 1.0, 0.8, 0.5 * alpha), false, 2.0)
        _body_in(Rect2(box.position + Vector2(10, 0), box.size - Vector2(20, 0)), t["text"], int(16 + 2 * pop), Color(0.6, 1.0, 0.8, alpha), HORIZONTAL_ALIGNMENT_LEFT)
        y += 36.0
