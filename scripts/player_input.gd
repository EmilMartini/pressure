class_name PlayerInput
extends RefCounted
## Reads one player's input from a joypad, the keyboard + mouse, or both merged.
## Player 1 merges keyboard/mouse with joypad 0. Extra joypads join as new players.
## Nothing here touches the InputMap, so adding a player is just a new device id.

const STICK_DEADZONE := 0.22
const MOUSE_ACTIVE_SECONDS := 1.5

var device: int = -1          # joypad id, -1 = no joypad
var use_keyboard: bool = false

# Self-test overrides (see Main.autotest). Ignored during normal play.
var force_fire: bool = false
var force_move: Vector2 = Vector2.ZERO
var force_aim: Vector2 = Vector2.ZERO

var _prev: Dictionary = {}
var _cur: Dictionary = {}
var _last_mouse := Vector2.INF
var _mouse_active_until := 0.0

## "pad" or "kb": whichever this player touched last. Drives on-screen prompts.
var last_kind := "kb"
var _last_mouse_screen := Vector2i(-1, -1)

const PROMPTS := {
    "interact": ["A", "E"],
    "fire": ["RT", "LMB"],
    "vent": ["LB", "Space"],
    "swap": ["X", "Q"],
    "aim": ["Y", "Tab"],
    "pause": ["Start", "Esc"],
    "sheet": ["Back", "C"],
}
const PAD_BUTTONS := [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_LEFT_SHOULDER,
    JOY_BUTTON_RIGHT_SHOULDER, JOY_BUTTON_START, JOY_BUTTON_BACK, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN,
    JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT]
const KB_KEYS := [KEY_W, KEY_A, KEY_S, KEY_D, KEY_E, KEY_Q, KEY_TAB, KEY_SPACE, KEY_C, KEY_ESCAPE]


## The label to show for an action on this player's current device.
func prompt(action: String) -> String:
    var pair: Array = PROMPTS.get(action, ["?", "?"])
    return pair[0] if last_kind == "pad" else pair[1]


func _update_kind() -> void:
    var pad := false
    if device >= 0:
        pad = Vector2(Input.get_joy_axis(device, JOY_AXIS_LEFT_X), Input.get_joy_axis(device, JOY_AXIS_LEFT_Y)).length() > STICK_DEADZONE \
            or Vector2(Input.get_joy_axis(device, JOY_AXIS_RIGHT_X), Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y)).length() > STICK_DEADZONE \
            or Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT) > 0.5
        if not pad:
            for b in PAD_BUTTONS:
                if Input.is_joy_button_pressed(device, b):
                    pad = true
                    break
    var kb := false
    if use_keyboard:
        for k in KB_KEYS:
            if Input.is_physical_key_pressed(k):
                kb = true
                break
        if not kb:
            kb = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
        if not kb:
            var m := DisplayServer.mouse_get_position()
            if m != _last_mouse_screen and _last_mouse_screen.x >= 0:
                kb = true
            _last_mouse_screen = m
    if pad:
        last_kind = "pad"
    elif kb:
        last_kind = "kb"
    elif device >= 0 and not use_keyboard:
        last_kind = "pad"


func _init(p_device: int, p_keyboard: bool) -> void:
    device = p_device
    use_keyboard = p_keyboard


## Call once per physics frame before reading anything else.
func poll() -> void:
    _update_kind()
    _prev = _cur.duplicate()
    _cur = {
        "toggle_aim": _button(JOY_BUTTON_Y, KEY_TAB),
        "vent": _button(JOY_BUTTON_LEFT_SHOULDER, KEY_SPACE),
        "swap": _button(JOY_BUTTON_X, KEY_Q),
        "interact": _button(JOY_BUTTON_A, KEY_E),
        "start": _button(JOY_BUTTON_START, KEY_ENTER),
    }
    for action in _cur.keys():
        if _cur[action] and not _prev.get(action, false):
            _edges[action] = true


## True on the physics frame the named button went down.
func just_pressed(action: String) -> bool:
    return _cur.get(action, false) and not _prev.get(action, false)


## Like just_pressed, but each press is handed out once. Use this from _process code,
## which can run several times per physics tick and would otherwise see one press twice.
func take_pressed(action: String) -> bool:
    if _edges.has(action):
        _edges.erase(action)
        return true
    return false


var _edges: Dictionary = {}


func move_vector() -> Vector2:
    if force_move != Vector2.ZERO:
        return force_move.limit_length(1.0)
    var v := Vector2.ZERO
    if device >= 0:
        v = Vector2(
            Input.get_joy_axis(device, JOY_AXIS_LEFT_X),
            Input.get_joy_axis(device, JOY_AXIS_LEFT_Y))
        if v.length() < STICK_DEADZONE:
            v = Vector2.ZERO
    if use_keyboard and v == Vector2.ZERO:
        v = Vector2(
            _key(KEY_D) - _key(KEY_A),
            _key(KEY_S) - _key(KEY_W))
    return v.limit_length(1.0)


## Direction the player is aiming, or Vector2.ZERO when no aim input is active.
## `node` is any Node2D in the world, used for the mouse position.
func aim_vector(node: Node2D) -> Vector2:
    if force_aim != Vector2.ZERO:
        return force_aim.normalized()
    if device >= 0:
        var v := Vector2(
            Input.get_joy_axis(device, JOY_AXIS_RIGHT_X),
            Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y))
        if v.length() >= STICK_DEADZONE:
            return v.normalized()
    if use_keyboard:
        var mouse := node.get_global_mouse_position()
        var now := Time.get_ticks_msec() / 1000.0
        if mouse != _last_mouse:
            _last_mouse = mouse
            _mouse_active_until = now + MOUSE_ACTIVE_SECONDS
        if now < _mouse_active_until or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
            var d := mouse - node.global_position
            if d.length() > 1.0:
                return d.normalized()
    return Vector2.ZERO


func fire_held() -> bool:
    if force_fire:
        return true
    var held := false
    if device >= 0:
        held = Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT) > 0.5 \
            or Input.is_joy_button_pressed(device, JOY_BUTTON_RIGHT_SHOULDER)
    if use_keyboard:
        held = held or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
    return held


func _button(joy_button: JoyButton, key: Key) -> bool:
    var v := false
    if device >= 0:
        v = Input.is_joy_button_pressed(device, joy_button)
    if use_keyboard:
        v = v or Input.is_physical_key_pressed(key)
    return v


func _key(key: Key) -> float:
    return 1.0 if (use_keyboard and Input.is_physical_key_pressed(key)) else 0.0
