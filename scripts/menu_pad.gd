class_name MenuPad
extends RefCounted
## Controller navigation for menus. Any connected pad moves focus with the d-pad or the
## left stick, A presses the focused button, B calls `on_cancel`, the shoulders call
## `on_tab`. Joypad events are stripped from the ui_* actions so nothing is handled twice.

const REPEAT_DELAY := 0.4
const REPEAT_RATE := 0.12

var on_cancel: Callable
var on_tab: Callable
var _was: Dictionary = {}
var _held: Dictionary = {}


static func strip_joypad_from_ui_actions() -> void:
    for action in ["ui_accept", "ui_cancel", "ui_up", "ui_down", "ui_left", "ui_right", "ui_focus_next", "ui_focus_prev"]:
        if not InputMap.has_action(action):
            continue
        for ev in InputMap.action_get_events(action):
            if ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
                InputMap.action_erase_event(action, ev)


func poll(viewport: Viewport, delta: float) -> void:
    var up := false
    var down := false
    var left := false
    var right := false
    var accept := false
    var cancel := false
    for d in Input.get_connected_joypads():
        var ay := Input.get_joy_axis(d, JOY_AXIS_LEFT_Y)
        up = up or Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_UP) or ay < -0.55
        down = down or Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_DOWN) or ay > 0.55
        left = left or Input.is_joy_button_pressed(d, JOY_BUTTON_LEFT_SHOULDER) or Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_LEFT)
        right = right or Input.is_joy_button_pressed(d, JOY_BUTTON_RIGHT_SHOULDER) or Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_RIGHT)
        accept = accept or Input.is_joy_button_pressed(d, JOY_BUTTON_A)
        cancel = cancel or Input.is_joy_button_pressed(d, JOY_BUTTON_B)
    var focus := viewport.gui_get_focus_owner()
    if _edge("up", up, delta, true) and focus != null:
        var n := focus.find_prev_valid_focus()
        if n != null:
            n.grab_focus()
            Sfx.play("ui_move")
    if _edge("down", down, delta, true) and focus != null:
        var n := focus.find_next_valid_focus()
        if n != null:
            n.grab_focus()
            Sfx.play("ui_move")
    if _edge("left", left, delta, false) and on_tab.is_valid():
        on_tab.call(-1)
    if _edge("right", right, delta, false) and on_tab.is_valid():
        on_tab.call(1)
    if _edge("accept", accept, delta, false) and focus is BaseButton:
        focus.pressed.emit()
    if _edge("cancel", cancel, delta, false) and on_cancel.is_valid():
        on_cancel.call()


## True on the press, and again on repeat while held when `repeat` is set.
## True while any connected pad holds a shoulder button (for screens where the d-pad
## means something else and only LB/RB should switch tabs or players).
func shoulder_held() -> bool:
    for d in Input.get_connected_joypads():
        if Input.is_joy_button_pressed(d, JOY_BUTTON_LEFT_SHOULDER) or Input.is_joy_button_pressed(d, JOY_BUTTON_RIGHT_SHOULDER):
            return true
    return false


func _edge(key: String, down: bool, delta: float, repeat: bool) -> bool:
    var was: bool = _was.get(key, false)
    _was[key] = down
    if not down:
        _held[key] = 0.0
        return false
    if not was:
        _held[key] = 0.0
        return true
    if not repeat:
        return false
    var h: float = _held.get(key, 0.0) + delta
    if h >= REPEAT_DELAY:
        _held[key] = h - REPEAT_RATE
        return true
    _held[key] = h
    return false
