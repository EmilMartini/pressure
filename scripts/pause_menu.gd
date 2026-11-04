class_name PauseMenu
extends CanvasLayer
## Pause overlay: Escape or Start on a joined pad. Keeps processing while the tree
## is paused so it can resume. Also used as the run-over menu.

var main: Main
var _panel: PanelContainer
var _title: Label
var _summary: Label
var _resume: Button
var _start_was_down: Dictionary = {}
var _test_clock := -1.0


## Test hook: open, screenshot after a second, close.
func show_for_test() -> void:
    show_menu()
    _test_clock = 0.0


func _init(p_main: Main) -> void:
    main = p_main
    layer = 50
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
    _panel.custom_minimum_size = Vector2(560, 460)
    center.add_child(_panel)
    var v := VBoxContainer.new()
    v.add_theme_constant_override("separation", 10)
    _panel.add_child(v)
    _title = UiTheme.label("PAUSED", 44)
    v.add_child(_title)
    _summary = UiTheme.label("", 18, UiTheme.DIM)
    _summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _summary.custom_minimum_size = Vector2(500, 0)
    v.add_child(_summary)
    _resume = UiTheme.button("Resume", hide_menu)
    v.add_child(_resume)
    v.add_child(UiTheme.button("Restart run", func():
        Sfx.play("ui_confirm")
        get_tree().paused = false
        get_tree().reload_current_scene()))
    v.add_child(UiTheme.button("Main menu", func():
        Sfx.play("ui_back")
        get_tree().paused = false
        get_tree().change_scene_to_file("res://scenes/menu.tscn")))
    v.add_child(UiTheme.button("Quit game", func(): get_tree().quit()))
    visible = false


func _process(delta: float) -> void:
    if _test_clock >= 0.0:
        _test_clock += delta
        if _test_clock > 1.0 and _test_clock - delta <= 1.0:
            await RenderingServer.frame_post_draw
            get_viewport().get_texture().get_image().save_png("res://autotest/pause.png")
        if _test_clock > 1.6:
            _test_clock = -1.0
            hide_menu()
        return
    var toggle := Input.is_action_just_pressed("ui_cancel")
    for d in Input.get_connected_joypads():
        if not main.is_device_joined(d):
            continue
        var down := Input.is_joy_button_pressed(d, JOY_BUTTON_START)
        if down and not _start_was_down.get(d, false):
            toggle = true
        _start_was_down[d] = down
    if toggle:
        if visible:
            hide_menu()
        else:
            show_menu()


func show_menu() -> void:
    _title.text = "RUN OVER" if main.game_over else ("DUNGEON CLEARED" if main.victory else "PAUSED")
    _summary.text = ""
    if main.game_over or main.victory:
        var lines: Array = ["Floor %d   %d kills   %d scrap" % [main.floor_number, main.total_kills, main.scrap]]
        if not Progress.run_unlocks.is_empty():
            var names: Array = []
            for u in Progress.run_unlocks:
                names.append(Progress.unlock_label(u))
            lines.append("Unlocked: " + ", ".join(names))
        for g in Progress.next_goals(3):
            lines.append("Next: %s  %d / %d  (%s)" % [g["name"], g["progress"], g["goal"], g["desc"]])
        _summary.text = "\n".join(lines)
    _resume.text = "Continue" if (main.game_over or main.victory) else "Resume"
    visible = true
    get_tree().paused = true
    Sfx.play("ui_open")
    _resume.grab_focus()


func hide_menu() -> void:
    visible = false
    get_tree().paused = false
    Sfx.play("ui_back")
