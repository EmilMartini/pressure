extends Control
## Main menu: play, codex (achievements and unlocks), wipe save, quit.
## Keyboard, mouse and controller all work through Godot's ui_* actions.

var _root: VBoxContainer
var _codex: PanelContainer
var _codex_center: CenterContainer
var _wipe_armed := false
var _wipe_button: Button
var _title_time := 0.0


func _ready() -> void:
    # The scene root does not inherit the window size by itself; size it explicitly.
    size = get_viewport_rect().size
    get_viewport().size_changed.connect(func(): size = get_viewport_rect().size)
    theme = UiTheme.make()
    RenderingServer.set_default_clear_color(Art.CLEAR)
    _build_main()
    _build_codex()
    _codex.visible = false
    if OS.get_cmdline_user_args().has("--menu-shot"):
        _menu_shot()


## Test hook: save screenshots of the menu and the codex, then quit.
func _menu_shot() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://autotest"))
    await get_tree().create_timer(0.8).timeout
    await RenderingServer.frame_post_draw
    get_viewport().get_texture().get_image().save_png("res://autotest/menu.png")
    _show_codex()
    await get_tree().create_timer(0.3).timeout
    await RenderingServer.frame_post_draw
    get_viewport().get_texture().get_image().save_png("res://autotest/codex.png")
    get_tree().quit()


func _process(delta: float) -> void:
    _title_time += delta
    queue_redraw()
    if _codex.visible and Input.is_action_just_pressed("ui_cancel"):
        _show_main()


func _draw() -> void:
    var vp := get_viewport_rect().size
    # Dark stone backdrop, a few decals, vignette.
    draw_texture_rect(Art.FLOOR, Rect2(Vector2.ZERO, vp), true, Color(0.10, 0.09, 0.10))
    var rng := RandomNumberGenerator.new()
    rng.seed = 7
    var decals: Array = Art.TILES["decals"]
    for i in 24:
        var t: AtlasTexture = Art.tile(decals[rng.randi() % decals.size()])
        var p := Vector2(rng.randf() * vp.x, rng.randf() * vp.y)
        draw_texture_rect(t, Rect2(p, Vector2(48, 48)), false, Color(0.25, 0.22, 0.24))
    # Element glow that drifts behind the title.
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
    _root.add_child(UiTheme.button("Codex", _show_codex))
    _wipe_button = UiTheme.button("Wipe save", _on_wipe)
    _root.add_child(_wipe_button)
    _root.add_child(UiTheme.button("Quit", func(): get_tree().quit()))
    play.grab_focus()


func _build_codex() -> void:
    if _codex_center == null:
        _codex_center = CenterContainer.new()
        _codex_center.set_anchors_preset(Control.PRESET_FULL_RECT)
        add_child(_codex_center)
    _codex = PanelContainer.new()
    _codex.custom_minimum_size = Vector2(820, 560)
    _codex_center.add_child(_codex)
    var v := VBoxContainer.new()
    v.add_theme_constant_override("separation", 6)
    _codex.add_child(v)
    v.add_child(UiTheme.label("CODEX", 40))
    v.add_child(UiTheme.label("Every run starts naked. These grow what a run can hold.", 18, UiTheme.DIM))
    var scroll := ScrollContainer.new()
    scroll.custom_minimum_size = Vector2(780, 380)
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    v.add_child(scroll)
    var list := VBoxContainer.new()
    list.add_theme_constant_override("separation", 4)
    scroll.add_child(list)
    for a in Progress.ACHIEVEMENTS:
        var done: bool = Progress.achievements_done.has(a["id"])
        var rewards: Array = []
        for r in a["rewards"]:
            rewards.append(Progress.unlock_label(r))
        var progress := mini(Progress.stat(a["stat"]), a["goal"])
        var text := "%s  %s   %d / %d\n    %s   ->   %s" % [
            "[x]" if done else "[ ]", a["name"], progress, a["goal"], a["desc"], ", ".join(rewards)]
        var l := UiTheme.label(text, 18, Color(0.6, 1.0, 0.75) if done else UiTheme.BONE)
        l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
        list.add_child(l)
    var back := UiTheme.button("Back", _show_main)
    v.add_child(back)


func _show_codex() -> void:
    _root.visible = false
    _codex.visible = true
    # Rebuild so progress is current.
    _codex.queue_free()
    _build_codex()
    (_codex.get_child(0).get_child(_codex.get_child(0).get_child_count() - 1) as Button).grab_focus()


func _show_main() -> void:
    _codex.visible = false
    _root.visible = true
    (_root.get_child(1) as Button).grab_focus()


func _on_play() -> void:
    Sfx.play("ui_confirm")
    get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_wipe() -> void:
    if not _wipe_armed:
        _wipe_armed = true
        _wipe_button.text = "Really wipe? (click again)"
        return
    Progress.reset()
    _wipe_armed = false
    _wipe_button.text = "Wipe save"
    Sfx.play("ui_back")
