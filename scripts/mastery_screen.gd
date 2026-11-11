class_name MasteryScreen
extends PanelContainer
## The Shrine's talent tree (see Mastery and design/Talent tree.md): five branch columns of
## five nodes, joined top to bottom. A passive is one icon with rank pips; a choice node shows
## both options' icons, the picked one lit. Closed nodes are dark, open ones outlined, bought
## ones lit. The tree itself carries no words but the branch names and the next cost; the
## detail panel under it reads top-down for the focused node: name, what it does, then the
## next rank and its cost (or why it is closed). Then Last Breath, Refund all and Back.
##
## Controls. Pad: d-pad / stick moves through the tree, A buys (on a bought choice node A
## flips the pick), X flips a choice node, B closes. Keyboard: arrows move, Enter / Space / E
## buys, Tab / Q / X flips. Mouse: hover focuses; a click on an option of a choice node picks
## it (and buys the node if it is not bought yet); a click on a passive buys; right-click flips.
## The hub (and the fallback menu) poll the pad and close on B / Esc.

const CELL := Vector2(212, 60)
const GAP := Vector2(16, 12)
const ICON := 40.0
const LIT := Color(1.0, 0.82, 0.35)
const OWNED := Color(0.6, 1.0, 0.75)
const LOCKED := Color(0.45, 0.42, 0.45)
const CARD_BG := Color(0.06, 0.05, 0.07, 0.95)
const REFUND_SECS := 4.0
const TOAST_SECS := 2.6
const DETAIL_H := 104.0
const NAME_PX := 28

var on_close: Callable
var tab := 0                       # index into _focusables: tree nodes (row-major), survival, refund, back

var _cells: Array[Button] = []     # one per node, row-major (row 0: one per branch, ...)
var _ids: Array = []               # node id per cell
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
var _bought_at: Dictionary = {}    # cell index (-1 survival) -> _time of the last purchase
var _note := ""                    # the toast's text
var _note_t := 0.0                 # seconds the toast has left
var _cols := 5
var _rows := 5


func _init(p_on_close: Callable) -> void:
    on_close = p_on_close


func _ready() -> void:
    custom_minimum_size = Vector2(1160, 668)
    _ember_tex = Mastery.ember_icon()
    var brs: Array = Mastery.branches()
    _cols = brs.size()
    _rows = 0
    for br in brs:
        _rows = maxi(_rows, (br["nodes"] as Array).size())
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
    var hint := _text("A buy    X switch    B back", 20, UiTheme.DIM)
    UiTheme.to_body(hint, 16)
    hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    header.add_child(hint)

    # Branch names over the columns, in the branch colour.
    var names := HBoxContainer.new()
    names.add_theme_constant_override("separation", int(GAP.x))
    names.alignment = BoxContainer.ALIGNMENT_CENTER
    v.add_child(names)
    for br in brs:
        var l := _text(String(br["name"]).to_upper(), 22, Color(br["color"]))
        l.custom_minimum_size = Vector2(CELL.x, 26)
        l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        names.add_child(l)

    var center := CenterContainer.new()
    v.add_child(center)
    var grid := GridContainer.new()
    grid.columns = _cols
    grid.add_theme_constant_override("h_separation", int(GAP.x))
    grid.add_theme_constant_override("v_separation", int(GAP.y))
    center.add_child(grid)
    for row in _rows:
        for col in _cols:
            var ns: Array = brs[col]["nodes"]
            var i := _cells.size()
            _ids.append(String(ns[row]["id"]) if row < ns.size() else "")
            var b := _card_button(CELL)
            b.button_mask = 0   # clicks are read in _on_cell_input
            b.draw.connect(_draw_cell.bind(i))
            b.pressed.connect(_activate.bind(i))   # pad A (ui_accept on the focused node)
            b.gui_input.connect(_on_cell_input.bind(i))
            grid.add_child(b)
            _cells.append(b)

    _survival = _card_button(Vector2(0, 50))
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
    for c in _cells:
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


## Tree neighbours for the arrows and d-pad; focus_next / focus_previous are the node
## below / above, because MenuPad walks those for up and down.
func _link_focus() -> void:
    var n := _cells.size()
    for i in n:
        var c := _cells[i]
        var col := i % _cols
        var left: Control = _cells[i - 1] if col > 0 else c
        var right: Control = _cells[i + 1] if col < _cols - 1 and i + 1 < n else c
        var up: Control = _cells[i - _cols] if i >= _cols else c
        var down: Control = _cells[i + _cols] if i + _cols < n else _survival
        _link(c, left, right, up, down)
    var last_row: Control = _cells[(n - 1) / _cols * _cols + _cols / 2] if n > 0 else _survival
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


## Focus entry `i` (wrapped): the tree's nodes in reading order, then the survival row,
## Refund all and Back. The hub's shoulders and d-pad left / right call this through
## MenuPad.on_tab with tab +- 1.
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


## Buy the focused node's next rank; a bought choice node flips instead.
func _activate(i: int) -> void:
    if i < 0 or i >= _ids.size() or String(_ids[i]) == "":
        return
    var id: String = _ids[i]
    if Mastery.is_choice(id) and Mastery.is_full(id):
        _flip(i)
        return
    _buy(i)


func _buy(i: int) -> void:
    var id: String = _ids[i]
    if Mastery.buy(id):
        _bought_at[i] = _time
        if Mastery.is_choice(id):
            _toast("%s learned" % String(Mastery.option(id, Mastery.pick(id))["name"]))
        else:
            _toast("%s %d: %s" % [String(Mastery.node(id)["name"]), Mastery.rank(id), Mastery.effect_text(id, Mastery.rank(id))])
        Sfx.play("ui_confirm")
    else:
        _toast(_why_not(id))
        Sfx.play("error")
    _refresh()


func _flip(i: int) -> void:
    if i < 0 or i >= _ids.size():
        return
    var id: String = _ids[i]
    if not Mastery.is_choice(id):
        return
    _set_pick(i, Mastery.other_side(Mastery.pick(id)))


func _set_pick(i: int, s: String) -> void:
    var id: String = _ids[i]
    if Mastery.pick(id) == s:
        return
    Mastery.set_pick(id, s)
    _toast("%s chosen" % String(Mastery.option(id, s)["name"]))
    Sfx.play("ui_move")
    _refresh()


func _buy_survival() -> void:
    if Mastery.buy_survival():
        _bought_at[-1] = _time
        _toast("Last Breath %d: %d revive%s per run" % [Mastery.survival, Mastery.survival, "" if Mastery.survival == 1 else "s"])
        Sfx.play("ui_confirm")
    else:
        var c := Mastery.survival_next_cost()
        _toast("Last Breath is full" if c < 0 else _short_of(c))
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


func _why_not(id: String) -> String:
    var req := Mastery.requirement_text(id)
    if req != "":
        return req
    var c := Mastery.next_cost(id)
    if c < 0:
        return "Already full"
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
    _spent_label.text = "Spent %d of %d" % [Mastery.spent(), Mastery.total_cost()]
    for c in _cells:
        c.queue_redraw()
    if _survival != null:
        _survival.queue_redraw()
    if _detail_box != null:
        _detail_box.queue_redraw()


## The detail panel's content for focus entry `i`: name, rank / max (pips), the effect
## line, the next rank and its cost (-1: none), a status in place of the next rank, and
## the dim second line.
func _detail(i: int) -> Dictionary:
    if i < _ids.size():
        var id: String = _ids[i]
        if id == "":
            return { "name": "" }
        var r := Mastery.rank(id)
        var m := Mastery.max_rank(id)
        var out := { "rank": r, "max": m, "next": "", "cost": -1, "status": "", "other": "" }
        if Mastery.is_choice(id):
            var s := Mastery.pick(id)
            var o := Mastery.option(id, s)
            var other := Mastery.option(id, Mastery.other_side(s))
            out["name"] = String(o["name"]).to_upper()
            out["max"] = 0
            out["effect"] = String(o["desc"])
            out["other"] = "Or %s: %s" % [String(other["name"]), String(other["desc"])]
            if r <= 0:
                out["next"] = "Learn the choice:"
                out["cost"] = Mastery.next_cost(id)
        else:
            var d := Mastery.node(id)
            out["name"] = String(d["name"]).to_upper()
            out["effect"] = String(d["desc"]) if r <= 0 else "%s Now %s." % [String(d["desc"]), Mastery.effect_text(id, r)]
            if r < m:
                out["next"] = "Rank %d: %s" % [r + 1, Mastery.effect_text(id, r + 1)]
                out["cost"] = Mastery.next_cost(id)
        var req := Mastery.requirement_text(id)
        if req != "":
            out["next"] = ""
            out["cost"] = -1
            out["status"] = "Closed. %s." % req
        elif r >= m:
            out["status"] = "Learned." if Mastery.is_choice(id) else "Full."
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
            "status": "Full." if c < 0 else "", "other": "The first rank is cheap. The others are long-term goals." }
    if i == _ids.size() + 1:
        return { "name": "REFUND ALL", "effect": "Get back all %d spent Embers. Free, any time." % Mastery.spent(),
            "status": "Press twice to confirm.", "other": "Your choices stay as they are." }
    return { "name": "BACK", "effect": "Return to the Hollow.",
        "other": "Embers come from cleared rooms, elites, new reactions, bosses and first kills." }


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
        _flip_focused()
    _x_was = x_down
    for c in _cells:
        c.queue_redraw()
    _survival.queue_redraw()


func _flip_focused() -> void:
    var at := _cells.find(get_viewport().gui_get_focus_owner())
    if at >= 0:
        _flip(at)


func _input(event: InputEvent) -> void:
    if not is_visible_in_tree() or not event is InputEventKey:
        return
    var k := event as InputEventKey
    if not k.pressed or k.echo:
        return
    var at := _cells.find(get_viewport().gui_get_focus_owner())
    if at < 0:
        return
    match k.physical_keycode:
        KEY_TAB, KEY_Q, KEY_X:
            _flip(at)
            get_viewport().set_input_as_handled()
        KEY_E, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
            _activate(at)
            get_viewport().set_input_as_handled()


## Mouse on a node: on a choice node a click picks the option under the pointer (and buys
## the node when it is not bought); on a passive it buys. Right-click flips.
func _on_cell_input(event: InputEvent, i: int) -> void:
    if not event is InputEventMouseButton:
        return
    var mb := event as InputEventMouseButton
    if not mb.pressed:
        return
    var c := _cells[i]
    if not c.has_focus():
        c.grab_focus()
    var id: String = _ids[i]
    if id == "":
        return
    if mb.button_index == MOUSE_BUTTON_RIGHT:
        _flip(i)
    elif mb.button_index == MOUSE_BUTTON_LEFT:
        if Mastery.is_choice(id):
            var s := "a" if mb.position.x < c.size.x / 2.0 else "b"
            _set_pick(i, s)
            if Mastery.rank(id) <= 0:
                _buy(i)
        else:
            _buy(i)
    c.accept_event()


func _on_visibility_changed() -> void:
    if not visible:
        _disarm_refund()
        return
    _x_was = true   # an X still held from elsewhere must be released first
    _note_t = 0.0
    var back := Mastery.take_rebuild_note()
    if back > 0:
        _toast("Your talents were rebuilt. %d Embers refunded." % back, 8.0)
    _refresh()
    if not _focusables.is_empty():
        (_focusables[clampi(tab, 0, _focusables.size() - 1)] as Control).grab_focus.call_deferred()


# --- Drawing ---------------------------------------------------------------


func _branch_color(i: int) -> Color:
    return Color(Mastery.branches()[i % _cols]["color"])


func _draw_cell(i: int) -> void:
    if i >= _cells.size():
        return
    var b := _cells[i]
    var id: String = _ids[i]
    if id == "":
        return
    var r := Rect2(Vector2.ZERO, b.size)
    var focused := b.has_focus()
    var open := Mastery.is_open(id)
    var rk := Mastery.rank(id)
    var full := Mastery.is_full(id)
    var bc := _branch_color(i)
    var cx := r.size.x / 2.0
    # The connector up to the node above: lit once the path through it is open.
    if i >= _cols:
        b.draw_line(Vector2(cx, 0.0), Vector2(cx, -GAP.y), Color(bc, 0.9) if open else Color(LOCKED, 0.5), 4.0 if open else 2.0)
    var choice := Mastery.is_choice(id)
    var w := ICON * 2.0 + 44.0 if choice else ICON + 20.0
    var box := Rect2(Vector2(cx - w / 2.0, 4.0), Vector2(w, r.size.y - 8.0))
    b.draw_rect(box, CARD_BG)
    var since := _time - float(_bought_at.get(i, -10.0))
    if since < 0.6:
        b.draw_rect(box, Color(LIT, 0.35 * (1.0 - since / 0.6)))
    if rk > 0:
        b.draw_rect(box, Color(bc, 0.16))
    var edge := Color(LOCKED, 0.5)
    var ew := 2.0
    if full:
        edge = bc
        ew = 3.0
    elif open:
        edge = Color(UiTheme.BONE, 0.7)
    if focused:
        edge = UiTheme.FOCUS
        ew = 3.0
    b.draw_rect(box, edge, false, ew)
    var iy := box.position.y + 4.0
    if choice:
        var pk := Mastery.pick(id)
        for k in 2:
            var s := "a" if k == 0 else "b"
            var ir := Rect2(Vector2(box.position.x + 10.0 + k * (ICON + 24.0), iy), Vector2(ICON, ICON))
            var lit_opt := s == pk
            var tint := Color.WHITE
            if not open:
                tint = Color(0.45, 0.42, 0.45, 0.5)
            elif rk <= 0:
                tint = Color(1, 1, 1, 0.75) if lit_opt else Color(0.6, 0.57, 0.6, 0.5)
            elif not lit_opt:
                tint = Color(0.55, 0.52, 0.55, 0.45)
            Art.draw_icon(b, Mastery.node_icon(id, s), ir, tint)
            if lit_opt and rk > 0:
                b.draw_rect(ir.grow(2.0), bc, false, 2.0)
        # The split between the two options.
        b.draw_line(Vector2(cx, box.position.y + 8.0), Vector2(cx, box.end.y - 8.0), Color(UiTheme.BONE, 0.25), 1.0)
    else:
        var ir := Rect2(Vector2(cx - ICON / 2.0, iy), Vector2(ICON, ICON))
        var tint := Color.WHITE if open else Color(0.45, 0.42, 0.45, 0.5)
        if open and rk <= 0:
            tint = Color(1, 1, 1, 0.75)
        Art.draw_icon(b, Mastery.node_icon(id), ir, tint)
        var m := Mastery.max_rank(id)
        for p in m:
            var pip := Rect2(Vector2(cx - m * 7.0 + p * 14.0 + 1.0, box.end.y - 8.0), Vector2(12.0, 5.0))
            if p < rk:
                b.draw_rect(pip, OWNED)
            else:
                b.draw_rect(pip, Color(UiTheme.DIM, 0.9), false, 1.0)
    # The next cost, right of the node, while it can be bought.
    if open and not full:
        var c := Mastery.next_cost(id)
        var afford := Mastery.embers >= c
        var tag := str(c)
        var col := Mastery.EMBER_COLOR if afford else Color(Mastery.EMBER_COLOR, 0.45)
        if afford and focused:
            col = Mastery.EMBER_COLOR.lerp(Color.WHITE, 0.35 * (0.5 + 0.5 * sin(_time * 4.0)))
        var tx := box.end.x + 8.0
        Art.draw_icon(b, _ember_tex, Rect2(Vector2(tx, r.size.y / 2.0 - 10.0), Vector2(18, 18)), Color(1, 1, 1, 0.9 if afford else 0.45))
        _str(b, Vector2(tx + 20.0, r.size.y / 2.0 + 6.0), tag, 20, col, 0.0)


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
    Art.draw_icon(b, Mastery.survival_icon(), Rect2(Vector2(12, (r.size.y - 36.0) / 2.0), Vector2(36, 36)), Color.WHITE if rk > 0 else Color(0.75, 0.7, 0.72))
    _str(b, Vector2(60, 32), "LAST BREATH", 22, LIT if rk > 0 else UiTheme.BONE, 260.0)
    for p in m:
        var pip := Rect2(Vector2(300.0 + p * 30.0, 15.0), Vector2(20, 20))
        if p < rk:
            b.draw_rect(pip, OWNED)
        else:
            b.draw_rect(pip, UiTheme.DIM, false, 2.0)
    var c := Mastery.survival_next_cost()
    if c >= 0:
        var tw := Art.FONT.get_string_size(str(c), HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
        var tx := r.size.x - 16.0 - tw
        Art.draw_icon(b, _ember_tex, Rect2(Vector2(tx - 26.0, 14.0), Vector2(22, 22)), Color.WHITE if Mastery.embers >= c else Color(1, 1, 1, 0.45))
        _str(b, Vector2(tx, 33.0), str(c), 22, Mastery.EMBER_COLOR if Mastery.embers >= c else Color(Mastery.EMBER_COLOR, 0.45), 0.0)


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


## The detail panel: name and pips, effect, next rank and cost (or status), second line, toast.
func _draw_detail() -> void:
    var b := _detail_box
    var w := b.size.x
    b.draw_rect(Rect2(Vector2.ZERO, b.size), Color(CARD_BG, 0.7))
    b.draw_rect(Rect2(Vector2.ZERO, b.size), Color(UiTheme.BONE, 0.12), false, 1.0)
    var d := _detail(tab)
    if String(d.get("name", "")) == "":
        return
    var x := 16.0
    var name_w := _str(b, Vector2(x, 30.0), String(d["name"]), NAME_PX, LIT, w * 0.55)
    var m := int(d.get("max", 0))
    var rk := int(d.get("rank", 0))
    for p in m:
        var pip := Rect2(Vector2(x + name_w + 16.0 + p * 22.0, 12.0), Vector2(16, 16))
        if p < rk:
            b.draw_rect(pip, OWNED)
        else:
            b.draw_rect(pip, Color(UiTheme.DIM, 0.9), false, 2.0)
    _lit_numbers(b, Vector2(x, 58.0), String(d.get("effect", "")), Art.BODY_SIZE, UiTheme.BONE, OWNED)
    var next := String(d.get("next", ""))
    var cost := int(d.get("cost", -1))
    var y2 := 84.0
    var after := x
    if next != "":
        after = x + _lit_numbers(b, Vector2(x, y2), next, Art.BODY_SIZE, Color(UiTheme.BONE, 0.85), Color.WHITE)
        if cost >= 0:
            var afford := Mastery.embers >= cost
            after += 12.0
            Art.draw_icon(b, _ember_tex, Rect2(Vector2(after, y2 - 18.0), Vector2(22, 22)), Color(1, 1, 1, 1.0 if afford else 0.5))
            after += 26.0
            after += _str(b, Vector2(after, y2 + 2.0), str(cost), 26, Mastery.EMBER_COLOR if afford else Color(Mastery.EMBER_COLOR, 0.5), 0.0)
    var status := String(d.get("status", ""))
    if status != "":
        var sc := OWNED if status in ["Full.", "Learned."] else (LOCKED.lightened(0.3) if status.begins_with("Closed") else UiTheme.DIM)
        after = x + _str(b, Vector2(x, y2), status, Art.BODY_SIZE, sc, w * 0.4, Art.FONT_BODY)
    var other := String(d.get("other", ""))
    if other != "":
        var ox := maxf(after + 28.0, w * 0.42)
        _str(b, Vector2(ox, y2), other, Art.SMALL_SIZE, Color(UiTheme.DIM, 0.95), w - ox - 16.0, Art.FONT_BODY)
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
