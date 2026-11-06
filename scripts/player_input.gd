class_name PlayerInput
extends RefCounted
## Reads one player's input from a joypad, the keyboard + mouse, or both merged.
## Player 1 merges keyboard/mouse with joypad 0. Extra joypads join as new players.
## Guns aim and fire on their own; the player moves, vents, interacts, and opens menus.

const STICK_DEADZONE := 0.22

var device: int = -1          # joypad id, -1 = no joypad
var use_keyboard: bool = false

# Self-test overrides (see Main.autotest). Ignored during normal play.
var force_move: Vector2 = Vector2.ZERO
var force_fire := false      # the bot can hold the trigger
var force_aim := Vector2.ZERO # and aim it

var _prev: Dictionary = {}
var _cur: Dictionary = {}
var _edges: Dictionary = {}

## "pad" or "kb": whichever this player touched last. Drives on-screen prompts.
var last_kind := "kb"
var lock_kind := false   # tests pin the kind so a stray mouse move cannot flip it
var _last_mouse_screen := Vector2i(-1, -1)
## Seconds since the last aim input (right stick pushed, mouse moved; the bot aims by holding
## fire with force_aim instead, so its door shots never linger as aim), and
## that aim's direction while it came from the stick (the mouse is read live).
var aim_idle := 99.0
var last_aim := Vector2.ZERO
var _aim_mouse := Vector2i(-1, -1)

const PROMPTS := {
    "interact": ["A", "E"],
    "vent": ["LB", "Space"],
    "active": ["X", "F"],
    "fire": ["RT", "LMB"],
    "pause": ["Start", "Esc"],
    "sheet": ["Back", "C"],
    "swap": ["Y", "Q"],   # at a ring / trinket pedestal: replace the other piece
}
const PAD_BUTTONS := [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_LEFT_SHOULDER,
    JOY_BUTTON_RIGHT_SHOULDER, JOY_BUTTON_START, JOY_BUTTON_BACK, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN,
    JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT]
const KB_KEYS := [KEY_W, KEY_A, KEY_S, KEY_D, KEY_E, KEY_Q, KEY_SPACE, KEY_C, KEY_ESCAPE]


func _init(p_device: int, p_keyboard: bool) -> void:
    device = p_device
    use_keyboard = p_keyboard


## The label to show for an action on this player's current device.
func prompt(action: String) -> String:
    var pair: Array = PROMPTS.get(action, ["?", "?"])
    return pair[0] if last_kind == "pad" else pair[1]


func _update_kind() -> void:
    if lock_kind:
        return
    var pad := false
    if device >= 0:
        pad = Vector2(Input.get_joy_axis(device, JOY_AXIS_LEFT_X), Input.get_joy_axis(device, JOY_AXIS_LEFT_Y)).length() > STICK_DEADZONE
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


## Call once per physics frame before reading anything else.
func poll() -> void:
    _update_kind()
    _update_aim_idle()
    _prev = _cur.duplicate()
    _cur = {
        "vent": _button(JOY_BUTTON_LEFT_SHOULDER, KEY_SPACE),
        "interact": _button(JOY_BUTTON_A, KEY_E),
        "active": _button(JOY_BUTTON_X, KEY_F),
        "start": _button(JOY_BUTTON_START, KEY_ENTER),
        "swap": _button(JOY_BUTTON_Y, KEY_Q),
    }
    for action in _cur.keys():
        if _cur[action] and not _prev.get(action, false):
            _edges[action] = true


func _update_aim_idle() -> void:
    aim_idle += 1.0 / float(Engine.physics_ticks_per_second)
    if device >= 0:
        var r := Vector2(Input.get_joy_axis(device, JOY_AXIS_RIGHT_X), Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y))
        if r.length() > STICK_DEADZONE:
            aim_idle = 0.0
            last_aim = r.normalized()
            return
    if use_keyboard and DisplayServer.get_name() != "headless":
        var m := DisplayServer.mouse_get_position()
        if _aim_mouse.x >= 0 and m.distance_to(_aim_mouse) > 3.0:
            aim_idle = 0.0
            last_aim = Vector2.ZERO   # the cursor is read live in aim_vector
        _aim_mouse = m


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


## Manual fire: right trigger on a pad, left mouse button on keyboard and mouse.
func fire_held() -> bool:
    if force_fire:
        return true
    if device >= 0 and Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT) > 0.45:
        return true
    return use_keyboard and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)


## Where a manual shot goes: the right stick if pushed, else the mouse cursor while the
## mouse is the active device, else Vector2.ZERO (the player falls back to facing).
func aim_vector(from_world: Vector2, viewport: Viewport) -> Vector2:
    if force_aim != Vector2.ZERO:
        return force_aim
    if device >= 0:
        var r := Vector2(Input.get_joy_axis(device, JOY_AXIS_RIGHT_X), Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y))
        if r.length() > STICK_DEADZONE:
            return r.normalized()
    if use_keyboard and last_kind == "kb" and viewport != null:
        var cam := viewport.get_camera_2d()
        if cam != null:
            var world_mouse := viewport.get_canvas_transform().affine_inverse() * viewport.get_mouse_position()
            var d := world_mouse - from_world
            if d.length() > 4.0:
                return d.normalized()
    return Vector2.ZERO


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


func _button(joy_button: JoyButton, key: Key) -> bool:
    var v := false
    if device >= 0:
        v = Input.is_joy_button_pressed(device, joy_button)
    if use_keyboard:
        v = v or Input.is_physical_key_pressed(key)
    return v


func _key(key: Key) -> float:
    return 1.0 if (use_keyboard and Input.is_physical_key_pressed(key)) else 0.0
