class_name ClassSelect
extends Control
## Class picker shown by Play: one card per class in a grid. Locked classes are dimmed
## and say how to earn them. Arrows / d-pad / left stick move, Enter / A picks, Esc / B
## backs out, and the mouse works too. `on_pick` receives the chosen class id.

const CARD_SIZE := Vector2(238, 142)
const CARD_GAP := 10
const PER_ROW := 5
const GRACE := 0.25            # seconds before input counts, so the Play press does not pick
const REPEAT_DELAY := 0.4
const REPEAT_RATE := 0.12
const LOCKED_COLOR := Color(0.40, 0.38, 0.38)

var _on_pick: Callable
var _on_cancel: Callable
var _classes: Array = []
var _cards: Array[Button] = []
var _desc: Label
var _armed_in := GRACE
var _was: Dictionary = {}
var _held: Dictionary = {}


func _init(on_pick: Callable, on_cancel: Callable) -> void:
    _on_pick = on_pick
    _on_cancel = on_cancel


func _ready() -> void:
    set_anchors_preset(Control.PRESET_FULL_RECT)
    theme = UiTheme.make()
    texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    var dim := ColorRect.new()
    dim.color = Color(0, 0, 0, 0.55)
    dim.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(dim)
    var center := CenterContainer.new()
    center.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(center)
    var v := VBoxContainer.new()
    v.add_theme_constant_override("separation", 10)
    center.add_child(v)
    v.add_child(UiTheme.label("CHOOSE YOUR CLASS", 36))
    var rows := VBoxContainer.new()
    rows.add_theme_constant_override("separation", CARD_GAP)
    v.add_child(rows)
    _desc = UiTheme.label("", 20, UiTheme.BONE)
    _desc.custom_minimum_size = Vector2(PER_ROW * CARD_SIZE.x + (PER_ROW - 1) * CARD_GAP, 50)
    _desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    v.add_child(_desc)
    v.add_child(UiTheme.label("Arrows / D-pad  move     Enter / A  choose     Esc / B  back", 20, UiTheme.DIM))

    _classes = Classes.all()
    var row: HBoxContainer = null
    for i in _classes.size():
        if i % PER_ROW == 0:
            row = HBoxContainer.new()
            row.alignment = BoxContainer.ALIGNMENT_CENTER
            row.add_theme_constant_override("separation", CARD_GAP)
            rows.add_child(row)
        var card := _make_card(i, _classes[i])
        row.add_child(card)
        _cards.append(card)
    for i in _cards.size():
        var card := _cards[i]
        card.focus_neighbor_left = card.get_path_to(_cards[_neighbour(i, Vector2i.LEFT)])
        card.focus_neighbor_right = card.get_path_to(_cards[_neighbour(i, Vector2i.RIGHT)])
        card.focus_neighbor_top = card.get_path_to(_cards[_neighbour(i, Vector2i.UP)])
        card.focus_neighbor_bottom = card.get_path_to(_cards[_neighbour(i, Vector2i.DOWN)])
        card.focus_previous = card.focus_neighbor_left
        card.focus_next = card.focus_neighbor_right

    var start := 0
    for i in _classes.size():
        if _classes[i]["id"] == Progress.chosen_class and Classes.is_unlocked(String(_classes[i]["id"])):
            start = i
    _cards[start].grab_focus()
    _show_info(start)


func _make_card(i: int, c: Dictionary) -> Button:
    var open := Classes.is_unlocked(String(c["id"]))
    var tint: Color = c["tint"]
    var b := Button.new()
    b.custom_minimum_size = CARD_SIZE
    b.focus_mode = Control.FOCUS_ALL
    var edge := tint.darkened(0.45) if open else Color(0.22, 0.20, 0.20)
    b.add_theme_stylebox_override("normal", _card_box(Color(0.10, 0.08, 0.10, 0.96), edge, 2))
    b.add_theme_stylebox_override("hover", _card_box(Color(0.15, 0.12, 0.14, 0.97), UiTheme.BONE, 2))
    b.add_theme_stylebox_override("focus", _card_box(Color(0.15, 0.12, 0.14, 0.97), UiTheme.FOCUS, 4))
    b.add_theme_stylebox_override("pressed", _card_box(Color(0.25, 0.12, 0.10, 0.97), UiTheme.FOCUS, 4))
    b.pressed.connect(_choose.bind(i))
    b.focus_entered.connect(_show_info.bind(i))
    b.mouse_entered.connect(func():
        if not b.has_focus():
            b.grab_focus())
    var box := VBoxContainer.new()
    box.set_anchors_preset(Control.PRESET_FULL_RECT)
    box.offset_left = 10
    box.offset_right = -10
    box.offset_top = 6
    box.offset_bottom = -6
    box.add_theme_constant_override("separation", 0)
    box.mouse_filter = Control.MOUSE_FILTER_IGNORE
    b.add_child(box)
    var title_col: Color = tint if c["element"] != Element.Kind.NONE else UiTheme.BONE
    # Title row: the class icon (a 32 px spell tile, greyed while locked) and the name.
    var head := HBoxContainer.new()
    head.alignment = BoxContainer.ALIGNMENT_CENTER
    head.add_theme_constant_override("separation", 8)
    head.mouse_filter = Control.MOUSE_FILTER_IGNORE
    box.add_child(head)
    var icon := TextureRect.new()
    icon.texture = Art.icon_pixel(Classes.icon(c), 32) if Settings.flag("post_fx") else Classes.icon(c)
    icon.custom_minimum_size = Vector2(32, 32)
    icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
    icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
    if not open:
        icon.modulate = Color(0.32, 0.3, 0.32)
    head.add_child(icon)
    var title := UiTheme.label(String(c["name"]), 28, title_col if open else LOCKED_COLOR)
    title.mouse_filter = Control.MOUSE_FILTER_IGNORE
    head.add_child(title)
    if not open:
        box.add_child(_card_label("Locked", 20, UiTheme.DIM))
        var how := _card_label(Classes.unlock_text(c), 20, UiTheme.DIM)
        how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        how.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
        box.add_child(how)
        return b
    var gun_id := String(c["start_gun"])
    var gun_text := "Pick of two guns" if c["id"] == "vagrant" or gun_id == "" else Guns.make(gun_id).display_name
    box.add_child(_card_label(gun_text, 20, UiTheme.BONE))
    var item_id := String(c["start_item"])
    var item_text := "No gear"
    if item_id != "":
        item_text = String(Items.get_item(item_id).get("name", item_id))
    box.add_child(_card_label(item_text, 20, UiTheme.BONE))
    box.add_child(_card_label(_short_affinity(c), 20, tint if c["element"] != Element.Kind.NONE else UiTheme.DIM))
    box.add_child(_card_label(Classes.quirk_text(c), 20, UiTheme.DIM))
    return b


## The affinity squeezed to fit a card: "Fire +20% pot +10% dmg".
func _short_affinity(c: Dictionary) -> String:
    if c["element"] == Element.Kind.NONE:
        return "No element"
    return "%s +%d%% pot +%d%% dmg" % [Element.NAMES[c["element"]],
        roundi(Classes.AFFINITY_POTENCY * 100.0), roundi(Classes.AFFINITY_DMG * 100.0)]


func _card_label(text: String, size: int, color: Color) -> Label:
    var l := UiTheme.label(text, size, color)
    l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    l.custom_minimum_size = Vector2(CARD_SIZE.x - 20, 0)
    l.mouse_filter = Control.MOUSE_FILTER_IGNORE
    return l


func _card_box(fill: Color, border: Color, width: int) -> StyleBoxFlat:
    var s := StyleBoxFlat.new()
    s.bg_color = fill
    s.border_color = border
    s.set_border_width_all(width)
    s.set_corner_radius_all(4)
    s.set_content_margin_all(4)
    return s


## The bottom line: flavour for the focused class, and the full affinity or unlock rule.
func _show_info(i: int) -> void:
    if _desc == null or i < 0 or i >= _classes.size():
        return
    var c: Dictionary = _classes[i]
    var flavour := String(c["desc"]).replace("\n", "  ")
    if Classes.is_unlocked(String(c["id"])):
        _desc.text = "%s\n%s" % [flavour, Classes.affinity_text(c)]
    else:
        _desc.text = "%s\nLocked: %s" % [flavour, Classes.unlock_text(c)]


## Grid neighbour of card `i` in direction `dir`, wrapping at the edges.
func _neighbour(i: int, dir: Vector2i) -> int:
    var count := _cards.size()
    if count <= 0:
        return 0
    if dir.x != 0:
        return wrapi(i + dir.x, 0, count)
    var col := i % PER_ROW
    var rows := ceili(float(count) / PER_ROW)
    var r := wrapi(floori(float(i) / PER_ROW) + dir.y, 0, rows)
    return mini(r * PER_ROW + col, count - 1)


func _focused_index() -> int:
    return _cards.find(get_viewport().gui_get_focus_owner())


func _move(dir: Vector2i) -> void:
    var at := _focused_index()
    if at < 0:
        at = 0
    else:
        at = _neighbour(at, dir)
    _cards[at].grab_focus()
    Sfx.play("ui_move")


func _choose(i: int) -> void:
    if not visible or _armed_in > 0.0 or i < 0 or i >= _classes.size():
        return
    var id := String(_classes[i]["id"])
    if not Classes.is_unlocked(id):
        Sfx.play("ui_back")
        return
    Sfx.play("ui_confirm")
    if _on_pick.is_valid():
        _on_pick.call(id)


func _cancel() -> void:
    if not visible:
        return
    Sfx.play("ui_back")
    if _on_cancel.is_valid():
        _on_cancel.call()


func _process(delta: float) -> void:
    if not visible:
        return
    if _armed_in > 0.0:
        _armed_in -= delta
    if _focused_index() < 0 and not _cards.is_empty():
        _cards[0].grab_focus()
    # Pads are polled directly; their events are stripped from the ui_* actions.
    var up := false
    var down := false
    var left := false
    var right := false
    var accept := false
    var cancel := false
    for d in Input.get_connected_joypads():
        var ax := Input.get_joy_axis(d, JOY_AXIS_LEFT_X)
        var ay := Input.get_joy_axis(d, JOY_AXIS_LEFT_Y)
        up = up or Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_UP) or ay < -0.55
        down = down or Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_DOWN) or ay > 0.55
        left = left or Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_LEFT) or ax < -0.55
        right = right or Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_RIGHT) or ax > 0.55
        accept = accept or Input.is_joy_button_pressed(d, JOY_BUTTON_A)
        cancel = cancel or Input.is_joy_button_pressed(d, JOY_BUTTON_B)
    var armed := _armed_in <= 0.0
    if _edge("up", up, delta, true) and armed:
        _move(Vector2i.UP)
    if _edge("down", down, delta, true) and armed:
        _move(Vector2i.DOWN)
    if _edge("left", left, delta, true) and armed:
        _move(Vector2i.LEFT)
    if _edge("right", right, delta, true) and armed:
        _move(Vector2i.RIGHT)
    if _edge("accept", accept, delta, false) and armed:
        _choose(_focused_index())
    if _edge("cancel", cancel, delta, false) and armed:
        _cancel()


func _input(event: InputEvent) -> void:
    # Keyboard: arrows move through the focus neighbours natively and Enter presses the
    # focused card; Escape backs out here.
    if not visible or _armed_in > 0.0:
        return
    if event is InputEventKey and event.pressed and not event.echo and event.is_action("ui_cancel"):
        get_viewport().set_input_as_handled()
        _cancel()


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
