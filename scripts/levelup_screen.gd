class_name LevelUpScreen
extends CanvasLayer
## Level-up overlay: pauses the run and offers one player three boon cards. Several
## level-ups (one player gaining two levels, or two players at once) queue up and are
## shown one after another. Keeps processing while the tree is paused.
## Shrine talents: Wider Choice adds a fourth card (every other level-up at rank 1, every
## level-up at rank 2); Second Thoughts gives rerolls of the offer (button, X, or R).
##
## A card reads top to bottom, sized for a TV at the 1280x720 base (x1.5 at 1080p):
## category word and rarity word, the icon, the name (rarity colour), the effect as a big
## headline ("+16% damage"), your value now > after, a second stat or a cost, and in plain
## words what it changes. Rarity owns the frame and name colour (WoW palette, plus the word);
## an element boon carries the neutral element badge. The focused card is lifted, lit and
## carries the Choose prompt; the others dim.

const CARD_SIZE := Vector2(352, 392)
const CARD_SIZE_FOUR := Vector2(292, 392)
const CARD_GAP := 22
const MAX_CARDS := 4
const ICON_BOX := 96           # icon well at the top of a card (the 32 px tile at 2x)
const ICON_TOP := 46.0
const LIFT := 10.0             # the focused card rises this much
const GRACE := 0.35            # seconds before a pick is accepted, so mashing does not choose
const COST_COL := Color(1.0, 0.45, 0.40)
const HEAD_COL := Color(1.0, 1.0, 1.0)

var main
var _queue: Array = []         # players waiting for their level-up
var _player = null             # player choosing right now
var _options: Array = []
var _cards: Array[Button] = []
var _names: Array[Label] = []
var _heads: Array[Label] = []
var _deltas: Array[Label] = []
var _extras: Array[Label] = []
var _affects: Array[Label] = []
var _card_icons: Array = []    # icon Texture2D per card
var _card_cols: Array = []     # rarity colour per card (the frame)
var _title: Label
var _hint: Label
var _reroll: Button
var _pad := MenuPad.new()
var _armed_in := 0.0
var _x_was := false


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
    dim.color = Color(0, 0, 0, 0.72)
    dim.set_anchors_preset(Control.PRESET_FULL_RECT)
    root.add_child(dim)
    var center := CenterContainer.new()
    center.set_anchors_preset(Control.PRESET_FULL_RECT)
    root.add_child(center)
    var v := VBoxContainer.new()
    v.add_theme_constant_override("separation", 12)
    center.add_child(v)
    _title = UiTheme.label("", 44)
    v.add_child(_title)
    _hint = UiTheme.label("", 24, UiTheme.DIM)
    v.add_child(_hint)
    var row := HBoxContainer.new()
    row.alignment = BoxContainer.ALIGNMENT_CENTER
    row.add_theme_constant_override("separation", CARD_GAP)
    row.custom_minimum_size = Vector2(0, CARD_SIZE.y + LIFT + 44.0)
    v.add_child(row)
    for i in MAX_CARDS:
        _card_icons.append(Art.icon("", Vector2i(45, 16)))
        _card_cols.append(Items.RARITY_COLORS[0])
        var card := _make_card(i)
        row.add_child(card)
        _cards.append(card)
    var reroll_row := CenterContainer.new()
    v.add_child(reroll_row)
    _reroll = UiTheme.button("Reroll", _on_reroll)
    _reroll.custom_minimum_size = Vector2(320, 48)
    _reroll.visible = false
    reroll_row.add_child(_reroll)
    _link_cards(3)
    MenuPad.strip_joypad_from_ui_actions()
    _pad.on_tab = _step
    visible = false


## A card is a Button drawn by hand (frame, icon well, badge, prompt) with its labels on
## top in a column. The column sits inside a holder that the focused card lifts.
func _make_card(i: int) -> Button:
    var b := Button.new()
    b.custom_minimum_size = CARD_SIZE
    b.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
    b.focus_mode = Control.FOCUS_ALL
    for state in ["normal", "hover", "focus", "pressed", "disabled"]:
        b.add_theme_stylebox_override(state, StyleBoxEmpty.new())
    b.draw.connect(_draw_card.bind(i))
    b.pressed.connect(_choose.bind(i))
    b.mouse_entered.connect(func():
        if visible and not b.has_focus():
            b.grab_focus())
    var box := VBoxContainer.new()
    box.set_anchors_preset(Control.PRESET_FULL_RECT)
    box.offset_top = ICON_TOP + ICON_BOX + 8.0
    box.offset_left = 14
    box.offset_right = -14
    box.offset_bottom = -12
    box.add_theme_constant_override("separation", 4)
    box.mouse_filter = Control.MOUSE_FILTER_IGNORE
    b.add_child(box)
    var name_label := _lab(30, UiTheme.BONE)
    box.add_child(name_label)
    _names.append(name_label)
    var head := _lab(44, HEAD_COL)
    head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    box.add_child(head)
    _heads.append(head)
    var delta := _lab(30, UiTheme.BONE)
    box.add_child(delta)
    _deltas.append(delta)
    var extra := _lab(26, UiTheme.BONE)
    extra.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    box.add_child(extra)
    _extras.append(extra)
    var spacer := Control.new()
    spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
    spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
    box.add_child(spacer)
    var aff := _lab(24, UiTheme.DIM.lightened(0.3))
    aff.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    box.add_child(aff)
    _affects.append(aff)
    return b


func _lab(size: int, col: Color) -> Label:
    var l := UiTheme.label("", size, col)
    l.mouse_filter = Control.MOUSE_FILTER_IGNORE
    return l


## Frame, top row (category, rarity), icon well and element badge of card `i`, drawn
## before its labels (they are children). The focused card gets the lit frame and the
## Choose prompt under it.
func _draw_card(i: int) -> void:
    if i >= _cards.size() or i >= _options.size():
        return
    var b: Button = _cards[i]
    var opt: Dictionary = _options[i]
    var r := Rect2(Vector2.ZERO, b.size)
    var col: Color = _card_cols[i]
    var focused := b.has_focus()
    var rarity: int = clampi(int(opt.get("rarity", 0)), 0, Items.RARITY_COLORS.size() - 1)
    b.draw_rect(r, Color(0.035, 0.03, 0.045))   # opaque: nothing of the room shows through
    ItemCard.draw_frame(b, r, col, focused)
    var font: Font = Art.FONT
    # Top row: category word (neutral) left, rarity word (rarity colour) and pips right.
    b.draw_string(font, Vector2(16, 34), String(opt.get("cat", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UiTheme.DIM.lightened(0.2))
    var rname := String(Items.RARITY_NAMES[rarity]).to_upper()
    var rw := font.get_string_size(rname, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
    b.draw_string(font, Vector2(r.size.x - 16.0 - rw, 34), rname, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Items.RARITY_TEXT_COLORS[rarity])
    ItemCard.draw_pips(b, Vector2(r.size.x - 16.0 - rw - 8.0 - float(rarity + 1) * 8.0, 22), rarity + 1, col, 6.0)
    # Icon well, the 32 px tile at 2x.
    var well := Rect2(Vector2((r.size.x - ICON_BOX) / 2.0, ICON_TOP), Vector2(ICON_BOX, ICON_BOX))
    b.draw_texture_rect(Art.PARTICLES["light"], well.grow(34.0), false, Color(col, 0.20 if focused else 0.08))
    b.draw_rect(well, Color(0, 0, 0, 0.5))
    b.draw_rect(well, Color(col, 0.6), false, 2.0)
    Art.draw_icon(b, _card_icons[i], well.grow(-16.0), Color.WHITE)
    var el := LevelUps.element_of(opt)
    if el != Element.Kind.NONE:
        var bs := ItemCard.element_badge_size(el, 20)
        ItemCard.draw_element_badge(b, Vector2(well.end.x - bs.x * 0.5, well.end.y - bs.y + 4.0), el, 20)
    if focused and _player != null and is_instance_valid(_player):
        # The Choose prompt hangs under the focused card.
        var label: String = _player.input.prompt("interact")
        var kind: String = _player.input.last_kind
        var text := "Choose"
        var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
        var total := 32.0 + 10.0 + tw
        var x := (r.size.x - total) / 2.0
        var cy := r.size.y + 26.0
        Prompts.draw(b, Vector2(x + 16.0, cy), label, kind, 26.0)
        b.draw_string(font, Vector2(x + 42.0, cy + 9.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color.WHITE)


## Queue a level-up for `player`; shows at once when nothing else is showing.
func open(player) -> void:
    _queue.append(player)
    if not visible:
        _show_next()


func is_open() -> bool:
    return visible


## Captures (PayoutShot): show these exact options for `player`.
func open_with(player, opts: Array) -> void:
    _player = player
    _options = opts
    _fill_cards()
    _armed_in = GRACE
    visible = true
    get_tree().paused = true
    _cards[mini(1, _options.size() - 1)].grab_focus()


func close_for_test() -> void:
    _close()


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
    _player.levelups_shown += 1
    _options = LevelUps.roll(_player, _card_count(_player))
    _fill_cards()
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


## Three cards, or four with the Shrine's Wider Choice (rank 1: every other level-up).
func _card_count(p) -> int:
    var extra := int(Mastery.bonus("levelup_extra"))
    if extra >= 2 or (extra == 1 and int(p.levelups_shown) % 2 == 1):
        return 4
    return 3


## Fill the card widgets from `_options` and wire focus between the visible ones.
func _fill_cards() -> void:
    _title.text = "%s  LEVEL %d" % [_player.display_name().to_upper(), _player.level]
    _title.add_theme_color_override("font_color", UiTheme.BONE)
    _hint.text = "Choose one boon"
    if not _queue.is_empty():
        _hint.text += "   (%d more to pick)" % _queue.size()
    var card_size := CARD_SIZE_FOUR if _options.size() > 3 else CARD_SIZE
    for i in _cards.size():
        var card := _cards[i]
        if i >= _options.size():
            card.visible = false
            continue
        var opt: Dictionary = _options[i]
        var rarity: int = clampi(int(opt.get("rarity", 0)), 0, Items.RARITY_COLORS.size() - 1)
        card.visible = true
        card.custom_minimum_size = card_size
        _card_icons[i] = LevelUps.icon(opt)
        _card_cols[i] = Items.RARITY_COLORS[rarity]
        _names[i].text = String(opt["name"])
        _names[i].add_theme_color_override("font_color", Items.RARITY_TEXT_COLORS[rarity])
        var head := LevelUps.describe(opt)
        _heads[i].text = head
        # Long headlines (an element name) step down so they stay on one or two lines.
        _heads[i].add_theme_font_size_override("font_size", 44 if head.length() <= 14 else 36)
        _deltas[i].text = LevelUps.before_after(opt, _player)
        var lines: Array = []
        var cost := false
        for ln in LevelUps.extra_lines(opt):
            lines.append(String(ln[0]))
            cost = cost or bool(ln[1])
        _extras[i].text = "\n".join(lines)
        _extras[i].visible = not lines.is_empty()
        _extras[i].add_theme_color_override("font_color", COST_COL if cost else UiTheme.BONE)
        _affects[i].text = String(opt.get("affects", ""))
        for l in [_names[i], _heads[i], _deltas[i], _extras[i], _affects[i]]:
            l.custom_minimum_size = Vector2(card_size.x - 28.0, 0)
        card.queue_redraw()
    var left := int(_player.levelup_rerolls)
    _reroll.visible = left > 0
    _reroll.text = "Reroll   %d left   (X / R)" % left
    _link_cards(_options.size())


## Left / right wrap over the `count` visible cards; down goes to the reroll button when
## it is showing (MenuPad walks focus_next / focus_previous for up and down).
func _link_cards(count: int) -> void:
    count = maxi(1, mini(count, _cards.size()))
    var reroll_on := _reroll != null and _reroll.visible
    for i in count:
        var card := _cards[i]
        var prev := _cards[wrapi(i - 1, 0, count)]
        var next := _cards[wrapi(i + 1, 0, count)]
        var below: Control = _reroll if reroll_on else card
        card.focus_neighbor_left = card.get_path_to(prev)
        card.focus_neighbor_right = card.get_path_to(next)
        card.focus_neighbor_top = card.get_path_to(card)
        card.focus_neighbor_bottom = card.get_path_to(below)
        card.focus_previous = card.get_path_to(card)
        card.focus_next = card.get_path_to(below)
    if _reroll != null:
        var mid := _cards[mini(1, count - 1)]
        _reroll.focus_neighbor_top = _reroll.get_path_to(mid)
        _reroll.focus_previous = _reroll.get_path_to(mid)
        _reroll.focus_neighbor_bottom = _reroll.get_path_to(_reroll)
        _reroll.focus_next = _reroll.get_path_to(_reroll)
        _reroll.focus_neighbor_left = _reroll.get_path_to(_reroll)
        _reroll.focus_neighbor_right = _reroll.get_path_to(_reroll)


## Second Thoughts: spend one reroll on a fresh offer of the same size.
func _on_reroll() -> void:
    if not visible or _player == null or not is_instance_valid(_player) or int(_player.levelup_rerolls) <= 0:
        return
    _player.levelup_rerolls -= 1
    Telemetry.event("levelup_reroll", { "level": int(_player.level), "left": int(_player.levelup_rerolls) })
    _options = LevelUps.roll(_player, _options.size())
    _fill_cards()
    _armed_in = GRACE
    Sfx.play("ui_confirm")
    _cards[mini(1, _options.size() - 1)].grab_focus()


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
        Telemetry.levelup(_options, i, int(_player.level))
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
        _armed_in -= delta / maxf(Engine.time_scale, 0.001)   # real time, immune to hit-stop
    # Something else (the pause menu closing) may unpause underneath us.
    if not get_tree().paused:
        get_tree().paused = true
    var focus := get_viewport().gui_get_focus_owner()
    # The focused card rises and stays bright; the others dim, so the choice reads at a glance.
    for i in _cards.size():
        var c := _cards[i]
        var on := c == focus
        c.modulate = Color.WHITE if on or _cards.find(focus) < 0 else Color(0.62, 0.62, 0.66)
        c.position.y = 0.0 if on else LIFT
        c.queue_redraw()
    if focus != null and _cards.find(focus) < 0 and focus != _reroll:
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
    var x_down := false
    for d in Input.get_connected_joypads():
        x_down = x_down or Input.is_joy_button_pressed(d, JOY_BUTTON_X)
    if x_down and not _x_was and _armed_in <= 0.0:
        _on_reroll()
    _x_was = x_down


func _input(event: InputEvent) -> void:
    # E (the keyboard's interact) confirms the focused card, matching the drawn prompt.
    if not visible or not event is InputEventKey or not event.pressed or event.echo:
        return
    if (event as InputEventKey).physical_keycode == KEY_R:
        get_viewport().set_input_as_handled()
        if _armed_in <= 0.0:
            _on_reroll()
        return
    if (event as InputEventKey).physical_keycode != KEY_E:
        return
    var at := _cards.find(get_viewport().gui_get_focus_owner())
    if at >= 0:
        get_viewport().set_input_as_handled()
        _choose(at)
