class_name LevelUpScreen
extends CanvasLayer
## Level-up overlay: pauses the run and offers one player three upgrade cards. Several
## level-ups (one player gaining two levels, or two players at once) queue up and are
## shown one after another. Keeps processing while the tree is paused.

const CARD_SIZE := Vector2(300, 340)
const CARD_GAP := 28
const ICON_BOX := 120          # height of the icon area at the top of a card
const GRACE := 0.35            # seconds before a pick is accepted, so mashing does not choose

var main
var _queue: Array = []         # players waiting for their level-up
var _player = null             # player choosing right now
var _options: Array = []
var _cards: Array[Button] = []
var _names: Array[Label] = []
var _rarities: Array[Label] = []
var _effects: Array[Label] = []
var _descs: Array[Label] = []
var _card_icons: Array = []    # Vector2i per card
var _card_tints: Array = []    # icon tint per card
var _card_cols: Array = []     # rarity colour per card (the frame)
var _title: Label
var _hint: Label
var _prompt: Control
var _pad := MenuPad.new()
var _armed_in := 0.0


func _init(p_main) -> void:
    main = p_main
    layer = 40   # above the HUD, below the pause menu (50)
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
    v.add_theme_constant_override("separation", 14)
    center.add_child(v)
    _title = UiTheme.label("", 48)
    v.add_child(_title)
    _hint = UiTheme.label("", 18, UiTheme.DIM)
    _hint.add_theme_font_override("font", Art.FONT)
    _hint.add_theme_font_size_override("font_size", 20)
    v.add_child(_hint)
    var row := HBoxContainer.new()
    row.alignment = BoxContainer.ALIGNMENT_CENTER
    row.add_theme_constant_override("separation", CARD_GAP)
    v.add_child(row)
    for i in 3:
        _card_icons.append(Vector2i(45, 16))
        _card_tints.append(Color.WHITE)
        _card_cols.append(Items.RARITY_COLORS[0])
        var card := _make_card(i)
        row.add_child(card)
        _cards.append(card)
    for i in 3:
        var card := _cards[i]
        var prev := _cards[wrapi(i - 1, 0, 3)]
        var next := _cards[wrapi(i + 1, 0, 3)]
        card.focus_neighbor_left = card.get_path_to(prev)
        card.focus_neighbor_right = card.get_path_to(next)
        card.focus_previous = card.get_path_to(prev)
        card.focus_next = card.get_path_to(next)
        card.focus_neighbor_top = card.get_path_to(card)
        card.focus_neighbor_bottom = card.get_path_to(card)
    _prompt = Control.new()
    _prompt.custom_minimum_size = Vector2(0, 40)
    _prompt.draw.connect(_draw_prompt)
    v.add_child(_prompt)
    MenuPad.strip_joypad_from_ui_actions()
    _pad.on_tab = _step
    visible = false


func _make_card(i: int) -> Button:
    var b := Button.new()
    b.custom_minimum_size = CARD_SIZE
    b.focus_mode = Control.FOCUS_ALL
    # The card is drawn like every ItemCard: rarity frame, icon, then the labels on top.
    for state in ["normal", "hover", "focus", "pressed", "disabled"]:
        b.add_theme_stylebox_override(state, StyleBoxEmpty.new())
    b.draw.connect(_draw_card.bind(i))
    b.pressed.connect(_choose.bind(i))
    b.mouse_entered.connect(func():
        if visible and not b.has_focus():
            b.grab_focus())
    var box := VBoxContainer.new()
    box.set_anchors_preset(Control.PRESET_FULL_RECT)
    box.offset_top = ICON_BOX + 28
    box.offset_left = 16
    box.offset_right = -16
    box.offset_bottom = -14
    box.add_theme_constant_override("separation", 6)
    box.mouse_filter = Control.MOUSE_FILTER_IGNORE
    b.add_child(box)
    var rarity_label := UiTheme.label("", 20, UiTheme.DIM)
    rarity_label.add_theme_font_override("font", Art.FONT)
    rarity_label.add_theme_font_size_override("font_size", 20)
    rarity_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    box.add_child(rarity_label)
    _rarities.append(rarity_label)
    var name_label := UiTheme.label("", 34)
    name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    box.add_child(name_label)
    _names.append(name_label)
    var effect := UiTheme.label("", 30, Color.WHITE)
    effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    effect.custom_minimum_size = Vector2(CARD_SIZE.x - 32, 0)
    effect.mouse_filter = Control.MOUSE_FILTER_IGNORE
    box.add_child(effect)
    _effects.append(effect)
    var desc := UiTheme.label("", 16, UiTheme.BONE)
    desc.add_theme_font_override("font", Art.FONT)
    desc.add_theme_font_size_override("font_size", 20)
    desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    desc.custom_minimum_size = Vector2(CARD_SIZE.x - 32, 0)
    desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
    box.add_child(desc)
    _descs.append(desc)
    return b


## Frame and icon of card `i`, drawn before its labels (they are children).
func _draw_card(i: int) -> void:
    if i >= _cards.size():
        return
    var b: Button = _cards[i]
    var r := Rect2(Vector2.ZERO, b.size)
    var col: Color = _card_cols[i]
    var focused := b.has_focus()
    ItemCard.draw_frame(b, r, col, focused)
    # Icon well at the top, the tile at 6x.
    var well := Rect2(Vector2((r.size.x - ICON_BOX) / 2.0, 20.0), Vector2(ICON_BOX, ICON_BOX))
    b.draw_texture_rect(Art.PARTICLES["light"], well.grow(30.0), false, Color(col, 0.22 if focused else 0.12))
    b.draw_rect(well, Color(0, 0, 0, 0.45))
    b.draw_rect(well, Color(col, 0.5), false, 2.0)
    b.draw_texture_rect(Art.tile(_card_icons[i]), well.grow(-12.0), false, _card_tints[i])
    b.draw_line(Vector2(20, well.end.y + 6.0), Vector2(r.size.x - 20.0, well.end.y + 6.0), Color(col, 0.4), 2.0)


## Queue a level-up for `player`; shows at once when nothing else is showing.
func open(player) -> void:
    _queue.append(player)
    if not visible:
        _show_next()


func is_open() -> bool:
    return visible


func _show_next() -> void:
    _player = null
    while not _queue.is_empty():
        var p = _queue.pop_front()
        if is_instance_valid(p):
            _player = p
            break
    if _player == null:
        _close()
        return
    _options = LevelUps.roll(_player, 3)
    var col: Color = _player.color
    _title.text = "%s  LEVEL %d" % [_player.display_name().to_upper(), _player.level]
    _title.add_theme_color_override("font_color", col)
    _hint.text = "Choose one upgrade"
    if not _queue.is_empty():
        _hint.text += "   (%d more to pick)" % _queue.size()
    for i in _cards.size():
        var card := _cards[i]
        if i >= _options.size():
            card.visible = false
            continue
        var opt: Dictionary = _options[i]
        var rarity: int = clampi(int(opt.get("rarity", 0)), 0, Items.RARITY_COLORS.size() - 1)
        var rarity_col: Color = Items.RARITY_COLORS[rarity]
        card.visible = true
        _card_icons[i] = opt["icon"]
        _card_tints[i] = LevelUps.tint(opt)
        _card_cols[i] = rarity_col
        card.queue_redraw()
        _names[i].text = opt["name"]
        _names[i].add_theme_color_override("font_color", rarity_col)
        _rarities[i].text = String(Items.RARITY_NAMES[rarity]).to_upper()
        _rarities[i].add_theme_color_override("font_color", rarity_col)
        _effects[i].text = LevelUps.describe(opt)
        _descs[i].text = opt["desc"]
    _pad = MenuPad.new()
    _pad.on_tab = _step
    _armed_in = GRACE
    if not visible:
        visible = true
        Sfx.play("ui_open")
    get_tree().paused = true
    var mid: int = mini(1, _options.size() - 1)
    if mid >= 0:
        _cards[mid].grab_focus()
    _prompt.queue_redraw()


func _close() -> void:
    var was_open := visible
    visible = false
    _player = null
    _options = []
    if was_open:
        get_tree().paused = false


func _choose(i: int) -> void:
    if not visible or _armed_in > 0.0 or i >= _options.size() or _player == null:
        return
    var opt: Dictionary = _options[i]
    if is_instance_valid(_player):
        _player.apply_upgrade(opt)
    Sfx.play("ui_confirm")
    _show_next()


## Move focus between cards (pad shoulders / d-pad left-right through MenuPad).
func _step(step: int) -> void:
    var focus := get_viewport().gui_get_focus_owner()
    var at := _cards.find(focus)
    if at < 0:
        at = 1
    var count := _options.size()
    if count <= 0:
        return
    _cards[wrapi(at + step, 0, count)].grab_focus()
    if step != 0:
        Sfx.play("ui_move")


func _process(delta: float) -> void:
    if not visible:
        return
    if _armed_in > 0.0:
        _armed_in -= delta
    # Something else (the pause menu closing) may unpause underneath us.
    if not get_tree().paused:
        get_tree().paused = true
    _prompt.queue_redraw()
    for c in _cards:
        c.queue_redraw()
    var focus := get_viewport().gui_get_focus_owner()
    if focus != null and _cards.find(focus) < 0:
        return   # another overlay (the pause menu) owns focus; leave the input to it
    if focus == null:
        # Focus was lost (a click on the backdrop, an overlay closing): back to a card.
        if Input.is_action_just_pressed("ui_left"):
            _step(-1)
        elif Input.is_action_just_pressed("ui_right"):
            _step(1)
        else:
            _step(0)
    # Keyboard left/right moves through the cards' focus neighbours natively.
    # Polled even during the grace period so a held A only counts once it is re-pressed.
    _pad.poll(get_viewport(), delta)


func _input(event: InputEvent) -> void:
    # E (the keyboard's interact) confirms the focused card, matching the drawn prompt.
    if not visible or not event is InputEventKey or not event.pressed or event.echo:
        return
    if (event as InputEventKey).physical_keycode != KEY_E:
        return
    var at := _cards.find(get_viewport().gui_get_focus_owner())
    if at >= 0:
        get_viewport().set_input_as_handled()
        _choose(at)


func _draw_prompt() -> void:
    if _player == null or not is_instance_valid(_player):
        return
    var label: String = _player.input.prompt("interact")
    var kind: String = _player.input.last_kind
    var font: Font = Art.FONT
    var text := "Choose"
    var text_w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
    var total := 32.0 + 10.0 + text_w
    var x := (_prompt.size.x - total) / 2.0
    var cy := _prompt.size.y / 2.0
    Prompts.draw(_prompt, Vector2(x + 16.0, cy), label, kind, 24.0)
    _prompt.draw_string(font, Vector2(x + 42.0, cy + 7.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UiTheme.BONE)
