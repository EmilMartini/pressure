class_name ClassSelect
extends Control
## Class picker shown by Play: an Isaac-style carousel. The selected class stands in the
## middle of the screen, big, with its name, element, starting gun and gear, affinity,
## quirk and a line of flavour; two neighbours on each side shrink and dim away from it
## and the ring wraps around. Locked classes show as a black silhouette with a "?" and
## their unlock goal, and cannot be picked.
##
## Left / right (d-pad, stick, shoulders, A / D, arrows, mouse wheel) rotate, A / Enter /
## a click on the centre picks, B / Esc backs out, a click on a neighbour rotates to it.
## Everything is laid out from the visible viewport rect every frame, so it stays centred
## whatever the window size. `on_pick` receives the chosen class id.

const GRACE := 0.25            # seconds before input counts, so the Play press does not pick
const REPEAT_DELAY := 0.35
const REPEAT_RATE := 0.12
const SLIDE_SECS := 0.18
const FIG_PX := 16             # FigureGen figures are 16 x 16
const FIG_SCALE := 10.0        # centre figure: 160 px; neighbours 6x and 4x
const STEP_SECS := 0.42        # idle / step frame swap
const DENY_SECS := 0.3
## Carousel slots by distance from the centre: x offset (px at 1280 wide), figure scale
## and brightness. Fractional distances (mid-slide) interpolate.
const SLOT_X := [0.0, 290.0, 480.0, 570.0]
const SLOT_SCALE := [1.0, 0.6, 0.4, 0.3]
const SLOT_BRIGHT := [1.0, 0.55, 0.32, 0.2]
const MAX_SLOT := 2.6          # beyond this distance a figure is not drawn

## Vertical layout of the centred block (px).
const TITLE_H := 44.0
const STAGE_H := 184.0
const PIPS_H := 22.0
const NAME_H := 48.0
const INFO_H := 166.0
const GAP := 12.0

const LOCKED_COLOR := Color(0.40, 0.38, 0.38)
const SIL_EDGE := Color(0.36, 0.32, 0.36)
const BACKDROP := Color(0.02, 0.015, 0.03, 0.82)

var _on_pick: Callable
var _on_cancel: Callable
var _classes: Array = []
var _figs: Array = []              # per class: FigureGen figure { frames: [idle, step], ... }
var _gun_names: Dictionary = {}    # gun id -> display name
var _target := 0                   # unbounded index the carousel is heading to
var _pos := 0.0                    # unbounded, tweened toward _target
var _info_a := 1.0                 # info block fade after a move
var _tween: Tween = null
var _time := 0.0
var _deny := 0.0
var _picked := false
var _armed_in := GRACE
var _was: Dictionary = {}
var _held: Dictionary = {}
var _kind := "kb"                  # "pad" or "kb": which prompts to draw
var _hits: Array = []              # [Rect2, slot offset] per drawn figure, for the mouse


func _init(on_pick: Callable, on_cancel: Callable) -> void:
    _on_pick = on_pick
    _on_cancel = on_cancel


func _ready() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_STOP
    focus_mode = Control.FOCUS_ALL
    theme = UiTheme.make()
    texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    resized.connect(queue_redraw)
    get_viewport().size_changed.connect(queue_redraw)
    _classes = Classes.all()
    for c in _classes:
        var cdef: Dictionary = c
        var th := FigureGen.element_theme(int(cdef["element"]))
        if th == "":
            th = "vagrant"
        # Wearing its starting item when that is a drawn piece (the Tarsmith's coat), like
        # in game.
        var worn: Dictionary = {}
        var start_item := String(cdef.get("start_item", ""))
        var start_slot := String(Items.get_item(start_item).get("slot", ""))
        if WornGear.SLOTS.has(start_slot):
            worn[start_slot] = start_item
        _figs.append(FigureGen.generate_from({ th: FigureGen.CLASS_WEIGHT }, Color(0, 0, 0, 0), worn))
        var gun_id := String(cdef["start_gun"])
        if gun_id != "" and not _gun_names.has(gun_id):
            var gd: GunData = Guns.make(gun_id)
            _gun_names[gun_id] = gd.display_name if gd != null else gun_id
    var start := 0
    for i in _classes.size():
        if _classes[i]["id"] == Progress.chosen_class and Classes.is_unlocked(String(_classes[i]["id"])):
            start = i
    _target = start
    _pos = float(start)
    _kind = "pad" if not Input.get_connected_joypads().is_empty() else "kb"
    grab_focus()


# --- Selection -----------------------------------------------------------------


func _count() -> int:
    return maxi(1, _classes.size())


## Index of the selected class (where the carousel is heading).
func _sel() -> int:
    return posmod(_target, _count())


## `d` wrapped into [-n/2, n/2): the shortest way round the ring.
func _wrap_off(d: float) -> float:
    var n := float(_count())
    return fposmod(d + n * 0.5, n) - n * 0.5


func _rotate(dir: int) -> void:
    if dir == 0 or _picked or _classes.size() < 2:
        return
    _target += dir
    if _tween != null and _tween.is_valid():
        _tween.kill()
    _info_a = 0.2
    _tween = create_tween().set_parallel(true)
    _tween.tween_property(self, "_pos", float(_target), SLIDE_SECS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    _tween.tween_property(self, "_info_a", 1.0, SLIDE_SECS)
    Sfx.play("ui_move")


func _choose() -> void:
    if not visible or _picked or _armed_in > 0.0 or _classes.is_empty():
        return
    var id := String(_classes[_sel()]["id"])
    if not Classes.is_unlocked(id):
        Sfx.play("error")
        _deny = DENY_SECS
        return
    _picked = true
    Sfx.play("ui_confirm")
    if _on_pick.is_valid():
        _on_pick.call(id)


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
    # Pads are polled directly; their events are stripped from the ui_* actions.
    var left := false
    var right := false
    var accept := false
    var cancel := false
    var any_pad := false
    for d in Input.get_connected_joypads():
        var ax := Input.get_joy_axis(d, JOY_AXIS_LEFT_X)
        var l := Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_LEFT) or Input.is_joy_button_pressed(d, JOY_BUTTON_LEFT_SHOULDER) or ax < -0.55
        var r := Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_RIGHT) or Input.is_joy_button_pressed(d, JOY_BUTTON_RIGHT_SHOULDER) or ax > 0.55
        var a := Input.is_joy_button_pressed(d, JOY_BUTTON_A)
        var b := Input.is_joy_button_pressed(d, JOY_BUTTON_B)
        left = left or l
        right = right or r
        accept = accept or a
        cancel = cancel or b
        any_pad = any_pad or l or r or a or b
    if any_pad:
        _kind = "pad"
    var armed := _armed_in <= 0.0
    if _edge("left", left, delta, true) and armed:
        _rotate(-1)
    if _edge("right", right, delta, true) and armed:
        _rotate(1)
    if _edge("accept", accept, delta, false) and armed:
        _choose()
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
        KEY_LEFT, KEY_A:
            _rotate(-1)
        KEY_RIGHT, KEY_D:
            _rotate(1)
        KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
            if not k.echo:
                _choose()
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
    match mb.button_index:
        MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT:
            _rotate(-1)
        MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_RIGHT:
            _rotate(1)
        MOUSE_BUTTON_LEFT:
            # Topmost first: the centre figure is drawn last.
            for h_i in range(_hits.size() - 1, -1, -1):
                var hit: Array = _hits[h_i]
                var r: Rect2 = hit[0]
                if r.has_point(mb.position):
                    var off := int(hit[1])
                    if off == 0:
                        _choose()
                    else:
                        _rotate(off)
                    return


## True on the press, and again on repeat while held when `repeat` is set.
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


## The visible viewport in this control's local coordinates: the layout is centred on it
## rather than on our own rect, so a parent with an offset or odd size cannot shift it.
func _view_rect() -> Rect2:
    var vr := get_viewport_rect()
    return get_global_transform_with_canvas().affine_inverse() * vr


## Interpolate a slot table at fractional distance `d` from the centre.
func _slot(table: Array, d: float) -> float:
    var last := table.size() - 1
    var i0 := clampi(floori(d), 0, last)
    var i1 := mini(i0 + 1, last)
    return lerpf(float(table[i0]), float(table[i1]), clampf(d - float(i0), 0.0, 1.0))


func _draw() -> void:
    _hits.clear()
    if _classes.is_empty():
        return
    var vr := _view_rect()
    draw_rect(vr, BACKDROP)
    var cx := vr.get_center().x
    var block_h := TITLE_H + GAP + STAGE_H + PIPS_H + NAME_H + INFO_H
    var top := roundf(vr.get_center().y - block_h * 0.5)
    var sx := minf(1.0, vr.size.x / 1280.0)

    _text_c("CHOOSE YOUR CLASS", cx, top, 36, UiTheme.BONE)
    var stage_top := top + TITLE_H + GAP
    var fig_cy := roundf(stage_top + STAGE_H * 0.5)
    var sel := _sel()
    var sel_open := Classes.is_unlocked(String(_classes[sel]["id"]))

    # A soft pool of the selected class's colour behind the centre.
    var glow: Color = _tint(_classes[sel]) if sel_open else LOCKED_COLOR
    draw_circle(Vector2(cx, fig_cy), 118.0, Color(glow, 0.05))
    draw_circle(Vector2(cx, fig_cy), 86.0, Color(glow, 0.06))

    # Figures, far ones first so the centre sits on top.
    var order: Array = []
    var reach := minf(MAX_SLOT, float(_count() - 1) * 0.5 + 0.4)
    for i in _classes.size():
        var off := _wrap_off(float(i) - _pos)
        if absf(off) <= reach:
            order.append([absf(off), off, i])
    order.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
    for e in order:
        _draw_figure(int(e[2]), float(e[1]), cx, fig_cy, sx)

    # Position pips under the stage.
    var pip_y := stage_top + STAGE_H + 4.0
    var pip_step := 14.0
    var px0 := cx - pip_step * float(_classes.size() - 1) * 0.5
    for i in _classes.size():
        var open := Classes.is_unlocked(String(_classes[i]["id"]))
        var pc: Color = UiTheme.FOCUS if i == sel else (UiTheme.DIM if open else Color(0.22, 0.2, 0.22))
        var ps: float = 8.0 if i == sel else 6.0
        draw_rect(Rect2(Vector2(roundf(px0 + pip_step * float(i) - ps * 0.5), pip_y + (8.0 - ps) * 0.5), Vector2(ps, ps)), pc)

    _draw_info(sel, cx, stage_top + STAGE_H + PIPS_H)
    _draw_prompts(cx, vr.end.y - 34.0)


## One class figure at carousel offset `off` (0 = centre, fractional mid-slide).
func _draw_figure(i: int, off: float, cx: float, cy: float, sx: float) -> void:
    var d := absf(off)
    var c: Dictionary = _classes[i]
    var open := Classes.is_unlocked(String(c["id"]))
    var sc := FIG_SCALE * _slot(SLOT_SCALE, d)
    var bright := _slot(SLOT_BRIGHT, d)
    var fade := clampf((MAX_SLOT - d) / 0.5, 0.0, 1.0)
    var x := cx + signf(off) * _slot(SLOT_X, d) * sx
    var near := d < 0.5
    if near and _deny > 0.0:
        x += sin(_time * 70.0) * 6.0 * (_deny / DENY_SECS)
    var side := roundf(float(FIG_PX) * sc)
    var bob := roundf(sin(_time * 3.2) * 2.0) if near and open else 0.0
    var rect := Rect2(Vector2(roundf(x - side * 0.5), roundf(cy - side * 0.5 + bob)), Vector2(side, side))
    _hits.append([rect.grow(8.0), roundi(off)])
    # Floor shadow under the feet.
    draw_set_transform(Vector2(x, rect.end.y - sc * 0.8), 0.0, Vector2(1.0, 0.28))
    draw_circle(Vector2.ZERO, side * 0.34, Color(0, 0, 0, 0.45 * fade))
    draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
    var fig: Dictionary = _figs[i]
    var frames: Array = fig["frames"]
    var frame := 0
    if open and frames.size() > 1:
        # The centre walks in place; neighbours step slower and out of phase.
        var rate := STEP_SECS if near else STEP_SECS * 2.0
        frame = int(floorf((_time + float(i) * 0.37) / rate)) % 2
    var tex: Texture2D = frames[frame]
    if open:
        draw_texture_rect(tex, rect, false, Color(bright, bright, bright, fade))
        return
    # Locked: an outlined black silhouette with a "?" over it.
    var edge := Color(SIL_EDGE.r * bright * 1.4, SIL_EDGE.g * bright * 1.4, SIL_EDGE.b * bright * 1.4, fade)
    var o := maxf(1.0, roundf(sc * 0.25))
    for v in [Vector2(-o, 0), Vector2(o, 0), Vector2(0, -o), Vector2(0, o)]:
        draw_texture_rect(tex, Rect2(rect.position + (v as Vector2), rect.size), false, edge)
    draw_texture_rect(tex, rect, false, Color(0, 0, 0, fade))
    var qs := maxi(20, roundi(64.0 * sc / FIG_SCALE))
    var qc := Color(UiTheme.BONE.r * bright, UiTheme.BONE.g * bright, UiTheme.BONE.b * bright, fade * 0.9)
    _text_c("?", rect.get_center().x, rect.get_center().y - float(qs) * 0.55, qs, qc)


## Name and details of the selected class, centred on `cx` from `y` down.
func _draw_info(i: int, cx: float, y: float) -> void:
    var c: Dictionary = _classes[i]
    var open := Classes.is_unlocked(String(c["id"]))
    var a := clampf(_info_a, 0.0, 1.0)
    # Names stay neutral: an element never colours a name (GDD 6, "Rarity owns colour");
    # it shows as the spell icon, a swatch and its name below, and in the glow behind.
    _text_c(String(c["name"]).to_upper(), cx, y, 44, Color(UiTheme.BONE if open else LOCKED_COLOR, a))
    var row_y := y + NAME_H
    var flavour := String(c["desc"]).get_slice("\n", 0)
    if not open:
        _text_c("LOCKED", cx, row_y, 24, Color(UiTheme.FOCUS, a))
        _text_c(Classes.unlock_text(c), cx, row_y + 32.0, 22, Color(UiTheme.BONE, a))
        var prog := _unlock_progress(c)
        if prog.y > 0.0:
            var bw := 280.0
            var bar := Rect2(Vector2(roundf(cx - bw * 0.5), row_y + 66.0), Vector2(bw, 10.0))
            draw_rect(bar.grow(2.0), Color(0, 0, 0, 0.8 * a))
            draw_rect(bar, Color(0.2, 0.17, 0.19, a))
            draw_rect(Rect2(bar.position, Vector2(bw * clampf(prog.x / prog.y, 0.0, 1.0), bar.size.y)), Color(UiTheme.FOCUS, a))
        _text_c(flavour, cx, row_y + 92.0, 22, Color(UiTheme.DIM, a))
        return
    # Element: the class's spell icon and the element name.
    var elem := "NO ELEMENT" if c["element"] == Element.Kind.NONE else String(Element.NAMES[c["element"]]).to_upper()
    _icon_row([[Classes.icon(c), elem, UiTheme.BONE, Color.WHITE, c["element"]]], cx, row_y, a)
    # Starting gun and gear side by side.
    var gun_id := String(c["start_gun"])
    var gear: Array = []
    if c["id"] == "vagrant" or gun_id == "":
        gear.append([null, "Pick of two guns", UiTheme.BONE, Color.WHITE])
    else:
        gear.append([Art.gun_icon(gun_id), String(_gun_names.get(gun_id, gun_id)), UiTheme.BONE, Color.WHITE])
    var item_id := String(c["start_item"])
    if item_id == "":
        gear.append([null, "No gear", UiTheme.DIM, Color.WHITE])
    else:
        var it: Dictionary = Items.get_item(item_id)
        var gear_name := String(it.get("name", item_id))
        if int(it.get("rarity", 0)) > 0:
            gear_name += " (%s)" % Items.rarity_name(it)
        gear.append([Items.icon(it), gear_name, Items.rarity_text_color(it), Items.ui_icon_tint(it)])
    _icon_row(gear, cx, row_y + 38.0, a)
    var aff_col: Color = UiTheme.BONE if c["element"] != Element.Kind.NONE else UiTheme.DIM
    _text_c(Classes.affinity_text(c), cx, row_y + 82.0, 22, Color(aff_col, a))
    var quirk := Classes.quirk_text(c)
    _text_c(quirk if quirk != "" else "No quirk", cx, row_y + 110.0, 22, Color(UiTheme.BONE, a))
    _text_c(flavour, cx, row_y + 140.0, 20, Color(UiTheme.DIM, a))


## A centred row of [icon (or null), text, text colour, icon modulate, element swatch
## (optional Element.Kind; a small square of its colour after the icon)] entries, 32 px icons.
func _icon_row(entries: Array, cx: float, y: float, a: float) -> void:
    var fs := 24
    var icon_px := 32.0
    var sep := 44.0
    var total := 0.0
    var widths: Array = []
    for e in entries:
        var ent: Array = e
        var w := _tw(String(ent[1]), fs) + (icon_px + 8.0 if ent[0] != null else 0.0) + (SWATCH + 8.0 if _swatch_of(ent) != Element.Kind.NONE else 0.0)
        widths.append(w)
        total += w
    total += sep * float(maxi(0, entries.size() - 1))
    var x := roundf(cx - total * 0.5)
    for k in entries.size():
        var ent: Array = entries[k]
        if ent[0] != null:
            var im: Color = ent[3]
            Art.draw_icon(self, ent[0] as Texture2D, Rect2(Vector2(x, y), Vector2(icon_px, icon_px)), Color(im, a))
            x += icon_px + 8.0
        var sk := _swatch_of(ent)
        if sk != Element.Kind.NONE:
            var sq := Rect2(Vector2(x, roundf(y + (icon_px - SWATCH) * 0.5)), Vector2(SWATCH, SWATCH))
            draw_rect(sq.grow(1.0), Color(0, 0, 0, 0.9 * a))
            draw_rect(sq, Color(Element.COLORS[sk], a))
            x += SWATCH + 8.0
        var tc: Color = ent[2]
        _text(String(ent[1]), x, y + (icon_px - float(fs)) * 0.5, fs, Color(tc, a))
        x += _tw(String(ent[1]), fs) + sep


## The prompt strip for the current device, centred on `cx` at height `y`.
func _draw_prompts(cx: float, y: float) -> void:
    var groups: Array = []
    if _kind == "pad":
        groups = [[["LB", "RB"], "Rotate"], [["A"], "Choose"], [["B"], "Back"]]
    else:
        groups = [[["A", "D"], "Rotate"], [["Enter"], "Choose"], [["Esc"], "Back"]]
    var ks := 26.0
    var fs := 20
    var total := 0.0
    var widths: Array = []
    for g in groups:
        var grp: Array = g
        var w := 0.0
        for key in grp[0]:
            w += _key_w(String(key), ks) + 6.0
        w += 4.0 + _tw(String(grp[1]), fs)
        widths.append(w)
        total += w
    total += 40.0 * float(groups.size() - 1)
    var x := roundf(cx - total * 0.5)
    for gi in groups.size():
        var grp: Array = groups[gi]
        for key in grp[0]:
            var kw := _key_w(String(key), ks)
            Prompts.draw(self, Vector2(x + kw * 0.5, y), String(key), _kind, ks)
            x += kw + 6.0
        x += 4.0
        _text(String(grp[1]), x, y - float(fs) * 0.5, fs, UiTheme.DIM)
        x += _tw(String(grp[1]), fs) + 40.0


## Width Prompts.draw gives a key or button label at size `ks`.
func _key_w(label: String, ks: float) -> float:
    if _kind == "pad":
        if Prompts.FACE.has(label):
            return ks
        return ks * 0.55 * float(label.length()) + ks * 0.6
    return maxf(ks, ks * 0.5 * float(label.length()) + ks * 0.5)


const SWATCH := 12.0


func _swatch_of(ent: Array) -> int:
    return int(ent[4]) if ent.size() > 4 else Element.Kind.NONE


func _tint(c: Dictionary) -> Color:
    return UiTheme.BONE if c["element"] == Element.Kind.NONE else (c["tint"] as Color)


## (have, goal) toward the achievement that unlocks class `c`; goal 0 when none does.
func _unlock_progress(c: Dictionary) -> Vector2:
    var want := "class:" + String(c["id"])
    for ach in Progress.ACHIEVEMENTS:
        var ad: Dictionary = ach
        if (ad["rewards"] as Array).has(want):
            var goal := int(ad["goal"])
            return Vector2(float(mini(int(Progress.stat(String(ad["stat"]))), goal)), float(goal))
    return Vector2.ZERO


func _tw(t: String, fs: int) -> float:
    return Art.FONT.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x


## Text with its top-left at (x, y).
func _text(t: String, x: float, y: float, fs: int, col: Color) -> void:
    draw_string(Art.FONT, Vector2(roundf(x), roundf(y + Art.FONT.get_ascent(fs))), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## Text centred on `cx` with its top at `y`.
func _text_c(t: String, cx: float, y: float, fs: int, col: Color) -> void:
    _text(t, cx - _tw(t, fs) * 0.5, y, fs, col)
