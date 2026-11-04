class_name MasteryScreen
extends PanelContainer
## The mastery tree: spend points earned across runs on small permanent bonuses.
## One tab per branch; each node is a flat button so a controller can walk the list,
## the scroll follows focus, and pressing a node buys it.

const BOUGHT_COLOR := Color(0.6, 1.0, 0.75)
const LOCKED_COLOR := Color(0.45, 0.42, 0.45)
const BODY_SIZE := 16
const TAB_WINDOW := 5   # branch names shown at once in the tab bar, current in the middle
const TAB_HALF := 2

var on_close: Callable
var tab := 0
var _tab_labels: Array = []
var _status: Label
var _scroll: ScrollContainer
var _list: VBoxContainer
var _back: Button


func _init(p_on_close: Callable) -> void:
    on_close = p_on_close


func _ready() -> void:
    custom_minimum_size = Vector2(940, 620)
    var v := VBoxContainer.new()
    v.add_theme_constant_override("separation", 6)
    add_child(v)
    var title := UiTheme.label("MASTERY", 40)
    title.add_theme_font_override("font", Art.FONT)
    v.add_child(title)
    _status = _body_label("", UiTheme.BONE)
    v.add_child(_status)
    var bar := HBoxContainer.new()
    bar.alignment = BoxContainer.ALIGNMENT_CENTER
    bar.add_theme_constant_override("separation", 30)
    v.add_child(bar)
    for i in TAB_WINDOW:
        var l := UiTheme.label("", 24)
        bar.add_child(l)
        _tab_labels.append(l)
    v.add_child(_body_label("LB / RB  or  Q / E  switch branches      A / Enter buy      B / Esc back", UiTheme.DIM))
    _scroll = ScrollContainer.new()
    _scroll.custom_minimum_size = Vector2(900, 400)
    _scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    _scroll.follow_focus = true
    v.add_child(_scroll)
    _list = VBoxContainer.new()
    _list.add_theme_constant_override("separation", 2)
    _list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _scroll.add_child(_list)
    _back = UiTheme.button("Back", func(): on_close.call())
    v.add_child(_back)
    set_tab(0)


func _input(event: InputEvent) -> void:
    if not visible or not event is InputEventKey or not event.pressed or event.echo:
        return
    match (event as InputEventKey).physical_keycode:
        KEY_Q:
            set_tab(tab - 1)
        KEY_E:
            set_tab(tab + 1)


func set_tab(i: int) -> void:
    var names: Array = Mastery.branches()
    tab = wrapi(i, 0, names.size())
    for k in _tab_labels.size():
        var idx := wrapi(tab + k - TAB_HALF, 0, names.size())
        var l: Label = _tab_labels[k]
        l.text = names[idx]
        l.add_theme_color_override("font_color", UiTheme.FOCUS if idx == tab else UiTheme.DIM)
    _fill()
    Sfx.play("ui_move")
    await get_tree().process_frame
    if is_visible_in_tree():
        focus_first()


func focus_first() -> void:
    _focus_index(0)


func _focus_index(index: int) -> void:
    if _list.get_child_count() > 0:
        (_list.get_child(clampi(index, 0, _list.get_child_count() - 1)) as Control).grab_focus()
    else:
        _back.grab_focus()


## Rebuild the node list for the current branch.
func _fill() -> void:
    for c in _list.get_children():
        _list.remove_child(c)
        c.queue_free()
    var branch: String = Mastery.branches()[tab]
    var list: Array = Mastery.nodes_in_branch(branch)
    var bought := 0
    for n in list:
        if Mastery.is_bought(n["id"]):
            bought += 1
    _status.text = "Unspent points: %d      Purchased: %d / %d      %s: %d / %d" % [
        Mastery.points, Mastery.purchased_count(), Mastery.total_nodes(), branch, bought, list.size()]
    for i in list.size():
        _entry(list[i], i)


func _entry(n: Dictionary, index: int) -> void:
    var id: String = n["id"]
    var marker := "[ ]"
    var color := UiTheme.BONE
    var extra := ""
    if Mastery.is_bought(id):
        marker = "[x]"
        color = BOUGHT_COLOR
    elif not Mastery.is_reachable(id):
        marker = "[-]"
        color = LOCKED_COLOR
        extra = "   (needs %s)" % Mastery.get_node_data(n["parent"]).get("name", "?")
    var b := Button.new()
    b.text = "%s  %s    cost %d%s\n      %s   ->   %s" % [marker, n["name"], n["cost"], extra, n["desc"], Mastery.mods_text(n["mods"])]
    b.alignment = HORIZONTAL_ALIGNMENT_LEFT
    b.add_theme_font_override("font", ThemeDB.fallback_font)
    b.add_theme_font_size_override("font_size", BODY_SIZE)
    b.add_theme_color_override("font_color", color)
    b.add_theme_color_override("font_focus_color", Color.WHITE)
    b.add_theme_color_override("font_hover_color", Color.WHITE)
    b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    b.pressed.connect(_on_node_pressed.bind(id, index))
    _list.add_child(b)


func _on_node_pressed(id: String, index: int) -> void:
    if not Mastery.buy(id):
        Sfx.play("error")
        return
    Sfx.play("ui_confirm")
    # Deferred: the pressed button is still mid-signal and must not leave the tree yet.
    _refresh.call_deferred(index)


func _refresh(index: int) -> void:
    _fill()
    _focus_index(index)


func _body_label(text: String, color: Color) -> Label:
    var l := UiTheme.label(text, BODY_SIZE, color)
    l.add_theme_font_override("font", ThemeDB.fallback_font)
    return l
