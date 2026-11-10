class_name LoadoutScreen
extends Control
## The Gate's loadout (World and progression GDD, section 11): the Vagrant stands on the
## left wearing the Mark's accent; on the right four slots, Kit, Mark, Relic and Vow, and
## Descend. Locked Kits and Marks show with their unlock goal and cannot be taken down.
##
## Up / down (d-pad, stick, W / S, arrows) picks a slot; left / right (d-pad, stick,
## shoulders, A / D, arrows, mouse wheel) changes it; A / Enter / Space descends; B / Esc
## backs out. The mouse clicks a slot to pick it, its arrows to change it, and Descend.
## `on_pick` receives { kit, mark, relic, vow }.

const GRACE := 0.25
const REPEAT_DELAY := 0.35
const REPEAT_RATE := 0.12
const DENY_SECS := 0.3
const FIG_SCALE := 12.0
const ROWS := ["kit", "mark", "relic", "vow", "descend"]
const ROW_NAMES := { "kit": "KIT", "mark": "MARK", "relic": "RELIC", "vow": "VOW" }
const ROW_H := 92.0
const PANEL_W := 640.0
const LOCKED_COLOR := Color(0.40, 0.38, 0.38)
const BACKDROP := Color(0.02, 0.015, 0.03, 0.95)

var _on_pick: Callable
var _on_cancel: Callable
var _row := 4                       # starts on Descend: the last loadout is one press away
var _sel := { "kit": 0, "mark": 0, "relic": 0, "vow": 0 }
var _opts := {}                     # row -> Array of option ids
var _time := 0.0
var _deny := 0.0
var _deny_row := -1
var _picked := false
var _armed_in := GRACE
var _was: Dictionary = {}
var _held: Dictionary = {}
var _kind := "kb"
var _hits: Array = []               # [Rect2, row, dir (0 = the row itself)]
var _fig_key := ""
var _fig: Dictionary = {}
var _gun_names: Dictionary = {}


func _init(on_pick: Callable, on_cancel: Callable) -> void:
    _on_pick = on_pick
    _on_cancel = on_cancel


func _ready() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_STOP
    focus_mode = Control.FOCUS_ALL
    theme = UiTheme.make()
    texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    _opts["kit"] = Loadout.KITS.duplicate()
    var mark_ids: Array = []
    for m in Loadout.marks():
        mark_ids.append(m["id"])
    _opts["mark"] = mark_ids
    _opts["relic"] = [""] + Progress.relics
    var vow_ids: Array = []
    for v in Loadout.VOWS:
        vow_ids.append(v["id"])
    _opts["vow"] = vow_ids
    var lo := Loadout.current()
    for slot in ["kit", "mark", "relic", "vow"]:
        _sel[slot] = maxi(0, (_opts[slot] as Array).find(String(lo[slot])))
    for gid in Loadout.KITS:
        if String(gid) != "":
            _gun_names[gid] = Loadout.kit_name(String(gid))
    _kind = "pad" if not Input.get_connected_joypads().is_empty() else "kb"
    grab_focus()


# --- State -------------------------------------------------------------------


func option(slot: String) -> String:
    var arr: Array = _opts[slot]
    return String(arr[int(_sel[slot])]) if not arr.is_empty() else ""


func current() -> Dictionary:
    return { "kit": option("kit"), "mark": option("mark"), "relic": option("relic"), "vow": option("vow") }


func _open(slot: String, id: String) -> bool:
    match slot:
        "kit":
            return Loadout.kit_unlocked(id)
        "mark":
            return Loadout.mark_unlocked(id)
    return true


## The first slot holding something locked, or "" when the loadout can go down.
func blocked_slot() -> String:
    for slot in ["kit", "mark"]:
        if not _open(slot, option(slot)):
            return slot
    return ""


func select_row(r: int) -> void:
    r = clampi(r, 0, ROWS.size() - 1)
    if r != _row:
        _row = r
        Sfx.play("ui_move")


## Change slot `slot` by `dir` (wrapping).
func cycle(slot: String, dir: int) -> void:
    if _picked or not _opts.has(slot):
        return
    var n := (_opts[slot] as Array).size()
    if n < 2:
        Sfx.play("error")
        return
    _sel[slot] = posmod(int(_sel[slot]) + dir, n)
    Sfx.play("ui_move")


func descend() -> void:
    if not visible or _picked or _armed_in > 0.0:
        return
    var b := blocked_slot()
    if b != "":
        Sfx.play("error")
        _deny = DENY_SECS
        _deny_row = ROWS.find(b)
        _row = _deny_row
        return
    _picked = true
    Sfx.play("ui_confirm")
    if _on_pick.is_valid():
        _on_pick.call(current())


func _cancel() -> void:
    if not visible or _picked:
        return
    Sfx.play("ui_back")
    if _on_cancel.is_valid():
        _on_cancel.call()


# --- Input -------------------------------------------------------------------


func _process(delta: float) -> void:
    if not visible:
        return
    _time += delta
    _deny = maxf(0.0, _deny - delta)
    if _armed_in > 0.0:
        _armed_in -= delta
    var up := false
    var down := false
    var left := false
    var right := false
    var accept := false
    var cancel := false
    var any_pad := false
    for d in Input.get_connected_joypads():
        var ax := Input.get_joy_axis(d, JOY_AXIS_LEFT_X)
        var ay := Input.get_joy_axis(d, JOY_AXIS_LEFT_Y)
        var u := Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_UP) or ay < -0.55
        var dn := Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_DOWN) or ay > 0.55
        var l := Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_LEFT) or Input.is_joy_button_pressed(d, JOY_BUTTON_LEFT_SHOULDER) or ax < -0.55
        var r := Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_RIGHT) or Input.is_joy_button_pressed(d, JOY_BUTTON_RIGHT_SHOULDER) or ax > 0.55
        var a := Input.is_joy_button_pressed(d, JOY_BUTTON_A)
        var b := Input.is_joy_button_pressed(d, JOY_BUTTON_B)
        up = up or u
        down = down or dn
        left = left or l
        right = right or r
        accept = accept or a
        cancel = cancel or b
        any_pad = any_pad or u or dn or l or r or a or b
    if any_pad:
        _kind = "pad"
    var armed := _armed_in <= 0.0
    if _edge("up", up, delta, true) and armed:
        select_row(_row - 1)
    if _edge("down", down, delta, true) and armed:
        select_row(_row + 1)
    if _edge("left", left, delta, true) and armed and _row < 4:
        cycle(ROWS[_row], -1)
    if _edge("right", right, delta, true) and armed and _row < 4:
        cycle(ROWS[_row], 1)
    if _edge("accept", accept, delta, false) and armed:
        descend()
    if _edge("cancel", cancel, delta, false) and armed:
        _cancel()
    queue_redraw()


func _input(event: InputEvent) -> void:
    if not visible:
        return
    if event is InputEventMouseMotion:
        if (event as InputEventMouseMotion).relative.length() > 2.0:
            _kind = "kb"
        return
    if not event is InputEventKey or not event.pressed:
        return
    _kind = "kb"
    if _armed_in > 0.0:
        return
    var k := event as InputEventKey
    var handled := true
    match k.physical_keycode:
        KEY_UP, KEY_W:
            select_row(_row - 1)
        KEY_DOWN, KEY_S:
            select_row(_row + 1)
        KEY_LEFT, KEY_A:
            if _row < 4:
                cycle(ROWS[_row], -1)
        KEY_RIGHT, KEY_D:
            if _row < 4:
                cycle(ROWS[_row], 1)
        KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
            if not k.echo:
                descend()
        KEY_ESCAPE:
            if not k.echo:
                _cancel()
        _:
            handled = false
            if not k.echo and event.is_action("ui_cancel"):
                handled = true
                _cancel()
    if handled:
        get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
    if not event is InputEventMouseButton or not event.pressed:
        return
    var mb := event as InputEventMouseButton
    accept_event()
    _kind = "kb"
    if _armed_in > 0.0:
        return
    var hit_row := -1
    var hit_dir := 0
    for h_i in range(_hits.size() - 1, -1, -1):
        var hit: Array = _hits[h_i]
        if (hit[0] as Rect2).has_point(mb.position):
            hit_row = int(hit[1])
            hit_dir = int(hit[2])
            break
    match mb.button_index:
        MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
            var r := hit_row if hit_row >= 0 and hit_row < 4 else _row
            if r < 4:
                _row = r
                cycle(ROWS[r], -1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
        MOUSE_BUTTON_LEFT:
            if hit_row < 0:
                return
            if hit_row == 4:
                _row = 4
                descend()
            elif hit_dir != 0:
                _row = hit_row
                cycle(ROWS[hit_row], hit_dir)
            else:
                select_row(hit_row)


func _edge(key: String, down: bool, delta: float, repeat: bool) -> bool:
    var was: bool = _was.get(key, false)
    _was[key] = down
    if not down:
        _held[key] = 0.0
        return false
    if not was:
        _held[key] = 0.0
        return true
    if not repeat:
        return false
    var h: float = float(_held.get(key, 0.0)) + delta
    if h >= REPEAT_DELAY:
        _held[key] = h - REPEAT_RATE
        return true
    _held[key] = h
    return false


# --- Drawing -----------------------------------------------------------------


func _view_rect() -> Rect2:
    return get_global_transform_with_canvas().affine_inverse() * get_viewport_rect()


## The Vagrant wearing the Mark's item and the Relic when they are drawn pieces.
func _figure() -> Dictionary:
    var m := Loadout.mark(option("mark"))
    var key := "%s|%s" % [option("mark"), option("relic")]
    if key == _fig_key and not _fig.is_empty():
        return _fig
    var worn: Dictionary = {}
    for item_id in [String(m.get("start_item", "")), option("relic")]:
        var slot := String(Items.get_item(item_id).get("slot", ""))
        if item_id != "" and WornGear.SLOTS.has(slot):
            worn[slot] = item_id
    _fig = FigureGen.generate_from({ "vagrant": FigureGen.CLASS_WEIGHT }, Color(0, 0, 0, 0), worn)
    _fig_key = key
    return _fig


func _draw() -> void:
    _hits.clear()
    var vr := _view_rect()
    draw_rect(vr, BACKDROP)
    var cx := vr.get_center().x
    var sx := minf(1.0, vr.size.x / 1280.0)
    var top := roundf(vr.get_center().y - 300.0)
    _text_c("THE GATE", cx, top, 36, UiTheme.BONE)
    # The Vagrant on the left, the slots on the right.
    var fig_c := Vector2(roundf(cx - 330.0 * sx), roundf(vr.get_center().y + 10.0))
    _draw_vagrant(fig_c)
    var px := roundf(cx - 150.0 * sx)
    var y := top + 64.0
    for r in ROWS.size():
        _draw_row(r, px, y, PANEL_W * sx)
        y += ROW_H if r < 4 else 0.0
    _draw_prompts(cx, vr.end.y - 34.0)


func _draw_vagrant(c: Vector2) -> void:
    var fig := _figure()
    var frames: Array = fig["frames"]
    var tex: Texture2D = frames[int(floorf(_time / 0.42)) % frames.size()]
    var side := 16.0 * FIG_SCALE
    var accent := Loadout.accent(option("mark"))
    if accent.a > 0.0:
        draw_circle(c, 120.0, Color(accent, 0.05))
        draw_circle(c, 88.0, Color(accent, 0.07))
    draw_set_transform(Vector2(c.x, c.y + side * 0.5 - 8.0), 0.0, Vector2(1.0, 0.28))
    draw_circle(Vector2.ZERO, side * 0.34, Color(0, 0, 0, 0.45))
    draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
    var rect := Rect2(c - Vector2(side, side) * 0.5 + Vector2(0, roundf(sin(_time * 3.2) * 2.0)), Vector2(side, side))
    draw_texture_rect(tex, rect, false)
    if accent.a > 0.0:
        # The Mark's brand on the chest, as on the figure in a run (Player._draw_mark).
        var at := rect.get_center() + Vector2(0, 1.5 * FIG_SCALE)
        var pulse := 0.5 + 0.5 * sin(_time * 2.4)
        var s := FIG_SCALE * 0.75
        draw_texture_rect(Art.PARTICLES["light"], Rect2(at - Vector2(s, s) * 3.0, Vector2(s, s) * 6.0), false, Color(accent, 0.3 + 0.2 * pulse))
        draw_colored_polygon(PackedVector2Array([at + Vector2(0, -2.6 * s), at + Vector2(2.2 * s, 0), at + Vector2(0, 2.6 * s), at + Vector2(-2.2 * s, 0)]), Color(0.05, 0.04, 0.05, 0.95))
        draw_colored_polygon(PackedVector2Array([at + Vector2(0, -1.9 * s), at + Vector2(1.5 * s, 0), at + Vector2(0, 1.9 * s), at + Vector2(-1.5 * s, 0)]), accent)
    _text_c("THE VAGRANT", c.x, rect.end.y + 18.0, 24, UiTheme.DIM)


## One slot row at (x, y): its name, arrows, icon and option name, and a detail line.
func _draw_row(r: int, x: float, y: float, w: float) -> void:
    var focused := r == _row
    var shake := sin(_time * 70.0) * 6.0 * (_deny / DENY_SECS) if r == _deny_row and _deny > 0.0 else 0.0
    x += shake
    if r == 4:
        var blocked := blocked_slot() != ""
        var br := Rect2(Vector2(x, y + 12.0), Vector2(w, 56.0))
        draw_rect(br, Color(0.08, 0.06, 0.07, 0.95))
        draw_rect(br, UiTheme.FOCUS if focused else UiTheme.DIM, false, 3.0 if focused else 1.5)
        _text_c("DESCEND" if not blocked else "LOCKED: CHANGE IT TO DESCEND", br.get_center().x, br.position.y + 12.0, 28,
            (UiTheme.BONE if not blocked else LOCKED_COLOR))
        _hits.append([br, 4, 0])
        return
    var slot: String = ROWS[r]
    var box := Rect2(Vector2(x, y), Vector2(w, ROW_H - 10.0))
    draw_rect(box, Color(0.06, 0.05, 0.06, 0.9 if focused else 0.6))
    if focused:
        draw_rect(box, UiTheme.FOCUS, false, 2.5)
    _hits.append([box, r, 0])
    _text(String(ROW_NAMES[slot]), x + 14.0, y + 10.0, 20, UiTheme.FOCUS if focused else UiTheme.DIM)
    # Arrows either side of the option.
    var n := (_opts[slot] as Array).size()
    var la := Rect2(Vector2(x + 96.0, y + 4.0), Vector2(34.0, 42.0))
    var ra := Rect2(Vector2(x + w - 44.0, y + 4.0), Vector2(34.0, 42.0))
    if n > 1:
        _text_c("<", la.get_center().x, la.position.y + 6.0, 30, UiTheme.BONE if focused else UiTheme.DIM)
        _text_c(">", ra.get_center().x, ra.position.y + 6.0, 30, UiTheme.BONE if focused else UiTheme.DIM)
        _hits.append([la, r, -1])
        _hits.append([ra, r, 1])
    var id := option(slot)
    var open := _open(slot, id)
    var info := _option_text(slot, id, open)
    var name_col: Color = info[2] if open else LOCKED_COLOR
    var ix := x + 140.0
    var icon: Texture2D = info[3]
    if icon != null:
        Art.draw_icon(self, icon, Rect2(Vector2(ix, y + 8.0), Vector2(32, 32)), Color(1, 1, 1, 1) if open else Color(0.2, 0.2, 0.2))
        ix += 42.0
    _text(String(info[0]), ix, y + 12.0, 26, name_col)
    _text(String(info[1]), x + 140.0, y + 50.0, 18, UiTheme.FOCUS if not open else UiTheme.DIM)
    # Position pips: where this option sits among the slot's choices.
    if n > 1 and n <= 16:
        var pip_x := x + w - 54.0 - 9.0 * float(n)
        for i in n:
            var on := i == int(_sel[slot])
            draw_rect(Rect2(Vector2(pip_x + 9.0 * float(i), y + 66.0), Vector2(5, 5)), UiTheme.FOCUS if on else Color(0.28, 0.25, 0.27))


## [name, detail line, name colour, icon] for an option.
func _option_text(slot: String, id: String, open: bool) -> Array:
    match slot:
        "kit":
            if id == "":
                return ["Bare hands", "The entrance offers a pick of two weapons", UiTheme.BONE, null]
            var gd: GunData = Guns.make(id)
            var detail := "%s, weight %d" % [Element.NAMES[gd.element] if gd.element != Element.Kind.NONE else "No element", gd.weight] if gd != null else ""
            if not open:
                detail = "LOCKED: " + Loadout.unlock_text("kit:" + id)
            return [String(_gun_names.get(id, id)), detail, UiTheme.BONE, Art.gun_icon(id)]
        "mark":
            var m := Loadout.mark(id)
            var bits: Array = [Loadout.affinity_text(m)]
            var q := Loadout.quirk_text(m)
            if q != "":
                bits.append(q)
            var item_id := String(m.get("start_item", ""))
            if item_id != "":
                bits.append(String(Items.get_item(item_id).get("name", item_id)))
            var detail := ", ".join(bits)
            if not open:
                detail = "LOCKED: " + Loadout.unlock_text("mark:" + id)
            return [String(m.get("name", id)), detail, UiTheme.BONE, Loadout.mark_icon(id)]
        "relic":
            if id == "":
                var none_detail := "Items saved in a Well are sold back by the Wellkeeper" if Progress.relics.is_empty() else "Carry nothing extra"
                return ["No Relic", none_detail, UiTheme.DIM, null]
            var it: Dictionary = Items.get_item(id)
            var rn := String(it.get("name", id))
            if int(it.get("rarity", 0)) > 0:
                rn += " (%s)" % Items.rarity_name(it)
            return [rn, String(it.get("desc", "")).get_slice("\n", 0).left(70), Items.rarity_text_color(it), Items.icon(it)]
        "vow":
            var v := Loadout.vow(id)
            var detail := String(v["desc"])
            if float(v["embers"]) > 0.0:
                detail += ", +%d%% Embers" % roundi(float(v["embers"]) * 100.0)
            return [String(v["name"]), detail, UiTheme.BONE if id != "" else UiTheme.DIM, null]
    return [id, "", UiTheme.BONE, null]


func _draw_prompts(cx: float, y: float) -> void:
    var groups: Array = []
    if _kind == "pad":
        groups = [[["LB", "RB"], "Change"], [["A"], "Descend"], [["B"], "Back"]]
    else:
        groups = [[["W", "S"], "Slot"], [["A", "D"], "Change"], [["Enter"], "Descend"], [["Esc"], "Back"]]
    var ks := 26.0
    var fs := 20
    var total := 0.0
    for g in groups:
        var grp: Array = g
        for key in grp[0]:
            total += _key_w(String(key), ks) + 6.0
        total += 4.0 + _tw(String(grp[1]), fs)
    total += 40.0 * float(groups.size() - 1)
    var x := roundf(cx - total * 0.5)
    for g in groups:
        var grp: Array = g
        for key in grp[0]:
            var kw := _key_w(String(key), ks)
            Prompts.draw(self, Vector2(x + kw * 0.5, y), String(key), _kind, ks)
            x += kw + 6.0
        x += 4.0
        _text(String(grp[1]), x, y - float(fs) * 0.5, fs, UiTheme.DIM)
        x += _tw(String(grp[1]), fs) + 40.0


func _key_w(label: String, ks: float) -> float:
    if _kind == "pad":
        if Prompts.FACE.has(label):
            return ks
        return ks * 0.55 * float(label.length()) + ks * 0.6
    return maxf(ks, ks * 0.5 * float(label.length()) + ks * 0.5)


## Width of `t` drawn by _text: sentences in the body font (see the text rule in art.gd).
func _tw(t: String, fs: int) -> float:
    return Art.text_font(t).get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, Art.text_px(t, fs)).x


## `t` with its top edge at `y`: the pixel font at `fs`, or sentences in the body font.
func _text(t: String, x: float, y: float, fs: int, col: Color) -> void:
    var f := Art.text_font(t)
    var px := Art.text_px(t, fs)
    draw_string(f, Vector2(roundf(x), roundf(y + f.get_ascent(px))), t, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)
    TextCheck.note(self, t, f, px, f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x, size.x - x)


func _text_c(t: String, cx: float, y: float, fs: int, col: Color) -> void:
    _text(t, cx - _tw(t, fs) * 0.5, y, fs, col)
