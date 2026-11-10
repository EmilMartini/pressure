class_name PauseMenu
extends CanvasLayer
## Pause overlay: Escape or Start on a joined pad. Keeps processing while the tree
## is paused so it can resume. Also used as the run-over menu.

var main: Main
var _panel: PanelContainer
var _title: Label
var _summary: Label
var _report: VBoxContainer
var _resume: Button
var _options: OptionsMenu
var _options_center: CenterContainer
var _options_closed_ms := -100000
var _run_start_ms := 0
var _journal: Journal
var _journal_center: CenterContainer
var _sheet: CharacterSheet
var _sheet_center: CenterContainer
var _sheet_direct := false   # opened with a hotkey: closing it resumes play
var _start_was_down: Dictionary = {}
var _test_clock := -1.0
var _test_path := "res://autotest/pause.png"
var _pad := MenuPad.new()


## Test hook: open (the pause panel, or a player's sheet), screenshot after a second, close.
func show_for_test(path: String = "res://autotest/pause.png", sheet_player: Player = null) -> void:
    _test_path = path
    if sheet_player != null:
        show_sheet(sheet_player, true)
    else:
        show_menu()
    _test_clock = 0.0


func _init(p_main: Main) -> void:
    main = p_main
    _run_start_ms = Time.get_ticks_msec()
    layer = 50   # above the post-process (1), the Crisp world text (2) and the HUD (3)
    process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
    var root := Control.new()
    root.set_anchors_preset(Control.PRESET_FULL_RECT)
    root.theme = UiTheme.make()
    add_child(root)
    var dim := ColorRect.new()
    dim.color = Color(0, 0, 0, 0.6)
    dim.set_anchors_preset(Control.PRESET_FULL_RECT)
    root.add_child(dim)
    var center := CenterContainer.new()
    center.set_anchors_preset(Control.PRESET_FULL_RECT)
    root.add_child(center)
    _panel = PanelContainer.new()
    _panel.custom_minimum_size = Vector2(440, 0)
    center.add_child(_panel)
    var outer := VBoxContainer.new()
    outer.add_theme_constant_override("separation", 8)
    _panel.add_child(outer)
    _title = UiTheme.label("PAUSED", 44)
    outer.add_child(_title)
    _summary = UiTheme.label("", 20, UiTheme.DIM)
    _summary.visible = false
    outer.add_child(_summary)
    var cols := HBoxContainer.new()
    cols.add_theme_constant_override("separation", 24)
    outer.add_child(cols)
    # Run over: what happened, what it unlocked, what is next. Hidden while paused.
    _report = VBoxContainer.new()
    _report.add_theme_constant_override("separation", 4)
    _report.custom_minimum_size = Vector2(640, 0)
    _report.visible = false
    cols.add_child(_report)
    var v := VBoxContainer.new()
    v.add_theme_constant_override("separation", 10)
    v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    cols.add_child(v)
    _resume = UiTheme.button("Resume", _on_resume)
    v.add_child(_resume)
    v.add_child(UiTheme.button("Character", func(): show_sheet(main.players[0], false)))
    v.add_child(UiTheme.button("Journal", _show_journal))
    v.add_child(UiTheme.button("Options", _show_options))
    _sheet_center = CenterContainer.new()
    _sheet_center.set_anchors_preset(Control.PRESET_FULL_RECT)
    root.add_child(_sheet_center)
    _sheet = CharacterSheet.new(_hide_sheet)
    _sheet_center.add_child(_sheet)
    _sheet.visible = false
    _journal_center = CenterContainer.new()
    _journal_center.set_anchors_preset(Control.PRESET_FULL_RECT)
    root.add_child(_journal_center)
    _journal = Journal.new(_hide_journal)
    _journal_center.add_child(_journal)
    _journal.visible = false
    _options_center = CenterContainer.new()
    _options_center.set_anchors_preset(Control.PRESET_FULL_RECT)
    root.add_child(_options_center)
    _options = OptionsMenu.new(_hide_options)
    _options_center.add_child(_options)
    _options_center.visible = false
    MenuPad.strip_joypad_from_ui_actions()
    _pad.on_cancel = func():
        if _sheet.visible:
            _hide_sheet()
        elif _journal.visible:
            _hide_journal()
        elif visible:
            hide_menu()
    _pad.on_tab = func(step: int):
        if _journal.visible:
            _journal.set_tab(_journal.tab + step)
        elif _sheet.visible and _pad.shoulder_held():
            _cycle_sheet(step)   # the sheet walks its grid with the d-pad; shoulders switch player
    v.add_child(UiTheme.button("Restart run", func():
        Sfx.play("ui_confirm")
        main.abandon_run()   # leaving a run pays 75% of a death's Embers (Core loop reset 11.2)
        get_tree().paused = false
        get_tree().reload_current_scene()))
    v.add_child(UiTheme.button("Return to hub", func():
        Sfx.play("ui_back")
        main.return_to_hub()))
    v.add_child(UiTheme.button("Quit game", func():
        main.abandon_run()
        get_tree().quit()))
    visible = false


func _process(delta: float) -> void:
    if _test_clock >= 0.0:
        _test_clock += delta
        if _test_clock > 1.0 and _test_clock - delta <= 1.0:
            await RenderingServer.frame_post_draw
            get_viewport().get_texture().get_image().save_png(_test_path)
        if _test_clock > 1.6:
            _test_clock = -1.0
            hide_menu()
        return
    if _options_center.visible:
        return   # the options card polls pads and handles Esc itself
    if Time.get_ticks_msec() - _options_closed_ms < 200:
        return   # the Esc / B that closed the options card must not also close the pause
    if visible:
        _pad.poll(get_viewport(), delta)
    if main.gun_pick != null and main.gun_pick.is_open():
        return   # Escape there means "leave the mod", not "pause"
    var toggle := Input.is_action_just_pressed("ui_cancel")
    for d in Input.get_connected_joypads():
        if not main.is_device_joined(d):
            continue
        var down := Input.is_joy_button_pressed(d, JOY_BUTTON_START)
        if down and not _start_was_down.get(d, false):
            toggle = true
        _start_was_down[d] = down
    if toggle:
        if _sheet.visible:
            _hide_sheet()
        elif _journal.visible:
            _hide_journal()
        elif visible:
            hide_menu()
        else:
            show_menu()


func _input(event: InputEvent) -> void:
    if not _sheet.visible or not event is InputEventKey or not event.pressed or event.echo:
        return
    match (event as InputEventKey).physical_keycode:
        KEY_Q:
            _cycle_sheet(-1)
        KEY_E:
            _cycle_sheet(1)


## Open a player's character sheet. `direct` means a hotkey opened it mid-run, so
## closing it resumes play instead of returning to the pause panel.
func show_sheet(p: Player, direct: bool) -> void:
    if not visible:
        show_menu()
    _sheet_direct = direct
    _panel.visible = false
    _journal.visible = false
    _sheet.visible = true
    _sheet.show_player(p)
    Music.duck(true)


func _hide_sheet() -> void:
    _sheet.visible = false
    if _sheet_direct:
        hide_menu()
    else:
        _panel.visible = true
        _resume.grab_focus()


func _cycle_sheet(step: int) -> void:
    if _sheet.player == null or main.players.size() < 2:
        return
    var i := wrapi(main.players.find(_sheet.player) + step, 0, main.players.size())
    _sheet.show_player(main.players[i])
    Sfx.play("ui_move")


func _show_journal() -> void:
    Sfx.play("ui_open")
    _panel.visible = false
    _journal.visible = true
    _journal.set_tab(_journal.tab)


func _hide_journal() -> void:
    _journal.visible = false
    _panel.visible = true
    _resume.grab_focus()


func _on_resume() -> void:
    if main.game_over or main.victory:
        Sfx.play("ui_confirm")
        main.return_to_hub()
    else:
        hide_menu()


func _show_options() -> void:
    Sfx.play("ui_open")
    _panel.visible = false
    _options_center.visible = true


func _hide_options() -> void:
    _options_center.visible = false
    _options_closed_ms = Time.get_ticks_msec()
    _panel.visible = true
    _resume.grab_focus()


const FANFARE := Color(1.0, 0.82, 0.35)
const UNLOCK_KINDS := {
    "gun": "a new gun in the pool",
    "class": "a new class at the Gate",
    "obstacle": "a new door obstacle",
    "room": "a new room type",
    "shop": "bigger shops",
    "rarity": "rarer gear can drop",
    "secret": "the dungeon hides more",
}


func _section(text: String) -> void:
    var l := UiTheme.label(text, 26, UiTheme.FOCUS)
    l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    _report.add_child(l)


func _line(text: String, color: Color, px: int = 22) -> void:
    var l := UiTheme.label(text, px, color)
    l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    l.custom_minimum_size = Vector2(640, 0)
    _report.add_child(l)


## The run-over report: This run / You unlocked / Next.
func _fill_report() -> void:
    for c in _report.get_children():
        c.queue_free()
    _section("THIS RUN")
    var secs: int = (Time.get_ticks_msec() - _run_start_ms) / 1000
    var lo := Loadout.current()
    var cls := Loadout.mark_name(String(lo["mark"])) + (", " + Loadout.kit_name(String(lo["kit"])) if String(lo["kit"]) != "" else "")
    var levels: Array = []
    for p in main.players:
        levels.append("%s lv %d" % [p.display_name(), p.level])
    _line("Floor %d of %d    %d kills    %d:%02d    %s    %s" % [main.floor_number, Main.FLOORS, main.total_kills, secs / 60, secs % 60, cls, "   ".join(levels)], UiTheme.BONE)
    if main.game_over:
        _death_recap()
    _section("YOU UNLOCKED")
    if Progress.run_unlocks.is_empty():
        _line("Nothing new this time. Every run still counts toward the goals below.", UiTheme.DIM, 20)
    for u in Progress.run_unlocks:
        var kind := String(u).split(":")[0]
        _line("%s   %s" % [Progress.unlock_label(u), UNLOCK_KINDS.get(kind, "")], FANFARE)
    _section("NEXT")
    for g in Hub.goal_rows(3):
        _report.add_child(Hub.goal_bar(g, 640.0))
    _section("EMBERS")
    var award: Dictionary = Mastery.last_award
    _line("+%d this run    %d to spend at the Shrine    %d earned in all" % [int(award.get("total", 0)), Mastery.embers, Mastery.earned], Mastery.EMBER_COLOR, 22)
    _line(Mastery.award_text(award), UiTheme.BONE, 20)
    var bounties: Array = award.get("bounties", [])
    if not bounties.is_empty():
        var kinds: Array = []
        for k in bounties:
            kinds.append(String(k).replace("_", " ").capitalize())
        _line("First kill with this class: %s" % ", ".join(kinds), FANFARE, 20)


const HURT_RED := Color(1.0, 0.32, 0.26)
const RECAP_WINDOW := 10.0


## Death recap: the blow that ended it, the last RECAP_WINDOW s of damage by source, and
## health over the last Player.RECAP_SECS with each hit marked. Player 1's (single player
## first); in co-op the last one standing, who fell last.
func _death_recap() -> void:
    var p: Player = null
    for pl in main.players:
        if is_instance_valid(pl) and (p == null or pl.life_t > p.life_t):
            p = pl
    if p == null:
        return
    var killer := Telemetry.source_name(p.killed_by) if p.killed_by != "" else "Unknown"
    _section("KILLED BY %s" % killer.to_upper())
    var by: Dictionary = {}
    var hits: Dictionary = {}
    var total := 0.0
    for h in p.hurt_log:
        if p.life_t - float(h[0]) > RECAP_WINDOW:
            continue
        var src := Telemetry.source_name(String(h[2]))
        by[src] = float(by.get(src, 0.0)) + float(h[1])
        hits[src] = int(hits.get(src, 0)) + 1
        total += float(h[1])
    var keys := by.keys()
    keys.sort_custom(func(a, b): return float(by[a]) > float(by[b]))
    var parts: Array = []
    for k in keys:
        parts.append("%s %d (%d hit%s)" % [k, roundi(float(by[k])), int(hits[k]), "" if int(hits[k]) == 1 else "s"])
    if parts.is_empty():
        _line("No damage in the last 10 s.", UiTheme.DIM, 20)
    else:
        _line("Last 10 s: %d damage.  %s" % [roundi(total), "   ".join(parts)], HURT_RED, 20)
    var graph := HpGraph.new()
    graph.player = p
    graph.custom_minimum_size = Vector2(640, 86)
    _report.add_child(graph)


## Health over the last 30 s as a line, the 35% low-health line, a red tick per hit.
class HpGraph extends Control:
    var player: Player

    func _draw() -> void:
        var r := Rect2(Vector2(0, 4), Vector2(size.x, size.y - 22.0))
        draw_rect(r, Color(0.04, 0.03, 0.05, 0.9))
        draw_rect(r, Color(1, 1, 1, 0.15), false, 1.0)
        if player == null or not is_instance_valid(player):
            return
        var now := player.life_t
        var span := Player.RECAP_SECS
        var low_y := r.end.y - r.size.y * Sfx.HEART_LOW
        draw_dashed_line(Vector2(r.position.x, low_y), Vector2(r.end.x, low_y), Color(1.0, 0.3, 0.25, 0.4), 1.0, 6.0)
        for h in player.hurt_log:
            var x := r.position.x + r.size.x * (1.0 - (now - float(h[0])) / span)
            if x < r.position.x:
                continue
            var tall := clampf(float(h[1]) / maxf(1.0, player.max_hp) * 4.0, 0.15, 1.0) * r.size.y
            draw_line(Vector2(x, r.end.y), Vector2(x, r.end.y - tall), Color(1.0, 0.25, 0.2, 0.55), 2.0)
        var pts := PackedVector2Array()
        for s in player.hp_trace:
            var x := r.position.x + r.size.x * (1.0 - (now - float(s[0])) / span)
            if x < r.position.x:
                continue
            pts.append(Vector2(x, r.end.y - r.size.y * float(s[1])))
        pts.append(Vector2(r.end.x, r.end.y))   # the fall to zero
        if pts.size() >= 2:
            draw_polyline(pts, Color(0.0, 0.0, 0.0, 0.7), 4.0)
            draw_polyline(pts, Color(0.95, 0.9, 0.85), 2.0)
        var f := get_theme_default_font()
        draw_string(f, Vector2(r.position.x, size.y - 3.0), "-30 s", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UiTheme.DIM)
        draw_string(f, Vector2(r.end.x - 120.0, size.y - 3.0), "death", HORIZONTAL_ALIGNMENT_RIGHT, 120.0, 15, UiTheme.DIM)
        draw_string(f, Vector2(r.position.x + 4.0, low_y - 3.0), "35%", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.4, 0.35, 0.7))


func show_menu() -> void:
    var over := main.game_over or main.victory
    _title.text = "RUN OVER" if main.game_over else ("DUNGEON CLEARED" if main.victory else "PAUSED")
    _title.add_theme_color_override("font_color", FANFARE if main.victory else UiTheme.BONE)
    _report.visible = over
    if over:
        _fill_report()
        if not Progress.run_unlocks.is_empty():
            Sfx.play("unlock")
    _resume.text = "Back to hub" if over else "Resume"
    visible = true
    get_tree().paused = true
    Sfx.play("ui_open")
    Music.duck(true)
    _resume.grab_focus()


func hide_menu() -> void:
    visible = false
    _journal.visible = false
    _sheet.visible = false
    _options_center.visible = false
    _panel.visible = true
    get_tree().paused = false
    Music.duck(false)
    Sfx.play("ui_back")
