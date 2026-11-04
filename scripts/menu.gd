extends Control
## Main menu: play, journal (achievements, arsenal, gear), wipe save, quit.
## Keyboard, mouse and controller all work; pads are polled directly through MenuPad.

var _root: VBoxContainer
var _journal: Journal
var _journal_center: CenterContainer
var _wipe_armed := false
var _wipe_button: Button
var _title_time := 0.0
var _pad := MenuPad.new()


func _ready() -> void:
    # The scene root does not inherit the window size by itself; size it explicitly.
    size = get_viewport_rect().size
    get_viewport().size_changed.connect(func(): size = get_viewport_rect().size)
    theme = UiTheme.make()
    RenderingServer.set_default_clear_color(Art.CLEAR)
    MenuPad.strip_joypad_from_ui_actions()
    _pad.on_cancel = _on_cancel
    _pad.on_tab = func(step: int):
        if _journal.visible:
            _journal.set_tab(_journal.tab + step)
    _build_main()
    _build_journal()
    _journal.visible = false
    if OS.get_cmdline_user_args().has("--menu-shot"):
        Progress.save_path = "user://save_autotest.json"
        Progress.load_save()
        _menu_shot()


func _process(delta: float) -> void:
    _title_time += delta
    queue_redraw()
    _pad.poll(get_viewport(), delta)
    if _journal.visible and Input.is_action_just_pressed("ui_cancel"):
        _show_main()


func _on_cancel() -> void:
    if _journal.visible:
        _show_main()


func _draw() -> void:
    var vp := get_viewport_rect().size
    draw_texture_rect(Art.FLOOR, Rect2(Vector2.ZERO, vp), true, Color(0.10, 0.09, 0.10))
    var rng := RandomNumberGenerator.new()
    rng.seed = 7
    var decals: Array = Art.TILES["decals"]
    for i in 24:
        var t: AtlasTexture = Art.tile(decals[rng.randi() % decals.size()])
        var p := Vector2(rng.randf() * vp.x, rng.randf() * vp.y)
        draw_texture_rect(t, Rect2(p, Vector2(48, 48)), false, Color(0.25, 0.22, 0.24))
    var glow: Texture2D = Art.PARTICLES["light"]
    for i in 5:
        var k: int = [Element.Kind.WET, Element.Kind.SHOCK, Element.Kind.FIRE, Element.Kind.ICE, Element.Kind.OIL][i]
        var c: Color = Element.COLORS[k]
        c.a = 0.10 + 0.05 * sin(_title_time * 0.7 + i)
        var x := vp.x / 2.0 + cos(_title_time * 0.25 + i * 1.26) * 260.0
        var y := 130.0 + sin(_title_time * 0.4 + i * 0.9) * 40.0
        draw_texture_rect(glow, Rect2(Vector2(x - 180, y - 180), Vector2(360, 360)), false, c)
    draw_string(Art.FONT, Vector2(0, 150), "PRESSURE", HORIZONTAL_ALIGNMENT_CENTER, vp.x, 110, UiTheme.BONE)
    draw_string(Art.FONT, Vector2(0, 185), "a co-op reaction dungeon", HORIZONTAL_ALIGNMENT_CENTER, vp.x, 24, UiTheme.DIM)
    var stats := "Runs %d   Won %d   Achievements %d / %d   Guns %d / %d" % [
        Progress.stat("runs_started"), Progress.stat("runs_won"),
        Progress.achievements_count(), Progress.ACHIEVEMENTS.size(),
        Guns.ids().size(), Guns.all_ids().size()]
    draw_string(Art.FONT, Vector2(0, vp.y - 24), stats, HORIZONTAL_ALIGNMENT_CENTER, vp.x, 18, UiTheme.DIM)


func _build_main() -> void:
    var center := CenterContainer.new()
    center.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(center)
    _root = VBoxContainer.new()
    _root.add_theme_constant_override("separation", 12)
    center.add_child(_root)
    var spacer := Control.new()
    spacer.custom_minimum_size = Vector2(0, 140)
    _root.add_child(spacer)
    var play := UiTheme.button("Play", _on_play)
    _root.add_child(play)
    _root.add_child(UiTheme.button("Journal", _show_journal))
    _wipe_button = UiTheme.button("Wipe save", _on_wipe)
    _root.add_child(_wipe_button)
    _root.add_child(UiTheme.button("Quit", func(): get_tree().quit()))
    play.grab_focus()


func _build_journal() -> void:
    _journal_center = CenterContainer.new()
    _journal_center.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(_journal_center)
    _journal = Journal.new(_show_main)
    _journal_center.add_child(_journal)


func _show_journal() -> void:
    Sfx.play("ui_open")
    _root.visible = false
    _journal.visible = true
    _journal.set_tab(_journal.tab)


func _show_main() -> void:
    _journal.visible = false
    _root.visible = true
    (_root.get_child(1) as Button).grab_focus()


func _on_play() -> void:
    Sfx.play("ui_confirm")
    get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_wipe() -> void:
    if not _wipe_armed:
        _wipe_armed = true
        _wipe_button.text = "Really wipe? (press again)"
        return
    Progress.reset()
    _wipe_armed = false
    _wipe_button.text = "Wipe save"
    Sfx.play("ui_back")


## Test hook: save screenshots of the menu and each journal tab, then quit.
func _menu_shot() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://autotest"))
    await get_tree().create_timer(0.8).timeout
    await RenderingServer.frame_post_draw
    get_viewport().get_texture().get_image().save_png("res://autotest/menu.png")
    _show_journal()
    for i in Journal.TABS.size():
        _journal.set_tab(i)
        await get_tree().create_timer(0.3).timeout
        await RenderingServer.frame_post_draw
        get_viewport().get_texture().get_image().save_png("res://autotest/journal_%d.png" % i)
    get_tree().quit()
