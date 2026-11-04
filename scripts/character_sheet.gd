class_name CharacterSheet
extends PanelContainer
## One player's gear, set bonuses and every computed stat. Opened from the pause menu,
## or straight into it with C or the pad's Back button.

var on_close: Callable
var player: Player
var _title: Label
var _columns: HBoxContainer
var _left: VBoxContainer
var _right: VBoxContainer
var _back: Button


func _init(p_on_close: Callable) -> void:
    on_close = p_on_close


func _ready() -> void:
    custom_minimum_size = Vector2(1000, 640)
    var v := VBoxContainer.new()
    v.add_theme_constant_override("separation", 6)
    add_child(v)
    _title = UiTheme.label("CHARACTER", 40)
    v.add_child(_title)
    v.add_child(UiTheme.label("LB / RB  or  Q / E  other player      B / Esc back", 15, UiTheme.DIM))
    var scroll := ScrollContainer.new()
    scroll.custom_minimum_size = Vector2(960, 470)
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    v.add_child(scroll)
    _columns = HBoxContainer.new()
    _columns.add_theme_constant_override("separation", 30)
    scroll.add_child(_columns)
    _left = VBoxContainer.new()
    _left.custom_minimum_size = Vector2(440, 0)
    _columns.add_child(_left)
    _right = VBoxContainer.new()
    _right.custom_minimum_size = Vector2(460, 0)
    _columns.add_child(_right)
    _back = UiTheme.button("Back", func(): on_close.call())
    v.add_child(_back)


func show_player(p: Player) -> void:
    player = p
    _title.text = "P%d   CHARACTER" % (p.index + 1)
    _title.add_theme_color_override("font_color", p.color)
    for c in _left.get_children():
        c.queue_free()
    for c in _right.get_children():
        c.queue_free()
    _fill_gear()
    _fill_stats()
    _back.grab_focus()


func _line(parent: VBoxContainer, text: String, color: Color = UiTheme.BONE, size: int = 17) -> void:
    var l := UiTheme.label(text, size, color)
    l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    parent.add_child(l)


func _fill_gear() -> void:
    _line(_left, "GEAR", UiTheme.FOCUS, 22)
    for key in Player.EQUIP_KEYS:
        var slot_name: String = key.rstrip("12")
        if player.equipment.has(key):
            var it := Items.get_item(player.equipment[key])
            var set_tag := ""
            var sid := Items.set_of(it["id"])
            if sid != "":
                set_tag = "   [%s]" % Items.SETS[sid]["name"]
            _line(_left, "%s:  %s%s\n      %s" % [slot_name, it["name"], set_tag, it["desc"]], Items.rarity_color(it))
        else:
            _line(_left, "%s:  -" % slot_name, Color(0.45, 0.42, 0.45))
    _line(_left, "", UiTheme.DIM)
    _line(_left, "GUNS", UiTheme.FOCUS, 22)
    if player.guns.is_empty():
        _line(_left, "none", Color(0.45, 0.42, 0.45))
    for g in player.guns:
        var mod_text := "no mod"
        var col: Color = g.data.color()
        if g.mod != "":
            var m := Items.get_item(g.mod)
            mod_text = "%s: %s" % [m["name"], m["desc"]]
        var tag := "   (trigger)" if g == player.primary else ""
        _line(_left, "%s%s   %.1f shots/s   %d weight\n      %s" % [g.data.display_name, tag, g.fire_rate(), g.data.weight, mod_text], col)
    _line(_left, "", UiTheme.DIM)
    _line(_left, "SET BONUSES", UiTheme.FOCUS, 22)
    var counts := Items.set_counts(player)
    if counts.is_empty():
        _line(_left, "none (wear pieces of a matching family)", Color(0.45, 0.42, 0.45))
    for sid in counts.keys():
        var s: Dictionary = Items.SETS[sid]
        _line(_left, "%s  %d / %d pieces" % [s["name"], counts[sid], s["items"].size()], UiTheme.BONE, 18)
        var thresholds: Array = s["bonuses"].keys()
        thresholds.sort()
        for t in thresholds:
            var active: bool = counts[sid] >= int(t)
            var parts: Array = []
            for k in s["bonuses"][t].keys():
                parts.append(_describe_stat(k, float(s["bonuses"][t][k])))
            _line(_left, "   %s (%d)  %s" % ["[x]" if active else "[ ]", t, ", ".join(parts)], Color(0.6, 1.0, 0.75) if active else Color(0.5, 0.48, 0.5), 15)


func _fill_stats() -> void:
    var p := player
    _line(_right, "STATS", UiTheme.FOCUS, 22)
    var rows: Array = [
        ["Max HP", "%d" % int(p.max_hp)],
        ["Armour", "%d" % int(p.stat("armor"))],
        ["Dodge", "%d%%" % int(p.stat("dodge") * 100.0)],
        ["Regen", "%.1f / s" % p.stat("regen")],
        ["Move speed", "%d px/s  (%+d%%, weight %d/%d)" % [int(p.move_speed()), int(p.stat("speed") * 100.0), p.total_weight(), p.weight_capacity]],
        ["", ""],
        ["Damage", "%+d%%" % int(p.stat("dmg") * 100.0)],
        ["Attack speed", "%+d%%" % int(p.stat("fire_rate") * 100.0)],
        ["Crit chance", "%d%%" % int(p.stat("crit") * 100.0)],
        ["Crit damage", "x%.2f" % (2.0 + p.stat("crit_dmg"))],
        ["Projectiles", "%+d" % int(p.stat("proj_count"))],
        ["Pierce", "%+d" % int(p.stat("pierce"))],
        ["Range", "%+d%%" % int(p.stat("range") * 100.0)],
        ["Projectile speed", "%+d%%" % int(p.stat("proj_speed") * 100.0)],
        ["", ""],
        ["Reaction potency", "%+d%%" % int(p.stat("potency") * 100.0)],
        ["Wet / Shock / Fire", "%+d%% / %+d%% / %+d%%" % [int(p.stat("dmg_wet") * 100.0), int(p.stat("dmg_shock") * 100.0), int(p.stat("dmg_fire") * 100.0)]],
        ["Ice / Oil", "%+d%% / %+d%%" % [int(p.stat("dmg_ice") * 100.0), int(p.stat("dmg_oil") * 100.0)]],
        ["State duration", "%+d%%" % int(p.stat("state_duration") * 100.0)],
        ["Chain jumps", "%d" % (6 + int(p.stat("chain_jumps")))],
        ["Lifesteal", "%.0f HP per reaction" % p.stat("lifesteal")],
        ["Thorns", "%d" % int(p.stat("thorns"))],
        ["", ""],
        ["Pressure limit", "%d" % int(p.pressure_limit())],
        ["Pressure decay", "%+d%%" % int(p.stat("pressure_decay") * 100.0)],
        ["Vent radius / power", "%+d%% / %+d%%" % [int(p.stat("vent_radius") * 100.0), int(p.stat("vent_power") * 100.0)]],
        ["Focus gain", "%+d%%" % int(p.stat("focus_gain") * 100.0)],
        ["Scrap gain", "%+d%%" % int(p.stat("scrap_gain") * 100.0)],
    ]
    var grid := GridContainer.new()
    grid.columns = 2
    grid.add_theme_constant_override("h_separation", 24)
    grid.add_theme_constant_override("v_separation", 2)
    _right.add_child(grid)
    for r in rows:
        var a := UiTheme.label(r[0], 16, UiTheme.DIM)
        a.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
        a.custom_minimum_size = Vector2(190, 0)
        grid.add_child(a)
        var b := UiTheme.label(r[1], 16, UiTheme.BONE)
        b.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
        grid.add_child(b)


static func _describe_stat(key: String, v: float) -> String:
    var pct := "%+d%%" % int(v * 100.0)
    match key:
        "dmg": return "%s damage" % pct
        "dmg_wet": return "%s Wet damage" % pct
        "dmg_shock": return "%s Shock damage" % pct
        "dmg_fire": return "%s Fire damage" % pct
        "dmg_ice": return "%s Ice damage" % pct
        "dmg_oil": return "%s Oil damage" % pct
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
    return "%s %s" % [key, pct]
