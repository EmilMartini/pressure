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


func _init(p_device: int, p_keyboard: bool) -> void:
    device = p_device
    use_keyboard = p_keyboard


## Call once per physics frame before reading anything else.
func poll() -> void:
    _prev = _cur.duplicate()
    _cur = {
        "toggle_aim": _button(JOY_BUTTON_Y, KEY_TAB),
        "vent": _button(JOY_BUTTON_LEFT_SHOULDER, KEY_SPACE),
        "swap": _button(JOY_BUTTON_X, KEY_Q),
        "interact": _button(JOY_BUTTON_A, KEY_E),
        "start": _button(JOY_BUTTON_START, KEY_ENTER),
    }


## True on the frame the named button went down.
func just_pressed(action: String) -> bool:
    return _cur.get(action, false) and not _prev.get(action, false)


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
