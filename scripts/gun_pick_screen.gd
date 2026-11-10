class_name GunPickScreen
extends CanvasLayer
## Gun-pick overlay: when a player takes a gun mod and carries more than one gun it could
## go on, this pauses the run and shows one card per gun so they choose where it is fitted.
## Confirming calls back with the chosen gun; cancelling (B / Esc) calls back with null so
## the mod stays on its plinth. Keeps processing while the tree is paused.

const CARD_SIZE := Vector2(196, 292)
const CARD_GAP := 14
const ROW_GAP := 14
const PAD_TOP := 14            # card content margin above the icon
const ICON_BOX := 64           # height of the icon area at the top of a card
const BADGE_ROW := 26          # the element badge under the icon
const GRACE := 0.3             # seconds before a pick is accepted, so mashing does not choose
const MAX_PER_ROW := 6         # above this the cards wrap onto two rows
const MAX_MOD_LINES := 4
const FULL_COLOR := Color(0.95, 0.35, 0.30)

var main
var _player = null             # player choosing right now
var _guns: Array = []
var _on_pick: Callable
var _cards: Array[Button] = []
var _title: Label
var _desc: Label
var _rows: VBoxContainer
var _prompt: Control
var _pad := MenuPad.new()
var _armed_in := 0.0


func _init(p_main) -> void:
    main = p_main
    layer = 45   # above the level-up screen (40), below the pause menu (50)
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
    _title = UiTheme.label("", 40)
    v.add_child(_title)
    _desc = UiTheme.label("", 20, UiTheme.BONE)
    UiTheme.to_body(_desc, Art.BODY_SIZE)
    _desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _desc.custom_minimum_size = Vector2(760, 0)
    v.add_child(_desc)
    _rows = VBoxContainer.new()
    _rows.alignment = BoxContainer.ALIGNMENT_CENTER
    _rows.add_theme_constant_override("separation", ROW_GAP)
    v.add_child(_rows)
    _prompt = Control.new()
    _prompt.custom_minimum_size = Vector2(0, 40)
    _prompt.draw.connect(_draw_prompt)
    v.add_child(_prompt)
    MenuPad.strip_joypad_from_ui_actions()
    _pad.on_tab = _step
    _pad.on_cancel = _cancel
    visible = false


## Ask `player` which of `guns` gets the mod `item_id`. `on_pick` receives the chosen Gun,
## or null when the player backs out.
func pick(player, guns: Array, item_id: String, on_pick: Callable) -> void:
    if visible:
        _cancel()   # a pick already showing backs out first, so its callback still fires
    if guns.is_empty():
        if on_pick.is_valid():
            on_pick.call(null)
        return
    _player = player
    _guns = guns.duplicate()
    _on_pick = on_pick
    var item: Dictionary = Items.get_item(item_id)
    var col: Color = player.color if is_instance_valid(player) else UiTheme.BONE
    _title.text = "FIT %s TO" % String(item.get("name", item_id))
    _title.add_theme_color_override("font_color", col)
    _desc.text = String(item.get("desc", ""))
    _build_cards()
    _pad = MenuPad.new()
    _pad.on_tab = _step
    _pad.on_cancel = _cancel
    _armed_in = GRACE
    visible = true
    Sfx.play("ui_open")
    get_tree().paused = true
    _cards[0].grab_focus()
    _prompt.queue_redraw()


func is_open() -> bool:
    return visible


func _build_cards() -> void:
    for row in _rows.get_children():
        _rows.remove_child(row)
        row.queue_free()
    _cards.clear()
    var count := _guns.size()
    var per_row := count if count <= MAX_PER_ROW else ceili(count / 2.0)
    var row_of: Array[HBoxContainer] = []
    for i in count:
        if i % per_row == 0:
            var row := HBoxContainer.new()
            row.alignment = BoxContainer.ALIGNMENT_CENTER
            row.add_theme_constant_override("separation", CARD_GAP)
            _rows.add_child(row)
            row_of.append(row)
        var card := _make_card(i, _guns[i])
        row_of[row_of.size() - 1].add_child(card)
        _cards.append(card)
    # Left/right walk the cards in order (wrapping); up/down jump between the two rows.
    for i in count:
        var card := _cards[i]
        var prev := _cards[wrapi(i - 1, 0, count)]
        var next := _cards[wrapi(i + 1, 0, count)]
        card.focus_neighbor_left = card.get_path_to(prev)
        card.focus_neighbor_right = card.get_path_to(next)
        card.focus_previous = card.get_path_to(prev)
        card.focus_next = card.get_path_to(next)
        var other := card
        if count > per_row:
            var target := i + per_row if i < per_row else i - per_row
            other = _cards[clampi(target, 0, count - 1)]
        card.focus_neighbor_top = card.get_path_to(other)
        card.focus_neighbor_bottom = card.get_path_to(other)


func _make_card(i: int, gun) -> Button:
    var b := Button.new()
    b.custom_minimum_size = CARD_SIZE
    b.focus_mode = Control.FOCUS_ALL
    # Drawn like every ItemCard: a frame in the tier's rarity colour (Items.tier_color),
    # the icon, the element as a neutral badge, labels on top (GDD 6, "Rarity owns colour").
    for state in ["normal", "hover", "focus", "pressed", "disabled"]:
        b.add_theme_stylebox_override(state, StyleBoxEmpty.new())
    b.draw.connect(_draw_card.bind(b, gun))
    b.pressed.connect(_choose.bind(i))
    b.mouse_entered.connect(func():
        if visible and not b.has_focus():
            b.grab_focus())
    var box := VBoxContainer.new()
    box.set_anchors_preset(Control.PRESET_FULL_RECT)
    box.offset_top = PAD_TOP + ICON_BOX + 8 + BADGE_ROW
    box.offset_left = 10
    box.offset_right = -10
    box.offset_bottom = -8
    box.add_theme_constant_override("separation", 2)
    box.mouse_filter = Control.MOUSE_FILTER_IGNORE
    b.add_child(box)
    var tr := Items.tier_rarity(int(gun.tier))
    box.add_child(_card_label(gun.display_name(), 24, Items.RARITY_TEXT_COLORS[tr]))
    var dmg: float = gun.data.damage * gun.tier_mult()
    var rate: float = gun.fire_rate()
    var dps: float = gun.data.dps_at(dmg, gun.top_fire_rate() if gun.data.spin_up > 0.0 else rate)
    box.add_child(_card_label("%s   DPS %.0f" % [Items.RARITY_NAMES[tr], dps], 20, UiTheme.BONE))
    var fitted: int = gun.mods.size()
    var cap: int = gun.tier
    box.add_child(_card_label("mods %d / %d" % [fitted, cap], 20, FULL_COLOR if fitted >= cap else UiTheme.DIM))
    var lines := mini(fitted, MAX_MOD_LINES)
    for m in lines:
        if m == MAX_MOD_LINES - 1 and fitted > MAX_MOD_LINES:
            box.add_child(_card_label("+%d more" % (fitted - m), 20, UiTheme.DIM))
            break
        var mod_id := String(gun.mods[m])
        var item: Dictionary = Items.get_item(mod_id)
        var text := String(item.get("name", mod_id))
        if item.is_empty():
            box.add_child(_card_label(text, 20, UiTheme.DIM))
            continue
        # Name in its rarity colour with the rarity word after it (not colour alone).
        var row := HBoxContainer.new()
        row.add_theme_constant_override("separation", 6)
        row.mouse_filter = Control.MOUSE_FILTER_IGNORE
        var name_l := _card_label(text, 20, Items.rarity_text_color(item))
        name_l.custom_minimum_size = Vector2.ZERO
        name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        name_l.clip_text = true
        row.add_child(name_l)
        var word := _card_label(Items.rarity_name(item).to_upper(), 16, Items.rarity_text_color(item))
        word.custom_minimum_size = Vector2.ZERO
        word.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
        word.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
        row.add_child(word)
        box.add_child(row)
    return b


func _card_label(text: String, size: int, color: Color) -> Label:
    var l := UiTheme.label(text, size, color)
    l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    l.custom_minimum_size = Vector2(CARD_SIZE.x - 20, 0)
    l.mouse_filter = Control.MOUSE_FILTER_IGNORE
    return l


## Frame and icon of a gun card, drawn before its labels (they are children).
func _draw_card(b: Button, gun) -> void:
    if not is_instance_valid(b) or gun == null or not is_instance_valid(gun):
        return
    var r := Rect2(Vector2.ZERO, b.size)
    var col: Color = Items.tier_color(int(gun.tier))
    var focused := b.has_focus()
    ItemCard.draw_frame(b, r, col, focused)
    var well := Rect2(Vector2((r.size.x - ICON_BOX) / 2.0, PAD_TOP), Vector2(ICON_BOX, ICON_BOX))
    b.draw_texture_rect(Art.PARTICLES["light"], well.grow(24.0), false, Color(col, 0.22 if focused else 0.1))
    b.draw_rect(well, Color(0, 0, 0, 0.45))
    b.draw_rect(well, Color(col, 0.5), false, 2.0)
    Art.draw_icon(b, Art.gun_icon(gun.data.id), well)
    ItemCard.draw_pips(b, Vector2(well.position.x + 5.0, well.end.y - 9.0), int(gun.tier), col)
    var bs := ItemCard.element_badge_size(gun.data.element)
    ItemCard.draw_element_badge(b, Vector2(roundf((r.size.x - bs.x) / 2.0), well.end.y + 6.0), gun.data.element)


func _close() -> void:
    var was_open := visible
    visible = false
    _player = null
    _guns = []
    _on_pick = Callable()
    if was_open:
        get_tree().paused = false


func _choose(i: int) -> void:
    if not visible or _armed_in > 0.0 or i >= _guns.size():
        return
    var gun = _guns[i]
    var cb := _on_pick
    Telemetry.gun_pick(_guns, gun)
    Sfx.play("ui_confirm")
    # Close before calling back, so the callback may open another overlay (or this one).
    _close()
    if cb.is_valid():
        cb.call(gun if is_instance_valid(gun) else null)


func _cancel() -> void:
    if not visible:
        return
    var cb := _on_pick
    Sfx.play("ui_back")
    _close()
    if cb.is_valid():
        cb.call(null)


## Move focus between cards (pad shoulders / d-pad left-right through MenuPad).
func _step(step: int) -> void:
    var count := _cards.size()
    if count <= 0:
        return
    var at := _cards.find(get_viewport().gui_get_focus_owner())
    if at < 0:
        at = 0
    _cards[wrapi(at + step, 0, count)].grab_focus()
    if step != 0:
        Sfx.play("ui_move")


func _process(delta: float) -> void:
    if not visible:
        return
    if _armed_in > 0.0:
        _armed_in -= delta / maxf(Engine.time_scale, 0.001)   # real time, immune to hit-stop
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
    # E (the keyboard's interact) confirms the focused card, matching the drawn prompt;
    # Escape backs out and leaves the mod where it is.
    if not visible or not event is InputEventKey or not event.pressed or event.echo:
        return
    var key := (event as InputEventKey).physical_keycode
    if key != KEY_E and key != KEY_ESCAPE:
        return
    var focus := get_viewport().gui_get_focus_owner()
    if focus != null and _cards.find(focus) < 0:
        return   # another overlay owns focus
    get_viewport().set_input_as_handled()
    if key == KEY_ESCAPE:
        _cancel()
        return
    var at := _cards.find(focus)
    if at >= 0:
        _choose(at)


func _draw_prompt() -> void:
    if _player == null or not is_instance_valid(_player):
        return
    var label: String = _player.input.prompt("interact")
    var kind: String = _player.input.last_kind
    var font: Font = Art.FONT
    var size := 20
    var text := "Fit"
    var hint := "B / Esc  leave it"
    var text_w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
    var hint_w := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
    var gap := 48.0
    var total := 32.0 + 10.0 + text_w + gap + hint_w
    var x := (_prompt.size.x - total) / 2.0
    var cy := _prompt.size.y / 2.0
    Prompts.draw(_prompt, Vector2(x + 16.0, cy), label, kind, 24.0)
    _prompt.draw_string(font, Vector2(x + 42.0, cy + 7.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, UiTheme.BONE)
    _prompt.draw_string(font, Vector2(x + 42.0 + text_w + gap, cy + 7.0), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, size, UiTheme.DIM)
