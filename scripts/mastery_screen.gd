class_name MasteryScreen
extends PanelContainer
## The Shrine's talent board (see Mastery): eleven slot cards in a grid, each showing both
## sides with the active one lit, its rank pips and the next rank's cost, then the
## survival row (Last Breath), the Embers in the header and a free refund-all with a
## confirmation.
##
## Controls. Pad: d-pad / stick moves between cards (left / right through MenuPad.on_tab,
## which calls set_tab), A buys the next rank of the lit side, X switches side, B closes.
## Keyboard: arrows move, Enter / Space / E buys, Tab / Q / X switches side. Mouse: hover
## focuses, a click on the lit row buys, a click on the dark row (or a right-click)
## switches side. The hub (and the fallback menu) poll the pad and close on B / Esc.

const COLS := 4
const CARD_SIZE := Vector2(272, 128)
const ROW_H := 38.0
const ROW_TOP := 26.0
const ICON := 32.0
const LIT := Color(1.0, 0.82, 0.35)
const OWNED := Color(0.6, 1.0, 0.75)
const LOCKED := Color(0.45, 0.42, 0.45)
const CARD_BG := Color(0.06, 0.05, 0.07, 0.95)
const REFUND_SECS := 4.0

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
var _lines: Array[Label] = []
var _ember_tex: Texture2D
var _refund_armed := false
var _refund_left := 0.0
var _time := 0.0
var _x_was := false
var _bought_at: Dictionary = {}    # card index (-1 survival) -> _time of the last purchase
var _note := ""                    # one-off message for the third detail line


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
    _spent_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    header.add_child(_spent_label)
    var hint := _text("A buy   X switch side   B back", 20, UiTheme.DIM)
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

    var detail := VBoxContainer.new()
    detail.add_theme_constant_override("separation", 0)
    v.add_child(detail)
    for k in 3:
        var l := _text("", 20, UiTheme.BONE if k == 0 else UiTheme.DIM)
        l.clip_text = true
        l.custom_minimum_size = Vector2(1100, 0)
        detail.add_child(l)
        _lines.append(l)

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
        _note = "%s rank %d: %s" % [String(Mastery.side(sid, s)["name"]), Mastery.rank(sid, s), Mastery.effect_text(sid, s, Mastery.rank(sid, s))]
        Sfx.play("ui_confirm")
    else:
        _note = _why_not(sid, s)
        Sfx.play("error")
    _refresh()


func _toggle(i: int) -> void:
    if i < 0 or i >= _ids.size():
        return
    var sid: String = _ids[i]
    Mastery.toggle(sid)
    var s := Mastery.active_side(sid)
    _note = "%s is now active." % String(Mastery.side(sid, s)["name"])
    Sfx.play("ui_move")
    _refresh()


func _buy_survival() -> void:
    if Mastery.buy_survival():
        _bought_at[-1] = _time
        _note = "Last Breath rank %d: %d revive%s per run." % [Mastery.survival, Mastery.survival, "" if Mastery.survival == 1 else "s"]
        Sfx.play("ui_confirm")
    else:
        var c := Mastery.survival_next_cost()
        _note = "Last Breath is maxed." if c < 0 else "Not enough Embers: %d needed, %d held." % [c, Mastery.embers]
        Sfx.play("error")
    _refresh()


func _on_refund() -> void:
    var back := Mastery.spent()
    if back <= 0:
        _note = "Nothing to refund yet."
        Sfx.play("error")
        _refresh()
        return
    if not _refund_armed:
        _refund_armed = true
        _refund_left = REFUND_SECS
        _refund.text = "Confirm: refund %d" % back
        _note = "Press Refund again to get all %d Embers back. Your chosen sides stay." % back
        Sfx.play("ui_move")
        _refresh()
        return
    var got := Mastery.refund_all()
    _disarm_refund()
    _note = "Refunded %d Embers. Spend them again any way you like." % got
    Sfx.play("ui_back")
    _refresh()


func _disarm_refund() -> void:
    _refund_armed = false
    if _refund != null:
        _refund.text = "Refund all"


func _why_not(sid: String, s: String) -> String:
    var req := Mastery.requirement_text(sid, s)
    if req != "":
        return "%s: %s. The Trophy Wall shows how to unlock it." % [String(Mastery.side(sid, s)["name"]), req]
    var c := Mastery.next_cost(sid, s)
    if c < 0:
        return "%s is maxed. Switch side to invest in the other one." % String(Mastery.side(sid, s)["name"])
    return "Not enough Embers: %d needed, %d held." % [c, Mastery.embers]


# --- Text ------------------------------------------------------------------


func _on_focus(i: int) -> void:
    tab = i
    _note = ""
    _refresh()


func _refresh() -> void:
    if _embers_label == null:
        return
    _embers_label.text = "%d Embers" % Mastery.embers
    _spent_label.text = "spent %d of %d    ranks %d / %d    earned %d in all" % [
        Mastery.spent(), Mastery.total_cost(), Mastery.ranks_bought(), Mastery.ranks_total(), Mastery.earned]
    var texts := _detail(tab)
    for k in _lines.size():
        _lines[k].text = String(texts[k]) if k < texts.size() else ""
    if _note != "":
        _lines[2].text = _note
    for c in _cards:
        c.queue_redraw()
    if _survival != null:
        _survival.queue_redraw()


## Three lines for focus entry `i`: the lit side, the other side, what to press.
func _detail(i: int) -> Array:
    if i < _ids.size():
        var sid: String = _ids[i]
        var s := Mastery.active_side(sid)
        var o := Mastery.other_side(s)
        return [_side_line(sid, s, true), _side_line(sid, o, false),
            "A / Enter / click the lit row: buy the next rank.    X / Tab / right-click: switch side, free."]
    if i == _ids.size():
        var r := Mastery.survival
        var m := Mastery.survival_max()
        var now := "no revives yet" if r <= 0 else "%d revive%s per run at %d%% max HP" % [r, "" if r == 1 else "s", roundi(Mastery.REVIVE_FRACTION * 100.0)]
        var c := Mastery.survival_next_cost()
        var next := "Maxed." if c < 0 else "Next rank: one more revive for %d Embers." % c
        return ["LAST BREATH  rank %d / %d: %s. %s" % [r, m, now, String(Mastery.SURVIVAL["desc"])], next,
            "The first charge is cheap; the others are a long-term goal. Press A to buy."]
    if i == _ids.size() + 1:
        return ["Refund every rank and the survival track: %d Embers come back. Free, any time." % Mastery.spent(),
            "Your chosen sides stay as they are.", "Press twice to confirm."]
    return ["Back to the hub.", "Embers come from rooms cleared, elites, new reactions, bosses and first-kill bounties.", ""]


func _side_line(sid: String, s: String, lit: bool) -> String:
    var d := Mastery.side(sid, s)
    var r := Mastery.rank(sid, s)
    var m := Mastery.max_rank(sid, s)
    var head := "%s %s  rank %d / %d" % ["ACTIVE" if lit else "Other side:", String(d["name"]).to_upper() if lit else String(d["name"]), r, m]
    var now := Mastery.effect_text(sid, s, r) if r > 0 else String(d["desc"])
    var tail := ""
    var req := Mastery.requirement_text(sid, s)
    if req != "":
        tail = "   %s." % req
    elif r < m:
        tail = "   Next: %s for %d Embers." % [Mastery.effect_text(sid, s, r + 1), Mastery.next_cost(sid, s)]
    else:
        tail = "   Maxed."
    return "%s: %s.%s" % [head, now, tail]


# --- Input -----------------------------------------------------------------


func _process(delta: float) -> void:
    if not is_visible_in_tree():
        return
    _time += delta
    if _refund_armed:
        _refund_left -= delta
        if _refund_left <= 0.0:
            _disarm_refund()
            _note = ""
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
    _note = ""
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
    var rk := Mastery.rank(sid, act)
    var line := Mastery.effect_text(sid, act, rk) if rk > 0 else "Not learned yet"
    _str(b, Vector2(10, r.size.y - 6.0), line, 20, OWNED if rk > 0 else UiTheme.DIM, r.size.x - 20.0)


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
    _str(b, Vector2(68, 52), "Each rank: stand back up once per run at %d%% max HP." % roundi(Mastery.REVIVE_FRACTION * 100.0), 20, UiTheme.DIM, 560.0)
    for p in m:
        var pip := Rect2(Vector2(660.0 + p * 30.0, 22.0), Vector2(22, 22))
        if p < rk:
            b.draw_rect(pip, OWNED)
        else:
            b.draw_rect(pip, UiTheme.DIM, false, 2.0)
        _str(b, Vector2(660.0 + p * 30.0, 60.0), str(int(Mastery.SURVIVAL["costs"][p])), 20, OWNED if p < rk else UiTheme.DIM, 0.0)
    var c := Mastery.survival_next_cost()
    var tag := "MAX" if c < 0 else str(c)
    var tw := Art.FONT.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
    var tx := r.size.x - 16.0 - tw
    if c >= 0:
        Art.draw_icon(b, _ember_tex, Rect2(Vector2(tx - 30.0, 20.0), Vector2(24, 24)), Color.WHITE if Mastery.embers >= c else Color(1, 1, 1, 0.45))
    _str(b, Vector2(tx, 40.0), tag, 24, OWNED if c < 0 else (Mastery.EMBER_COLOR if Mastery.embers >= c else Color(Mastery.EMBER_COLOR, 0.45)), 0.0)


## Pixel-font text at `at` (baseline), cut with "..." to `max_w` px when that is > 0.
func _str(ci: CanvasItem, at: Vector2, text: String, px: int, col: Color, max_w: float) -> void:
    var t := text
    if max_w > 0.0 and Art.FONT.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > max_w:
        while t.length() > 1 and Art.FONT.get_string_size(t + "...", HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > max_w:
            t = t.substr(0, t.length() - 1)
        t = t.strip_edges() + "..."
    ci.draw_string(Art.FONT, at, t, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)


func _text(text: String, px: int, color: Color) -> Label:
    var l := UiTheme.label(text, px, color)
    l.add_theme_font_override("font", Art.FONT)
    l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    return l
