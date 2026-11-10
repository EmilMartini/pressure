class_name MasteryScreen
extends PanelContainer
## The Shrine's talent board (see Mastery): eleven slot cards in a grid, each showing both
## sides with the active one lit, its rank pips and the next rank's cost, then the
## survival row (Last Breath), the Embers in the header and a free refund-all with a
## confirmation. Under the board, the detail panel for the focused entry reads top-down:
## the name (pixel font) with rank pips, one effect line (body font, numbers lit), the next
## rank and its Ember cost, then the other side, smaller and dimmer. Purchases, switches
## and errors show as a short toast in the panel's corner.
##
## Controls. Pad: d-pad / stick moves between cards (left / right through MenuPad.on_tab,
## which calls set_tab), A buys the next rank of the lit side, X switches side, B closes.
## Keyboard: arrows move, Enter / Space / E buys, Tab / Q / X switches side. Mouse: hover
## focuses, a click on the lit row buys, a click on the dark row (or a right-click)
## switches side. The hub (and the fallback menu) poll the pad and close on B / Esc.

const COLS := 4
const CARD_SIZE := Vector2(272, 112)
const ROW_H := 38.0
const ROW_TOP := 26.0
const ICON := 32.0
const LIT := Color(1.0, 0.82, 0.35)
const OWNED := Color(0.6, 1.0, 0.75)
const LOCKED := Color(0.45, 0.42, 0.45)
const CARD_BG := Color(0.06, 0.05, 0.07, 0.95)
const REFUND_SECS := 4.0
const TOAST_SECS := 2.6
const DETAIL_H := 122.0
const NAME_PX := 32

var on_close: Callable
var tab := 0                       # index into _focusables: slots, survival, refund, back

var _cards: Array[Button] = []     # one per slot, in Mastery.SLOTS order
var _ids: Array = []               # slot id per card
var _survival: Button
var _refund: Button
var _back: Button
var _focusables: Array = []
var _embers_label: Label
var _spent_label: Label
var _detail_box: Control
var _num_re := RegEx.create_from_string("[+-]?\\d+(?:\\.\\d+)?%?")
var _ember_tex: Texture2D
var _refund_armed := false
var _refund_left := 0.0
var _time := 0.0
var _x_was := false
var _bought_at: Dictionary = {}    # card index (-1 survival) -> _time of the last purchase
var _note := ""                    # the toast's text
var _note_t := 0.0                 # seconds the toast has left


func _init(p_on_close: Callable) -> void:
    on_close = p_on_close


func _ready() -> void:
    custom_minimum_size = Vector2(1160, 668)
    _ember_tex = Mastery.ember_icon()
    var v := VBoxContainer.new()
    v.add_theme_constant_override("separation", 6)
    add_child(v)

    var header := HBoxContainer.new()
    header.add_theme_constant_override("separation", 14)
    v.add_child(header)
    header.add_child(_text("SHRINE", 36, UiTheme.BONE))
    var ember := TextureRect.new()
    ember.texture = _ember_tex
    ember.custom_minimum_size = Vector2(32, 32)
    ember.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    ember.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    ember.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    ember.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    header.add_child(ember)
    _embers_label = _text("", 28, Mastery.EMBER_COLOR)
    _embers_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    header.add_child(_embers_label)
    _spent_label = _text("", 20, UiTheme.DIM)
    UiTheme.to_body(_spent_label, 16)
    _spent_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    header.add_child(_spent_label)
    var hint := _text("A buy    X switch side    B back", 20, UiTheme.DIM)
    UiTheme.to_body(hint, 16)
    hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    header.add_child(hint)

    var grid := GridContainer.new()
    grid.columns = COLS
    grid.add_theme_constant_override("h_separation", 8)
    grid.add_theme_constant_override("v_separation", 8)
    v.add_child(grid)
    for sl in Mastery.slots():
        var i := _cards.size()
        _ids.append(String(sl["id"]))
        var b := _card_button(CARD_SIZE)
        b.button_mask = 0   # clicks are read per row in _on_card_input
        b.draw.connect(_draw_card.bind(i))
        b.pressed.connect(_buy.bind(i))
        b.gui_input.connect(_on_card_input.bind(i))
        grid.add_child(b)
        _cards.append(b)

    _survival = _card_button(Vector2(0, 66))
    _survival.draw.connect(_draw_survival)
    _survival.pressed.connect(_buy_survival)
    v.add_child(_survival)

    _detail_box = Control.new()
    _detail_box.custom_minimum_size = Vector2(0, DETAIL_H)
    _detail_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _detail_box.draw.connect(_draw_detail)
    v.add_child(_detail_box)

    var footer := HBoxContainer.new()
    footer.add_theme_constant_override("separation", 16)
    v.add_child(footer)
    _refund = UiTheme.button("Refund all", _on_refund)
    _refund.custom_minimum_size = Vector2(300, 48)
    footer.add_child(_refund)
    var spacer := Control.new()
    spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    footer.add_child(spacer)
    _back = UiTheme.button("Back", func(): on_close.call())
    _back.custom_minimum_size = Vector2(160, 48)
    footer.add_child(_back)

    _focusables = []
    for c in _cards:
        _focusables.append(c)
    _focusables.append_array([_survival, _refund, _back])
    for i in _focusables.size():
        var f: Control = _focusables[i]
        f.focus_mode = Control.FOCUS_ALL
        f.focus_entered.connect(_on_focus.bind(i))
        f.mouse_entered.connect(func():
            if is_visible_in_tree() and not f.has_focus():
                f.grab_focus())
    _refund.focus_exited.connect(_disarm_refund)
    _link_focus()
    visibility_changed.connect(_on_visibility_changed)
    Mastery.changed.connect(_refresh)
    _refresh()


func _card_button(min_size: Vector2) -> Button:
    var b := Button.new()
    b.custom_minimum_size = min_size
    for state in ["normal", "hover", "focus", "pressed", "disabled"]:
        b.add_theme_stylebox_override(state, StyleBoxEmpty.new())
    b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    return b


## Grid neighbours for the arrows and d-pad; focus_next / focus_previous are the card
## below / above, because MenuPad walks those for up and down.
func _link_focus() -> void:
    var n := _cards.size()
    for i in n:
        var c := _cards[i]
        var col := i % COLS
        var left: Control = _cards[i - 1] if col > 0 else c
        var right: Control = _cards[i + 1] if col < COLS - 1 and i + 1 < n else c
        var up: Control = _cards[i - COLS] if i >= COLS else c
        var down: Control = _cards[i + COLS] if i + COLS < n else _survival
        c.focus_neighbor_left = c.get_path_to(left)
        c.focus_neighbor_right = c.get_path_to(right)
        c.focus_neighbor_top = c.get_path_to(up)
        c.focus_neighbor_bottom = c.get_path_to(down)
        c.focus_previous = c.get_path_to(up)
        c.focus_next = c.get_path_to(down)
    var last_row: Control = _cards[(n - 1) / COLS * COLS]
    _link(_survival, _survival, _survival, last_row, _refund)
    _link(_refund, _refund, _back, _survival, _refund)
    _link(_back, _refund, _back, _survival, _back)


func _link(c: Control, left: Control, right: Control, up: Control, down: Control) -> void:
    c.focus_neighbor_left = c.get_path_to(left)
    c.focus_neighbor_right = c.get_path_to(right)
    c.focus_neighbor_top = c.get_path_to(up)
    c.focus_neighbor_bottom = c.get_path_to(down)
    c.focus_previous = c.get_path_to(up)
    c.focus_next = c.get_path_to(down)


# --- Public API ------------------------------------------------------------


## Focus entry `i` (wrapped) of the board: the slot cards in reading order, then the
## survival row, Refund all and Back. The hub's shoulders and d-pad left / right call
## this through MenuPad.on_tab with tab +- 1.
func set_tab(i: int) -> void:
    if _focusables.is_empty():
        tab = maxi(0, i)
        return
    tab = wrapi(i, 0, _focusables.size())
    if is_visible_in_tree():
        (_focusables[tab] as Control).grab_focus.call_deferred()
        Sfx.play("ui_move")
    _refresh()


# --- Actions ---------------------------------------------------------------


func _buy(i: int) -> void:
    if i < 0 or i >= _ids.size():
        return
    var sid: String = _ids[i]
    var s := Mastery.active_side(sid)
    if Mastery.buy(sid, s):
        _bought_at[i] = _time
        _toast("%s rank %d: %s" % [String(Mastery.side(sid, s)["name"]), Mastery.rank(sid, s), Mastery.effect_text(sid, s, Mastery.rank(sid, s))])
        Sfx.play("ui_confirm")
    else:
        _toast(_why_not(sid, s))
        Sfx.play("error")
    _refresh()


func _toggle(i: int) -> void:
    if i < 0 or i >= _ids.size():
        return
    var sid: String = _ids[i]
    Mastery.toggle(sid)
    var s := Mastery.active_side(sid)
    _toast("%s active" % String(Mastery.side(sid, s)["name"]))
    Sfx.play("ui_move")
    _refresh()


func _buy_survival() -> void:
    if Mastery.buy_survival():
        _bought_at[-1] = _time
        _toast("Last Breath rank %d: %d revive%s per run" % [Mastery.survival, Mastery.survival, "" if Mastery.survival == 1 else "s"])
        Sfx.play("ui_confirm")
    else:
        var c := Mastery.survival_next_cost()
        _toast("Last Breath is maxed" if c < 0 else _short_of(c))
        Sfx.play("error")
    _refresh()


func _on_refund() -> void:
    var back := Mastery.spent()
    if back <= 0:
        _toast("Nothing to refund yet")
        Sfx.play("error")
        _refresh()
        return
    if not _refund_armed:
        _refund_armed = true
        _refund_left = REFUND_SECS
        _refund.text = "Confirm: refund %d" % back
        _toast("Press again to refund %d Embers" % back, REFUND_SECS)
        Sfx.play("ui_move")
        _refresh()
        return
    var got := Mastery.refund_all()
    _disarm_refund()
    _toast("Refunded %d Embers" % got)
    Sfx.play("ui_back")
    _refresh()


func _disarm_refund() -> void:
    _refund_armed = false
    if _refund != null:
        _refund.text = "Refund all"


func _why_not(sid: String, s: String) -> String:
    var req := Mastery.requirement_text(sid, s)
    if req != "":
        return "%s first" % req
    var c := Mastery.next_cost(sid, s)
    if c < 0:
        return "%s is maxed. X switches side." % String(Mastery.side(sid, s)["name"])
    return _short_of(c)


func _short_of(cost: int) -> String:
    return "Needs %d Embers, you have %d" % [cost, Mastery.embers]


## Shows `text` as the toast for `secs`.
func _toast(text: String, secs: float = TOAST_SECS) -> void:
    _note = text
    _note_t = secs


# --- Text ------------------------------------------------------------------


func _on_focus(i: int) -> void:
    tab = i
    _refresh()


func _refresh() -> void:
    if _embers_label == null:
        return
    _embers_label.text = "%d Embers" % Mastery.embers
    _spent_label.text = "Spent %d of %d    Ranks %d / %d    Earned %d" % [
        Mastery.spent(), Mastery.total_cost(), Mastery.ranks_bought(), Mastery.ranks_total(), Mastery.earned]
    for c in _cards:
        c.queue_redraw()
    if _survival != null:
        _survival.queue_redraw()
    if _detail_box != null:
        _detail_box.queue_redraw()


## The detail panel's content for focus entry `i`: name, rank / max (pips), the effect
## line, the next rank's gain and its cost (-1: none), a status in place of the next rank
## (maxed, locked) and the dim secondary line.
func _detail(i: int) -> Dictionary:
    if i < _ids.size():
        var sid: String = _ids[i]
        var s := Mastery.active_side(sid)
        var d := Mastery.side(sid, s)
        var r := Mastery.rank(sid, s)
        var m := Mastery.max_rank(sid, s)
        var out := { "name": String(d["name"]).to_upper(), "rank": r, "max": m,
            "effect": _effect_line(sid, s), "next": "", "cost": -1, "status": "", "other": _other_line(sid, Mastery.other_side(s)) }
        var req := Mastery.requirement_text(sid, s)
        if req != "":
            out["status"] = "Locked. %s to unlock." % req
        elif r >= m:
            out["status"] = "Maxed."
        else:
            out["next"] = "Rank %d: %s" % [r + 1, Mastery.effect_text(sid, s, r + 1)]
            out["cost"] = Mastery.next_cost(sid, s)
        return out
    if i == _ids.size():
        var r := Mastery.survival
        var m := Mastery.survival_max()
        var hp := roundi(Mastery.REVIVE_FRACTION * 100.0)
        var now := "No revives yet." if r <= 0 else "Now %d revive%s per run." % [r, "" if r == 1 else "s"]
        var c := Mastery.survival_next_cost()
        return { "name": "LAST BREATH", "rank": r, "max": m,
            "effect": "When you would fall, stand back up at %d%% HP. %s" % [hp, now],
            "next": "" if c < 0 else "Rank %d: %d revive%s per run" % [r + 1, r + 1, "" if r == 0 else "s"], "cost": c,
            "status": "Maxed." if c < 0 else "", "other": "The first rank is cheap. The others are long-term goals." }
    if i == _ids.size() + 1:
        return { "name": "REFUND ALL", "effect": "Get back all %d spent Embers. Free, any time." % Mastery.spent(),
            "status": "Press twice to confirm.", "other": "Your chosen sides stay as they are." }
    return { "name": "BACK", "effect": "Return to the hub.",
        "other": "Embers come from cleared rooms, elites, new reactions, bosses and first kills." }


## What the side does: its plain description, then what the owned ranks give now.
func _effect_line(sid: String, s: String) -> String:
    var desc := String(Mastery.side(sid, s)["desc"]).strip_edges().trim_suffix(".")
    var r := Mastery.rank(sid, s)
    if r <= 0:
        return desc + "."
    return "%s. Now %s." % [desc, Mastery.effect_text(sid, s, r)]


func _other_line(sid: String, o: String) -> String:
    var d := Mastery.side(sid, o)
    var r := Mastery.rank(sid, o)
    var m := Mastery.max_rank(sid, o)
    var what := Mastery.effect_text(sid, o, r) if r > 0 else String(d["desc"]).strip_edges().trim_suffix(".").to_lower()
    return "Other side: %s, rank %d of %d: %s. X switches, free." % [String(d["name"]), r, m, what]


# --- Input -----------------------------------------------------------------


func _process(delta: float) -> void:
    if not is_visible_in_tree():
        return
    _time += delta
    if _note_t > 0.0:
        _note_t -= delta
        _detail_box.queue_redraw()
    if _refund_armed:
        _refund_left -= delta
        if _refund_left <= 0.0:
            _disarm_refund()
            _note_t = 0.0
            _refresh()
    var x_down := false
    for d in Input.get_connected_joypads():
        x_down = x_down or Input.is_joy_button_pressed(d, JOY_BUTTON_X)
    if x_down and not _x_was:
        _toggle_focused()
    _x_was = x_down
    for c in _cards:
        c.queue_redraw()
    _survival.queue_redraw()


func _toggle_focused() -> void:
    var at := _cards.find(get_viewport().gui_get_focus_owner())
    if at >= 0:
        _toggle(at)


func _input(event: InputEvent) -> void:
    if not is_visible_in_tree() or not event is InputEventKey:
        return
    var k := event as InputEventKey
    if not k.pressed or k.echo:
        return
    var at := _cards.find(get_viewport().gui_get_focus_owner())
    match k.physical_keycode:
        KEY_TAB, KEY_Q, KEY_X:
            if at >= 0:
                _toggle(at)
                get_viewport().set_input_as_handled()
        KEY_E:
            if at >= 0:
                _buy(at)
                get_viewport().set_input_as_handled()


## Mouse on a card: left-click the lit row buys, the dark row switches to it; right-click
## anywhere switches.
func _on_card_input(event: InputEvent, i: int) -> void:
    if not event is InputEventMouseButton:
        return
    var mb := event as InputEventMouseButton
    if not mb.pressed:
        return
    var c := _cards[i]
    if not c.has_focus():
        c.grab_focus()
    if mb.button_index == MOUSE_BUTTON_RIGHT:
        _toggle(i)
    elif mb.button_index == MOUSE_BUTTON_LEFT:
        var sid: String = _ids[i]
        var row := _row_at(mb.position)
        if row == "" or row == Mastery.active_side(sid):
            _buy(i)
        else:
            _toggle(i)
    c.accept_event()


func _row_at(p: Vector2) -> String:
    if p.y >= ROW_TOP and p.y < ROW_TOP + ROW_H + 2.0:
        return "a"
    if p.y >= ROW_TOP + ROW_H + 2.0 and p.y < ROW_TOP + 2.0 * ROW_H + 4.0:
        return "b"
    return ""


func _on_visibility_changed() -> void:
    if not visible:
        _disarm_refund()
        return
    _x_was = true   # an X still held from elsewhere must be released first
    _note_t = 0.0
    _refresh()
    if not _focusables.is_empty():
        (_focusables[clampi(tab, 0, _focusables.size() - 1)] as Control).grab_focus.call_deferred()


# --- Drawing ---------------------------------------------------------------


func _draw_card(i: int) -> void:
    if i >= _cards.size():
        return
    var b := _cards[i]
    var sid: String = _ids[i]
    var sl := Mastery.slot(sid)
    var r := Rect2(Vector2.ZERO, b.size)
    var focused := b.has_focus()
    var act := Mastery.active_side(sid)
    b.draw_rect(r, CARD_BG)
    var since := _time - float(_bought_at.get(i, -10.0))
    if since < 0.6:
        b.draw_rect(r, Color(LIT, 0.25 * (1.0 - since / 0.6)))
    b.draw_rect(r, UiTheme.FOCUS if focused else Color(UiTheme.BONE, 0.22), false, 3.0 if focused else 2.0)
    _str(b, Vector2(10, 20), String(sl["name"]).to_upper(), 20, UiTheme.BONE if focused else UiTheme.DIM, r.size.x - 20.0)
    for k in ["a", "b"]:
        _draw_row(b, sid, k, k == act, ROW_TOP + (0.0 if k == "a" else ROW_H + 4.0), r.size.x)


func _draw_row(b: Control, sid: String, s: String, lit: bool, y: float, w: float) -> void:
    var d := Mastery.side(sid, s)
    var row := Rect2(6.0, y, w - 12.0, ROW_H)
    var avail := Mastery.is_available(sid, s)
    var rk := Mastery.rank(sid, s)
    var m := Mastery.max_rank(sid, s)
    if lit:
        b.draw_rect(row, Color(LIT, 0.13))
        b.draw_rect(Rect2(row.position, Vector2(4.0, ROW_H)), LIT)
    var icon_rect := Rect2(row.position + Vector2(10.0, (ROW_H - ICON) / 2.0), Vector2(ICON, ICON))
    var tint := Color.WHITE if avail and (lit or rk > 0) else Color(0.5, 0.47, 0.5, 0.8)
    Art.draw_icon(b, Mastery.talent_icon(sid, s), icon_rect, tint)
    var name_col := LIT if lit else (UiTheme.BONE if avail else LOCKED)
    var right_w := 64.0
    _str(b, Vector2(row.position.x + 50.0, y + 19.0), String(d["name"]), 20, name_col, row.size.x - 50.0 - right_w)
    for p in m:
        var pip := Rect2(row.position.x + 51.0 + p * 15.0, y + 25.0, 11.0, 8.0)
        if p < rk:
            b.draw_rect(pip, OWNED if lit else Color(OWNED, 0.55))
        else:
            b.draw_rect(pip, Color(UiTheme.DIM, 0.9), false, 1.5)
    var tag := ""
    var tag_col := UiTheme.DIM
    if not avail:
        tag = "locked"
        tag_col = LOCKED
    elif rk >= m:
        tag = "MAX"
        tag_col = OWNED
    else:
        var c := Mastery.next_cost(sid, s)
        tag = str(c)
        tag_col = Mastery.EMBER_COLOR if Mastery.embers >= c else Color(Mastery.EMBER_COLOR, 0.45)
        if lit and Mastery.embers >= c:
            var pulse := 0.5 + 0.5 * sin(_time * 4.0)
            tag_col = Mastery.EMBER_COLOR.lerp(Color.WHITE, 0.35 * pulse)
    var tw := Art.FONT.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
    var tx := row.end.x - 8.0 - tw
    if tag != "MAX" and tag != "locked":
        Art.draw_icon(b, _ember_tex, Rect2(Vector2(tx - 20.0, y + 10.0), Vector2(18, 18)), Color(1, 1, 1, 0.9 if Mastery.embers >= int(tag) else 0.45))
    _str(b, Vector2(tx, y + 25.0), tag, 20, tag_col, 0.0)


func _draw_survival() -> void:
    var b := _survival
    var r := Rect2(Vector2.ZERO, b.size)
    var focused := b.has_focus()
    b.draw_rect(r, CARD_BG)
    var since := _time - float(_bought_at.get(-1, -10.0))
    if since < 0.6:
        b.draw_rect(r, Color(LIT, 0.25 * (1.0 - since / 0.6)))
    b.draw_rect(r, UiTheme.FOCUS if focused else Color(UiTheme.BONE, 0.22), false, 3.0 if focused else 2.0)
    var rk := Mastery.survival
    var m := Mastery.survival_max()
    Art.draw_icon(b, Mastery.survival_icon(), Rect2(Vector2(12, (r.size.y - 44.0) / 2.0), Vector2(44, 44)), Color.WHITE if rk > 0 else Color(0.75, 0.7, 0.72))
    _str(b, Vector2(68, 27), "SURVIVAL   LAST BREATH", 22, LIT if rk > 0 else UiTheme.BONE, 360.0)
    _str(b, Vector2(68, 54), "Each rank: stand back up once per run at %d%% HP." % roundi(Mastery.REVIVE_FRACTION * 100.0), Art.SMALL_SIZE + 1, UiTheme.DIM, 560.0, Art.FONT_BODY)
    for p in m:
        var pip := Rect2(Vector2(660.0 + p * 30.0, 22.0), Vector2(22, 22))
        if p < rk:
            b.draw_rect(pip, OWNED)
        else:
            b.draw_rect(pip, UiTheme.DIM, false, 2.0)
        _str(b, Vector2(660.0 + p * 30.0, 60.0), str(int(Mastery.SURVIVAL["costs"][p])), 20, OWNED if p < rk else Color(Mastery.EMBER_COLOR, 0.7), 0.0)
    var c := Mastery.survival_next_cost()
    var tag := "MAX" if c < 0 else str(c)
    var tw := Art.FONT.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
    var tx := r.size.x - 16.0 - tw
    if c >= 0:
        Art.draw_icon(b, _ember_tex, Rect2(Vector2(tx - 30.0, 20.0), Vector2(24, 24)), Color.WHITE if Mastery.embers >= c else Color(1, 1, 1, 0.45))
    _str(b, Vector2(tx, 40.0), tag, 24, OWNED if c < 0 else (Mastery.EMBER_COLOR if Mastery.embers >= c else Color(Mastery.EMBER_COLOR, 0.45)), 0.0)


## Text at `at` (baseline) in `font` (the pixel font by default), cut with "..." to
## `max_w` px when that is > 0. Returns the drawn width.
func _str(ci: CanvasItem, at: Vector2, text: String, px: int, col: Color, max_w: float, font: Font = null) -> float:
    var f: Font = font if font != null else Art.FONT
    var t := text
    if max_w > 0.0 and f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > max_w:
        while t.length() > 1 and f.get_string_size(t + "...", HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > max_w:
            t = t.substr(0, t.length() - 1)
        t = t.strip_edges() + "..."
    ci.draw_string(f, at, t, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)
    var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
    TextCheck.note(self, t, f, px, w, max_w)
    return w


## Body-font text at `at` (baseline) with every number ("+4%", "25", "4.5") in `num_col`.
## Returns the drawn width.
func _lit_numbers(ci: CanvasItem, at: Vector2, text: String, px: int, col: Color, num_col: Color) -> float:
    var f: Font = Art.FONT_BODY
    var x := at.x
    var from := 0
    for m in _num_re.search_all(text):
        var before := text.substr(from, m.get_start() - from)
        ci.draw_string(f, Vector2(x, at.y), before, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)
        x += f.get_string_size(before, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
        ci.draw_string(f, Vector2(x, at.y), m.get_string(), HORIZONTAL_ALIGNMENT_LEFT, -1, px, num_col)
        x += f.get_string_size(m.get_string(), HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
        from = m.get_end()
    var rest := text.substr(from)
    ci.draw_string(f, Vector2(x, at.y), rest, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)
    x += f.get_string_size(rest, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
    TextCheck.note(self, text, f, px, x - at.x, _detail_box.size.x - 32.0)
    return x - at.x


## The detail panel: name and pips, effect, next rank and cost, other side, toast.
func _draw_detail() -> void:
    var b := _detail_box
    var w := b.size.x
    b.draw_rect(Rect2(Vector2.ZERO, b.size), Color(CARD_BG, 0.7))
    b.draw_rect(Rect2(Vector2.ZERO, b.size), Color(UiTheme.BONE, 0.12), false, 1.0)
    var d := _detail(tab)
    var x := 16.0
    var name_w := _str(b, Vector2(x, 34.0), String(d["name"]), NAME_PX, LIT, w * 0.55)
    var m := int(d.get("max", 0))
    var rk := int(d.get("rank", 0))
    for p in m:
        var pip := Rect2(Vector2(x + name_w + 16.0 + p * 22.0, 14.0), Vector2(16, 16))
        if p < rk:
            b.draw_rect(pip, OWNED)
        else:
            b.draw_rect(pip, Color(UiTheme.DIM, 0.9), false, 2.0)
    _lit_numbers(b, Vector2(x, 64.0), String(d.get("effect", "")), Art.BODY_SIZE, UiTheme.BONE, OWNED)
    var next := String(d.get("next", ""))
    var cost := int(d.get("cost", -1))
    if next != "":
        var nx := x + _lit_numbers(b, Vector2(x, 90.0), next, Art.BODY_SIZE, Color(UiTheme.BONE, 0.85), Color.WHITE)
        if cost >= 0:
            var afford := Mastery.embers >= cost
            nx += 14.0
            Art.draw_icon(b, _ember_tex, Rect2(Vector2(nx, 72.0), Vector2(22, 22)), Color(1, 1, 1, 1.0 if afford else 0.5))
            nx += 26.0
            nx += _str(b, Vector2(nx, 92.0), str(cost), 28, Mastery.EMBER_COLOR if afford else Color(Mastery.EMBER_COLOR, 0.5), 0.0)
            if not afford:
                _str(b, Vector2(nx + 10.0, 90.0), "you have %d" % Mastery.embers, Art.SMALL_SIZE + 1, UiTheme.DIM, 0.0, Art.FONT_BODY)
    var status := String(d.get("status", ""))
    if status != "":
        var sc := OWNED if status == "Maxed." else (LOCKED.lightened(0.3) if status.begins_with("Locked") else UiTheme.DIM)
        _str(b, Vector2(x, 90.0), status, Art.BODY_SIZE, sc, w - 32.0, Art.FONT_BODY)
    _str(b, Vector2(x, 113.0), String(d.get("other", "")), Art.SMALL_SIZE, Color(UiTheme.DIM, 0.85), w - 32.0, Art.FONT_BODY)
    if _note_t > 0.0 and _note != "":
        var a := clampf(_note_t / 0.4, 0.0, 1.0)
        var px := Art.BODY_SIZE
        var tw := Art.FONT_BODY.get_string_size(_note, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
        var box := Rect2(Vector2(w - tw - 40.0, 8.0), Vector2(tw + 28.0, 34.0))
        b.draw_rect(box, Color(0.16, 0.11, 0.08, 0.96 * a))
        b.draw_rect(box, Color(LIT, 0.8 * a), false, 2.0)
        b.draw_string(Art.FONT_BODY, box.position + Vector2(14.0, 24.0), _note, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(UiTheme.BONE, a))
        TextCheck.note(self, _note, Art.FONT_BODY, px, tw, w * 0.6)


func _text(text: String, px: int, color: Color) -> Label:
    var l := UiTheme.label(text, px, color)
    l.add_theme_font_override("font", Art.FONT)
    l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    return l
