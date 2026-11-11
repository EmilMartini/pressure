class_name TextCheck
extends Node
## The text-readability check (the text rule in art.gd), run with the bot:
##   godot --headless --path . res://scenes/main.tscn -- --autotest --text-shot --instance=N
## Opens each menu screen in turn (Shrine, pause menu, Build page, journal tabs, options,
## Gate, level-up) and measures every Label and Button under it plus every string the
## drawn screens report through `note`. Per screen it prints
##   [TEXT] <screen>: body >= N px, pixel >= N px, longest line W px (C chars) "...", K over
## and then `[TEXT] PASS n` or one `[TEXT] FAIL` line per problem: a sentence still in the
## pixel font, body text under Art.SMALL_SIZE, pixel text under 18 px, or a line wider than
## its box or the 1280 x 720 screen. Rows go to autotest/text/text.csv.

const MIN_PIXEL := 18
const SCREEN := Vector2(1280, 720)

## True while the check runs; `note` records nothing otherwise.
static var on := false
static var _rows: Array = []

var main: Node
var _done := false
var _t := 0.0


static func wanted() -> bool:
    return OS.get_cmdline_user_args().has("--text-shot")


## Drawn screens report each string they draw: its font, size, drawn width and the width
## it had room for (0 or less: unbounded).
static func note(_owner: Object, text: String, font: Font, px: int, w: float, max_w: float) -> void:
    if not on or text.strip_edges() == "":
        return
    _rows.append({ "text": text, "body": font == Art.FONT_BODY, "px": px, "w": w, "max": max_w })


func _init(m: Node) -> void:
    main = m
    name = "TextCheck"
    process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
    _t += delta
    if _done or _t < 1.0 or main.players.is_empty():
        return
    _done = true
    _run()


func _run() -> void:
    on = true
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://autotest/text"))
    var csv := FileAccess.open("res://autotest/text/text.csv", FileAccess.WRITE)
    csv.store_line("screen,font,px,width,max,text")
    var p: Player = main.players[0]
    var cl := CanvasLayer.new()
    cl.layer = 50
    add_child(cl)
    var layer := Control.new()   # carries the game's menu theme, as the hub and pause menu do
    layer.theme = UiTheme.make()
    layer.size = SCREEN
    cl.add_child(layer)
    var fails := 0
    var screens := 0

    # Shrine: every slot card, the survival row, Refund and Back.
    var shrine := MasteryScreen.new(func(): pass)
    shrine.position = Vector2(60, 26)
    layer.add_child(shrine)
    await _frames(2)
    _rows.clear()
    for i in shrine._focusables.size():
        shrine.tab = i
        shrine._refresh()
        await _frames(1)
    fails += _report("shrine", shrine, csv)
    screens += 1
    shrine.queue_free()
    await _frames(2)

    # Pause menu and its Build page.
    var pm: PauseMenu = main.pause_menu
    _rows.clear()
    pm.show_menu()
    await _frames(3)
    fails += _report("pause", pm, csv)
    _rows.clear()
    pm.show_sheet(p, true)
    await _frames(3)
    fails += _report("build", pm, csv)
    pm.hide_menu()
    await _frames(2)
    screens += 2

    # Journal, every tab.
    var j := Journal.new(func(): pass)
    layer.add_child(j)
    await _frames(2)
    _rows.clear()
    for k in Journal.TABS.size():
        j.set_tab(k)
        await _frames(2)
    fails += _report("journal", j, csv)
    screens += 1
    j.queue_free()
    await _frames(2)

    var opt := OptionsMenu.new(func(): pass)
    layer.add_child(opt)
    await _frames(2)
    _rows.clear()
    fails += _report("options", opt, csv)
    screens += 1
    opt.queue_free()
    await _frames(2)

    var gate := LoadoutScreen.new(func(_a = null, _b = null): pass, func(): pass)
    layer.add_child(gate)
    await _frames(3)
    _rows.clear()
    gate.queue_redraw()
    await _frames(2)
    fails += _report("gate", gate, csv)
    screens += 1
    gate.queue_free()
    await _frames(2)

    var lv = main.levelup
    if lv != null and lv.has_method("open"):
        _rows.clear()
        lv.open(p)
        await _frames(3)
        fails += _report("levelup", lv, csv)
        screens += 1
        if lv.has_method("close_for_test"):
            lv.close_for_test()

    # Pickup banner (hud.gd _draw_pick): every item's name in the pixel font at 34 px beside
    # its icon, and its one short line in the body font, inside the banner's widest box.
    _rows.clear()
    var room := SCREEN.x - 80.0 - 64.0
    var body_px := maxi(Art.bpx(18), 18)
    for id in Items.catalog.keys():
        var it: Dictionary = Items.catalog[id]
        var nm := String(it.get("name", "")).to_upper() + "  X3"
        _rows.append({ "text": nm, "body": false, "px": 34, "w": Art.FONT.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x + 46.0, "max": room, "named": true })
        var line := Hud._tagline(String(it.get("desc", "")))
        _rows.append({ "text": line, "body": true, "px": body_px, "w": Art.FONT_BODY.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, body_px).x, "max": room })
    # Green and red numbers (ItemCard.draw_numbers): the parser finds signed numbers only.
    for case in [["+25% scrap, -10 max HP", "+25% -10"], ["This gun: +40% fire rate, +50% pressure", "+40% +50%"], ["re-roll costs 5, +0.5 regen", "+0.5"]]:
        var got: Array = []
        for sp in ItemCard.number_spans(case[0]):
            got.append(String(case[0]).substr(sp[0], sp[1] - sp[0]))
        if " ".join(got) != case[1]:
            print("[TEXT] FAIL number spans in \"%s\": %s" % [case[0], got])
            fails += 1
    var holder := Node.new()
    fails += _report("pickup", holder, csv)
    holder.free()
    screens += 1

    csv.close()
    on = false
    if fails == 0:
        print("[TEXT] PASS %d" % screens)
    else:
        print("[TEXT] FAIL %d problems on %d screens" % [fails, screens])
    main.get_tree().quit()


func _frames(n: int) -> void:
    for k in n:
        await get_tree().process_frame


## Measures `root`'s visible Labels and Buttons and the noted strings; prints the summary
## and FAIL lines, returns the number of problems.
func _report(screen: String, root: Node, csv: FileAccess) -> int:
    var rows: Array = _rows.duplicate()
    for n in root.find_children("*", "", true, false):
        if not (n is Label or n is Button) or not (n as Control).is_visible_in_tree():
            continue
        var c := n as Control
        var text := String(c.get("text"))
        if text.strip_edges() == "":
            continue
        var f := c.get_theme_font("font")
        var px := c.get_theme_font_size("font_size")
        var wrap := n is Label and (n as Label).autowrap_mode != TextServer.AUTOWRAP_OFF
        var clip := n is Label and (n as Label).clip_text
        for line in text.split("\n"):
            var w := f.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
            if wrap:
                w = minf(w, c.size.x)
            # Room: the control's own width when it wraps or clips, else the screen edge.
            var room := c.size.x if (wrap or clip) else SCREEN.x - c.get_global_rect().position.x
            rows.append({ "text": line, "body": f == Art.FONT_BODY, "px": px, "w": w, "max": room, "named": c.has_meta("pixel") })
    var min_body := 999
    var min_pixel := 999
    var longest := {}
    var over := 0
    var problems: Array = []
    for r in rows:
        var t := String(r["text"])
        var px := int(r["px"])
        var w := float(r["w"])
        csv.store_line("%s,%s,%d,%.0f,%.0f,\"%s\"" % [screen, "body" if r["body"] else "pixel", px, w, float(r["max"]), t.replace("\"", "'")])
        if r["body"]:
            min_body = mini(min_body, px)
            if px < Art.SMALL_SIZE:
                problems.append("body %d px: %s" % [px, t.left(50)])
        else:
            min_pixel = mini(min_pixel, px)
            if px < MIN_PIXEL:
                problems.append("pixel %d px: %s" % [px, t.left(50)])
            if Art.is_prose(t) and not r.get("named", false):
                problems.append("sentence in pixel font: %s" % t.left(60))
        if float(r["max"]) > 0.0 and w > float(r["max"]) + 1.0:
            over += 1
            problems.append("over by %.0f px: %s" % [w - float(r["max"]), t.left(50)])
        if longest.is_empty() or w > float(longest["w"]):
            longest = r
    print("[TEXT] %s: body >= %s px, pixel >= %s px, longest line %.0f px (%d chars) \"%s\", %d over, %d strings" % [
        screen, "-" if min_body == 999 else str(min_body), "-" if min_pixel == 999 else str(min_pixel),
        float(longest.get("w", 0.0)), String(longest.get("text", "")).length(), String(longest.get("text", "")).left(48), over, rows.size()])
    for why in problems:
        print("[TEXT] FAIL %s: %s" % [screen, why])
    return problems.size()
