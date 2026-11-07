class_name WellScreen
extends CanvasLayer
## The Well's pick (World and progression GDD, section 11): which worn item goes down the
## well. One button per item (icon, name, rarity) and "Keep them"; pauses the run. Pad:
## d-pad / stick moves, A drops, B backs out. Keyboard: arrows, Enter or E, Esc. Mouse:
## click. `pick` calls back with the item id, or "" when the player keeps everything.

const GRACE := 0.3

var _on_pick: Callable
var _list: VBoxContainer
var _buttons: Array[Button] = []
var _pad := MenuPad.new()
var _armed_in := 0.0


func _init() -> void:
    layer = 45   # beside the gun pick, below the pause menu (50)
    process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
    var root := Control.new()
    root.set_anchors_preset(Control.PRESET_FULL_RECT)
    root.theme = UiTheme.make()
    root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    add_child(root)
    var dim := ColorRect.new()
    dim.color = Color(0, 0, 0, 0.65)
    dim.set_anchors_preset(Control.PRESET_FULL_RECT)
    root.add_child(dim)
    var center := CenterContainer.new()
    center.set_anchors_preset(Control.PRESET_FULL_RECT)
    root.add_child(center)
    var v := VBoxContainer.new()
    v.add_theme_constant_override("separation", 12)
    center.add_child(v)
    v.add_child(UiTheme.label("THE WELL", 40))
    # Placeholder text (section 9 review pending): plain and functional.
    var desc := UiTheme.label("Drop one worn item. It leaves this run; the Wellkeeper keeps it for you.", 20, UiTheme.BONE)
    desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    desc.custom_minimum_size = Vector2(620, 0)
    v.add_child(desc)
    _list = VBoxContainer.new()
    _list.add_theme_constant_override("separation", 8)
    v.add_child(_list)
    MenuPad.strip_joypad_from_ui_actions()
    _pad.on_cancel = _cancel
    visible = false


func is_open() -> bool:
    return visible


## Ask which of `items` (item ids) goes down the well.
func pick(_player, items: Array, on_pick: Callable) -> void:
    if visible:
        _cancel()
    _on_pick = on_pick
    for c in _list.get_children():
        _list.remove_child(c)
        c.queue_free()
    _buttons.clear()
    for id in items:
        var it: Dictionary = Items.get_item(String(id))
        var label := String(it.get("name", id))
        if int(it.get("rarity", 0)) > 0:
            label += "  (%s)" % Items.rarity_name(it)
        var item_id := String(id)
        var b := UiTheme.button(label, func(): _choose(item_id))
        b.icon = Items.icon(it)
        b.expand_icon = false
        b.add_theme_color_override("font_color", Items.rarity_text_color(it))
        b.custom_minimum_size = Vector2(560, 56)
        _list.add_child(b)
        _buttons.append(b)
    var keep := UiTheme.button("Keep them", _cancel)
    keep.custom_minimum_size = Vector2(560, 48)
    _list.add_child(keep)
    _buttons.append(keep)
    visible = true
    _armed_in = GRACE
    for k in ["accept", "cancel"]:
        _pad._was[k] = true   # the A that opened us must be released first
    get_tree().paused = true
    _buttons[0].grab_focus.call_deferred()


func _close() -> void:
    visible = false
    _on_pick = Callable()
    get_tree().paused = false


func _choose(id: String) -> void:
    if not visible or _armed_in > 0.0:
        return
    var cb := _on_pick
    Sfx.play("ui_confirm")
    _close()
    if cb.is_valid():
        cb.call(id)


func _cancel() -> void:
    if not visible:
        return
    var cb := _on_pick
    Sfx.play("ui_back")
    _close()
    if cb.is_valid():
        cb.call("")


func _process(delta: float) -> void:
    if not visible:
        return
    if _armed_in > 0.0:
        _armed_in -= delta / maxf(Engine.time_scale, 0.001)
    if not get_tree().paused:
        get_tree().paused = true
    var focus := get_viewport().gui_get_focus_owner()
    if focus == null and not _buttons.is_empty():
        _buttons[0].grab_focus()
    _pad.poll(get_viewport(), delta)


func _input(event: InputEvent) -> void:
    if not visible or not event is InputEventKey or not event.pressed or event.echo:
        return
    var key := (event as InputEventKey).physical_keycode
    if key == KEY_ESCAPE:
        get_viewport().set_input_as_handled()
        _cancel()
    elif key == KEY_E:
        var focus := get_viewport().gui_get_focus_owner()
        if focus is Button and _buttons.has(focus):
            get_viewport().set_input_as_handled()
            (focus as Button).pressed.emit()
