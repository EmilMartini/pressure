class_name CharacterSheet
extends PanelContainer
## One player's character screen, paper-doll style: gear slots around the figure, guns
## below (press to drop one onto the floor), a readable stat panel on the right, and a
## tooltip for whatever is focused. Opened from the pause menu, or with C / the pad's Back.

const SLOT_LAYOUT := {
    "head": Vector2(24, 20), "chest": Vector2(24, 92), "hands": Vector2(24, 164), "feet": Vector2(24, 236),
    "trinket1": Vector2(336, 20), "trinket2": Vector2(336, 92), "ring1": Vector2(336, 164), "ring2": Vector2(336, 236),
}
const SLOT_SIZE := 60.0

var on_close: Callable
var player: Player
var _title: Label
var _doll: Control
var _tooltip: RichTextLabel
var _guns_row: HFlowContainer
var _stats: VBoxContainer
var _back: Button
var _body_font: Font


func _init(p_on_close: Callable) -> void:
    on_close = p_on_close


func _ready() -> void:
    _body_font = ThemeDB.fallback_font
    custom_minimum_size = Vector2(1100, 660)
    size = custom_minimum_size
    var v := VBoxContainer.new()
    v.add_theme_constant_override("separation", 4)
    add_child(v)
    _title = UiTheme.label("CHARACTER", 36)
    v.add_child(_title)
    v.add_child(_hint("LB / RB  or  Q / E  other player      move to a slot for details      press a gun to drop it      B / Esc back"))

    var columns := HBoxContainer.new()
    columns.add_theme_constant_override("separation", 24)
    v.add_child(columns)

    var left := VBoxContainer.new()
    left.add_theme_constant_override("separation", 6)
    left.custom_minimum_size = Vector2(420, 0)
    left.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
    columns.add_child(left)
    _doll = Control.new()
    _doll.custom_minimum_size = Vector2(420, 310)
    _doll.draw.connect(_draw_doll)
    left.add_child(_doll)
    _guns_row = HFlowContainer.new()
    _guns_row.add_theme_constant_override("h_separation", 6)
    _guns_row.add_theme_constant_override("v_separation", 6)
    _guns_row.custom_minimum_size = Vector2(420, 0)
    _guns_row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
    left.add_child(_guns_row)
    _tooltip = RichTextLabel.new()
    _tooltip.bbcode_enabled = true
    _tooltip.fit_content = true
    _tooltip.custom_minimum_size = Vector2(420, 120)
    _tooltip.add_theme_font_override("normal_font", _body_font)
    _tooltip.add_theme_font_override("bold_font", _body_font)
    _tooltip.add_theme_font_size_override("normal_font_size", 15)
    _tooltip.add_theme_font_size_override("bold_font_size", 16)
    left.add_child(_tooltip)

    var scroll := ScrollContainer.new()
    scroll.custom_minimum_size = Vector2(560, 500)
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    columns.add_child(scroll)
    _stats = VBoxContainer.new()
    _stats.add_theme_constant_override("separation", 2)
    _stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.add_child(_stats)

    _back = UiTheme.button("Back", func(): on_close.call())
    v.add_child(_back)


func _hint(text: String) -> Label:
    var l := Label.new()
    l.text = text
    l.add_theme_font_override("font", _body_font)
    l.add_theme_font_size_override("font_size", 13)
    l.add_theme_color_override("font_color", UiTheme.DIM)
    l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    return l


func show_player(p: Player) -> void:
    player = p
    _title.text = "P%d   CHARACTER" % (p.index + 1)
    _title.add_theme_color_override("font_color", p.color)
    for c in _doll.get_children():
        c.queue_free()
    for c in _guns_row.get_children():
        c.queue_free()
    for c in _stats.get_children():
        c.queue_free()
    _build_slots()
    _build_guns()
    _build_stats()
    _tooltip.text = "[color=#9a948f]Move to a slot or a gun to see details.[/color]"
    _doll.queue_redraw()
    await get_tree().process_frame
    if _doll.get_child_count() > 0:
        (_doll.get_child(0) as Control).grab_focus()
    else:
        _back.grab_focus()


# --- Paper doll ------------------------------------------------------------


func _slot_button(pos: Vector2, icon: Vector2i, tint: Color, border: Color, filled: bool) -> Button:
    var b := Button.new()
    b.position = pos
    b.size = Vector2(SLOT_SIZE, SLOT_SIZE)
    b.icon = Art.tile(icon)
    b.expand_icon = true
    b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
    b.add_theme_color_override("icon_normal_color", tint if filled else Color(0.35, 0.32, 0.34))
    b.add_theme_color_override("icon_hover_color", tint if filled else Color(0.5, 0.47, 0.5))
    b.add_theme_color_override("icon_focus_color", tint if filled else Color(0.5, 0.47, 0.5))
    b.add_theme_color_override("icon_pressed_color", tint)
    var normal := StyleBoxFlat.new()
    normal.bg_color = Color(0.08, 0.06, 0.08, 0.95)
    normal.border_color = border
    normal.set_border_width_all(2)
    normal.set_content_margin_all(8)
    var focus := normal.duplicate()
    focus.border_color = Color.WHITE
    focus.set_border_width_all(3)
    b.add_theme_stylebox_override("normal", normal)
    b.add_theme_stylebox_override("hover", focus)
    b.add_theme_stylebox_override("focus", focus)
    b.add_theme_stylebox_override("pressed", focus)
    _doll.add_child(b)
    return b


func _build_slots() -> void:
    for key in Player.EQUIP_KEYS:
        var slot_name: String = key.rstrip("12")
        var pos: Vector2 = SLOT_LAYOUT[key]
        var b: Button
        if player.equipment.has(key):
            var it := Items.get_item(player.equipment[key])
            b = _slot_button(pos, Items.icon(it), Items.icon_tint(it), Items.rarity_color(it), true)
            var text := _item_tooltip(it)
            b.focus_entered.connect(func(): _tooltip.text = text)
            b.mouse_entered.connect(func(): _tooltip.text = text)
        else:
            b = _slot_button(pos, Items.SLOT_ICONS[slot_name], Color.WHITE, Color(0.3, 0.27, 0.3), false)
            var text := "[b]%s[/b]\n[color=#9a948f]Empty. Gear drops from elites and bosses, and sits in shops and treasure rooms.[/color]" % slot_name.capitalize()
            b.focus_entered.connect(func(): _tooltip.text = text)
            b.mouse_entered.connect(func(): _tooltip.text = text)


func _item_tooltip(it: Dictionary) -> String:
    var col := Items.rarity_color(it).to_html(false)
    var text := "[b][color=#%s]%s[/color][/b]   [color=#9a948f]%s %s[/color]\n%s" % [col, it["name"], Items.RARITY_NAMES[it["rarity"]], it["slot"], it["desc"]]
    var sid := Items.set_of(it["id"])
    if sid != "":
        var s: Dictionary = Items.SETS[sid]
        var counts := Items.set_counts(player)
        text += "\n[color=#c9b37a]%s set  %d / %d[/color]" % [s["name"], counts.get(sid, 0), s["items"].size()]
    return text


func _draw_doll() -> void:
    var r := Rect2(Vector2.ZERO, _doll.size)
    _doll.draw_rect(r, Color(0.05, 0.04, 0.06, 0.8))
    _doll.draw_rect(r, Color(0.3, 0.26, 0.28), false, 2.0)
    if player == null:
        return
    # The figure: a big tinted sprite with a glow behind it and a plinth under it.
    var center := Vector2(_doll.size.x / 2.0, 150.0)
    _doll.draw_texture_rect(Art.PARTICLES["light"], Rect2(center - Vector2(130, 130), Vector2(260, 260)), false, Color(player.color, 0.18))
    _doll.draw_colored_polygon(PackedVector2Array([center + Vector2(-50, 90), center + Vector2(50, 90), center + Vector2(60, 110), center + Vector2(-60, 110)]), Color(0.3, 0.27, 0.29))
    var tiles: Array = Art.TILES["player"]
    var tex: AtlasTexture = Art.tile(tiles[player.index % tiles.size()])
    _doll.draw_texture_rect(tex, Rect2(center - Vector2(72, 80), Vector2(144, 144)), false, player.color.lerp(Color.WHITE, 0.35))
    _doll.draw_string(_body_font, Vector2(center.x - 100, 300), "%d / %d HP" % [int(player.hp), int(player.max_hp)], HORIZONTAL_ALIGNMENT_CENTER, 200, 15, UiTheme.BONE)


# --- Guns ------------------------------------------------------------------


func _build_guns() -> void:
    if player.guns.is_empty():
        _guns_row.add_child(_hint("no guns"))
        return
    for g in player.guns:
        var b := Button.new()
        b.custom_minimum_size = Vector2(48, 48)
        b.icon = Art.tile(Art.gun_tile(g.data.id))
        b.expand_icon = true
        b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
        var ec: Color = g.data.color()
        for state in ["icon_normal_color", "icon_hover_color", "icon_focus_color", "icon_pressed_color"]:
            b.add_theme_color_override(state, ec)
        var normal := StyleBoxFlat.new()
        normal.bg_color = Color(0.08, 0.06, 0.08, 0.95)
        normal.border_color = Color.WHITE if g == player.primary else Color(ec, 0.8)
        normal.set_border_width_all(3 if g == player.primary else 2)
        normal.set_content_margin_all(8)
        var focus := normal.duplicate()
        focus.border_color = Color(1.0, 0.45, 0.15)
        b.add_theme_stylebox_override("normal", normal)
        b.add_theme_stylebox_override("hover", focus)
        b.add_theme_stylebox_override("focus", focus)
        b.add_theme_stylebox_override("pressed", focus)
        var text := _gun_tooltip(g)
        b.focus_entered.connect(func(): _tooltip.text = text)
        b.mouse_entered.connect(func(): _tooltip.text = text)
        b.pressed.connect(func(): _drop_gun(g))
        _guns_row.add_child(b)


func _gun_tooltip(g: Gun) -> String:
    var ec := g.data.color().to_html(false)
    var text := "[b][color=#%s]%s[/color][/b]   [color=#9a948f]%s, weight %d%s[/color]\n%.1f shots/s, %.0f damage" % [
        ec, g.data.display_name, Element.NAMES[g.data.element], g.data.weight, "   TRIGGER" if g == player.primary else "", g.fire_rate(), g.data.damage]
    if g.data.projectile_count > 1:
        text += ", %d projectiles" % g.data.projectile_count
    if g.data.pierce > 0:
        text += ", pierce %d" % g.data.pierce
    if g.mod != "":
        var m := Items.get_item(g.mod)
        text += "\n[color=#%s]%s[/color]: %s" % [Items.rarity_color(m).to_html(false), m["name"], m["desc"]]
    text += "\n[color=#78d6d6]Press to drop it on the floor here.[/color]"
    return text


func _drop_gun(g: Gun) -> void:
    if player == null or not is_instance_valid(g):
        return
    var main := player.main()
    var id := player.drop_gun(g)
    if id != "" and main != null and main.current != null:
        main.current.add_floor_gun(id, player.global_position + Vector2(0, 40))
    Sfx.play("ui_back")
    show_player(player)


# --- Stats -----------------------------------------------------------------


func _group(title: String) -> void:
    var l := Label.new()
    l.text = title
    l.add_theme_font_size_override("font_size", 22)
    l.add_theme_color_override("font_color", UiTheme.FOCUS)
    _stats.add_child(l)


func _row(name: String, value: String, color: Color = UiTheme.BONE) -> void:
    var h := HBoxContainer.new()
    var a := Label.new()
    a.text = name
    a.add_theme_font_override("font", _body_font)
    a.add_theme_font_size_override("font_size", 15)
    a.add_theme_color_override("font_color", UiTheme.DIM)
    a.custom_minimum_size = Vector2(230, 0)
    h.add_child(a)
    var b := Label.new()
    b.text = value
    b.add_theme_font_override("font", _body_font)
    b.add_theme_font_size_override("font_size", 15)
    b.add_theme_color_override("font_color", color)
    h.add_child(b)
    _stats.add_child(h)


func _pct(v: float) -> String:
    return "%+d%%" % int(round(v * 100.0))


func _build_stats() -> void:
    var p := player
    _group("ATTRIBUTES")
    _row("Max health", "%d" % int(p.max_hp))
    _row("Armour", "%d" % int(p.stat("armor")))
    _row("Dodge", "%d%%" % int(p.stat("dodge") * 100.0))
    _row("Regeneration", "%.1f / s" % p.stat("regen"))
    _row("Move speed", "%d  (%s, weight %d / %d)" % [int(p.move_speed()), _pct(p.stat("speed")), p.total_weight(), p.weight_capacity])
    _group("OFFENSE")
    _row("Damage", _pct(p.stat("dmg")))
    _row("Attack speed", _pct(p.stat("fire_rate")))
    _row("Critical chance", "%d%%" % int(p.stat("crit") * 100.0))
    _row("Critical damage", "x%.2f" % (2.0 + p.stat("crit_dmg")))
    _row("Projectiles", "%+d" % int(p.stat("proj_count")))
    _row("Pierce", "%+d" % int(p.stat("pierce")))
    _row("Range", _pct(p.stat("range")))
    _row("Projectile speed", _pct(p.stat("proj_speed")))
    _row("Reaction potency", _pct(p.stat("potency")))
    _group("ELEMENTS")
    var any := false
    for e in Element.ALL:
        var k: String = Items.ELEMENT_KEYS[e]
        var d := p.stat("dmg_" + k)
        var pot := p.stat("potency_" + k)
        if d != 0.0 or pot != 0.0:
            any = true
            _row(Element.NAMES[e], "damage %s, potency %s" % [_pct(d), _pct(pot)], Element.COLORS[e])
    if not any:
        _row("All elements", "no bonuses yet")
    _row("Element duration", _pct(p.stat("state_duration")))
    _row("Chain jumps", "%d" % (6 + int(p.stat("chain_jumps"))))
    _group("PRESSURE & VENT")
    _row("Pressure limit", "%d" % int(p.pressure_limit()))
    _row("Pressure decay", _pct(p.stat("pressure_decay")))
    _row("Vent radius / power", "%s / %s" % [_pct(p.stat("vent_radius")), _pct(p.stat("vent_power"))])
    _row("Focus gain", _pct(p.stat("focus_gain")))
    _group("SUSTAIN & ECONOMY")
    _row("Lifesteal", "%.0f HP per reaction" % p.stat("lifesteal"))
    _row("Thorns", "%d" % int(p.stat("thorns")))
    _row("Scrap gain", _pct(p.stat("scrap_gain")))
    _group("SET BONUSES")
    var counts := Items.set_counts(p)
    if counts.is_empty():
        _row("None", "wear pieces of one family")
    for sid in counts.keys():
        var s: Dictionary = Items.SETS[sid]
        var thresholds: Array = s["bonuses"].keys()
        thresholds.sort()
        var parts: Array = []
        for t in thresholds:
            var active: bool = counts[sid] >= int(t)
            var bits: Array = []
            for k in s["bonuses"][t].keys():
                bits.append(_describe_stat(k, float(s["bonuses"][t][k])))
            parts.append("%s(%d) %s" % ["* " if active else "", t, ", ".join(bits)])
        _row("%s  %d / %d" % [s["name"], counts[sid], s["items"].size()], "\n".join(parts), Color(0.6, 1.0, 0.75) if counts[sid] >= 2 else UiTheme.BONE)


static func _describe_stat(key: String, v: float) -> String:
    var pct := "%+d%%" % int(round(v * 100.0))
    if key.begins_with("dmg_"):
        return "%s %s damage" % [pct, key.substr(4).capitalize()]
    if key.begins_with("potency_"):
        return "%s %s potency" % [pct, key.substr(8).capitalize()]
    match key:
        "dmg": return "%s damage" % pct
        "state_duration": return "%s element duration" % pct
        "lifesteal": return "%d HP per reaction" % int(v)
        "chain_jumps": return "+%d chain jumps" % int(v)
        "crit": return "%s crit" % pct
        "crit_dmg": return "+%.1fx crit damage" % v
        "vs_burning": return "%s vs burning" % pct
        "vs_frozen": return "%s vs frozen" % pct
        "vs_oiled": return "%s vs oiled" % pct
        "armor": return "+%d armour" % int(v)
        "speed": return "%s move speed" % pct
        "scrap_gain": return "%s scrap" % pct
        "carry": return "+%d carry" % int(v)
        "pressure_limit": return "+%d pressure limit" % int(v)
        "max_hp": return "+%d max HP" % int(v)
        "regen": return "+%.0f regen" % v
        "range": return "%s range" % pct
        "proj_speed": return "%s projectile speed" % pct
    return "%s %s" % [key, pct]
