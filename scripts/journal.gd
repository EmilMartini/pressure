class_name Journal
extends PanelContainer
## The journal: what is unlocked, what is not, and how to unlock it.
## Tabs: Achievements, Arsenal (guns), Gear (items by rarity), Reactions, Fusions (by
## compound), Cataclysms (by fusion field), Secrets (puzzle kinds found, hidden rooms and
## alcoves). Entries are flat buttons
## so a controller can walk the list and the scroll follows focus. On the Gear tab the
## focused entry's ItemCard shows on the right.

const TABS := ["Achievements", "Arsenal", "Gear", "Reactions", "Fusions", "Cataclysms", "Secrets"]

var on_close: Callable
var tab := 0
var _tab_labels: Array = []
var _scroll: ScrollContainer
var _list: VBoxContainer
var _back: Button
var _card_view: Control
var _card_item: Dictionary = {}


func _init(p_on_close: Callable) -> void:
    on_close = p_on_close


func _ready() -> void:
    custom_minimum_size = Vector2(1120, 640)
    var v := VBoxContainer.new()
    v.add_theme_constant_override("separation", 6)
    add_child(v)
    v.add_child(UiTheme.label("JOURNAL", 40))
    var bar := HBoxContainer.new()
    bar.alignment = BoxContainer.ALIGNMENT_CENTER
    bar.add_theme_constant_override("separation", 30)
    v.add_child(bar)
    for i in TABS.size():
        var l := UiTheme.label(TABS[i], 24)
        bar.add_child(l)
        _tab_labels.append(l)
    v.add_child(UiTheme.label("LB / RB  or  Q / E  switch tabs      stick / arrows scroll      B / Esc back", 20, UiTheme.DIM))
    var body := HBoxContainer.new()
    body.add_theme_constant_override("separation", 16)
    v.add_child(body)
    _scroll = ScrollContainer.new()
    _scroll.custom_minimum_size = Vector2(560, 450)
    _scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    _scroll.follow_focus = true
    body.add_child(_scroll)
    _card_view = Control.new()
    _card_view.custom_minimum_size = Vector2(ItemCard.DEFAULT_WIDTH + 20.0, 450)
    _card_view.clip_contents = true
    _card_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    _card_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _card_view.draw.connect(_draw_card)
    _card_view.visible = false
    body.add_child(_card_view)
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
    tab = wrapi(i, 0, TABS.size())
    for k in _tab_labels.size():
        _tab_labels[k].add_theme_color_override("font_color", UiTheme.FOCUS if k == tab else UiTheme.DIM)
    for c in _list.get_children():
        c.queue_free()
    _card_item = {}
    _card_view.visible = tab == 2
    _card_view.queue_redraw()
    match tab:
        0:
            _fill_achievements()
        1:
            _fill_arsenal()
        2:
            _fill_gear()
        3:
            _fill_reactions()
        4:
            _fill_fusions()
        5:
            _fill_cataclysms()
        6:
            _fill_secrets()
    Sfx.play("ui_move")
    await get_tree().process_frame
    if is_visible_in_tree():
        focus_first()


func focus_first() -> void:
    for c in _list.get_children():
        if c is Control and (c as Control).focus_mode != Control.FOCUS_NONE:
            (c as Control).grab_focus()
            return
    _back.grab_focus()


func _entry(text: String, color: Color) -> Button:
    var b := Button.new()
    b.text = text
    b.alignment = HORIZONTAL_ALIGNMENT_LEFT
    b.add_theme_font_size_override("font_size", 20)
    b.add_theme_color_override("font_color", color)
    b.add_theme_color_override("font_focus_color", Color.WHITE)
    b.add_theme_color_override("font_hover_color", Color.WHITE)
    b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _list.add_child(b)
    return b


## Puts a 32 px icon at the left of an entry; `dim` greys it out (locked, not yet done).
func _set_icon(b: Button, tex: Texture2D, dim: bool) -> void:
    # The world's pixel treatment (one icon pixel per screen cell, in the palette).
    b.icon = Art.icon_pixel(tex, 32) if Settings.flag("post_fx") else tex
    b.add_theme_constant_override("h_separation", 10)
    if dim:
        var grey := Color(0.32, 0.3, 0.32)
        for k in ["icon_normal_color", "icon_focus_color", "icon_hover_color", "icon_pressed_color"]:
            b.add_theme_color_override(k, grey)


## Element swatches as an entry's icon (Element.Kinds or Colors): the element mark,
## while the text stays neutral (GDD 6, "Rarity owns colour").
func _swatch(b: Button, colors: Array) -> void:
    b.icon = ItemCard.swatch_texture(colors, 20)
    b.add_theme_constant_override("h_separation", 10)


func _header(text: String, color: Color) -> void:
    var l := UiTheme.label(text, 22, color)
    l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    _list.add_child(l)


func _fill_achievements() -> void:
    for a in Progress.ACHIEVEMENTS:
        var done: bool = Progress.achievements_done.has(a["id"])
        var rewards: Array = []
        for r in a["rewards"]:
            rewards.append(Progress.unlock_label(r))
        var progress := mini(Progress.stat(a["stat"]), a["goal"])
        var text := "%s  %s    %d / %d\n      %s   ->   %s" % ["[x]" if done else "[ ]", a["name"], progress, a["goal"], a["desc"], ", ".join(rewards)]
        _set_icon(_entry(text, Color(0.6, 1.0, 0.75) if done else UiTheme.BONE), Progress.achievement_icon(a), not done)


func _fill_arsenal() -> void:
    _header("Guns   (%d / %d unlocked)" % [Guns.ids().size(), Guns.all_ids().size()], UiTheme.BONE)
    for id in Guns.all_ids():
        var g := Guns.make(id)
        var unlocked := Progress.has("gun:" + id)
        var el: String = Element.NAMES[g.element]
        var line := "%s    %s %s   weight %d   DPS %.0f\n      %s" % [g.display_name, el, g.archetype, g.weight, g.dps(), g.how()]
        var b: Button
        if unlocked:
            b = _entry(line, UiTheme.BONE)
        else:
            b = _entry(line + "\n      LOCKED   " + Progress.unlock_source("gun:" + id), Color(0.5, 0.48, 0.5))
        _set_icon(b, Art.gun_icon(id), not unlocked)


func _fill_reactions() -> void:
    var defs: Array = Elements.all_defs()
    var found := 0
    for d in defs:
        if Progress.discovered(d["name"]):
            found += 1
    _header("Reactions   (%d / %d discovered)   fire one to reveal what it does" % [found, defs.size()], UiTheme.BONE)
    for d in defs:
        var pair := "%s + %s" % [Element.NAMES[d["a"]], Element.NAMES[d["b"]]]
        if Progress.discovered(d["name"]):
            _swatch(_entry("%s   %s   x%d\n      %s" % [d["name"], pair, Progress.stat("reaction:" + d["name"]), d["desc"]], UiTheme.BONE), [d["a"], d["b"]])
        else:
            _entry("???   %s\n      undiscovered" % pair, Color(0.45, 0.42, 0.45))


## Fusions by compound: a header per compound (what makes it, where it lives), then one entry
## per third element, ??? until it has fired once; then its name, recipe and what it does.
func _fill_fusions() -> void:
    var names: Array = Fusions.all_fusion_names()
    var found := 0
    for n in names:
        if Progress.fusion_discovered(n):
            found += 1
    _header("Fusions   (%d / %d discovered)   a reaction leaves a compound; hit it with a third element" % [found, names.size()], UiTheme.BONE)
    for cid in Fusions.FUSIONS:
        var c: Dictionary = Fusions.compound(cid)
        var row: Dictionary = Fusions.FUSIONS[cid]
        var got := 0
        for k in row:
            if Progress.fusion_discovered(row[k]["name"]):
                got += 1
        var lives := String(c["where"]).replace("+", " and ").replace("floor", "on the floor").replace("cloud", "in the air").replace("enemy", "on the enemy")
        _header("%s   (%s + %s, lives %s)   %d / %d" % [c["name"], Element.NAMES[c["a"]], Element.NAMES[c["b"]], lives, got, row.size()], UiTheme.BONE)
        for k in row:
            var e: Dictionary = row[k]
            var recipe := "%s + %s" % [c["name"], Element.NAMES[k]]
            if Progress.fusion_discovered(e["name"]):
                var extra := "   leaves a field" if e.get("leaves_field", false) else ""
                _swatch(_entry("%s   %s   x%.1f%s   fired %d\n      %s" % [e["name"], recipe, float(e["mult"]), extra, Progress.stat("fusion:" + e["name"]), e["desc"]], UiTheme.BONE), [c["color"], k])
            else:
                _entry("???   %s" % recipe, Color(0.45, 0.42, 0.45))


## Cataclysms by fusion field: a header per field (its fusion's recipe and payload), then one
## entry per fourth element that sets it off, ??? until it has.
func _fill_cataclysms() -> void:
    var names: Array = Fusions.all_cataclysm_names()
    var found := 0
    for n in names:
        if Progress.fusion_discovered(n):
            found += 1
    _header("Cataclysms   (%d / %d discovered)   a fusion field meets a fourth element" % [found, names.size()], UiTheme.BONE)
    for fname in Fusions.CATACLYSMS:
        var info := Fusions.by_name(fname)
        var row: Dictionary = Fusions.CATACLYSMS[fname]
        var f: Dictionary = info["entry"].get("field", {})
        var payload: int = int(f.get("payload", 0))
        var c: Dictionary = Fusions.compound(String(info["source"]))
        var known := Progress.fusion_discovered(fname)
        var got := 0
        for k in row:
            if Progress.fusion_discovered(row[k]["name"]):
                got += 1
        var title: String = fname if known else "???"
        _header("%s field   (%s + %s, rains %s)   %d / %d" % [title, c.get("name", "?"), Element.NAMES[info["element"]], Element.NAMES[payload], got, row.size()], UiTheme.BONE)
        for k in row:
            var e: Dictionary = row[k]
            var recipe := "%s + %s" % [fname if known else "???", Element.NAMES[k]]
            if Progress.fusion_discovered(e["name"]):
                _swatch(_entry("%s   %s   x%.1f   fired %d\n      %s" % [e["name"], recipe, float(e["mult"]), Progress.stat("fusion:" + e["name"]), e["desc"]], UiTheme.BONE), [payload, k])
            else:
                _entry("???   %s" % recipe, Color(0.45, 0.42, 0.45))


## Each puzzle kind stays ??? until it has been solved once; then its name and how.
func _fill_secrets() -> void:
    _header("Secrets   (%d / %d kinds solved)   %d found in all" % [Secrets.kinds_solved(), Secrets.ORDER.size(), Progress.stat("secrets_found")], UiTheme.BONE)
    _header("Hidden rooms opened: %d      Alcoves broken open: %d" % [Progress.stat("hidden_rooms"), Progress.stat("secret:alcove")], UiTheme.DIM)
    for k in Secrets.ORDER:
        var n := Progress.stat("secret:" + k)
        if n > 0:
            var spec: Dictionary = Secrets.KINDS[k]
            _entry("%s   x%d\n      %s" % [spec["name"], n, spec["desc"]], Color(1.0, 0.85, 0.5))
        else:
            _entry("???\n      not yet found", Color(0.45, 0.42, 0.45))


func _fill_gear() -> void:
    var cap := Items.max_rarity_unlocked()
    for r in 5:
        # Rarity owns colour here (GDD 6): rarity-coloured names under a header that
        # prints the rarity word; focus frames the entry in its rarity colour.
        var col: Color = Items.RARITY_TEXT_COLORS[r]
        var ids: Array = Items._by_rarity[r]
        if r > cap:
            var source := Progress.unlock_source("rarity:" + Items.RARITY_NAMES[r].to_lower())
            _header("%s   (%d items)   LOCKED   %s" % [Items.RARITY_NAMES[r], ids.size(), source], Color(0.5, 0.48, 0.5))
            continue
        _header("%s   (%d items)" % [Items.RARITY_NAMES[r], ids.size()], col)
        var sorted: Array = ids.duplicate()
        sorted.sort_custom(func(a, b): return Items.get_item(a)["slot"] < Items.get_item(b)["slot"])
        for id in sorted:
            var it := Items.get_item(id)
            var b := _entry("%s   [%s]" % [it["name"], ItemCard.SLOT_TITLES.get(it["slot"], it["slot"])], col)
            _set_icon(b, Items.icon(it), false)
            for k in ["icon_normal_color", "icon_focus_color", "icon_hover_color", "icon_pressed_color"]:
                b.add_theme_color_override(k, Items.ui_icon_tint(it))
            b.add_theme_color_override("font_focus_color", col)
            b.add_theme_color_override("font_hover_color", col)
            var frame := UiTheme._box(Color(0.18, 0.14, 0.16, 0.95), Items.RARITY_COLORS[r], 3)
            b.add_theme_stylebox_override("focus", frame)
            b.add_theme_stylebox_override("hover", frame)
            b.focus_entered.connect(_show_card.bind(it))
            b.mouse_entered.connect(_show_card.bind(it))


func _show_card(it: Dictionary) -> void:
    _card_item = it
    _card_view.queue_redraw()


func _draw_card() -> void:
    if _card_item.is_empty():
        var font: Font = Art.FONT
        _card_view.draw_string(font, Vector2(10, 40), "Move to an item to see its card.", HORIZONTAL_ALIGNMENT_LEFT, _card_view.size.x - 20.0, 20, UiTheme.DIM)
        return
    ItemCard.draw(_card_view, Rect2(Vector2(10, 6), Vector2(ItemCard.DEFAULT_WIDTH, 0)), _card_item)
